/* chacha20.h —— RFC 8439 ChaCha20 + Poly1305 AEAD
 *
 * 只暴露 AEAD 接口（ChaCha20-Poly1305）。纯流加密 chacha20_xor 是内部实现，
 * 不对外提供，避免被误用来产出无认证的密文。
 *
 * 自测：cc -DCHACHA20_TEST -o /tmp/t chacha20.c && /tmp/t
 * 含 RFC 8439 §2.3.2（块函数）、§2.5.2（Poly1305）、§2.8.2（AEAD）已知答案。
 */
#ifndef LUAJAVA_CHACHA20_H
#define LUAJAVA_CHACHA20_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ChaCha20-Poly1305 AEAD 加密。
 * out 至少 len 字节；tag 写入 16 字节认证标签。
 * aad 可为 NULL（aad_len 需为 0）。 */
void chacha20poly1305_encrypt(uint8_t *out, const uint8_t *in, size_t len,
                              const uint8_t key[32], const uint8_t nonce[12],
                              const uint8_t *aad, size_t aad_len,
                              uint8_t tag[16]);

/* 安全清零：用 volatile 写，避免被编译器当成死存储优化掉（清密钥/明文字段时必须用它，
 * 不能用 memset）。 */
void chacha20_memzero(void *p, size_t n);

/* 解密并校验标签。返回 0 表示成功，-1 表示标签不匹配（此时 out 内容未定义）。 */
int chacha20poly1305_decrypt(uint8_t *out, const uint8_t *in, size_t len,
                             const uint8_t key[32], const uint8_t nonce[12],
                             const uint8_t *aad, size_t aad_len,
                             const uint8_t tag[16]);

#ifdef __cplusplus
}
#endif

#endif
