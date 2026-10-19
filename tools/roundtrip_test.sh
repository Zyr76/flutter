#!/bin/bash
# roundtrip_test.sh —— LUAX 加密链路自测
#
# 校验三件事：
#   1. chacha20.c 自身正确（RFC 8439 已知答案 + 往返）
#   2. chacha20.c 与 tools/encrypt_luax.py 逐字节等价
#   3. luac 产出的字节码经加密后，能被 C 端按 luax_load 的逻辑解密、加载、执行
#
# 只在宿主机跑，不需要设备。用法：tools/roundtrip_test.sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CPP="$ROOT/app/src/main/cpp"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "== 1. chacha20.c 自测 =="
cc -O2 -DCHACHA20_TEST -o "$TMP/t_chacha" "$CPP/chacha20.c"
"$TMP/t_chacha"

echo
echo "== 2. 宿主编译 luac（与 so 同一份 lua 源码）=="
LUA_SRC=$(ls "$CPP"/lua/*.c | grep -v -E '/lua\.c$|/luac\.c$')
# shellcheck disable=SC2086
cc -O2 -DLUA_USE_POSIX -o "$TMP/luac" "$CPP/lua/luac.c" $LUA_SRC -lm
"$TMP/luac" -v

printf 'local s = 0\nfor i = 1, 100 do s = s + i end\nprint("sum =", s)\n' > "$TMP/hello.lua"
"$TMP/luac" -s -o "$TMP/hello.luac" "$TMP/hello.lua"

echo
echo "== 3. Python 加密 =="
python3 "$ROOT/tools/encrypt_luax.py" "$TMP/hello.luac" "$TMP/hello.luax"

echo
echo "== 4. C 端解密 + 加载 + 执行（模拟 luax_load）=="
cat > "$TMP/loader.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "chacha20.h"
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#define HDR 24
/* key 由 -DKEY_HEX 传入，取自 luajava.c 的 LUAX_KEY，避免两边不同步 */
static uint8_t K[32];
static void load_key(const char *hex) {
    for (int i = 0; i < 32; i++) { unsigned v; sscanf(hex + i * 2, "%2x", &v); K[i] = (uint8_t)v; }
}

int main(int argc, char **argv) {
    load_key(argv[2]);
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("open"); return 1; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    uint8_t *buf = malloc(n);
    if (fread(buf, 1, n, f) != (size_t)n) return 1;
    fclose(f);
    if (memcmp(buf, "LUAX", 4) != 0) { puts("magic 不符"); return 1; }
    if (buf[4] != 0x55) { printf("版本不符 %d\n", buf[4]); return 1; }
    uint32_t plen = buf[20] | (buf[21]<<8) | (buf[22]<<16) | ((uint32_t)buf[23]<<24);
    if ((size_t)plen != (size_t)n - HDR) { puts("长度不符"); return 1; }
    uint8_t *plain = malloc(plen);
    memcpy(plain, buf + HDR, plen);
    chacha20_xor(plain, plen, K, buf + 8, 1);
    if (plain[0] != 0x1b || memcmp(plain + 1, "Lua", 3) != 0) {
        puts("解密结果不是 Lua 字节码头（key 不一致？）"); return 1;
    }
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    int rc = luaL_loadbufferx(L, (char*)plain, plen, "@hello.luac", "b");
    if (rc != LUA_OK) { printf("加载失败: %s\n", lua_tostring(L, -1)); return 1; }
    free(plain);
    rc = lua_pcall(L, 0, 0, 0);
    if (rc != LUA_OK) { printf("执行失败: %s\n", lua_tostring(L, -1)); return 1; }
    lua_close(L);
    return 0;
}
EOF
KEY_HEX=$(python3 - "$CPP/luajava.c" <<'PY2'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r"LUAX_KEY\[32\] = \{([^}]*)\}", s, re.S)
print("".join(x.strip().replace("0x", "") for x in m.group(1).split(",") if x.strip()))
PY2
)
echo "  取自 luajava.c 的 key: ${KEY_HEX:0:8}… (${#KEY_HEX} 字符)"
# shellcheck disable=SC2086
cc -O2 -I "$CPP" -I "$CPP/lua" -o "$TMP/loader" "$TMP/loader.c" "$CPP/chacha20.c" $LUA_SRC -lm
"$TMP/loader" "$TMP/hello.luax" "$KEY_HEX"
echo
echo "结论：加密→解密→加载→执行 全链路一致"
