#include "luax.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "chacha20.h"
#include "lauxlib.h"

/* 密钥分片：32 字节密钥拆成两半，两半都不以明文存储。
 * K_A / K_B 分别是「前半 ^ M1」「后半 ^ M2」的结果，
 * 掩码在运行期由与密钥无关的常量按固定规则算出，因此：
 *   - 直接 dump .rodata 看不到密钥；
 *   - 必须把这两段代码一起逆向才能还原。
 * 注意：这提高的是「取密钥的门槛」，不是数学意义上的保密——密钥最终仍以此进程内
 * 的形式存在，能读进程内存的攻击者依然可以拿到。 */
static const uint8_t K_A[16] = {
    0xe0, 0x81, 0xc8, 0x8c, 0xa3, 0x90, 0xcc, 0x85,
    0x0f, 0x53, 0xc1, 0xce, 0x36, 0xd0, 0x3c, 0x0a,
};
static const uint8_t K_B[16] = {
    0x85, 0x43, 0x4a, 0xf0, 0x00, 0x32, 0xb8, 0x29,
    0xb3, 0x98, 0x54, 0xf3, 0x4b, 0x3d, 0x67, 0x8d,
};

static uint8_t g_key[32];
static int g_key_ready = 0;

static void luax_build_key(void) {
    int i;
    if (g_key_ready) {
        return;
    }
    for (i = 0; i < 16; i++) {
        uint8_t m1 = (uint8_t)(((0x37 * (i + 1) + 0x5A) & 0xFF)
                               ^ ((0x18 << (i & 3)) & 0xFF));
        uint8_t m2 = (uint8_t)(((0x9E + (i + 1) * 17) & 0xFF)
                               ^ (uint8_t)LUAX_MAGIC_STR[i & 3]);
        g_key[i] = (uint8_t)(K_A[i] ^ m1);
        g_key[16 + i] = (uint8_t)(K_B[i] ^ m2);
    }
    g_key_ready = 1;
}

/* 库加载时组装一次；并发首次调用写的值相同，属良性竞争 */
__attribute__((constructor))
static void luax_key_ctor(void) {
    luax_build_key();
}

static const uint8_t *luax_key(void) {
    luax_build_key();
    return g_key;
}

/* ===================== 外层 base64 =====================
 * 密文以 ASCII 承载，便于文本通道传输、也能被 Java String 安全传递：
 *     LUAXB64\n<base64(头+密文+标签)，每行 76 字符>
 * AEAD 校验发生在 base64 解码之后，不受外层编码影响。
 */
static const char B64_CHARS[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static int luax_b64_val(int c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

/* 编码：返回 malloc 的字符串（末尾有 \0），*outlen 不含 \0 */
static char *luax_b64_encode(const uint8_t *in, size_t n, size_t *outlen) {
    size_t cap = 4 * ((n + 2) / 3);
    size_t total = LUAX_B64_MAGIC_LEN + 2 + cap + cap / 76 + 2;
    char *out = (char *)malloc(total);
    size_t o = 0, i, col = 0;

    if (out == NULL) {
        return NULL;
    }
    memcpy(out, LUAX_B64_MAGIC, LUAX_B64_MAGIC_LEN);
    o = LUAX_B64_MAGIC_LEN;
    out[o++] = '\n';
    for (i = 0; i < n; i += 3) {
        uint32_t v = (uint32_t)in[i] << 16;
        size_t rem = n - i;
        if (rem > 1) {
            v |= (uint32_t)in[i + 1] << 8;
        }
        if (rem > 2) {
            v |= (uint32_t)in[i + 2];
        }
        out[o++] = B64_CHARS[(v >> 18) & 0x3F];
        out[o++] = B64_CHARS[(v >> 12) & 0x3F];
        out[o++] = (rem > 1) ? B64_CHARS[(v >> 6) & 0x3F] : '=';
        out[o++] = (rem > 2) ? B64_CHARS[v & 0x3F] : '=';
        col += 4;
        if (col >= 76) {
            out[o++] = '\n';
            col = 0;
        }
    }
    if (col != 0) {
        out[o++] = '\n';
    }
    out[o] = '\0';
    *outlen = o;
    return out;
}

/* 解码：忽略空白，遇到 '=' 结束。失败返回 NULL */
static uint8_t *luax_b64_decode(const char *s, size_t n, size_t *outlen) {
    uint8_t *out = (uint8_t *)malloc(n / 4 * 3 + 4);
    uint32_t acc = 0;
    size_t o = 0, i;
    int bits = 0;

    if (out == NULL) {
        return NULL;
    }
    for (i = 0; i < n; i++) {
        int c = (unsigned char)s[i];
        int v;
        if (c == '\r' || c == '\n' || c == ' ' || c == '\t') {
            continue;
        }
        if (c == '=') {
            break;
        }
        v = luax_b64_val(c);
        if (v < 0) {
            free(out);
            return NULL;
        }
        acc = (acc << 6) | (uint32_t)v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out[o++] = (uint8_t)((acc >> bits) & 0xFF);
        }
    }
    *outlen = o;
    return out;
}

int luax_is_encrypted(const char *s, size_t n) {
    return n > LUAX_B64_MAGIC_LEN
        && memcmp(s, LUAX_B64_MAGIC, LUAX_B64_MAGIC_LEN) == 0;
}

/* 解析内层二进制（头 + 密文 + 标签） */
static int luax_load_blob(lua_State *L, const char *s, size_t n,
                          const char *chunkname) {
    const uint8_t *p = (const uint8_t *)s;
    uint32_t plain_len;
    uint8_t *plain;
    int mode, rc;

    if (n < LUAX_HDR || memcmp(s, LUAX_MAGIC_STR, 4) != 0) {
        lua_pushliteral(L, "LUAX: 内层头部校验失败");
        return LUA_ERRSYNTAX;
    }
    if (p[4] != LUAX_VERSION) {
        lua_pushfstring(L, "LUAX: 不支持的密文版本 %d（需要 %d）",
                        (int)p[4], (int)LUAX_VERSION);
        return LUA_ERRSYNTAX;
    }
    plain_len = (uint32_t)p[20] | ((uint32_t)p[21] << 8)
              | ((uint32_t)p[22] << 16) | ((uint32_t)p[23] << 24);
    /* 密文后带 16 字节标签；头部 24 字节作为 AAD 参与认证，
     * 因此 magic/version/flags/nonce/长度 任何一项被改都会校验失败。 */
    if (plain_len == 0 || n < (size_t)LUAX_HDR + LUAX_TAG_LEN
            || (size_t)plain_len != n - LUAX_HDR - LUAX_TAG_LEN) {
        lua_pushliteral(L, "LUAX: 长度字段与文件实际大小不符");
        return LUA_ERRSYNTAX;
    }
    mode = (p[5] & LUAX_FLAG_BYTECODE) ? 1 : 0;

    plain = (uint8_t *)malloc(plain_len);
    if (plain == NULL) {
        lua_pushliteral(L, "LUAX: 解密缓冲分配失败");
        return LUA_ERRMEM;
    }
    if (chacha20poly1305_decrypt(plain, p + LUAX_HDR, plain_len, luax_key(),
                                 p + 8, p, LUAX_HDR,
                                 p + LUAX_HDR + plain_len) != 0) {
        chacha20_memzero(plain, plain_len);
        free(plain);
        lua_pushliteral(L, "LUAX: 密文校验失败（文件被篡改或密钥不匹配）");
        return LUA_ERRSYNTAX;
    }
    rc = luaL_loadbufferx(L, (const char *)plain, plain_len, chunkname,
                          mode ? "b" : "t");
    chacha20_memzero(plain, plain_len);
    free(plain);
    return rc;
}

int luax_decrypt_load(lua_State *L, const char *s, size_t n,
                      const char *chunkname) {
    uint8_t *blob;
    size_t dlen = 0;
    int rc;

    if (!luax_is_encrypted(s, n)) {
        lua_pushliteral(L, "LUAX: 不是 LUAX 密文（缺少 LUAXB64 头）");
        return LUA_ERRSYNTAX;
    }
    blob = luax_b64_decode(s + LUAX_B64_MAGIC_LEN, n - LUAX_B64_MAGIC_LEN, &dlen);
    if (blob == NULL) {
        lua_pushliteral(L, "LUAX: base64 解码失败");
        return LUA_ERRSYNTAX;
    }
    rc = luax_load_blob(L, (const char *)blob, dlen, chunkname);
    chacha20_memzero(blob, dlen);
    free(blob);
    return rc;
}

int luax_loadfile(lua_State *L, const char *filename, const char *mode) {
    FILE *f;
    uint8_t head[LUAX_HDR];
    uint8_t *buf;
    long size;
    size_t got;
    int rc;
    size_t name_len;
    char *chunk;

    (void)mode;
    f = fopen(filename, "rb");
    if (f == NULL) {
        return -1;                 /* 交给原有流程报 open 错误 */
    }
    got = fread(head, 1, sizeof(head), f);
    if (got < LUAX_B64_MAGIC_LEN + 1
            || !luax_is_encrypted((const char *)head, got)) {
        fclose(f);
        return -1;
    }
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return -1;
    }
    size = ftell(f);
    if (size < (long)sizeof(head)) {
        fclose(f);
        return -1;
    }
    rewind(f);
    buf = (uint8_t *)malloc((size_t)size);
    if (buf == NULL) {
        fclose(f);
        lua_pushliteral(L, "LUAX: 内存不足");
        return LUA_ERRMEM;
    }
    got = fread(buf, 1, (size_t)size, f);
    fclose(f);
    if (got != (size_t)size) {
        free(buf);
        lua_pushliteral(L, "LUAX: 读取失败");
        return LUA_ERRSYNTAX;
    }

    name_len = strlen(filename);
    chunk = (char *)malloc(name_len + 2);
    if (chunk != NULL) {
        chunk[0] = '@';
        memcpy(chunk + 1, filename, name_len + 1);
    }
    rc = luax_decrypt_load(L, (const char *)buf, (size_t)size,
                           chunk != NULL ? chunk : filename);
    free(chunk);
    free(buf);
    return rc;
}

/* ------------------------------------------------------------------ */

static int luax_random_nonce(uint8_t nonce[12]) {
    FILE *f = fopen("/dev/urandom", "rb");
    size_t got;
    if (f == NULL) {
        return 0;
    }
    got = fread(nonce, 1, 12, f);
    fclose(f);
    return got == 12;
}

unsigned char *luax_encrypt(const unsigned char *data, size_t n, size_t *outlen) {
    uint8_t nonce[12];
    uint8_t *out;
    size_t total;
    int is_bytecode;

    if (data == NULL || n == 0 || n > 0x7fffffffu) {
        return NULL;
    }
    if (!luax_random_nonce(nonce)) {
        return NULL;               /* 拿不到随机数就失败，绝不用固定 nonce */
    }
    total = (size_t)LUAX_HDR + n + LUAX_TAG_LEN;
    out = (uint8_t *)malloc(total);
    if (out == NULL) {
        return NULL;
    }
    /* 打包装的是 console.build 编译后的字节码，按 \x1bLua 头自动置 flags */
    is_bytecode = (n >= 4 && data[0] == 0x1b
                   && memcmp(data + 1, "Lua", 3) == 0) ? 1 : 0;

    memcpy(out, LUAX_MAGIC_STR, 4);
    out[4] = (uint8_t)LUAX_VERSION;
    out[5] = is_bytecode ? LUAX_FLAG_BYTECODE : 0;
    out[6] = 0;
    out[7] = 0;
    memcpy(out + 8, nonce, 12);
    out[20] = (uint8_t)((uint32_t)n);
    out[21] = (uint8_t)((uint32_t)n >> 8);
    out[22] = (uint8_t)((uint32_t)n >> 16);
    out[23] = (uint8_t)((uint32_t)n >> 24);

    /* 头部 24 字节作为 AAD；密文写在其后，标签再跟在密文后 */
    chacha20poly1305_encrypt(out + LUAX_HDR, data, n, luax_key(), nonce,
                             out, LUAX_HDR, out + LUAX_HDR + n);

    /* 外层套 base64：产物是纯 ASCII 文本 */
    {
        size_t txtlen = 0;
        char *txt = luax_b64_encode(out, total, &txtlen);
        chacha20_memzero(out, total);
        free(out);
        if (txt == NULL) {
            return NULL;
        }
        *outlen = txtlen;
        return (unsigned char *)txt;
    }
}
