#include "luax.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "chacha20.h"
#include "lauxlib.h"

/* 演示密钥：正式发布前务必替换，并按文档建议拆成「so 常量 + 运行时派生」两片 */
static const uint8_t LUAX_KEY[32] = {
    0x69, 0x79, 0x57, 0x7a, 0xd6, 0x04, 0x77, 0x57,
    0x5e, 0xe3, 0x16, 0xe0, 0x0b, 0xbc, 0xcf, 0x00,
    0x66, 0xd6, 0xda, 0x4a, 0xbf, 0x63, 0xec, 0x57,
    0xc8, 0x85, 0x4c, 0xc1, 0x7c, 0xe4, 0xbb, 0x7b
};

int luax_is_encrypted(const char *s, size_t n) {
    return n >= LUAX_HDR && memcmp(s, LUAX_MAGIC_STR, 4) == 0;
}

int luax_decrypt_load(lua_State *L, const char *s, size_t n,
                      const char *chunkname) {
    const uint8_t *p = (const uint8_t *)s;
    uint32_t plain_len;
    uint8_t *plain;
    int mode, rc;

    if (!luax_is_encrypted(s, n)) {
        lua_pushliteral(L, "LUAX: 头部校验失败");
        return LUA_ERRSYNTAX;
    }
    if (p[4] != LUAX_VERSION) {
        lua_pushfstring(L, "LUAX: 版本不匹配（文件 %d，运行时 %d）",
                        (int)p[4], (int)LUAX_VERSION);
        return LUA_ERRSYNTAX;
    }
    plain_len = (uint32_t)p[20] | ((uint32_t)p[21] << 8)
              | ((uint32_t)p[22] << 16) | ((uint32_t)p[23] << 24);
    if (plain_len == 0 || (size_t)plain_len != n - LUAX_HDR) {
        lua_pushliteral(L, "LUAX: 长度字段与文件实际大小不符");
        return LUA_ERRSYNTAX;
    }
    mode = (p[5] & LUAX_FLAG_BYTECODE) ? 1 : 0;

    plain = (uint8_t *)malloc(plain_len);
    if (plain == NULL) {
        lua_pushliteral(L, "LUAX: 解密缓冲分配失败");
        return LUA_ERRMEM;
    }
    memcpy(plain, p + LUAX_HDR, plain_len);
    chacha20_xor(plain, plain_len, LUAX_KEY, p + 8, 1);
    rc = luaL_loadbufferx(L, (const char *)plain, plain_len, chunkname,
                          mode ? "b" : "t");
    memset(plain, 0, plain_len);
    free(plain);
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
    if (got != sizeof(head) || !luax_is_encrypted((const char *)head, got)) {
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

uint8_t *luax_encrypt(const uint8_t *data, size_t n, size_t *outlen) {
    uint8_t nonce[12];
    uint8_t *plain, *out;
    size_t total;
    int is_bytecode;

    if (data == NULL || n == 0 || n > 0x7fffffffu) {
        return NULL;
    }
    if (!luax_random_nonce(nonce)) {
        return NULL;               /* 拿不到随机数就失败，绝不用固定 nonce */
    }
    total = (size_t)LUAX_HDR + n;
    plain = (uint8_t *)malloc(n);
    out = (uint8_t *)malloc(total);
    if (plain == NULL || out == NULL) {
        free(plain);
        free(out);
        return NULL;
    }
    memcpy(plain, data, n);
    /* 打包装的是 console.build 编译后的字节码，按 \x1bLua 头自动置 flags */
    is_bytecode = (n >= 4 && plain[0] == 0x1b
                   && memcmp(plain + 1, "Lua", 3) == 0) ? 1 : 0;
    chacha20_xor(plain, n, LUAX_KEY, nonce, 1);

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
    memcpy(out + LUAX_HDR, plain, n);

    memset(plain, 0, n);
    free(plain);
    *outlen = total;
    return out;
}
