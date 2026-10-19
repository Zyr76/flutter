/* chacha20.c —— RFC 8439 ChaCha20 流加密精简实现
 *
 * 编译自测：
 *   cc -DCHACHA20_TEST -o /tmp/t_chacha chacha20.c && /tmp/t_chacha
 * 测试含 RFC 8439 §2.3.2 的块函数已知答案，以及往返加解密。
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

static uint32_t load32le(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8)
         | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void chacha20_block(uint8_t ks[64], const uint8_t key[32],
                           const uint8_t nonce[12], uint32_t counter) {
    uint32_t st[16], x[16];
    int i;

    st[0] = 0x61707865; st[1] = 0x3320646e;
    st[2] = 0x79622d32; st[3] = 0x6b206574;      /* "expand 32-byte k" */
    for (i = 0; i < 8; i++) st[4 + i] = load32le(key + i * 4);
    st[12] = counter;
    st[13] = load32le(nonce);
    st[14] = load32le(nonce + 4);
    st[15] = load32le(nonce + 8);

    memcpy(x, st, sizeof(x));
    for (i = 0; i < 10; i++) {
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
        uint32_t v = x[i] + st[i];
        ks[i * 4]     = (uint8_t)(v);
        ks[i * 4 + 1] = (uint8_t)(v >> 8);
        ks[i * 4 + 2] = (uint8_t)(v >> 16);
        ks[i * 4 + 3] = (uint8_t)(v >> 24);
    }
    memset(st, 0, sizeof(st));
    memset(x, 0, sizeof(x));
}

void chacha20_xor(uint8_t *data, size_t len, const uint8_t key[32],
                  const uint8_t nonce[12], uint32_t counter) {
    uint8_t ks[64];
    size_t off = 0;

    while (off < len) {
        size_t n = len - off < 64 ? len - off : 64;
        size_t i;
        chacha20_block(ks, key, nonce, counter + (uint32_t)(off / 64));
        for (i = 0; i < n; i++) data[off + i] ^= ks[i];
        off += n;
    }
    memset(ks, 0, sizeof(ks));
}

/* ------------------------------------------------------------------ */
#ifdef CHACHA20_TEST
#include <stdio.h>

static int hexeq(const uint8_t *got, const char *hex, size_t n) {
    size_t i;
    for (i = 0; i < n; i++) {
        unsigned v;
        if (sscanf(hex + i * 2, "%2x", &v) != 1 || got[i] != (uint8_t)v) return 0;
    }
    return 1;
}

int main(void) {
    int bad = 0;
    uint8_t key[32], nonce[12], buf[114];
    const char *plain = "Ladies and Gentlemen of the class of '99: If I could "
                        "offer you only one tip for the future, sunscreen would be it.";
    size_t plen = strlen(plain);

    /* RFC 8439 §2.4.2 的 key / nonce */
    for (int i = 0; i < 32; i++) key[i] = (uint8_t)i;
    memset(nonce, 0, sizeof(nonce));
    nonce[7] = 0x4a;

    /* ① 块函数已知答案（§2.3.2，counter=1 的 keystream 前 16 字节） */
    {
        uint8_t zero[64] = {0}, ks[64];
        uint8_t n2[12] = {0};
        n2[3] = 0x09; n2[7] = 0x4a;  /* 000000090000004a00000000 */
        memcpy(ks, zero, 64);
        chacha20_xor(ks, 64, key, n2, 1);
        if (hexeq(ks, "10f1e7e4d13b5915500fdd1fa32071c4", 16)) {
            printf("  ✔ RFC 8439 §2.3.2 块函数已知答案\n");
        } else {
            printf("  ✘ 块函数已知答案不符：");
            for (int i = 0; i < 16; i++) printf("%02x", ks[i]);
            printf("\n");
            bad++;
        }
    }

    /* ② 往返加解密 */
    memcpy(buf, plain, plen);
    chacha20_xor(buf, plen, key, nonce, 1);
    if (memcmp(buf, plain, plen) != 0) printf("  ✔ 加密后内容已改变\n");
    else { printf("  ✘ 加密后内容未变\n"); bad++; }
    chacha20_xor(buf, plen, key, nonce, 1);
    if (memcmp(buf, plain, plen) == 0) printf("  ✔ 往返解密还原\n");
    else { printf("  ✘ 往返解密失败\n"); bad++; }

    /* ③ 跨块（>64 字节）与非对齐长度 */
    {
        uint8_t a[130], b[130];
        for (int i = 0; i < 130; i++) a[i] = b[i] = (uint8_t)(i * 7);
        chacha20_xor(a, 130, key, nonce, 1);
        chacha20_xor(a, 130, key, nonce, 1);   /* 第二次抵消为原文 */
        if (memcmp(a, b, 130) == 0) printf("  ✔ 130 字节跨块往返\n");
        else { printf("  ✘ 跨块往返失败\n"); bad++; }
    }

    printf(bad == 0 ? "全部通过\n" : "有 %d 项失败\n", bad);
    return bad ? 1 : 0;
}
#endif
