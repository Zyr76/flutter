/* chacha20.c —— RFC 8439 ChaCha20 + Poly1305 AEAD
 *
 * 自测：cc -DCHACHA20_TEST -o /tmp/t chacha20.c && /tmp/t
 * 覆盖 §2.3.2 块函数、§2.5.2 Poly1305、§2.8.2 AEAD 三组已知答案，
 * 外加往返与篡改检测。
 */
#include "chacha20.h"

#include <string.h>

#define ROTL32(v, n) (((v) << (n)) | ((v) >> (32 - (n))))
#define QR(a, b, c, d) do { \
    a += b; d ^= a; d = ROTL32(d, 16); \
    c += d; b ^= c; b = ROTL32(b, 12); \
    a += b; d ^= a; d = ROTL32(d, 8);  \
    c += d; b ^= c; b = ROTL32(b, 7);  \
} while (0)

void chacha20_memzero(void *p, size_t n) {
    volatile uint8_t *v = (volatile uint8_t *)p;
    while (n--) {
        *v++ = 0;
    }
}

static uint32_t load32le(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8)
         | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void store32le(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16);
    p[3] = (uint8_t)(v >> 24);
}

static void store64le(uint8_t *p, uint64_t v) {
    store32le(p, (uint32_t)v);
    store32le(p + 4, (uint32_t)(v >> 32));
}

/* ---------------------------- ChaCha20 ---------------------------- */

static void chacha20_block(uint8_t ks[64], const uint8_t key[32],
                           const uint8_t nonce[12], uint32_t counter) {
    uint32_t st[16], x[16];
    int i;

    st[0] = 0x61707865; st[1] = 0x3320646e;
    st[2] = 0x79622d32; st[3] = 0x6b206574;      /* "expand 32-byte k" */
    for (i = 0; i < 8; i++) {
        st[4 + i] = load32le(key + i * 4);
    }
    st[12] = counter;
    st[13] = load32le(nonce);
    st[14] = load32le(nonce + 4);
    st[15] = load32le(nonce + 8);

    memcpy(x, st, sizeof(x));
    for (i = 0; i < 10; i++) {                   /* 20 轮 = 10 次双轮 */
        QR(x[0], x[4], x[ 8], x[12]);
        QR(x[1], x[5], x[ 9], x[13]);
        QR(x[2], x[6], x[10], x[14]);
        QR(x[3], x[7], x[11], x[15]);
        QR(x[0], x[5], x[10], x[15]);
        QR(x[1], x[6], x[11], x[12]);
        QR(x[2], x[7], x[ 8], x[13]);
        QR(x[3], x[4], x[ 9], x[14]);
    }
    for (i = 0; i < 16; i++) {
        store32le(ks + i * 4, x[i] + st[i]);
    }
    chacha20_memzero(st, sizeof(st));
    chacha20_memzero(x, sizeof(x));
}

/* 内部实现：AEAD 的流加密部分与自测使用，不对外暴露 */
static void chacha20_xor(uint8_t *data, size_t len, const uint8_t key[32],
                         const uint8_t nonce[12], uint32_t counter) {
    uint8_t ks[64];
    size_t off = 0;

    while (off < len) {
        size_t n = len - off < 64 ? len - off : 64;
        size_t i;
        chacha20_block(ks, key, nonce, counter + (uint32_t)(off / 64));
        for (i = 0; i < n; i++) {
            data[off + i] ^= ks[i];
        }
        off += n;
    }
    chacha20_memzero(ks, sizeof(ks));
}

/* ---------------------------- Poly1305 ----------------------------
 * 5 个 26 位肢（poly1305-donna-32），只用 32/64 位整数，可移植。
 */

typedef struct {
    uint32_t r[5];
    uint32_t h[5];
    uint32_t pad[4];
    size_t leftover;
    uint8_t buffer[16];
    int final;
} poly1305_state;

static void poly1305_init(poly1305_state *st, const uint8_t key[32]) {
    /* r &= 0xffffffc0ffffffc0ffffffc0fffffff */
    st->r[0] = (load32le(key + 0)) & 0x3ffffff;
    st->r[1] = (load32le(key + 3) >> 2) & 0x3ffff03;
    st->r[2] = (load32le(key + 6) >> 4) & 0x3ffc0ff;
    st->r[3] = (load32le(key + 9) >> 6) & 0x3f03fff;
    st->r[4] = (load32le(key + 12) >> 8) & 0x00fffff;

    st->h[0] = 0; st->h[1] = 0; st->h[2] = 0; st->h[3] = 0; st->h[4] = 0;
    st->pad[0] = load32le(key + 16);
    st->pad[1] = load32le(key + 20);
    st->pad[2] = load32le(key + 24);
    st->pad[3] = load32le(key + 28);
    st->leftover = 0;
    st->final = 0;
}

static void poly1305_blocks(poly1305_state *st, const uint8_t *m, size_t bytes) {
    const uint32_t hibit = st->final ? 0u : (1u << 24);   /* 1 << 128 */
    uint32_t r0 = st->r[0], r1 = st->r[1], r2 = st->r[2];
    uint32_t r3 = st->r[3], r4 = st->r[4];
    uint32_t s1 = r1 * 5, s2 = r2 * 5, s3 = r3 * 5, s4 = r4 * 5;
    uint32_t h0 = st->h[0], h1 = st->h[1], h2 = st->h[2];
    uint32_t h3 = st->h[3], h4 = st->h[4];

    while (bytes >= 16) {
        uint64_t d0, d1, d2, d3, d4;
        uint32_t c;

        h0 += (load32le(m + 0)) & 0x3ffffff;
        h1 += (load32le(m + 3) >> 2) & 0x3ffffff;
        h2 += (load32le(m + 6) >> 4) & 0x3ffffff;
        h3 += (load32le(m + 9) >> 6) & 0x3ffffff;
        h4 += (load32le(m + 12) >> 8) | hibit;

        d0 = (uint64_t)h0 * r0 + (uint64_t)h1 * s4 + (uint64_t)h2 * s3
           + (uint64_t)h3 * s2 + (uint64_t)h4 * s1;
        d1 = (uint64_t)h0 * r1 + (uint64_t)h1 * r0 + (uint64_t)h2 * s4
           + (uint64_t)h3 * s3 + (uint64_t)h4 * s2;
        d2 = (uint64_t)h0 * r2 + (uint64_t)h1 * r1 + (uint64_t)h2 * r0
           + (uint64_t)h3 * s4 + (uint64_t)h4 * s3;
        d3 = (uint64_t)h0 * r3 + (uint64_t)h1 * r2 + (uint64_t)h2 * r1
           + (uint64_t)h3 * r0 + (uint64_t)h4 * s4;
        d4 = (uint64_t)h0 * r4 + (uint64_t)h1 * r3 + (uint64_t)h2 * r2
           + (uint64_t)h3 * r1 + (uint64_t)h4 * r0;

        c = (uint32_t)(d0 >> 26); h0 = (uint32_t)d0 & 0x3ffffff;
        d1 += c; c = (uint32_t)(d1 >> 26); h1 = (uint32_t)d1 & 0x3ffffff;
        d2 += c; c = (uint32_t)(d2 >> 26); h2 = (uint32_t)d2 & 0x3ffffff;
        d3 += c; c = (uint32_t)(d3 >> 26); h3 = (uint32_t)d3 & 0x3ffffff;
        d4 += c; c = (uint32_t)(d4 >> 26); h4 = (uint32_t)d4 & 0x3ffffff;
        h0 += c * 5; c = (h0 >> 26); h0 = h0 & 0x3ffffff;
        h1 += c;

        m += 16;
        bytes -= 16;
    }

    st->h[0] = h0; st->h[1] = h1; st->h[2] = h2;
    st->h[3] = h3; st->h[4] = h4;
}

static void poly1305_update(poly1305_state *st, const uint8_t *m, size_t bytes) {
    if (st->leftover) {
        size_t want = 16 - st->leftover;
        if (want > bytes) {
            want = bytes;
        }
        memcpy(st->buffer + st->leftover, m, want);
        bytes -= want;
        m += want;
        st->leftover += want;
        if (st->leftover < 16) {
            return;
        }
        poly1305_blocks(st, st->buffer, 16);
        st->leftover = 0;
    }
    if (bytes >= 16) {
        size_t want = bytes & ~(size_t)15;
        poly1305_blocks(st, m, want);
        m += want;
        bytes -= want;
    }
    if (bytes) {
        memcpy(st->buffer + st->leftover, m, bytes);
        st->leftover += bytes;
    }
}

/* RFC 8439：AAD 与密文各自补零到 16 字节边界 */
static void poly1305_update_padded(poly1305_state *st, const uint8_t *m, size_t bytes) {
    static const uint8_t zero[16] = {0};
    poly1305_update(st, m, bytes);
    if (bytes % 16 != 0) {
        poly1305_update(st, zero, 16 - (bytes % 16));
    }
}

static void poly1305_finish(poly1305_state *st, uint8_t mac[16]) {
    uint32_t h0, h1, h2, h3, h4, c;
    uint32_t g0, g1, g2, g3, g4;
    uint64_t f;
    uint32_t mask;

    if (st->leftover) {
        size_t i = st->leftover;
        st->buffer[i++] = 1;
        for (; i < 16; i++) {
            st->buffer[i] = 0;
        }
        st->final = 1;
        poly1305_blocks(st, st->buffer, 16);
    }

    h0 = st->h[0]; h1 = st->h[1]; h2 = st->h[2]; h3 = st->h[3]; h4 = st->h[4];

    c = h1 >> 26; h1 &= 0x3ffffff;
    h2 += c; c = h2 >> 26; h2 &= 0x3ffffff;
    h3 += c; c = h3 >> 26; h3 &= 0x3ffffff;
    h4 += c; c = h4 >> 26; h4 &= 0x3ffffff;
    h0 += c * 5; c = h0 >> 26; h0 &= 0x3ffffff;
    h1 += c;

    /* h + -p */
    g0 = h0 + 5; c = g0 >> 26; g0 &= 0x3ffffff;
    g1 = h1 + c; c = g1 >> 26; g1 &= 0x3ffffff;
    g2 = h2 + c; c = g2 >> 26; g2 &= 0x3ffffff;
    g3 = h3 + c; c = g3 >> 26; g3 &= 0x3ffffff;
    g4 = h4 + c - (1u << 26);

    /* h < p 时取 h，否则取 h-p */
    mask = (g4 >> 31) - 1;
    g0 &= mask; g1 &= mask; g2 &= mask; g3 &= mask; g4 &= mask;
    mask = ~mask;
    h0 = (h0 & mask) | g0;
    h1 = (h1 & mask) | g1;
    h2 = (h2 & mask) | g2;
    h3 = (h3 & mask) | g3;
    h4 = (h4 & mask) | g4;

    /* h = h % 2^128 */
    h0 = ((h0) | (h1 << 26)) & 0xffffffffu;
    h1 = ((h1 >> 6) | (h2 << 20)) & 0xffffffffu;
    h2 = ((h2 >> 12) | (h3 << 14)) & 0xffffffffu;
    h3 = ((h3 >> 18) | (h4 << 8)) & 0xffffffffu;

    /* mac = (h + pad) % 2^128 */
    f = (uint64_t)h0 + st->pad[0];              h0 = (uint32_t)f;
    f = (uint64_t)h1 + st->pad[1] + (f >> 32);  h1 = (uint32_t)f;
    f = (uint64_t)h2 + st->pad[2] + (f >> 32);  h2 = (uint32_t)f;
    f = (uint64_t)h3 + st->pad[3] + (f >> 32);  h3 = (uint32_t)f;

    store32le(mac + 0, h0);
    store32le(mac + 4, h1);
    store32le(mac + 8, h2);
    store32le(mac + 12, h3);

    chacha20_memzero(st, sizeof(*st));
}

/* ------------------------- ChaCha20-Poly1305 ------------------------- */

static void poly1305_auth(uint8_t tag[16], const uint8_t *m, size_t bytes,
                          const uint8_t key[32]) {
    poly1305_state st;
    poly1305_init(&st, key);
    poly1305_update(&st, m, bytes);
    poly1305_finish(&st, tag);
}

void chacha20poly1305_encrypt(uint8_t *out, const uint8_t *in, size_t len,
                              const uint8_t key[32], const uint8_t nonce[12],
                              const uint8_t *aad, size_t aad_len,
                              uint8_t tag[16]) {
    uint8_t polykey[64];
    uint8_t lens[16];
    poly1305_state st;

    /* Poly1305 的密钥 = ChaCha20 第 0 块的前 32 字节 */
    chacha20_block(polykey, key, nonce, 0);

    if (len > 0) {
        memcpy(out, in, len);
        chacha20_xor(out, len, key, nonce, 1);
    }

    poly1305_init(&st, polykey);
    poly1305_update_padded(&st, aad, aad_len);
    poly1305_update_padded(&st, out, len);
    store64le(lens, (uint64_t)aad_len);
    store64le(lens + 8, (uint64_t)len);
    poly1305_update(&st, lens, 16);
    poly1305_finish(&st, tag);

    chacha20_memzero(polykey, sizeof(polykey));
}

int chacha20poly1305_decrypt(uint8_t *out, const uint8_t *in, size_t len,
                             const uint8_t key[32], const uint8_t nonce[12],
                             const uint8_t *aad, size_t aad_len,
                             const uint8_t tag[16]) {
    uint8_t polykey[64];
    uint8_t lens[16];
    uint8_t expected[16];
    poly1305_state st;
    uint8_t diff = 0;
    int i;

    chacha20_block(polykey, key, nonce, 0);

    poly1305_init(&st, polykey);
    poly1305_update_padded(&st, aad, aad_len);
    poly1305_update_padded(&st, in, len);
    store64le(lens, (uint64_t)aad_len);
    store64le(lens + 8, (uint64_t)len);
    poly1305_update(&st, lens, 16);
    poly1305_finish(&st, expected);

    /* 常量时间比较，避免按字节提前返回 */
    for (i = 0; i < 16; i++) {
        diff |= (uint8_t)(expected[i] ^ tag[i]);
    }
    chacha20_memzero(polykey, sizeof(polykey));
    chacha20_memzero(expected, sizeof(expected));

    if (diff != 0) {
        return -1;
    }
    if (len > 0) {
        if (out != in) {
            memcpy(out, in, len);
        }
        chacha20_xor(out, len, key, nonce, 1);
    }
    return 0;
}

/* ------------------------------------------------------------------ */
#ifdef CHACHA20_TEST
#include <stdio.h>

static int hexeq(const uint8_t *got, const char *hex, size_t n) {
    size_t i;
    for (i = 0; i < n; i++) {
        unsigned v;
        if (sscanf(hex + i * 2, "%2x", &v) != 1 || got[i] != (uint8_t)v) {
            return 0;
        }
    }
    return 1;
}

static void fromhex(uint8_t *out, const char *hex) {
    size_t i;
    for (i = 0; hex[i] && hex[i + 1]; i += 2) {
        unsigned v;
        sscanf(hex + i, "%2x", &v);
        out[i / 2] = (uint8_t)v;
    }
}

int main(void) {
    int bad = 0;

    /* ① RFC 8439 §2.3.2：块函数（counter=1，nonce=000000090000004a00000000） */
    {
        uint8_t key[32], nonce[12] = {0}, ks[64] = {0}, n2[12] = {0};
        int i;
        for (i = 0; i < 32; i++) key[i] = (uint8_t)i;
        n2[3] = 0x09; n2[7] = 0x4a;
        (void)nonce;
        chacha20_xor(ks, 64, key, n2, 1);
        if (hexeq(ks, "10f1e7e4d13b5915500fdd1fa32071c4", 16)) {
            printf("  ✔ §2.3.2 ChaCha20 块函数\n");
        } else {
            printf("  ✘ §2.3.2 块函数不符: ");
            for (i = 0; i < 16; i++) printf("%02x", ks[i]);
            printf("\n");
            bad++;
        }
    }

    /* ② RFC 8439 §2.5.2：Poly1305 单独已知答案 */
    {
        uint8_t key[32], msg[64], tag[16];
        int i;
        fromhex(key, "85d6be7857556d337f4452fe42d506a8"
                     "0103808afb0db2fd4abff6af4149f51b");
        fromhex(msg, "43727970746f6772617068696320466f72756d"
                     "2052657365617263682047726f7570");
        poly1305_auth(tag, msg, 34, key);
        if (hexeq(tag, "a8061dc1305136c6c22b8baf0c0127a9", 16)) {
            printf("  ✔ §2.5.2 Poly1305\n");
        } else {
            printf("  ✘ §2.5.2 Poly1305 不符: ");
            for (i = 0; i < 16; i++) printf("%02x", tag[i]);
            printf("\n");
            bad++;
        }
    }

    /* ③ RFC 8439 §2.8.2：AEAD 完整已知答案 */
    {
        uint8_t key[32], nonce[12], aad[12], tag[16], out[114];
        const char *plain = "Ladies and Gentlemen of the class of '99: If I could "
                            "offer you only one tip for the future, sunscreen "
                            "would be it.";
        size_t plen = strlen(plain);
        int i;

        fromhex(key, "808182838485868788898a8b8c8d8e8f"
                     "909192939495969798999a9b9c9d9e9f");
        fromhex(nonce, "070000004041424344454647");
        fromhex(aad, "50515253c0c1c2c3c4c5c6c7");

        chacha20poly1305_encrypt(out, (const uint8_t *)plain, plen,
                                 key, nonce, aad, 12, tag);
        if (!hexeq(out, "d31a8d34648e60db7b86afbc53ef7ec2"
                        "a4aded51296e08fea9e2b5a736ee62d6"
                        "3dbea45e8ca9671282fafb69da92728b"
                        "1a71de0a9e060b2905d6a5b67ecd3b36"
                        "92ddbd7f2d778b8c9803aee328091b58"
                        "fab324e4fad675945585808b4831d7bc"
                        "3ff4def08e4b7a9de576d26586cec64b"
                        "6116", 114)) {
            printf("  ✘ §2.8.2 AEAD 密文不符: ");
            for (i = 0; i < 16; i++) printf("%02x", out[i]);
            printf("...\n");
            bad++;
        } else if (hexeq(tag, "1ae10b594f09e26a7e902ecbd0600691", 16)) {
            printf("  ✔ §2.8.2 AEAD 密文与标签\n");
        } else {
            printf("  ✘ §2.8.2 AEAD 标签不符: ");
            for (i = 0; i < 16; i++) printf("%02x", tag[i]);
            printf("\n");
            bad++;
        }

        /* 解密回原文 */
        if (chacha20poly1305_decrypt(out, out, plen, key, nonce, aad, 12, tag) == 0
                && memcmp(out, plain, plen) == 0) {
            printf("  ✔ AEAD 解密还原\n");
        } else {
            printf("  ✘ AEAD 解密失败\n");
            bad++;
        }

        /* 篡改密文一个比特 → 必须拒绝 */
        out[0] ^= 0x01;
        {
            uint8_t tmp[114];
            chacha20poly1305_encrypt(tmp, (const uint8_t *)plain, plen,
                                     key, nonce, aad, 12, tag);
            tmp[3] ^= 0x80;
            if (chacha20poly1305_decrypt(out, tmp, plen, key, nonce, aad, 12, tag) != 0) {
                printf("  ✔ 篡改密文被拒绝\n");
            } else {
                printf("  ✘ 篡改密文未被发现\n");
                bad++;
            }
            /* 篡改 AAD → 必须拒绝 */
            aad[0] ^= 0xff;
            if (chacha20poly1305_decrypt(out, tmp, plen, key, nonce, aad, 12, tag) != 0) {
                printf("  ✔ 篡改 AAD 被拒绝\n");
            } else {
                printf("  ✘ 篡改 AAD 未被发现\n");
                bad++;
            }
        }
    }

    /* ④ 往返 + 跨块长度 */
    {
        uint8_t key[32], nonce[12] = {0}, a[130], b[130], tag[16];
        int i;
        for (i = 0; i < 32; i++) key[i] = (uint8_t)(i * 7 + 1);
        nonce[11] = 0x5a;
        for (i = 0; i < 130; i++) a[i] = b[i] = (uint8_t)(i * 3);
        chacha20poly1305_encrypt(a, a, 130, key, nonce, NULL, 0, tag);
        if (memcmp(a, b, 130) != 0
                && chacha20poly1305_decrypt(a, a, 130, key, nonce, NULL, 0, tag) == 0
                && memcmp(a, b, 130) == 0) {
            printf("  ✔ 130 字节跨块往返（无 AAD）\n");
        } else {
            printf("  ✘ 跨块往返失败\n");
            bad++;
        }
    }

    printf(bad == 0 ? "全部通过\n" : "有 %d 项失败\n", bad);
    return bad ? 1 : 0;
}
#endif
