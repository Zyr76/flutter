/* luax.h —— LUAX 加密脚本的读写入口
 *
 * 解密挂载点：lua/lauxlib.c 的 luaL_loadfilex（require/loadfile/dofile 都经过它）。
 * 加密入口：供打包模块 bin.lua 通过 com.androlua.LuaX 调用。
 */
#ifndef LUAJAVA_LUAX_H
#define LUAJAVA_LUAX_H

#include <stddef.h>

/* 只前置声明，避免把 lua.h 的包含顺序带进 lua 核心的编译单元 */
typedef struct lua_State lua_State;

#ifdef __cplusplus
extern "C" {
#endif

#define LUAX_MAGIC_STR    "LUAX"
#define LUAX_HDR          24
#define LUAX_VERSION      0x55
#define LUAX_FLAG_BYTECODE 1

int luax_is_encrypted(const char *s, size_t n);

/* 解密并加载。不是 LUAX 密文返回 -1；否则返回 lua 状态码（错误消息留在栈顶）。 */
int luax_decrypt_load(lua_State *L, const char *s, size_t n,
                      const char *chunkname);

/* 读文件判断是否为 LUAX 并加载。不是 LUAX 返回 -1（调用方走原有流程）。 */
int luax_loadfile(lua_State *L, const char *filename, const char *mode);

/* 加密任意内容（自动识别 \x1bLua 字节码头并置 flags）。
 * 成功返回 malloc 的缓冲，*outlen 为总长度；失败返回 NULL。 */
unsigned char *luax_encrypt(const unsigned char *data, size_t n, size_t *outlen);

/* 注册 LUAX 库：提供 luax.loadso(path)，并把容器 searcher 插进 package.searchers。
 * 由 luaL_openlibs 自动调用。 */
int luaopen_luax(lua_State *L);

#ifdef __cplusplus
}
#endif

#endif
