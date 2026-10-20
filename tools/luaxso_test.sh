#!/bin/bash
# luaxso_test.sh —— 加密容器 .so 的端到端自测（宿主，无需设备）
#
# 覆盖：
#   1. 生成容器 .so，只有 luax_blob / luax_blob_len 两个符号
#   2. require "<base64名>" 能加载并执行模块
#   3. 明文 Lua 模块、普通 C 模块不受影响（searcher 不越界）
#   4. 不存在的模块报错正常
#   5. luax.loadso 按路径直接加载
#
# 用法：tools/luaxso_test.sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CPP="$ROOT/app/src/main/cpp"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "== 1. 构建宿主 lua（含 luax 库）=="
LUA_SRC=$(ls "$CPP"/lua/*.c | grep -v -E '/lua\.c$|/luac\.c$')
# shellcheck disable=SC2086
cc -O2 -DLUA_USE_POSIX -DLUA_USE_DLOPEN -I "$CPP" -I "$CPP/lua" \
   -o "$TMP/lua" "$CPP/lua/lua.c" "$CPP/luax.c" "$CPP/chacha20.c" $LUA_SRC -lm -ldl
"$TMP/lua" -v

echo
echo "== 2. 生成容器 .so =="
mkdir -p "$TMP/containers"
NAME=$(python3 "$ROOT/tools/luaxso.py" gen "$ROOT/app/src/main/luaxso/hello.lua" -o "$TMP/containers" 2>/dev/null)
echo "  模块名: $NAME"
cc -shared -fPIC -O2 -o "$TMP/containers/lib$NAME.so" "$TMP/containers/luax_blob_$NAME.c"
SIZE=$(stat -c%s "$TMP/containers/lib$NAME.so")
echo "  .so 大小: $SIZE 字节"
SYMS=$(nm -D "$TMP/containers/lib$NAME.so" | grep -c "luax_blob")
[ "$SYMS" -ge 2 ] || { echo "  ✘ luax_blob 符号不全"; exit 1; }
echo "  ✔ 数据符号 luax_blob / luax_blob_len 都在"

echo
echo "== 3. 边界用例 =="
cat > "$TMP/plain.lua" <<'EOF'
local M = {}
function M.v() return "明文模块" end
return M
EOF
cat > "$TMP/cmock.c" <<'EOF'
static int dummy(void) { return 0; }
void *cmock_entry = (void*)dummy;
EOF
cc -shared -fPIC -O2 -o "$TMP/libcmock.so" "$TMP/cmock.c"

cat > "$TMP/edge.lua" <<EOF
package.path  = "$TMP/?.lua;" .. package.path
package.cpath = "$TMP/containers/lib?.so;$TMP/lib?.so;" .. package.cpath

local m = require "$NAME"
assert(type(m) == "table", "容器模块应返回 table")
assert(m.greet("世界"):find("来自加密 so 容器"), "模块内容不对")
print("  ✔ require 加密容器: " .. m.greet("世界"))

local p = require "plain"
assert(p.v() == "明文模块", "明文模块被影响")
print("  ✔ 明文模块照常: " .. p.v())

local ok2 = pcall(require, "cmock")
assert(not ok2, "非容器 .so 不应被接管成成功")
print("  ✔ 非容器 .so 未被劫持")

local ok3 = pcall(require, "bm90aGVyZQ")
assert(not ok3, "不存在的模块应失败")
print("  ✔ 不存在的模块正常报错")

local d = luax.loadso("$TMP/containers/lib$NAME.so")
assert(type(d) == "table")
print("  ✔ luax.loadso 直载: " .. d.greet("直连"))
EOF
(cd "$TMP" && ./lua edge.lua)

echo
echo "结论：加密容器 .so 生成、require 加载、边界行为全部正确"
