#!/usr/bin/env python3
"""encrypt_dir.py —— 批量把目录下的 .lua 加密到输出目录（保持相对路径）

供 Gradle 构建期调用；也可手动执行：

    python3 tools/encrypt_dir.py app/src/main/luax app/build/generated/luax_assets

只处理 .lua 文件，其余文件忽略；目录不存在时直接退出（等价于不启用）。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from encrypt_luax import encrypt_file  # noqa: E402


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    src, dst = sys.argv[1], sys.argv[2]
    if not os.path.isdir(src):
        print("源目录不存在，跳过：", src)
        return
    count = 0
    for root, _, files in os.walk(src):
        for name in sorted(files):
            if not name.endswith(".lua"):
                continue
            full = os.path.join(root, name)
            rel = os.path.relpath(full, src)
            out = os.path.join(dst, rel)
            parent = os.path.dirname(out)
            if parent:
                os.makedirs(parent, exist_ok=True)
            encrypt_file(full, out)
            count += 1
    print("已加密 %d 个脚本 -> %s" % (count, dst))


if __name__ == "__main__":
    main()
