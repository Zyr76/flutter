/* chacha20.h —— RFC 8439 ChaCha20 + Poly1305 AEAD
 *
 * 提供两层：
 *   chacha20_xor()             纯流加密（兼容旧 LUAX v1 密文）
 *   chacha20poly1305_encrypt() / _decrypt()   AEAD（LUAX v2 使用）
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

/* ChaCha20 流加密。counter 从 1 开始；0 留给 AEAD 派生 Poly1305 密钥。
 * nonce 为 RFC 8439 的 96 位。 */
void chacha20_xor(uint8_t *data, size_t len, const uint8_t key[32],
                  const uint8_t nonce[12], uint32_t counter);

/* ChaCha20-Poly1305 AEAD 加密。
 * out 至少 len 字节；tag 写入 16 字节认证标签。
 * aad 可为 NULL（aad_len 需为 0）。 */
void chacha20poly1305_encrypt(uint8_t *out, const uint8_t *in, size_t len,
                              const uint8_t key[32], const uint8_t nonce[12],
                              const uint8_t *aad, size_t aad_len,
                              uint8_t tag[16]);

/* 解密并校验标签。返回 0 表示成功，-1 表示标签不匹配（此时 out 内容未定义）。 */
int chacha20poly1305_decrypt(uint8_t *out, const uint8_t *in, size_t len,
                             const uint8_t key[32], const uint8_t nonce[12],
                             const uint8_t *aad, size_t aad_len,
                             const uint8_t tag[16]);

#ifdef __cplusplus
}
#endif

#endif
