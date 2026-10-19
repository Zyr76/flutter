/* chacha20.h —— RFC 8439 ChaCha20 流加密（无 AEAD）
 *
 * 用法：
 *   chacha20_xor(buf, len, key32, nonce12, counter);
 * 同一 key+nonce+counter 再调一次即可还原（流加密自反）。
 */
#ifndef LUAJAVA_CHACHA20_H
#define LUAJAVA_CHACHA20_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* counter 从 1 开始；0 预留给将来接 Poly1305 的密钥块 */
void chacha20_xor(uint8_t *data, size_t len, const uint8_t key[32],
                  const uint8_t nonce[12], uint32_t counter);

#ifdef __cplusplus
}
#endif

#endif
