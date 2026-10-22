#!/usr/bin/env python3
"""encrypt_luax.py —— 把 .lua / .luac 加密成 LUAX v2 密文

格式（24 字节头 + 密文 + 16 字节标签，全部小端）：

    offset 0..3   magic "LUAX"
    offset 4      version = 0x56（v2：ChaCha20-Poly1305）
    offset 5      flags：bit0 = 1 字节码 / 0 源码文本
    offset 6..7   reserved
    offset 8..19  nonce（12 字节随机）
    offset 20..23 plain_len
    offset 24..   ChaCha20 密文
    末尾 16 字节   Poly1305 认证标签

头部 24 字节整体作为 AAD 参与认证，所以 magic/version/flags/nonce/长度
任何一项被修改都会导致校验失败（这是 v1 缺少的）。

用法：
    python3 encrypt_luax.py input.lua  output.luax
    python3 encrypt_luax.py input.luac output.luax

与 chacha20.c 的一致性由 tools/roundtrip_test.sh 保证。
"""
import hmac
import os
import struct
import sys

# 必须与 luajava.c / luax.c 里的 LUAX_KEY 完全一致
KEY_HEX = "6979577ad60477575ee316e00bbccf0066d6da4abf63ec57c8854cc17ce4bb7b"

MAGIC = b"LUAX"
VERSION = 0x56
HEADER_SIZE = 24
TAG_SIZE = 16

_P = (1 << 130) - 5
_R_MASK = 0x0FFFFFFC0FFFFFFC0FFFFFFC0FFFFFFF
_M128 = (1 << 128) - 1


def rotl32(v, n):
    return ((v << n) | (v >> (32 - n))) & 0xFFFFFFFF


def block(key, nonce, counter):
    """RFC 8439 块函数：返回 64 字节 keystream。"""
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


def poly1305_mac(msg, key32):
    """RFC 8439 §2.5。用大整数实现，便于核对。"""
    r = int.from_bytes(key32[:16], "little") & _R_MASK
    s = int.from_bytes(key32[16:32], "little")
    acc = 0
    for i in range(0, len(msg), 16):
        chunk = msg[i:i + 16]
        # 末尾追加 1 位（0x01），等价于把 2^(8*len) 加到数值上
        acc = ((acc + int.from_bytes(chunk + b"\x01", "little")) * r) % _P
    return ((acc + s) & _M128).to_bytes(16, "little")


def _pad16(b):
    rem = len(b) % 16
    return b if rem == 0 else b + b"\x00" * (16 - rem)


def aead_encrypt(key32, nonce, aad, data):
    """返回 (密文, 16 字节标签)。"""
    poly_key = block(key32, nonce, 0)[:32]     # 第 0 块的前 32 字节
    ct = chacha20_xor(data, key32, nonce, 1)
    mac_data = _pad16(aad) + _pad16(ct) + struct.pack("<QQ", len(aad), len(ct))
    return ct, poly1305_mac(mac_data, poly_key)


def aead_decrypt(key32, nonce, aad, ct, tag):
    poly_key = block(key32, nonce, 0)[:32]
    mac_data = _pad16(aad) + _pad16(ct) + struct.pack("<QQ", len(aad), len(ct))
    if not hmac.compare_digest(poly1305_mac(mac_data, poly_key), tag):
        raise ValueError("LUAX: 密文校验失败")
    return chacha20_xor(ct, key32, nonce, 1)


def encrypt_bytes(data, key_hex=KEY_HEX):
    """加密一段内容，返回完整 v2 密文。"""
    is_bytecode = 1 if data[:4] == b"\x1bLua" else 0
    nonce = os.urandom(12)
    key = bytes.fromhex(key_hex)
    header = MAGIC + bytes([VERSION, is_bytecode, 0, 0]) + nonce + struct.pack("<I", len(data))
    ct, tag = aead_encrypt(key, nonce, header, data)
    return header + ct + tag


def decrypt_bytes(blob, key_hex=KEY_HEX):
    """解密并校验，返回 (明文, is_bytecode)。仅用于测试与排查。"""
    if len(blob) < HEADER_SIZE or blob[:4] != MAGIC:
        raise ValueError("不是 LUAX 密文")
    key = bytes.fromhex(key_hex)
    ver = blob[4]
    nonce = blob[8:20]
    plen = struct.unpack("<I", blob[20:24])[0]
    if ver != VERSION:
        raise ValueError("不支持的密文版本 %d（需要 %d）" % (ver, VERSION))
    if len(blob) != HEADER_SIZE + plen + TAG_SIZE:
        raise ValueError("长度字段与文件大小不符")
    ct = blob[HEADER_SIZE:HEADER_SIZE + plen]
    tag = blob[HEADER_SIZE + plen:]
    plain = aead_decrypt(key, nonce, blob[:HEADER_SIZE], ct, tag)
    return plain, blob[5] & 1


def encrypt_file(src, dst):
    data = open(src, "rb").read()
    with open(dst, "wb") as f:
        f.write(encrypt_bytes(data))
    return len(data), 1 if data[:4] == b"\x1bLua" else 0


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    n, bc = encrypt_file(sys.argv[1], sys.argv[2])
    print("已加密: %s -> %s  (%d 字节明文, %s)"
          % (sys.argv[1], sys.argv[2], n, "字节码" if bc else "源码"))


if __name__ == "__main__":
    main()
