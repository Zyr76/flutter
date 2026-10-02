/*
** lua_yyjson.c —— yyjson 的 Lua 绑定（单文件，零第三方依赖）
**
** 用法（与项目里已有的 cjson 保持同一套习惯，可以直接替换）：
**   local yyjson = require "yyjson"
**   local s = yyjson.encode({ a = 1, list = { 1, 2, 3 } })          -- 紧凑
**   local s = yyjson.encode(t, { indent = 2, sortKeys = true })     -- 美化 / 键排序
**   local v = yyjson.decode('{"a":1}')                              -- 解码
**   local v, err, pos = yyjson.decode("{bad json")                  -- 失败：nil, 错误, 位置
**   yyjson.decode(s, { comments = true, trailingCommas = true })    -- 允许扩展语法
**   yyjson.null        -- JSON null 的哨兵（像 cjson.null 那样用）
**   yyjson.version()   -- 底层 yyjson 版本号
**
** 语义（对齐 cjson，便于迁移）：
**   * 表 -> 数组的条件：键全是正整数（>=1）。空洞补 null，例如 {[1]=1,[3]=3} -> [1,null,3]；
**   * 空表编码成 {}（对象）；想让空表变成 []，用编码选项 { emptyArray = true }；
**   * 数字键在对象里会转成字符串键（{"1":...}），和 cjson 一致；
**   * function / thread / 普通 userdata 不能编码，会抛错；NaN / Inf 默认抛错，可用 { allowNaN = true } 放行；
**   * 解码时 JSON null 变成 yyjson.null（Lua 的 nil 放不进表，所以不能直接映射成 nil）；
**     想“把 null 当 nil 处理”就比一下：if v == yyjson.null then ... end
**   * 编码循环引用的表会在超过 200 层时报错，不会栈溢出。
*/

#include <lua.h>
#include <lauxlib.h>

#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "yyjson.h"

/* 嵌套深度上限：防循环引用打爆栈 */
#define LYYJSON_MAX_DEPTH 200

/* null 哨兵：模块的 null 字段与解码时写入的值必须是同一个指针 */
static const char yyjson_null_sentinel = 0;

/* ------------------------------------------------------------------ */
/* 编码：Lua -> yyjson mutable doc                                    */
/* ------------------------------------------------------------------ */

typedef struct {
    lua_State *L;
    yyjson_mut_doc *doc;
    yyjson_write_flag flags;
    int sort_keys;
    int empty_array;
    int allow_nan;
    char err[256]; /* 第一个错误信息；非空表示编码失败 */
} encode_ctx;

/* 记录错误（只记第一条），递归里不用 luaL_error，避免 longjmp 泄漏已分配的 doc */
static void set_err(encode_ctx *ctx, const char *fmt, ...) {
    va_list ap;
    if (ctx->err[0] != '\0') {
        return;
    }
    va_start(ap, fmt);
    vsnprintf(ctx->err, sizeof(ctx->err), fmt, ap);
    va_end(ap);
}

static yyjson_mut_val *lua_to_yyjson(encode_ctx *ctx, int idx, int depth);

/* 把可能是相对下标的位置转成绝对下标；栈随后怎么变都不会失效 */
static int abs_index(lua_State *L, int idx) {
    return idx > 0 ? idx : lua_gettop(L) + idx + 1;
}

/* 对象的键：字符串直接用；数字格式化成字符串；其它类型报错 */
static const char *obj_key_string(encode_ctx *ctx, lua_State *L, int idx, char *buf, size_t buflen) {
    if (lua_type(L, idx) == LUA_TSTRING) {
        return lua_tostring(L, idx);
    }
    if (lua_type(L, idx) == LUA_TNUMBER) {
        if (lua_isinteger(L, idx)) {
            snprintf(buf, buflen, LUA_INTEGER_FMT, (lua_Integer)lua_tointeger(L, idx));
        } else {
            snprintf(buf, buflen, "%.14g", (double)lua_tonumber(L, idx));
        }
        return buf;
    }
    set_err(ctx, "yyjson.encode: 不支持的表键类型 %s", luaL_typename(L, idx));
    return NULL;
}

/* 表里是否有「非正整数键」——有就是对象，没有就算数组 */
static int table_has_nonarray_key(lua_State *L, int idx, lua_Integer *max_index) {
    lua_Integer max = 0;
    int nonarray = 0;
    idx = abs_index(L, idx);
    lua_checkstack(L, 2);
    lua_pushnil(L);
    while (lua_next(L, idx) != 0) {
        if (lua_type(L, -2) == LUA_TNUMBER && lua_isinteger(L, -2) && lua_tointeger(L, -2) >= 1) {
            if (lua_tointeger(L, -2) > max) {
                max = lua_tointeger(L, -2);
            }
            lua_pop(L, 1); /* 只弹 value，留 key 继续迭代 */
        } else {
            nonarray = 1;
            lua_pop(L, 2);
            break;
        }
    }
    *max_index = max;
    return nonarray;
}

static int cmp_key(const void *a, const void *b) {
    return strcmp(*(const char *const *)a, *(const char *const *)b);
}

/* 对象编码：不排序就一遍写出；排序就先收进临时表，按键排好序再写 */
static yyjson_mut_val *encode_object(encode_ctx *ctx, int idx, int depth) {
    lua_State *L = ctx->L;
    yyjson_mut_val *obj;
    idx = abs_index(L, idx);
    obj = yyjson_mut_obj(ctx->doc);
    if (obj == NULL) {
        set_err(ctx, "yyjson.encode: 内存不足");
        return NULL;
    }

    if (!ctx->sort_keys) {
        lua_checkstack(L, 2);
        lua_pushnil(L);
        while (lua_next(L, idx) != 0) {
            char keybuf[64];
            yyjson_mut_val *k, *val;
            const char *key = obj_key_string(ctx, L, -2, keybuf, sizeof(keybuf));
            if (key == NULL) {
                lua_pop(L, 2);
                return NULL;
            }
            val = lua_to_yyjson(ctx, -1, depth + 1);
            if (val == NULL) {
                lua_pop(L, 2);
                return NULL;
            }
            k = yyjson_mut_strcpy(ctx->doc, key);
            if (k == NULL || !yyjson_mut_obj_add(obj, k, val)) {
                set_err(ctx, "yyjson.encode: 内存不足");
                lua_pop(L, 2);
                return NULL;
            }
            lua_pop(L, 1); /* 弹 value，留 key 继续 */
        }
        return obj;
    }

    {
        int tmpidx;
        size_t count = 0, cap = 0, i;
        char **keys = NULL;
        lua_newtable(L); /* tmp: 键 -> 值（保引用，也避免数字键回读取错） */
        tmpidx = lua_gettop(L);

        lua_checkstack(L, 2);
        lua_pushnil(L);
        while (lua_next(L, idx) != 0) {
            char keybuf[64];
            const char *key = obj_key_string(ctx, L, -2, keybuf, sizeof(keybuf));
            char *copy;
            if (key == NULL) {
                lua_pop(L, 2);
                goto fail;
            }
            copy = strdup(key);
            if (copy == NULL) {
                set_err(ctx, "yyjson.encode: 内存不足");
                lua_pop(L, 2);
                goto fail;
            }
            lua_pushvalue(L, -2);  /* key */
            lua_pushvalue(L, -2);  /* value */
            lua_rawset(L, tmpidx); /* tmp[key] = value */
            if (count == cap) {
                char **grown = (char **)realloc(keys, (cap ? cap * 2 : 8) * sizeof(char *));
                if (grown == NULL) {
                    free(copy);
                    set_err(ctx, "yyjson.encode: 内存不足");
                    lua_pop(L, 1);
                    goto fail;
                }
                keys = grown;
                cap = cap ? cap * 2 : 8;
            }
            keys[count++] = copy;
            lua_pop(L, 1); /* 弹 value，留 key 继续 */
        }

        if (count > 1) {
            qsort(keys, count, sizeof(char *), cmp_key);
        }
        for (i = 0; i < count; i++) {
            yyjson_mut_val *k, *val;
            lua_getfield(L, tmpidx, keys[i]);
            val = lua_to_yyjson(ctx, -1, depth + 1);
            lua_pop(L, 1);
            if (val == NULL) {
                free(keys[i]);
                i++;
                goto fail_rest;
            }
            k = yyjson_mut_strcpy(ctx->doc, keys[i]);
            if (k == NULL || !yyjson_mut_obj_add(obj, k, val)) {
                set_err(ctx, "yyjson.encode: 内存不足");
                free(keys[i]);
                i++;
                goto fail_rest;
            }
            free(keys[i]);
        }
        free(keys);
        lua_pop(L, 1); /* 弹 tmp */
        return obj;

    fail_rest:
        for (; i < count; i++) {
            free(keys[i]);
        }
        free(keys);
        lua_pop(L, 1); /* 弹 tmp */
        return NULL;

    fail:
        for (i = 0; i < count; i++) {
            free(keys[i]);
        }
        free(keys);
        lua_pop(L, 1); /* 弹 tmp */
        return NULL;
    }
}

static yyjson_mut_val *encode_table(encode_ctx *ctx, int idx, int depth) {
    lua_State *L = ctx->L;
    lua_Integer max_index = 0;
    idx = abs_index(L, idx);
    int nonarray = table_has_nonarray_key(L, idx, &max_index);
    int is_empty = (max_index == 0 && !nonarray);

    /* 数组：键全是正整数（空表默认当对象，可用 emptyArray 选项改成数组） */
    if (!nonarray && (!is_empty || ctx->empty_array)) {
        yyjson_mut_val *arr = yyjson_mut_arr(ctx->doc);
        lua_Integer i;
        if (arr == NULL) {
            luaL_error(L, "yyjson.encode: 内存不足");
        }
        for (i = 1; i <= max_index; i++) {
            yyjson_mut_val *item;
            lua_geti(L, idx, i);
            if (lua_isnil(L, -1)) {
                item = yyjson_mut_null(ctx->doc); /* 空洞补 null */
            } else {
                item = lua_to_yyjson(ctx, -1, depth + 1);
            }
            lua_pop(L, 1);
            if (item == NULL || !yyjson_mut_arr_append(arr, item)) {
                set_err(ctx, "yyjson.encode: 内存不足");
                return NULL;
            }
        }
        return arr;
    }
    return encode_object(ctx, idx, depth);
}

static yyjson_mut_val *lua_to_yyjson(encode_ctx *ctx, int idx, int depth) {
    lua_State *L = ctx->L;
    idx = abs_index(L, idx);
    /* 深递归下必须自己保证栈空间：lua_next 不会替我们扩容 */
    if (!lua_checkstack(L, 4)) {
        luaL_error(L, "yyjson.encode: Lua 栈空间不足");
    }
    if (depth > LYYJSON_MAX_DEPTH) {
        set_err(ctx, "yyjson.encode: 嵌套超过 %d 层（表里可能有循环引用）", LYYJSON_MAX_DEPTH);
        return NULL;
    }
    switch (lua_type(L, idx)) {
        case LUA_TNIL:
            return yyjson_mut_null(ctx->doc);
        case LUA_TBOOLEAN:
            return yyjson_mut_bool(ctx->doc, lua_toboolean(L, idx));
        case LUA_TNUMBER:
            if (lua_isinteger(L, idx)) {
                return yyjson_mut_int(ctx->doc, (int64_t)lua_tointeger(L, idx));
            } else {
                double d = (double)lua_tonumber(L, idx);
                if ((isnan(d) || isinf(d)) && !ctx->allow_nan) {
                    set_err(ctx, "yyjson.encode: NaN/Inf 不是合法 JSON（可用 { allowNaN = true }）");
                    return NULL;
                }
                return yyjson_mut_real(ctx->doc, d);
            }
        case LUA_TSTRING: {
            size_t len = 0;
            const char *s = lua_tolstring(L, idx, &len);
            return yyjson_mut_strncpy(ctx->doc, s, len);
        }
        case LUA_TTABLE:
            return encode_table(ctx, idx, depth);
        case LUA_TLIGHTUSERDATA:
            if (lua_touserdata(L, idx) == (const void *)&yyjson_null_sentinel) {
                return yyjson_mut_null(ctx->doc);
            }
            luaL_error(L, "yyjson.encode: 不支持编码 lightuserdata");
            return NULL;
        case LUA_TFUNCTION:
            set_err(ctx, "yyjson.encode: 不能编码 function");
            return NULL;
        case LUA_TUSERDATA:
            set_err(ctx, "yyjson.encode: 不能编码 userdata");
            return NULL;
        case LUA_TTHREAD:
            set_err(ctx, "yyjson.encode: 不能编码 thread");
            return NULL;
        default:
            set_err(ctx, "yyjson.encode: 不支持的类型 %s", luaL_typename(L, idx));
            return NULL;
    }
}

static void read_encode_opts(encode_ctx *ctx, int idx) {
    lua_State *L = ctx->L;
    lua_getfield(L, idx, "indent");
    if (lua_isnumber(L, -1)) {
        lua_Integer n = lua_tointeger(L, -1);
        if (n > 0) {
            /* yyjson 内置两种美化：2 空格 / 4 空格 */
            ctx->flags |= (n <= 2) ? YYJSON_WRITE_PRETTY_TWO_SPACES : YYJSON_WRITE_PRETTY;
        }
    }
    lua_pop(L, 1);

    lua_getfield(L, idx, "sortKeys");
    ctx->sort_keys = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "emptyArray");
    ctx->empty_array = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "allowNaN");
    ctx->allow_nan = lua_toboolean(L, -1);
    if (ctx->allow_nan) {
        ctx->flags |= YYJSON_WRITE_ALLOW_INF_AND_NAN;
    }
    lua_pop(L, 1);

    lua_getfield(L, idx, "escapeUnicode");
    if (lua_toboolean(L, -1)) {
        ctx->flags |= YYJSON_WRITE_ESCAPE_UNICODE;
    }
    lua_pop(L, 1);

    lua_getfield(L, idx, "escapeSlashes");
    if (lua_toboolean(L, -1)) {
        ctx->flags |= YYJSON_WRITE_ESCAPE_SLASHES;
    }
    lua_pop(L, 1);

    lua_getfield(L, idx, "newline");
    if (lua_toboolean(L, -1)) {
        ctx->flags |= YYJSON_WRITE_NEWLINE_AT_END;
    }
    lua_pop(L, 1);
}

/* encode(value [, opts]) -> string；不可编码时抛错（与 cjson 一致） */
static int l_encode(lua_State *L) {
    encode_ctx ctx;
    size_t len = 0;
    char *out;
    yyjson_mut_val *root;

    if (lua_gettop(L) < 1) {
        return luaL_error(L, "yyjson.encode: 缺少参数");
    }
    memset(&ctx, 0, sizeof(ctx));
    ctx.L = L;
    ctx.flags = YYJSON_WRITE_NOFLAG;
    if (!lua_isnoneornil(L, 2)) {
        luaL_checktype(L, 2, LUA_TTABLE);
        read_encode_opts(&ctx, 2);
    }

    ctx.doc = yyjson_mut_doc_new(NULL);
    if (ctx.doc == NULL) {
        return luaL_error(L, "yyjson.encode: 创建文档失败");
    }
    root = lua_to_yyjson(&ctx, 1, 0);
    if (root == NULL || ctx.err[0] != '\0') {
        yyjson_mut_doc_free(ctx.doc);
        return luaL_error(L, "%s", ctx.err[0] ? ctx.err : "yyjson.encode: 编码失败");
    }
    yyjson_mut_doc_set_root(ctx.doc, root);

    out = yyjson_mut_write_opts(ctx.doc, ctx.flags, NULL, &len, NULL);
    if (out == NULL) {
        yyjson_mut_doc_free(ctx.doc);
        return luaL_error(L, "yyjson.encode: 序列化失败");
    }
    lua_pushlstring(L, out, len);
    free(out);
    yyjson_mut_doc_free(ctx.doc);
    return 1;
}

/* ------------------------------------------------------------------ */
/* 解码：yyjson doc -> Lua                                            */
/* ------------------------------------------------------------------ */

/* nullidx 是栈上 null 哨兵的绝对下标（解码过程中复用） */
static void yyjson_to_lua(lua_State *L, yyjson_val *val, int nullidx) {
    if (yyjson_is_null(val)) {
        lua_pushvalue(L, nullidx);
    } else if (yyjson_is_bool(val)) {
        lua_pushboolean(L, yyjson_get_bool(val));
    } else if (yyjson_is_int(val)) {
        lua_pushinteger(L, (lua_Integer)yyjson_get_sint(val));
    } else if (yyjson_is_uint(val)) {
        uint64_t u = yyjson_get_uint(val);
        if (u <= (uint64_t)INT64_MAX) {
            lua_pushinteger(L, (lua_Integer)u);
        } else {
            lua_pushnumber(L, (lua_Number)u); /* 超出 Lua 整数范围，降级为浮点 */
        }
    } else if (yyjson_is_real(val)) {
        lua_pushnumber(L, (lua_Number)yyjson_get_real(val));
    } else if (yyjson_is_str(val)) {
        lua_pushlstring(L, yyjson_get_str(val), yyjson_get_len(val));
    } else if (yyjson_is_arr(val)) {
        yyjson_val *item;
        yyjson_arr_iter iter = yyjson_arr_iter_with(val);
        lua_createtable(L, (int)yyjson_arr_size(val), 0);
        while ((item = yyjson_arr_iter_next(&iter)) != NULL) {
            yyjson_to_lua(L, item, nullidx);
            lua_rawseti(L, -2, (lua_Integer)iter.idx);
        }
    } else if (yyjson_is_obj(val)) {
        yyjson_val *key, *item;
        yyjson_obj_iter iter = yyjson_obj_iter_with(val);
        lua_createtable(L, 0, (int)yyjson_obj_size(val));
        while ((key = yyjson_obj_iter_next(&iter)) != NULL) {
            item = yyjson_obj_iter_get_val(key);
            lua_pushlstring(L, yyjson_get_str(key), yyjson_get_len(key));
            yyjson_to_lua(L, item, nullidx);
            lua_rawset(L, -3);
        }
    } else {
        lua_pushnil(L);
    }
}

static yyjson_read_flag read_decode_opts(lua_State *L, int idx) {
    static const struct {
        const char *name;
        yyjson_read_flag flag;
    } map[] = {
        {"comments", YYJSON_READ_ALLOW_COMMENTS},
        {"trailingCommas", YYJSON_READ_ALLOW_TRAILING_COMMAS},
        {"infNaN", YYJSON_READ_ALLOW_INF_AND_NAN},
        {"json5", YYJSON_READ_JSON5},
        {"singleQuoted", YYJSON_READ_ALLOW_SINGLE_QUOTED_STR},
        {"unquotedKeys", YYJSON_READ_ALLOW_UNQUOTED_KEY},
        {"invalidUnicode", YYJSON_READ_ALLOW_INVALID_UNICODE},
        {"bom", YYJSON_READ_ALLOW_BOM},
        {"bignumAsRaw", YYJSON_READ_BIGNUM_AS_RAW},
    };
    yyjson_read_flag flags = YYJSON_READ_NOFLAG;
    size_t i;
    if (!lua_istable(L, idx)) {
        return flags;
    }
    for (i = 0; i < sizeof(map) / sizeof(map[0]); i++) {
        lua_getfield(L, idx, map[i].name);
        if (lua_toboolean(L, -1)) {
            flags |= map[i].flag;
        }
        lua_pop(L, 1);
    }
    return flags;
}

/* decode(string [, opts]) -> value | nil, err, pos */
static int l_decode(lua_State *L) {
    size_t len = 0;
    const char *s = luaL_checklstring(L, 1, &len);
    yyjson_read_flag flags = YYJSON_READ_NOFLAG;
    yyjson_read_err err;
    yyjson_doc *doc;
    char *buf;

    if (!lua_isnoneornil(L, 2)) {
        luaL_checktype(L, 2, LUA_TTABLE);
        flags = read_decode_opts(L, 2);
    }

    /* yyjson 的读取接口要可写 buffer（非 insitu 模式只是不写回），这里拷贝一份 */
    buf = (char *)malloc(len + 1);
    if (buf == NULL) {
        return luaL_error(L, "yyjson.decode: 内存不足");
    }
    memcpy(buf, s, len);
    buf[len] = '\0';

    doc = yyjson_read_opts(buf, len, flags, NULL, &err);
    if (doc == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, err.msg ? err.msg : "JSON 解析失败");
        lua_pushinteger(L, (lua_Integer)err.pos);
        free(buf);
        return 3;
    }

    lua_pushlightuserdata(L, (void *)&yyjson_null_sentinel); /* 栈顶：哨兵 */
    yyjson_to_lua(L, yyjson_doc_get_root(doc), lua_gettop(L));
    lua_remove(L, -2); /* 去掉哨兵，留下结果 */

    yyjson_doc_free(doc);
    free(buf);
    return 1;
}

static int l_version(lua_State *L) {
    lua_pushstring(L, YYJSON_VERSION_STRING);
    return 1;
}

static const luaL_Reg lyyjson_funcs[] = {
    {"encode", l_encode},
    {"decode", l_decode},
    {"version", l_version},
    {NULL, NULL},
};

int luaopen_yyjson(lua_State *L) {
    lua_newtable(L); /* M */
    lua_pushlightuserdata(L, (void *)&yyjson_null_sentinel);
    luaL_setfuncs(L, lyyjson_funcs, 1);
    lua_pushlightuserdata(L, (void *)&yyjson_null_sentinel);
    lua_setfield(L, -2, "null");
    lua_pushstring(L, YYJSON_VERSION_STRING);
    lua_setfield(L, -2, "version_str");
    return 1;
}
