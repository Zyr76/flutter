#!/bin/bash
# fxp_test.sh —— .fxp 扩展包生成自测（宿主，无需设备）
#
# 验证：
#   1. mkfxp 能把 class jar 用 d8 编成真 dex（不是字节码）
#   2. 包内布局正确：classes.dex / lib/<abi>/*.so / assets/** / fxp.json
#   3. 从 AAR 构建也能工作（simulated aar）
#
# 用法：tools/fxp_test.sh
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "== 1. 造一个 class jar + 假的 so / assets =="
mkdir -p "$TMP/src/demo" "$TMP/classes" "$TMP/libs" "$TMP/assets/flutter_assets"
cat > "$TMP/src/demo/Hello.java" <<'EOF'
package demo;
public class Hello {
    public static String greet(String n) { return "hi " + n; }
}
EOF
javac -d "$TMP/classes" "$TMP/src/demo/Hello.java"
(cd "$TMP/classes" && jar cf "$TMP/hello.jar" .)
printf '\x7fELF fake' > "$TMP/libs/libdemo.so"
printf 'asset' > "$TMP/assets/flutter_assets/a.txt"

echo "== 2. 用 jar 构建 =="
python3 "$ROOT/tools/mkfxp.py" --out "$TMP/demo.fxp" \
    --jar "$TMP/hello.jar" --libs "$TMP/libs" --assets "$TMP/assets" --name demo
python3 - "$TMP/demo.fxp" <<'EOF'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
names = set(z.namelist())
need = {"classes.dex", "lib/arm64-v8a/libdemo.so", "assets/flutter_assets/a.txt", "fxp.json"}
missing = need - names
assert not missing, "缺条目: %s" % missing
head = z.read("classes.dex")[:8]
assert head[:4] == b"dex\n", "classes.dex 不是 dex 格式: %r" % head
print("  ✔ 条目齐全，dex 头 =", head)
EOF

echo
echo "== 3. 用 AAR 构建（模拟 flutter AAR 结构）=="
mkdir -p "$TMP/aar/jni/arm64-v8a" "$TMP/aar/jni/armeabi-v7a" "$TMP/aar/assets/flutter_assets"
cp "$TMP/hello.jar" "$TMP/aar/classes.jar"
printf '\x7fELF so' > "$TMP/aar/jni/arm64-v8a/libflutter.so"
printf 'x' > "$TMP/aar/jni/armeabi-v7a/libflutter.so"   # 应被 abi 过滤掉
printf 'asset' > "$TMP/aar/assets/flutter_assets/b.txt"
(cd "$TMP/aar" && zip -qr "$TMP/fake.aar" .)
python3 "$ROOT/tools/mkfxp.py" --out "$TMP/aar.fxp" --aar "$TMP/fake.aar" --abi arm64-v8a --name flutter
python3 - "$TMP/aar.fxp" <<'EOF'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
names = set(z.namelist())
assert "lib/arm64-v8a/libflutter.so" in names, "缺 arm64 的 so"
assert "lib/armeabi-v7a/libflutter.so" not in names, "v7a 的 so 没被过滤"
assert "assets/flutter_assets/b.txt" in names, "assets 没进来"
print("  ✔ AAR 构建正确，且 abi 过滤生效")
print("  条目:", sorted(names))
EOF

echo
echo "结论：.fxp 生成、布局、abi 过滤全部正确"
echo "    打包时 bin.lua 会把 classes.dex 改名为 classes<N>.dex，lib/ 与 assets/ 原样并入产物"
