#!/bin/bash
# roundtrip_test.sh —— LUAX v2（ChaCha20-Poly1305）全链路自测（宿主，无需设备）
#
# 覆盖：
#   1. chacha20.c 自测：RFC 8439 §2.3.2 / §2.5.2 / §2.8.2 已知答案 + 篡改检测
#   2. 宿主编 luac，把 .lua 编成字节码
#   3. Python 加密 → C 端用真实 luax_decrypt_load 加载执行
#   4. 篡改检测：改密文 / 改头部 flags / 改 nonce，都必须被拒绝
#   5. Python ↔ C 双向交叉：C 加密 → Python 解密；Python 加密 → C 加载
#   6. require 路径（luaL_loadfilex 挂载点）
#
# 用法：tools/roundtrip_test.sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CPP="$ROOT/app/src/main/cpp"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LUA_SRC=$(ls "$CPP"/lua/*.c | grep -v -E '/lua\.c$|/luac\.c$')

echo "== 1. chacha20.c 自测 =="
cc -O2 -DCHACHA20_TEST -o "$TMP/t_chacha" "$CPP/chacha20.c"
"$TMP/t_chacha"

echo
echo "== 2. 宿主编译 luac =="
# shellcheck disable=SC2086
cc -O2 -DLUA_USE_POSIX -I "$CPP/lua" -o "$TMP/luac" "$CPP/lua/luac.c" \
   "$CPP/luax.c" "$CPP/chacha20.c" $LUA_SRC -lm
"$TMP/luac" -v

printf 'local s = 0\nfor i = 1, 100 do s = s + i end\nprint("sum =", s)\n' > "$TMP/hello.lua"
"$TMP/luac" -s -o "$TMP/hello.luac" "$TMP/hello.lua"

echo
echo "== 3. Python 加密（源码文本 + 字节码）=="
python3 "$ROOT/tools/encrypt_luax.py" "$TMP/hello.lua" "$TMP/text.luax"
python3 "$ROOT/tools/encrypt_luax.py" "$TMP/hello.luac" "$TMP/bin.luax"
python3 - "$TMP/text.luax" "$TMP/bin.luax" <<'EOF'
import sys
for p in sys.argv[1:]:
    b = open(p, "rb").read()
    print("  %-12s %d 字节  magic=%s ver=0x%02x flags=%d" %
          (p.split("/")[-1], len(b), b[:4].decode(), b[4], b[5]))
EOF

echo
echo "== 4. C 端用真实的 luax_decrypt_load 加载 =="
cat > "$TMP/loader.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include "luax.h"
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("open"); return 2; }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc((size_t)n);
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) return 2;
    fclose(f);

    lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    int rc = luax_decrypt_load(L, buf, (size_t)n, "@test");
    free(buf);
    if (rc != LUA_OK) {
        printf("  ✘ 加载失败: %s\n", lua_tostring(L, -1));
        return 1;
    }
    rc = lua_pcall(L, 0, 0, 0);
    if (rc != LUA_OK) {
        printf("  ✘ 执行失败: %s\n", lua_tostring(L, -1));
        return 1;
    }
    lua_close(L);
    return 0;
}
EOF
# shellcheck disable=SC2086
cc -O2 -I "$CPP" -I "$CPP/lua" -o "$TMP/loader" "$TMP/loader.c" \
   "$CPP/luax.c" "$CPP/chacha20.c" $LUA_SRC -lm
echo "  --- 文本密文 ---"
"$TMP/loader" "$TMP/text.luax"
echo "  --- 字节码密文 ---"
"$TMP/loader" "$TMP/bin.luax"

echo
echo "== 5. 篡改检测 =="
python3 - "$TMP/bin.luax" "$TMP" <<'EOF'
import sys
blob = bytearray(open(sys.argv[1], "rb").read())
out = sys.argv[2]
# 改密文最后一字节（属于密文区）
a = bytearray(blob); a[-17] ^= 0x01
open(out + "/tamper_ct.luax", "wb").write(a)
# 改头部 flags（把文本/字节码标志翻转）—— 头部是 AAD，必须被校验
b = bytearray(blob); b[5] ^= 0x01
open(out + "/tamper_flags.luax", "wb").write(b)
# 改 nonce
c = bytearray(blob); c[8] ^= 0xff
open(out + "/tamper_nonce.luax", "wb").write(c)
# 改版本号
d = bytearray(blob); d[4] = 0x57   # 不支持的版本号
open(out + "/tamper_ver.luax", "wb").write(d)
print("  已生成 4 个篡改样本")
EOF
for t in tamper_ct tamper_flags tamper_nonce tamper_ver; do
  if "$TMP/loader" "$TMP/$t.luax" > "$TMP/out.txt" 2>&1; then
    echo "  ✘ $t 未被拒绝（应当失败）"
    exit 1
  else
    echo "  ✔ $t 被拒绝: $(head -1 "$TMP/out.txt" | sed 's/^ *//')"
  fi
done

echo
echo "== 6. Python ↔ C 双向交叉 =="
cat > "$TMP/enc.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include "luax.h"
int main(int argc, char **argv) {
    (void)argc;
    FILE *f = fopen(argv[1], "rb");
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    unsigned char *in = malloc((size_t)n);
    if (fread(in, 1, (size_t)n, f) != (size_t)n) return 2;
    fclose(f);
    size_t outlen = 0;
    unsigned char *out = luax_encrypt(in, (size_t)n, &outlen);
    if (!out) { printf("加密失败\n"); return 1; }
    FILE *o = fopen(argv[2], "wb");
    fwrite(out, 1, outlen, o);
    fclose(o);
    free(in); free(out);
    return 0;
}
EOF
# shellcheck disable=SC2086
cc -O2 -I "$CPP" -I "$CPP/lua" -o "$TMP/enc" "$TMP/enc.c" \
   "$CPP/luax.c" "$CPP/chacha20.c" $LUA_SRC -lm
"$TMP/enc" "$TMP/hello.luac" "$TMP/c_enc.luax"
python3 - "$TMP/c_enc.luax" "$TMP/hello.luac" "$ROOT/tools" <<'EOF'
import sys
sys.path.insert(0, sys.argv[3])
import encrypt_luax as E
blob = open(sys.argv[1], "rb").read()
plain, is_bc = E.decrypt_bytes(blob)
orig = open(sys.argv[2], "rb").read()
print("  C 加密 → Python 解密: %s（ver=0x%02x flags=%d）" %
      ("一致 ✔" if plain == orig else "不一致 ✘", blob[4], is_bc))
assert plain == orig
EOF
"$TMP/loader" "$TMP/c_enc.luax" > /dev/null && echo "  C 加密 → C 加载: ✔"

echo
echo "== 7. require 路径（luaL_loadfilex 挂载点）=="
mkdir -p "$TMP/mod"
printf 'local M = {}\nfunction M.hello() return "加密模块" end\nreturn M\n' > "$TMP/mod/mod_src.lua"
cp "$TMP/mod/mod_src.lua" "$TMP/mod/mod.lua"
python3 "$ROOT/tools/encrypt_luax.py" "$TMP/mod/mod.lua" "$TMP/mod/mod.lua" > /dev/null
printf 'local m = require "mod"\nassert(m.hello() == "加密模块")\nprint("  ✔ require 加密模块 OK")\n' > "$TMP/mod/main.lua"
# shellcheck disable=SC2086
cc -O2 -DLUA_USE_POSIX -I "$CPP" -I "$CPP/lua" -o "$TMP/lua" \
   "$CPP/lua/lua.c" "$CPP/luax.c" "$CPP/chacha20.c" $LUA_SRC -lm
(cd "$TMP/mod" && ../lua main.lua)
cp "$TMP/mod/mod_src.lua" "$TMP/mod/mod.lua"
(cd "$TMP/mod" && ../lua main.lua > /dev/null && echo "  ✔ 明文模块对照 OK")

echo
echo "结论：LUAX v2（ChaCha20-Poly1305）加密→校验→解密→加载→执行 全链路一致，"
echo "     篡改可被检出"
