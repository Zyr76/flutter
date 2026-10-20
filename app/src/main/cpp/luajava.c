/******************************************************************************
* $Id$
* Copyright (C) 2003-2007 Kepler Project.
*
* Permission is hereby granted, free of charge, to any person obtaining
* a copy of this software and associated documentation files (the
* "Software"), to deal in the Software without restriction, including
* without limitation the rights to use, copy, modify, merge, publish,
* distribute, sublicense, and/or sell copies of the Software, and to
* permit persons to whom the Software is furnished to do so, subject to
* the following conditions:
*
* The above copyright notice and this permission notice shall be
* included in all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
******************************************************************************/

/***************************************************************************
*
* $ED
*    This module is the implementation of luajava's dinamic library.
*    In this module lua's functions are exported to be used in java by jni,
*    and also the functions that will be used and exported to lua so that
*    Java Objects' functions can be called.
*
*****************************************************************************/

#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

#include "luajava.h"
#include "luax.h"

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1getTop(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_gettop(L);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1setTop(JNIEnv *env, jobject jobj, jlong cptr,
                                   jint top) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_settop(L, (int) top);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1pushValue(JNIEnv *env, jobject jobj, jlong cptr,
                                      jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_pushvalue(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1rotate(JNIEnv *env, jobject jobj, jlong cptr,
                                   jint idx, jint n) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_rotate(L, (int) idx, n);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1copy(JNIEnv *env, jobject jobj, jlong cptr,
                                 jint fromidx, jint toidx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_copy(L, (int) fromidx, (int) toidx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1remove(JNIEnv *env, jobject jobj, jlong cptr,
                                   jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_remove(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1insert(JNIEnv *env, jobject jobj, jlong cptr,
                                   jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_insert(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1replace(JNIEnv *env, jobject jobj, jlong cptr,
                                    jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_replace(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1checkStack(JNIEnv *env, jobject jobj, jlong cptr,
                                       jint sz) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_checkstack(L, (int) sz);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1xmove(JNIEnv *env, jobject jobj, jlong from,
                                  jlong to, jint n) {
    lua_State *fr = getStateFromCPtr(env, from);
    lua_State *t = getStateFromCPtr(env, to);

    lua_xmove(fr, t, (int) n);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1isNumber(JNIEnv *env, jobject jobj, jlong cptr,
                                     jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_isnumber(L, (int) idx);
}

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1isInteger(JNIEnv *env, jobject jobj, jlong cptr,
                                      jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_isinteger(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1isString(JNIEnv *env, jobject jobj, jlong cptr,
                                     jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_isstring(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1isFunction(JNIEnv *env, jobject jobj, jlong cptr,
                                       jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_isfunction(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1isCFunction(JNIEnv *env, jobject jobj, jlong cptr,
                                        jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_iscfunction(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1isUserdata(JNIEnv *env, jobject jobj, jlong cptr,
                                       jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_isuserdata(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1isTable(JNIEnv *env, jobject jobj, jlong cptr,
                                    jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_istable(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1isBoolean(JNIEnv *env, jobject jobj, jlong cptr,
                                      jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_isboolean(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1isNil(JNIEnv *env, jobject jobj, jlong cptr,
                                  jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_isnil(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1isNone(JNIEnv *env, jobject jobj, jlong cptr,
                                   jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_isnone(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1isNoneOrNil(JNIEnv *env, jobject jobj, jlong cptr,
                                        jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_isnoneornil(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1type(JNIEnv *env, jobject jobj, jlong cptr,
                                 jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_type(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jstring JNICALL
Java_com_luajava_LuaState__1typeName(JNIEnv *env, jobject jobj, jlong cptr,
                                     jint tp) {
    lua_State *L = getStateFromCPtr(env, cptr);

    const char *name = lua_typename(L, tp);

    return (*env)->NewStringUTF(env, name);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1equal(JNIEnv *env, jobject jobj, jlong cptr,
                                  jint idx1, jint idx2) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_equal(L, idx1, idx2);
}

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1compare(JNIEnv *env, jobject jobj, jlong cptr,
                                    jint idx1, jint idx2, jint op) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_compare(L, idx1, idx2, op);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1rawequal(JNIEnv *env, jobject jobj, jlong cptr,
                                     jint idx1, jint idx2) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_rawequal(L, idx1, idx2);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1lessThan(JNIEnv *env, jobject jobj, jlong cptr,
                                     jint idx1, jint idx2) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_lessthan(L, idx1, idx2);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jdouble JNICALL
Java_com_luajava_LuaState__1toNumber(JNIEnv *env, jobject jobj, jlong cptr,
                                     jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jdouble) lua_tonumber(L, idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jlong JNICALL
Java_com_luajava_LuaState__1toInteger(JNIEnv *env, jobject jobj, jlong cptr,
                                      jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);
    if (lua_isinteger(L, idx))
        return (jlong) lua_tointeger(L, idx);
    else
        return (jlong) lua_tonumber(L, idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1toBoolean(JNIEnv *env, jobject jobj, jlong cptr,
                                      jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_toboolean(L, idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jstring JNICALL
Java_com_luajava_LuaState__1toString(JNIEnv *env, jobject jobj, jlong cptr,
                                     jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    const char *str = lua_tostring(L, idx);

    return (*env)->NewStringUTF(env, str);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1strlen(JNIEnv *env, jobject jobj, jlong cptr,
                                   jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_strlen(L, idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1objlen(JNIEnv *env, jobject jobj, jlong cptr,
                                   jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_objlen(L, idx);
}

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1rawlen(JNIEnv *env, jobject jobj, jlong cptr,
                                   jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_rawlen(L, idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jlong JNICALL
Java_com_luajava_LuaState__1toThread(JNIEnv *env, jobject jobj, jlong cptr,
                                     jint idx) {
    lua_State *L, *thr;
    L = getStateFromCPtr(env, cptr);

    thr = lua_tothread(L, (int) idx);
    return (jlong) thr;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1pushNil(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_pushnil(L);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1pushNumber(JNIEnv *env, jobject jobj, jlong cptr,
                                       jdouble number) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_pushnumber(L, (lua_Number) number);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1pushInteger(JNIEnv *env, jobject jobj, jlong cptr,
                                        jlong integer) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_pushinteger(L, (lua_Integer) integer);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1pushString(
        JNIEnv *env, jobject jobj, jlong cptr, jstring str) {
    lua_State *L = getStateFromCPtr(env, cptr);
    const char *uniStr;

    uniStr = (*env)->GetStringUTFChars(env, str, NULL);

    lua_pushstring(L, uniStr);

    (*env)->ReleaseStringUTFChars(env, str, uniStr);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1pushLString(
        JNIEnv *env, jobject jobj, jlong cptr, jbyteArray bytes, jint n) {
    lua_State *L = getStateFromCPtr(env, cptr);
    char *cBytes;

    cBytes = (char *) (*env)->GetByteArrayElements(env, bytes, NULL);

    lua_pushlstring(L, cBytes, n);

    (*env)->ReleaseByteArrayElements(env, bytes, cBytes, 0);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1pushBoolean(JNIEnv *env, jobject jobj, jlong cptr,
                                        jint jbool) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_pushboolean(L, (int) jbool);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1getTable(JNIEnv *env, jobject jobj, jlong cptr,
                                     jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_gettable(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1getField(JNIEnv *env, jobject jobj, jlong cptr,
                                     jint idx, jstring k) {
    lua_State *L = getStateFromCPtr(env, cptr);

    const char *uniStr;
    uniStr = (*env)->GetStringUTFChars(env, k, NULL);

    int ret = lua_getfield(L, (int) idx, uniStr);

    (*env)->ReleaseStringUTFChars(env, k, uniStr);
    return (jint) ret;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1getI(JNIEnv *env, jobject jobj, jlong cptr,
                                 jint idx, jlong n) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_geti(L, (int) idx, (lua_Integer) n);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1rawGet(JNIEnv *env, jobject jobj, jlong cptr,
                                   jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_rawget(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1rawGetI(JNIEnv *env, jobject jobj, jlong cptr,
                                    jint idx, jlong n) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_rawgeti(L, idx, (lua_Integer) n);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1createTable(JNIEnv *env, jobject jobj, jlong cptr,
                                        jint narr, jint nrec) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_createtable(L, (int) narr, (int) nrec);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1newTable(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_newtable(L);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1getMetaTable(JNIEnv *env, jobject jobj,
                                         jlong cptr, jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return lua_getmetatable(L, idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1getUserValue(JNIEnv *env, jobject jobj,
                                         jlong cptr, jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return lua_getuservalue(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1setTable(JNIEnv *env, jobject jobj, jlong cptr,
                                     jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_settable(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1setField(JNIEnv *env, jobject jobj, jlong cptr,
                                     jint idx, jstring k) {
    lua_State *L = getStateFromCPtr(env, cptr);

    const char *uniStr;
    uniStr = (*env)->GetStringUTFChars(env, k, NULL);

    lua_setfield(L, (int) idx, uniStr);

    (*env)->ReleaseStringUTFChars(env, k, uniStr);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1setI(JNIEnv *env, jobject jobj, jlong cptr,
                                 jint idx, jlong n) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_seti(L, (int) idx, (lua_Integer) n);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1rawSet(JNIEnv *env, jobject jobj, jlong cptr,
                                   jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_rawset(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1rawSetI(JNIEnv *env, jobject jobj, jlong cptr,
                                    jint idx, jlong n) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_rawseti(L, idx, (lua_Integer) n);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1setMetaTable(JNIEnv *env, jobject jobj,
                                         jlong cptr, jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return lua_setmetatable(L, idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1setUserValue(JNIEnv *env, jobject jobj,
                                         jlong cptr, jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_setuservalue(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1call(JNIEnv *env, jobject jobj, jlong cptr,
                                 jint nArgs, jint nResults) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_call(L, nArgs, nResults);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1pcall(JNIEnv *env, jobject jobj, jlong cptr,
                                  jint nArgs, jint nResults, jint errFunc) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_pcall(L, nArgs, nResults, errFunc);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1yield(JNIEnv *env, jobject jobj, jlong cptr,
                                  jint nResults) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_yield(L, nResults);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/
//lua5.5
JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1resume(JNIEnv *env, jobject jobj, jlong cptr,
                                   jlong cptr2, jint nArgs) {
    lua_State *L = getStateFromCPtr(env, cptr);
    lua_State *L2 = getStateFromCPtr(env, cptr2);
    
    int nres;  // 用来接收协程返回值的个数
    int status = lua_resume(L, L2, nArgs, &nres);
    
    return (jint)status;  // 返回状态码（LUA_OK, LUA_YIELD 等）
}


/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL Java_com_luajava_LuaState__1isYieldable(JNIEnv *env,
                                                               jobject jobj,
                                                               jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_isyieldable(L);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1status(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_status(L);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL Java_com_luajava_LuaState__1gc(JNIEnv *env, jobject jobj,
                                                      jlong cptr, jint what,
                                                      jint data) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_gc(L, what, data);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1next(JNIEnv *env, jobject jobj, jlong cptr,
                                 jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_next(L, idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1error(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) lua_error(L);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1concat(JNIEnv *env, jobject jobj, jlong cptr,
                                   jint n) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_concat(L, n);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL Java_com_luajava_LuaState__1pop(JNIEnv *env,
                                                       jobject jobj,
                                                       jlong cptr, jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_pop(L, (int) idx);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1pushGlobalTable(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);
    lua_pushglobaltable(L);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1setGlobal(JNIEnv *env, jobject jobj, jlong cptr,
                                      jstring name) {
    lua_State *L = getStateFromCPtr(env, cptr);

    const char *str = (*env)->GetStringUTFChars(env, name, NULL);

    lua_setglobal(L, str);

    (*env)->ReleaseStringUTFChars(env, name, str);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1getGlobal(JNIEnv *env, jobject jobj, jlong cptr,
                                      jstring name) {
    lua_State *L = getStateFromCPtr(env, cptr);

    const char *str = (*env)->GetStringUTFChars(env, name, NULL);

    int ret = lua_getglobal(L, str);

    (*env)->ReleaseStringUTFChars(env, name, str);
    return (jint) ret;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1LdoFile(JNIEnv *env, jobject jobj, jlong cptr,
                                    jstring fileName) {
    lua_State *L = getStateFromCPtr(env, cptr);

    const char *file = (*env)->GetStringUTFChars(env, fileName, NULL);

    int ret;

    ret = luaL_dofile(L, file);

    (*env)->ReleaseStringUTFChars(env, fileName, file);

    return (jint) ret;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1LdoString(JNIEnv *env, jobject jobj, jlong cptr,
                                      jstring str) {
    lua_State *L = getStateFromCPtr(env, cptr);

    const char *utfStr = (*env)->GetStringUTFChars(env, str, NULL);

    int ret;

    ret = luaL_dostring(L, utfStr);

    return (jint) ret;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1LgetMetaField(JNIEnv *env, jobject jobj,
                                          jlong cptr, jint obj, jstring e) {
    lua_State *L = getStateFromCPtr(env, cptr);
    const char *str = (*env)->GetStringUTFChars(env, e, NULL);
    int ret;

    ret = luaL_getmetafield(L, (int) obj, str);

    (*env)->ReleaseStringUTFChars(env, e, str);

    return (jint) ret;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1LcallMeta(JNIEnv *env, jobject jobj, jlong cptr,
                                      jint obj, jstring e) {
    lua_State *L = getStateFromCPtr(env, cptr);
    const char *str = (*env)->GetStringUTFChars(env, e, NULL);
    int ret;

    ret = luaL_callmeta(L, (int) obj, str);

    (*env)->ReleaseStringUTFChars(env, e, str);

    return (jint) ret;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1LargError(JNIEnv *env, jobject jobj, jlong cptr,
                                      jint numArg, jstring extraMsg) {
    lua_State *L = getStateFromCPtr(env, cptr);
    const char *msg = (*env)->GetStringUTFChars(env, extraMsg, NULL);
    int ret;

    ret = luaL_argerror(L, (int) numArg, msg);

    (*env)->ReleaseStringUTFChars(env, extraMsg, msg);

    return (jint) ret;;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jstring JNICALL
Java_com_luajava_LuaState__1LcheckString(JNIEnv *env, jobject jobj,
                                         jlong cptr, jint numArg) {
    lua_State *L = getStateFromCPtr(env, cptr);
    const char *res;

    res = luaL_checkstring(L, (int) numArg);

    return (*env)->NewStringUTF(env, res);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jstring JNICALL
Java_com_luajava_LuaState__1LoptString(JNIEnv *env, jobject jobj, jlong cptr,
                                       jint numArg, jstring def) {
    lua_State *L = getStateFromCPtr(env, cptr);
    const char *d = (*env)->GetStringUTFChars(env, def, NULL);
    const char *res;
    jstring ret;

    res = luaL_optstring(L, (int) numArg, d);

    ret = (*env)->NewStringUTF(env, res);

    (*env)->ReleaseStringUTFChars(env, def, d);

    return ret;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jdouble JNICALL
Java_com_luajava_LuaState__1LcheckNumber(JNIEnv *env, jobject jobj,
                                         jlong cptr, jint numArg) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jdouble) luaL_checknumber(L, (int) numArg);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jdouble JNICALL
Java_com_luajava_LuaState__1LoptNumber(JNIEnv *env, jobject jobj, jlong cptr,
                                       jint numArg, jdouble def) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jdouble) luaL_optnumber(L, (int) numArg, (lua_Number) def);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1LcheckInteger(JNIEnv *env, jobject jobj,
                                          jlong cptr, jint numArg) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) luaL_checkinteger(L, (int) numArg);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1LoptInteger(JNIEnv *env, jobject jobj, jlong cptr,
                                        jint numArg, jint def) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) luaL_optinteger(L, (int) numArg, (lua_Integer) def);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1LcheckStack(JNIEnv *env, jobject jobj, jlong cptr,
                                        jint sz, jstring msg) {
    lua_State *L = getStateFromCPtr(env, cptr);
    const char *m = (*env)->GetStringUTFChars(env, msg, NULL);

    luaL_checkstack(L, (int) sz, m);

    (*env)->ReleaseStringUTFChars(env, msg, m);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1LcheckType(JNIEnv *env, jobject jobj, jlong cptr,
                                       jint nArg, jint t) {
    lua_State *L = getStateFromCPtr(env, cptr);

    luaL_checktype(L, (int) nArg, (int) t);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1LcheckAny(JNIEnv *env, jobject jobj, jlong cptr,
                                      jint nArg) {
    lua_State *L = getStateFromCPtr(env, cptr);

    luaL_checkany(L, (int) nArg);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1LnewMetatable(JNIEnv *env, jobject jobj,
                                          jlong cptr, jstring tName) {
    lua_State *L = getStateFromCPtr(env, cptr);
    const char *name = (*env)->GetStringUTFChars(env, tName, NULL);
    int ret;

    ret = luaL_newmetatable(L, name);

    (*env)->ReleaseStringUTFChars(env, tName, name);

    return (jint) ret;;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1LgetMetatable(JNIEnv *env, jobject jobj,
                                          jlong cptr, jstring tName) {
    lua_State *L = getStateFromCPtr(env, cptr);
    const char *name = (*env)->GetStringUTFChars(env, tName, NULL);

    luaL_getmetatable(L, name);

    (*env)->ReleaseStringUTFChars(env, tName, name);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1Lwhere(JNIEnv *env, jobject jobj, jlong cptr,
                                   jint lvl) {
    lua_State *L = getStateFromCPtr(env, cptr);

    luaL_where(L, (int) lvl);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL Java_com_luajava_LuaState__1Lref(JNIEnv *env,
                                                        jobject jobj,
                                                        jlong cptr, jint t) {
    lua_State *L = getStateFromCPtr(env, cptr);

    return (jint) luaL_ref(L, (int) t);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1LunRef(JNIEnv *env, jobject jobj, jlong cptr,
                                   jint t, jint ref) {
    lua_State *L = getStateFromCPtr(env, cptr);

    luaL_unref(L, (int) t, (int) ref);
}

#define LUAJAVA_CPP_BLOCK_START "@cpp"
#define LUAJAVA_CPP_BLOCK_END "@endcpp"
#define LUAJAVA_CPP_RUN_PREFIX "luajava.cppBlock("
#define LUAJAVA_CPP_RUN_SUFFIX ")\n"

struct luajava_text_buffer {
    char *data;
    size_t size;
    size_t capacity;
};

static int luajava_text_buffer_reserve(struct luajava_text_buffer *buffer, size_t extra) {
    size_t required;
    size_t new_capacity;
    char *new_data;
    if (extra == 0) {
        return 0;
    }
    if (buffer->size > ((size_t) -1) - extra) {
        return 1;
    }
    required = buffer->size + extra;
    if (required <= buffer->capacity) {
        return 0;
    }
    new_capacity = (buffer->capacity == 0) ? 4096 : buffer->capacity;
    while (new_capacity < required) {
        if (new_capacity > ((size_t) -1) / 2) {
            new_capacity = required;
            break;
        }
        new_capacity *= 2;
    }
    new_data = (char *) realloc(buffer->data, new_capacity);
    if (new_data == NULL) {
        return 1;
    }
    buffer->data = new_data;
    buffer->capacity = new_capacity;
    return 0;
}

static int luajava_text_buffer_append(struct luajava_text_buffer *buffer, const char *text, size_t len) {
    if (len == 0) {
        return 0;
    }
    if (luajava_text_buffer_reserve(buffer, len) != 0) {
        return 1;
    }
    memcpy(buffer->data + buffer->size, text, len);
    buffer->size += len;
    return 0;
}

static int luajava_text_buffer_append_char(struct luajava_text_buffer *buffer, char ch) {
    return luajava_text_buffer_append(buffer, &ch, 1);
}

static int luajava_text_buffer_append_literal(struct luajava_text_buffer *buffer, const char *text) {
    return luajava_text_buffer_append(buffer, text, strlen(text));
}

static void luajava_text_buffer_clear(struct luajava_text_buffer *buffer) {
    buffer->size = 0;
}

static void luajava_text_buffer_free(struct luajava_text_buffer *buffer) {
    free(buffer->data);
    buffer->data = NULL;
    buffer->size = 0;
    buffer->capacity = 0;
}

static int luajava_read_file(const char *filename, struct luajava_text_buffer *buffer) {
    FILE *fp;
    size_t nread;
    char chunk[4096];
    fp = fopen(filename, "rb");
    if (fp == NULL) {
        return 1;
    }
    while ((nread = fread(chunk, 1, sizeof(chunk), fp)) > 0) {
        if (luajava_text_buffer_append(buffer, chunk, nread) != 0) {
            fclose(fp);
            return 1;
        }
    }
    if (ferror(fp)) {
        fclose(fp);
        return 1;
    }
    fclose(fp);
    return 0;
}

static int luajava_contains_bytes(const char *data, size_t data_len, const char *needle) {
    size_t i;
    size_t needle_len = strlen(needle);
    if (needle_len == 0 || data_len < needle_len) {
        return 0;
    }
    for (i = 0; i + needle_len <= data_len; i++) {
        if (memcmp(data + i, needle, needle_len) == 0) {
            return 1;
        }
    }
    return 0;
}

static int luajava_is_marker_line(const char *line, size_t len, const char *marker) {
    size_t start = 0;
    size_t end = len;
    size_t marker_len = strlen(marker);
    while (start < end && (line[start] == ' ' || line[start] == '\t')) {
        start++;
    }
    while (end > start &&
           (line[end - 1] == ' ' || line[end - 1] == '\t' || line[end - 1] == '\r')) {
        end--;
    }
    if (end - start != marker_len) {
        return 0;
    }
    return memcmp(line + start, marker, marker_len) == 0;
}

static int luajava_append_lua_escaped_string(struct luajava_text_buffer *out,
                                             const char *text,
                                             size_t len) {
    size_t i;
    unsigned char ch;
    char escaped[5];
    if (luajava_text_buffer_append_char(out, '"') != 0) {
        return 1;
    }
    for (i = 0; i < len; i++) {
        ch = (unsigned char) text[i];
        switch (ch) {
            case '\\':
                if (luajava_text_buffer_append_literal(out, "\\\\") != 0) {
                    return 1;
                }
                break;
            case '"':
                if (luajava_text_buffer_append_literal(out, "\\\"") != 0) {
                    return 1;
                }
                break;
            case '\n':
                if (luajava_text_buffer_append_literal(out, "\\n") != 0) {
                    return 1;
                }
                break;
            case '\r':
                if (luajava_text_buffer_append_literal(out, "\\r") != 0) {
                    return 1;
                }
                break;
            case '\t':
                if (luajava_text_buffer_append_literal(out, "\\t") != 0) {
                    return 1;
                }
                break;
            default:
                if (ch < 32) {
                    snprintf(escaped, sizeof(escaped), "\\%03u", (unsigned int) ch);
                    if (luajava_text_buffer_append_literal(out, escaped) != 0) {
                        return 1;
                    }
                } else {
                    if (luajava_text_buffer_append_char(out, (char) ch) != 0) {
                        return 1;
                    }
                }
                break;
        }
    }
    return luajava_text_buffer_append_char(out, '"');
}

static int luajava_preprocess_hybrid_script(const char *source,
                                            size_t source_len,
                                            struct luajava_text_buffer *out,
                                            int *has_hybrid,
                                            const char **error_message) {
    size_t i = 0;
    struct luajava_text_buffer block = {NULL, 0, 0};
    int block_mode = 0;
    *has_hybrid = 0;
    *error_message = NULL;

    while (i < source_len) {
        size_t line_start = i;
        size_t line_end;
        size_t line_len;
        int has_newline = 0;

        while (i < source_len && source[i] != '\n') {
            i++;
        }
        line_end = i;
        if (i < source_len && source[i] == '\n') {
            i++;
            has_newline = 1;
        }
        line_len = line_end - line_start;

        if (block_mode == 0) {
            if (luajava_is_marker_line(source + line_start, line_len, LUAJAVA_CPP_BLOCK_START)) {
                *has_hybrid = 1;
                block_mode = 1;
                continue;
            }
            if (luajava_text_buffer_append(out, source + line_start, line_len) != 0) {
                goto oom_error;
            }
            if (has_newline && luajava_text_buffer_append_char(out, '\n') != 0) {
                goto oom_error;
            }
            continue;
        }

        if (block_mode == 1 && luajava_is_marker_line(source + line_start, line_len, LUAJAVA_CPP_BLOCK_END)) {
            if (luajava_text_buffer_append_literal(out, LUAJAVA_CPP_RUN_PREFIX) != 0 ||
                luajava_append_lua_escaped_string(out,
                                                  block.data != NULL ? block.data : "",
                                                  block.size) != 0 ||
                luajava_text_buffer_append_literal(out, LUAJAVA_CPP_RUN_SUFFIX) != 0) {
                goto oom_error;
            }
            luajava_text_buffer_clear(&block);
            block_mode = 0;
            continue;
        }

        if (luajava_text_buffer_append(&block, source + line_start, line_len) != 0 ||
            (has_newline && luajava_text_buffer_append_char(&block, '\n') != 0)) {
            goto oom_error;
        }
    }

    if (block_mode == 1) {
        *error_message = "Unclosed @cpp block: missing @endcpp";
        luajava_text_buffer_free(&block);
        return 1;
    }

    luajava_text_buffer_free(&block);
    return 0;

oom_error:
    *error_message = "Out of memory while preprocessing hybrid block";
    luajava_text_buffer_free(&block);
    return 1;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jbyteArray JNICALL
Java_com_androlua_LuaX_encrypt(JNIEnv *env, jclass clazz, jbyteArray data) {
    jsize n;
    jbyte *src;
    uint8_t *out;
    size_t total = 0;
    jbyteArray ret;

    (void)clazz;
    if (data == NULL) {
        return NULL;
    }
    n = (*env)->GetArrayLength(env, data);
    if (n <= 0) {
        return NULL;
    }
    src = (*env)->GetByteArrayElements(env, data, NULL);
    if (src == NULL) {
        return NULL;
    }
    out = luax_encrypt((const uint8_t *)src, (size_t)n, &total);
    (*env)->ReleaseByteArrayElements(env, data, src, JNI_ABORT);
    if (out == NULL) {
        return NULL;
    }
    ret = (*env)->NewByteArray(env, (jsize)total);
    if (ret != NULL) {
        (*env)->SetByteArrayRegion(env, ret, 0, (jsize)total, (const jbyte *)out);
    }
    memset(out, 0, total);
    free(out);
    return ret;
}

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1LloadFile(JNIEnv *env, jobject jobj, jlong cptr,
                                      jstring fileName) {
    lua_State *L = getStateFromCPtr(env, cptr);
    const char *fn = (*env)->GetStringUTFChars(env, fileName, NULL);
    int ret;
    struct luajava_text_buffer source = {NULL, 0, 0};
    struct luajava_text_buffer transformed = {NULL, 0, 0};
    const char *script_source = NULL;
    size_t script_size = 0;
    int has_hybrid = 0;
    const char *hybrid_error = NULL;

    if (luajava_read_file(fn, &source) == 0) {
        script_source = source.data != NULL ? source.data : "";
        script_size = source.size;
        /* 加密脚本是二进制，必须在 @cpp 文本预处理之前分流 */
        if (luax_is_encrypted(script_source, script_size)) {
            ret = luax_decrypt_load(L, script_source, script_size, fn);
            luajava_text_buffer_free(&transformed);
            luajava_text_buffer_free(&source);
            (*env)->ReleaseStringUTFChars(env, fileName, fn);
            return (jint) ret;
        }
        if (luajava_contains_bytes(script_source, script_size, LUAJAVA_CPP_BLOCK_START)) {
            if (luajava_preprocess_hybrid_script(script_source, script_size, &transformed, &has_hybrid, &hybrid_error) == 0) {
                if (has_hybrid) {
                    ret = luaL_loadbuffer(L, transformed.data, transformed.size, fn);
                } else {
                    ret = luaL_loadbuffer(L, script_source, script_size, fn);
                }
            } else {
                lua_pushstring(L, hybrid_error != NULL ? hybrid_error : "Lua preprocess failed");
                ret = LUA_ERRSYNTAX;
            }
        } else {
            ret = luaL_loadbuffer(L, script_source, script_size, fn);
        }
    } else {
        ret = luaL_loadfile(L, fn);
    }

    luajava_text_buffer_free(&transformed);
    luajava_text_buffer_free(&source);

    (*env)->ReleaseStringUTFChars(env, fileName, fn);

    return (jint) ret;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1LloadBuffer(JNIEnv *env, jobject jobj, jlong cptr,
                                        jbyteArray buff, jlong sz, jstring n) {
    lua_State *L = getStateFromCPtr(env, cptr);
    jbyte *cBuff = (*env)->GetByteArrayElements(env, buff, NULL);
    const char *name = (*env)->GetStringUTFChars(env, n, NULL);
    int ret;

    if (luax_is_encrypted((const char *)cBuff, (size_t)sz)) {
        ret = luax_decrypt_load(L, (const char *)cBuff, (size_t)sz, name);
    } else {
        ret = luaL_loadbuffer(L, (const char *) cBuff, (int) sz, name);
    }

    (*env)->ReleaseStringUTFChars(env, n, name);

    (*env)->ReleaseByteArrayElements(env, buff, cBuff, 0);

    return (jint) ret;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1LloadString(JNIEnv *env, jobject jobj, jlong cptr,
                                        jstring str) {
    lua_State *L = getStateFromCPtr(env, cptr);
    const char *fn = (*env)->GetStringUTFChars(env, str, NULL);
    int ret;

    if (luax_is_encrypted(fn, strlen(fn))) {
        /* Java String 只能可靠承载文本，加密字节码请走 LloadFile / LloadBuffer */
        if (((const uint8_t *)fn)[5] & LUAX_FLAG_BYTECODE) {
            lua_pushliteral(L, "LUAX: LloadString 不支持加密字节码，请用 LloadFile");
            ret = LUA_ERRSYNTAX;
        } else {
            ret = luax_decrypt_load(L, fn, strlen(fn), "=(loadstring)");
        }
    } else {
        ret = luaL_loadstring(L, fn);
    }

    (*env)->ReleaseStringUTFChars(env, str, fn);

    return (jint) ret;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jstring JNICALL
Java_com_luajava_LuaState__1Lgsub(JNIEnv *env, jobject jobj, jlong cptr,
                                  jstring s, jstring p, jstring r) {
    lua_State *L = getStateFromCPtr(env, cptr);
    const char *utS = (*env)->GetStringUTFChars(env, s, NULL);
    const char *utP = (*env)->GetStringUTFChars(env, p, NULL);
    const char *utR = (*env)->GetStringUTFChars(env, r, NULL);

    const char *sub = luaL_gsub(L, utS, utP, utR);

    (*env)->ReleaseStringUTFChars(env, s, utS);
    (*env)->ReleaseStringUTFChars(env, p, utP);
    (*env)->ReleaseStringUTFChars(env, r, utR);

    return (*env)->NewStringUTF(env, sub);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jstring JNICALL
Java_com_luajava_LuaState__1getUpValue(JNIEnv *env, jobject jobj, jlong cptr,
                                       jint funcindex, jint n) {
    lua_State *L = getStateFromCPtr(env, cptr);

    const char *name = lua_getupvalue(L, (int) funcindex, (int) n);
    return (*env)->NewStringUTF(env, name);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jstring JNICALL
Java_com_luajava_LuaState__1setUpValue(JNIEnv *env, jobject jobj, jlong cptr,
                                       jint funcindex, jint n) {
    lua_State *L = getStateFromCPtr(env, cptr);

    const char *name = lua_setupvalue(L, (int) funcindex, (int) n);
    return (*env)->NewStringUTF(env, name);
}

struct luajava_dump_buffer {
    char *data;
    size_t size;
    size_t capacity;
};

static int writer(lua_State *L, const void *b, size_t size, void *B) {
    struct luajava_dump_buffer *buffer = (struct luajava_dump_buffer *) B;
    char *new_data;
    size_t new_capacity;
    (void) L;

    if (size == 0 || b == NULL) {
        return 0;
    }

    if (buffer->size > ((size_t) -1) - size) {
        return 1;
    }

    if (buffer->capacity < buffer->size + size) {
        new_capacity = (buffer->capacity == 0) ? size : buffer->capacity;
        while (new_capacity < buffer->size + size) {
            if (new_capacity > ((size_t) -1) / 2) {
                new_capacity = buffer->size + size;
                break;
            }
            new_capacity *= 2;
        }
        new_data = (char *) realloc(buffer->data, new_capacity);
        if (new_data == NULL) {
            return 1;
        }
        buffer->data = new_data;
        buffer->capacity = new_capacity;
    }

    memcpy(buffer->data + buffer->size, b, size);
    buffer->size += size;
    return 0;
}


JNIEXPORT jbyteArray JNICALL
Java_com_luajava_LuaState__1dump(JNIEnv *env, jobject jobj, jlong cptr,
                                 jint funcindex) {
    lua_State *L = getStateFromCPtr(env, cptr);
    struct luajava_dump_buffer buffer = {NULL, 0, 0};
    jbyteArray arr;
    luaL_checktype(L, funcindex, LUA_TFUNCTION);
    if (lua_dump(L, writer, &buffer, 0) != 0) {
        free(buffer.data);
        (*env)->ThrowNew(env, (*env)->FindClass(env, "com/luajava/LuaException"),
                         "unable to dump given function");
        return NULL;
    }

    arr = (*env)->NewByteArray(env, (jsize) buffer.size);
    if (arr == NULL) {
        free(buffer.data);
        return NULL;
    }
    if (buffer.size > 0) {
        (*env)->SetByteArrayRegion(env, arr, 0, (jsize) buffer.size, (const jbyte *) buffer.data);
    }
    free(buffer.data);
    return arr;
}

JNIEXPORT jint JNICALL
Java_com_luajava_LuaState__1isThread(JNIEnv *env, jobject instance, jlong ptr, jint idx) {

    lua_State *L = getStateFromCPtr(env, ptr);

    return (jint) lua_isthread(L, (int) idx);

}

JNIEXPORT jbyteArray JNICALL
Java_com_luajava_LuaState__1toBuffer(JNIEnv *env, jobject instance, jlong cptr, jint idx) {
    lua_State *L = getStateFromCPtr(env, cptr);
    size_t size = 0;
    const char *str = lua_tolstring(L, idx, &size);
    jbyteArray arr = (*env)->NewByteArray(env, size);
    jbyte *data = (*env)->GetByteArrayElements(env, arr, 0);
    memcpy(data, str, size);
    (*env)->ReleaseByteArrayElements(env, arr, data, 0);
    return arr;
}
