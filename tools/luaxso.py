#!/usr/bin/env python3
"""luaxso.py —— 把 Lua 模块的密文做成独立 .so 容器

用法：
    python3 tools/luaxso.py gen hello.lua -o build/luaxso
    # 输出模块名（原文件名 base64url、无填充），并生成 luax_blob_<name>.c

CMake 用它生成 C 源码，再编成 lib<name>.so。运行时：

    local m = require "<name>"      -- name 就是上面输出的字符串

容器 .so 里只有两个符号，不含任何 Lua 代码：

    const unsigned char luax_blob[];      LUAX 密文
    const unsigned long luax_blob_len;    长度

解密和执行由 libluajava.so 里的 luax 库完成（require 的 searcher 接管）。
"""
import argparse
import base64
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from encrypt_luax import encrypt_bytes  # noqa: E402


def module_name(path):
    stem = os.path.splitext(os.path.basename(path))[0]
    # urlsafe base64，去掉 '=' 填充，保证只含 [A-Za-z0-9_-]
    return base64.urlsafe_b64encode(stem.encode("utf-8")).decode("ascii").rstrip("=")


def emit_c(lua_path, out_dir):
    data = open(lua_path, "rb").read()
    blob = encrypt_bytes(data)
    name = module_name(lua_path)
    os.makedirs(out_dir, exist_ok=True)
    out_c = os.path.join(out_dir, "luax_blob_%s.c" % name)
    lines = [
        "/* 自动生成，请勿编辑：%s */" % os.path.basename(lua_path),
        "#include <stddef.h>",
        "",
        "const unsigned char luax_blob[] = {",
    ]
    for i in range(0, len(blob), 16):
        chunk = blob[i:i + 16]
        lines.append("  " + ",".join("0x%02x" % b for b in chunk) + ",")
    lines.append("};")
    lines.append("const unsigned long luax_blob_len = %dUL;" % len(blob))
    lines.append("")
    with open(out_c, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    return name, out_c, len(data), len(blob)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    gen = sub.add_parser("gen", help="生成容器 C 源码，标准输出为模块名")
    gen.add_argument("lua")
    gen.add_argument("-o", "--out", required=True)
    args = ap.parse_args()

    if args.cmd == "gen":
        name, out_c, plain_len, blob_len = emit_c(args.lua, args.out)
        sys.stderr.write("%s -> %s (明文 %d, 密文 %d)\n" %
                         (args.lua, out_c, plain_len, blob_len))
        print(name)


if __name__ == "__main__":
    main()
