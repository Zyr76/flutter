#!/usr/bin/env python3
"""mkfxp.py —— 生成 .fxp 扩展包（本质是 zip）

.fxp 用来把「一大块可选能力」从宿主 APK 里拆出来，打包时再按需合并回去。
首个用途是把 Flutter 引擎（dex + 两个 so + assets）从编辑器里剥离。

包内布局（与 APK 条目一一对应）：

    classes.dex              会被改造为 classes<N>.dex 追加进产物 APK
    lib/<abi>/*.so           原样写入 lib/<abi>/
    assets/**                原样写入 assets/
    fxp.json                 元信息（格式版本、abi、minApi、名称）

用法：

    # 从 Flutter AAR 构建（最常见）
    python3 tools/mkfxp.py --out flutter.fxp \
        --aar flutter_bridge/build/host/outputs/repo/.../flutter_release-1.0.aar

    # 从已有 jar + 目录构建（调试用）
    python3 tools/mkfxp.py --out demo.fxp \
        --jar build/classes.jar --libs out/jni --assets out/flutter_assets \
        --name demo

依赖：JDK 的 java、Android SDK 的 d8.jar 与 android.jar。都从 $ANDROID_HOME
（默认 ~/android/sdk）自动找最新版本。
"""
import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile

SDK = os.environ.get("ANDROID_HOME") or os.path.expanduser("~/android/sdk")


def find_newest(pattern):
    items = sorted(glob.glob(pattern))
    return items[-1] if items else None


def find_d8():
    for root in (SDK, "/opt/android-sdk", os.path.expanduser("~/android-sdk")):
        p = find_newest(os.path.join(root, "build-tools", "*", "lib", "d8.jar"))
        if p:
            return p
    return None


def find_android_jar():
    for root in (SDK, "/opt/android-sdk", os.path.expanduser("~/android-sdk")):
        p = find_newest(os.path.join(root, "platforms", "android-*", "android.jar"))
        if p:
            return p
    return None


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        raise SystemExit("命令失败: " + " ".join(cmd[:3]))


def collect(args, work):
    """把各类输入摊平成待打包的文件列表。"""
    jars, libs, assets = [], {}, {}   # libs: 相对路径 -> 源文件

    for aar in args.aar:
        with zipfile.ZipFile(aar) as z:
            for n in z.namelist():
                if n == "classes.jar":
                    dst = os.path.join(work, os.path.basename(aar) + ".classes.jar")
                    with z.open(n) as src, open(dst, "wb") as out:
                        shutil.copyfileobj(src, out)
                    jars.append(dst)
                elif n.startswith("jni/") and n.endswith(".so"):
                    parts = n.split("/")
                    if len(parts) >= 3 and parts[1] in args.abi:
                        # AAR 里是 jni/<abi>/x.so，.fxp 里统一成 lib/<abi>/x.so
                        libs["lib/" + n[len("jni/"):]] = ("aar", aar, n)
                elif n.startswith("assets/") and not n.endswith("/"):
                    assets[n] = ("aar", aar, n)

    for j in args.jar:
        jars.append(j)

    for d in args.libs:
        for name in sorted(os.listdir(d)):
            if name.endswith(".so"):
                libs["lib/%s/%s" % (args.abi[0], name)] = ("file", os.path.join(d, name), None)

    for d in args.assets:
        root = d.rstrip("/")
        for base, _, files in os.walk(root):
            for f in files:
                full = os.path.join(base, f)
                rel = os.path.relpath(full, root)
                key = "assets/" + rel.replace(os.sep, "/")
                assets[key] = ("file", full, None)

    return jars, libs, assets


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="输出 .fxp 路径")
    ap.add_argument("--aar", action="append", default=[], help="输入 AAR（可多次）")
    ap.add_argument("--jar", action="append", default=[], help="额外 class jar（可多次）")
    ap.add_argument("--libs", action="append", default=[], help="额外的 .so 目录（可多次）")
    ap.add_argument("--assets", action="append", default=[], help="额外的 assets 目录（可多次）")
    ap.add_argument("--abi", action="append", default=[], help="允许的 ABI，默认 arm64-v8a")
    ap.add_argument("--min-api", type=int, default=24)
    ap.add_argument("--name", default=None, help="包名，默认取输出文件名")
    args = ap.parse_args()

    if not args.abi:
        args.abi = ["arm64-v8a"]
    if not (args.aar or args.jar):
        raise SystemExit("至少要给一个 --aar 或 --jar")

    d8 = find_d8()
    android_jar = find_android_jar()
    if not d8 or not android_jar:
        raise SystemExit("找不到 d8.jar 或 android.jar，请设置 ANDROID_HOME")

    work = tempfile.mkdtemp(prefix="mkfxp_")
    try:
        jars, libs, assets = collect(args, work)
        if not jars:
            raise SystemExit("没有任何 class 输入（AAR 里没找到 classes.jar）")

        dexdir = os.path.join(work, "dex")
        os.makedirs(dexdir, exist_ok=True)
        run(["java", "-cp", d8, "com.android.tools.r8.D8",
             "--release", "--min-api", str(args.min_api),
             "--lib", android_jar, "--output", dexdir] + jars)
        dex = os.path.join(dexdir, "classes.dex")
        if not os.path.isfile(dex):
            raise SystemExit("d8 没有产出 classes.dex")

        name = args.name or os.path.splitext(os.path.basename(args.out))[0]
        meta = {
            "format": 1,
            "name": name,
            "abi": args.abi,
            "minApi": args.min_api,
            "created": time.strftime("%Y-%m-%dT%H:%M:%S"),
        }

        os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
        with zipfile.ZipFile(args.out, "w", zipfile.ZIP_DEFLATED) as z:
            z.write(dex, "classes.dex")
            for key, src in sorted(libs.items()):
                if src[0] == "aar":
                    with zipfile.ZipFile(src[1]) as za, za.open(src[2]) as fsrc:
                        z.writestr(key, fsrc.read())
                else:
                    z.write(src[1], key)
            for key, src in sorted(assets.items()):
                if src[0] == "aar":
                    with zipfile.ZipFile(src[1]) as za, za.open(src[2]) as fsrc:
                        z.writestr(key, fsrc.read())
                else:
                    z.write(src[1], key)
            z.writestr("fxp.json", json.dumps(meta, ensure_ascii=False, indent=2))

        with zipfile.ZipFile(args.out) as z:
            total = sum(i.file_size for i in z.infolist())
            n = 2 + len(libs) + len(assets)
        print("已生成 %s：%d 个条目，解压后 %.1f MB" % (args.out, n, total / 1048576.0))
        print("  dex: %d bytes" % os.path.getsize(dex))
        for k in sorted(libs):
            print("  lib: %s" % k)
        print("  模块名（打包时自动合并，无需 Lua 侧处理）: %s" % name)
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
