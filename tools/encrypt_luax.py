#!/usr/bin/env python3
"""encrypt_luax.py —— 把 .lua / .luac 加密成 LUAX 密文，供 libluajava.so 的 JNI 钩子加载

用法：
    python3 encrypt_luax.py input.lua  output.luax
    python3 encrypt_luax.py input.luac output.luax

格式（24 字节头，全部小端）：
    offset 0..3   magic "LUAX"
    offset 4      version（必须与 C 侧 LUAX_VERSION 一致）
    offset 5      flags：bit0 = 1 字节码 / 0 源码文本
    offset 6..7   reserved
    offset 8..19  nonce (12 字节随机)
    offset 20..23 plain_len
    offset 24..   密文

与 chacha20.c 的等价性由 tools/roundtrip_test.sh 保证。
"""
import os
import struct
import sys

# 必须与 luajava.c 里的 LUAX_KEY 完全一致
KEY_HEX = "6979577ad60477575ee316e00bbccf0066d6da4abf63ec57c8854cc17ce4bb7b"

MAGIC = b"LUAX"
VERSION = 0x55
HEADER_SIZE = 24


def rotl32(v, n):
    return ((v << n) | (v >> (32 - n))) & 0xFFFFFFFF


def block(key, nonce, counter):
    st = [0x61707865, 0x3320646E, 0x79622D32, 0x6B206574]
    st += list(struct.unpack("<8I", key))
    st += [counter] + list(struct.unpack("<3I", nonce))
    x = st[:]
    for _ in range(10):
        for a, b, c, d in ((0, 4, 8, 12), (1, 5, 9, 13), (2, 6, 10, 14), (3, 7, 11, 15),
                           (0, 5, 10, 15), (1, 6, 11, 12), (2, 7, 8, 13), (3, 4, 9, 14)):
            x[a] = (x[a] + x[b]) & 0xFFFFFFFF
            x[d] = rotl32(x[d] ^ x[a], 16)
            x[c] = (x[c] + x[d]) & 0xFFFFFFFF
            x[b] = rotl32(x[b] ^ x[c], 12)
            x[a] = (x[a] + x[b]) & 0xFFFFFFFF
            x[d] = rotl32(x[d] ^ x[a], 8)
            x[c] = (x[c] + x[d]) & 0xFFFFFFFF
            x[b] = rotl32(x[b] ^ x[c], 7)
    return struct.pack("<16I", *[(x[i] + st[i]) & 0xFFFFFFFF for i in range(16)])


def chacha20_xor(data, key, nonce, counter=1):
    out = bytearray(data)
    for off in range(0, len(out), 64):
        ks = block(key, nonce, counter + off // 64)
        for i in range(min(64, len(out) - off)):
            out[off + i] ^= ks[i]
    return bytes(out)


def encrypt_file(src, dst):
    data = open(src, "rb").read()
    is_bytecode = 1 if src.endswith(".luac") else 0
    nonce = os.urandom(12)
    key = bytes.fromhex(KEY_HEX)
    ct = chacha20_xor(data, key, nonce, 1)
    header = MAGIC + bytes([VERSION, is_bytecode, 0, 0]) + nonce + struct.pack("<I", len(data))
    with open(dst, "wb") as f:
        f.write(header + ct)
    return len(data), is_bytecode


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    n, bc = encrypt_file(sys.argv[1], sys.argv[2])
    print("已加密: %s -> %s  (%d 字节明文, %s)" %
          (sys.argv[1], sys.argv[2], n, "字节码" if bc else "源码"))


if __name__ == "__main__":
    main()
