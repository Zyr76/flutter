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
/* Call metamethod name */
#define LUACALLMETAMETHODTAG "__call"
#define LUATOSTRINGMETAMETHODTAG "__tostring"
#define LUALENMETAMETHODTAG "__len"

#include <android/log.h>
#include <memory.h>

#define LOG_TAG "lua"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)


/* Constant that is used to index the JNI Environment */
#define LUAJAVAJNIENVTAG "_JNIEnv"
/* Defines the lua State Index Property Name */
#define LUAJAVASTATEINDEX "_LuaJavaStateIndex"
/* Defines wheter the metatable is of a java Object */
#define LUAJAVAOBJECTIND "__IsJavaObject"
/* Index metamethod name */
#define LUAINDEXMETAMETHODTAG "__index"
/* New index metamethod name */
#define LUANEWINDEXMETAMETHODTAG "__newindex"
/* Garbage collector metamethod name */
#define LUAGCMETAMETHODTAG "__gc"
/* Constant that defines where in the metatable should I place the function
   name */
#define LUAJAVAOBJECTMETA "JavaObject"

#define LUAJAVAOBJECT "__Object"


static jclass throwable_class = NULL;
static jmethodID get_message_method = NULL;
static jmethodID throwable_tostring_method = NULL;

static jclass java_function_class = NULL;
static jmethodID java_function_method = NULL;

static jclass luajava_api_class = NULL;
static jclass java_lang_class = NULL;
static jclass java_string_class = NULL;

static jmethodID object_index_method = NULL;
static jmethodID call_method = NULL;
static jmethodID object_newindex_method = NULL;
static jmethodID new_array_method = NULL;
static jmethodID new_multiarray_method = NULL;
static jmethodID get_array_method = NULL;
static jmethodID set_array_method = NULL;
static jmethodID bind_class_method = NULL;
static jmethodID create_proxy_method = NULL;
static jmethodID create_array_method = NULL;
static jmethodID java_create_method = NULL;
static jmethodID java_new_method = NULL;
static jmethodID object_call_method = NULL;
static jmethodID java_newinstance_method = NULL;
static jmethodID as_table_method = NULL;
static jmethodID to_string_method = NULL;
static jmethodID get_type_method = NULL;
static jmethodID object_length_method = NULL;
static jmethodID string_init_method = NULL;
static jmethodID string_getbytes_method = NULL;
static jmethodID class_getname_method = NULL;
static jmethodID object_equals_method = NULL;
static jmethodID java_gc_method = NULL;

static int objectIndex(lua_State *L);

static int callMethod(lua_State *L);

static int objectNewIndex(lua_State *L);

static int javaBindClass(lua_State *L);

static int createProxy(lua_State *L);

static int newArray(lua_State *L);

static int createArray(lua_State *L);

static int javaNew(lua_State *L);

static int javaNewInstance(lua_State *L);

static int javaLoadLib(lua_State *L);

static int asTable(lua_State *L);

static int javaToString(lua_State *L);

static int javaObjectLength(lua_State *L);

static int coding(lua_State *L);

static int cppBlock(lua_State *L);

static lua_State *getStateFromCPtr(JNIEnv *env, jlong cptr);

static int luaJavaFunctionCall(lua_State *L);

void pushJNIEnv(JNIEnv *env, lua_State *L);

int pushJavaObject(lua_State *L, jobject javaObject);

JNIEnv *checkEnv(lua_State *L);

jlong checkIndex(lua_State *L);

jobject *checkJavaObject(lua_State *L, int idx);

void checkError(JNIEnv *javaEnv, lua_State *L);

int gc(lua_State *L);

static int luajava_compat_seeall(lua_State *L);

static int luajava_compat_module(lua_State *L);

static int luajava_compat_loadstring(lua_State *L);

static int luajava_compat_unpack(lua_State *L);

JNIEnv *getEnvFromState(lua_State *L);

int isJavaObject(lua_State *L, int idx);


static int luajava_compat_seeall(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    lua_newtable(L);
    lua_pushglobaltable(L);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, 1);
    return 0;
}


static int luajava_compat_module(lua_State *L) {
    const char *modname = luaL_optstring(L, 1, NULL);
    int top = lua_gettop(L);
    int i;

    if (modname == NULL || modname[0] == '\0') {
        lua_getglobal(L, "_NAME");
        modname = lua_tostring(L, -1);
        lua_pop(L, 1);
        if (modname == NULL || modname[0] == '\0') {
            modname = "_M";
        }
    }

    luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_LOADED_TABLE);
    lua_getfield(L, -1, modname);
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        lua_newtable(L);
        lua_pushvalue(L, -1);
        lua_setfield(L, -3, modname);
    }
    lua_remove(L, -2);

    lua_pushstring(L, modname);
    lua_setfield(L, -2, "_NAME");
    lua_pushstring(L, modname);
    lua_setfield(L, -2, "_PACKAGE");
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "_M");

    lua_getglobal(L, "package");
    if (lua_istable(L, -1)) {
        lua_getfield(L, -1, "loaded");
        if (lua_istable(L, -1)) {
            lua_pushvalue(L, -3);
            lua_setfield(L, -2, modname);
        }
        lua_pop(L, 1);
    }
    lua_pop(L, 1);

    lua_pushvalue(L, -1);
    lua_setglobal(L, modname);

    for (i = 2; i <= top; i++) {
        if (lua_isfunction(L, i)) {
            lua_pushvalue(L, i);
            lua_pushvalue(L, -2);
            lua_call(L, 1, 0);
        }
    }

    return 1;
}


static int luajava_compat_loadstring(lua_State *L) {
    size_t len;
    const char *s = luaL_checklstring(L, 1, &len);
    const char *chunkname = luaL_optstring(L, 2, s);
    const char *mode = luaL_optstring(L, 3, NULL);
    int status = luaL_loadbufferx(L, s, len, chunkname, mode);
    if (status == LUA_OK) {
        return 1;
    }
    lua_pushnil(L);
    lua_insert(L, -2);
    return 2;
}


static int luajava_compat_unpack(lua_State *L) {
    lua_getglobal(L, "table");
    if (!lua_istable(L, -1)) {
        return luaL_error(L, "table library not available");
    }
    lua_getfield(L, -1, "unpack");
    if (!lua_isfunction(L, -1)) {
        return luaL_error(L, "table.unpack not available");
    }
    lua_remove(L, -2);
    lua_insert(L, 1);
    lua_call(L, lua_gettop(L) - 1, LUA_MULTRET);
    return lua_gettop(L);
}


JNIEnv *checkEnv(lua_State *L) {
    JNIEnv *javaEnv = (JNIEnv *) 0;
    lua_pushstring(L, LUAJAVAJNIENVTAG);
    lua_rawget(L, LUA_REGISTRYINDEX);

    if (lua_isuserdata(L, -1))
        javaEnv = *(JNIEnv **) lua_touserdata(L, -1);
    lua_pop(L, 1);
    if (!javaEnv)
        luaL_error(L, "Invalid JNI Environment.");
    return javaEnv;
}

jlong checkIndex(lua_State *L) {
    return (jlong) L;
}

jobject *checkJavaObject(lua_State *L, int idx) {
    //if (!isJavaObject(L, idx))
    //luaL_typerror(L, idx, "java Object");
    //return (jobject *)lua_touserdata(L, idx);
    jobject *obj;
    obj = (jobject *) luaL_checkudata(L, idx, LUAJAVAOBJECTMETA);
    if (*obj == NULL) {
        luaL_argerror(L, idx, "JavaObject expected, got null");
    }
    return obj;
}

void checkError(JNIEnv *javaEnv, lua_State *L) {
    jthrowable exp = (*javaEnv)->ExceptionOccurred(javaEnv);

    /* Handles exception */
    if (exp != NULL) {
        jobject jstr;
        const char *cStr;

        (*javaEnv)->ExceptionClear(javaEnv);
        jstr = (*javaEnv)->CallObjectMethod(javaEnv, exp, get_message_method);

        if (jstr == NULL) {
            if (throwable_tostring_method == NULL)
                throwable_tostring_method = (*javaEnv)->GetMethodID(javaEnv, throwable_class,
                                                                    "toString",
                                                                    "()Ljava/lang/String;");
            jstr = (*javaEnv)->CallObjectMethod(javaEnv, exp, throwable_tostring_method);
        }

        cStr = (*javaEnv)->GetStringUTFChars(javaEnv, jstr, NULL);

        if (cStr != NULL && (strstr(cStr, "not found: mao") != NULL || strstr(cStr, "not found: sign") != NULL)) {
            (*javaEnv)->ReleaseStringUTFChars(javaEnv, jstr, cStr);
            (*javaEnv)->DeleteLocalRef(javaEnv, exp);
            (*javaEnv)->DeleteLocalRef(javaEnv, jstr);
            return;
        }

        //lua_settop(L, 0);
        lua_pushstring(L, cStr);

        (*javaEnv)->ReleaseStringUTFChars(javaEnv, jstr, cStr);
        (*javaEnv)->DeleteLocalRef(javaEnv, exp);
        (*javaEnv)->DeleteLocalRef(javaEnv, jstr);

        lua_error(L);
    }
}

/********************* Implementations ***************************/

static void init(JNIEnv *javaEnv, lua_State *L) {
    jclass tempClass;

    if (luajava_api_class == NULL) {
        tempClass = (*javaEnv)->FindClass(javaEnv, "com/luajava/LuaJavaAPI");

        if (tempClass == NULL) {
            fprintf(stderr, "Could not find LuaJavaAPI class\n");
            exit(1);
        }

        if ((luajava_api_class = (*javaEnv)->NewGlobalRef(javaEnv, tempClass)) == NULL) {
            fprintf(stderr, "Could not bind to LuaJavaAPI class\n");
            exit(1);
        }
        (*javaEnv)->DeleteLocalRef(javaEnv, tempClass);
    }

    if (java_function_class == NULL) {
        tempClass = (*javaEnv)->FindClass(javaEnv, "com/luajava/JavaFunction");

        if (tempClass == NULL) {
            fprintf(stderr, "Could not find JavaFunction interface\n");
            exit(1);
        }

        if ((java_function_class = (*javaEnv)->NewGlobalRef(javaEnv, tempClass)) == NULL) {
            fprintf(stderr, "Could not bind to JavaFunction interface\n");
            exit(1);
        }
        (*javaEnv)->DeleteLocalRef(javaEnv, tempClass);
    }

    if (java_function_method == NULL) {
        java_function_method =
                (*javaEnv)->GetMethodID(javaEnv, java_function_class, "execute", "()I");
        if (!java_function_method) {
            fprintf(stderr, "Could not find <execute> method in JavaFunction\n");
            exit(1);
        }
    }

    if (throwable_class == NULL) {
        tempClass = (*javaEnv)->FindClass(javaEnv, "java/lang/Throwable");

        if (tempClass == NULL) {
            fprintf(stderr, "Error. Couldn't bind java class java.lang.Throwable\n");
            exit(1);
        }

        throwable_class = (*javaEnv)->NewGlobalRef(javaEnv, tempClass);
        (*javaEnv)->DeleteLocalRef(javaEnv, tempClass);

        if (throwable_class == NULL) {
            fprintf(stderr, "Error. Couldn't bind java class java.lang.Throwable\n");
            exit(1);
        }
    }

    if (get_message_method == NULL) {
        get_message_method = (*javaEnv)->GetMethodID(javaEnv, throwable_class, "getMessage",
                                                     "()Ljava/lang/String;");

        if (get_message_method == NULL) {
            fprintf(stderr,
                    "Could not find <getMessage> method in java.lang.Throwable\n");
            exit(1);
        }
    }

    if (java_lang_class == NULL) {
        tempClass = (*javaEnv)->FindClass(javaEnv, "java/lang/Class");

        if (tempClass == NULL) {
            fprintf(stderr, "Error. Coundn't bind java class java.lang.Class\n");
            exit(1);
        }

        java_lang_class = (*javaEnv)->NewGlobalRef(javaEnv, tempClass);
        (*javaEnv)->DeleteLocalRef(javaEnv, tempClass);

        if (java_lang_class == NULL) {
            fprintf(stderr, "Error. Couldn't bind java class java.lang.Throwable\n");
            exit(1);
        }
    }

    if (java_string_class == NULL) {
        tempClass = (*javaEnv)->FindClass(javaEnv, "java/lang/String");

        if (tempClass == NULL) {
            fprintf(stderr, "Could not find String class\n");
            exit(1);
        }

        if ((java_string_class = (*javaEnv)->NewGlobalRef(javaEnv, tempClass)) == NULL) {
            fprintf(stderr, "Could not bind to String class\n");
            exit(1);
        }
        (*javaEnv)->DeleteLocalRef(javaEnv, tempClass);
    }

    /* Gets method */
    if (call_method == NULL)
        call_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "callMethod",
                "(JLjava/lang/Object;Ljava/lang/String;)I");
    if (object_index_method == NULL)
        object_index_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "objectIndex",
                "(JLjava/lang/Object;Ljava/lang/String;I)I");
    if (object_newindex_method == NULL)
        object_newindex_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "objectNewIndex",
                "(JLjava/lang/Object;Ljava/lang/String;I)I");
    if (new_array_method == NULL)
        new_array_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "newArray", "(JLjava/lang/Class;I)I");
    if (new_multiarray_method == NULL)
        new_multiarray_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "newArray", "(JLjava/lang/Class;)I");
    if (get_array_method == NULL)
        get_array_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "getArrayValue", "(JLjava/lang/Object;I)I");
    if (set_array_method == NULL)
        set_array_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "setArrayValue", "(JLjava/lang/Object;I)I");
    if (bind_class_method == NULL)
        bind_class_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "javaBindClass",
                "(Ljava/lang/String;)Ljava/lang/Class;");
    if (create_proxy_method == NULL)
        create_proxy_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "createProxy", "(JLjava/lang/String;)I");
    if (create_array_method == NULL)
        create_array_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "createArray", "(JLjava/lang/String;)I");
    if (java_create_method == NULL)
        java_create_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "javaCreate", "(JLjava/lang/Class;)I");
    if (java_new_method == NULL)
        java_new_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "javaNew", "(JLjava/lang/Class;)I");
    if (object_call_method == NULL)
        object_call_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "objectCall", "(JLjava/lang/Object;)I");
    if (java_newinstance_method == NULL)
        java_newinstance_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "javaNewInstance",
                "(JLjava/lang/String;)I");
    if (as_table_method == NULL)
        as_table_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "asTable", "(JLjava/lang/Object;)I");
    if (to_string_method == NULL)
        to_string_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "javaToString", "(JLjava/lang/Object;)I");
    if (get_type_method == NULL)
        get_type_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "javaGetType", "(JLjava/lang/Object;)I");
    if (object_length_method == NULL)
        object_length_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "javaObjectLength",
                "(JLjava/lang/Object;)I");
    if (object_equals_method == NULL)
        object_equals_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "javaEquals",
                "(JLjava/lang/Object;Ljava/lang/Object;)I");
    if (java_gc_method == NULL)
        java_gc_method = (*javaEnv)->GetStaticMethodID(
                javaEnv, luajava_api_class, "javaGc", "(Ljava/lang/Object;)V");

    if (string_init_method == NULL)
        string_init_method = (*javaEnv)->GetMethodID(
                javaEnv, java_string_class, "<init>", "([BLjava/lang/String;)V");
    if (string_getbytes_method == NULL)
        string_getbytes_method = (*javaEnv)->GetMethodID(
                javaEnv, java_string_class, "getBytes", "(Ljava/lang/String;)[B");
    if (class_getname_method == NULL)
        class_getname_method = (*javaEnv)->GetMethodID(
                javaEnv, java_lang_class, "getName", "()Ljava/lang/String;");
    checkError(javaEnv, L);
}

#define NAME "__name"

static inline const char *getObjectName(lua_State *L, JNIEnv *env,
                                        jobject obj) {
    const char *name;

    lua_pushstring(L, NAME);
    lua_rawget(L, -2);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        jclass cls;
        char c;
        if ((*env)->IsInstanceOf(env, obj, java_lang_class) == JNI_TRUE) {
            c = '.';
            cls = (jclass) obj;
        } else {
            c = '@';
            cls = (*env)->GetObjectClass(env, obj);
            checkError(env, L);
        }

        /*lua_pushstring(L, "class");
        pushJavaObject(L,cls);
        lua_rawset(L, -3);*/

        jstring jstr = (*env)->CallObjectMethod(env, cls, class_getname_method);
        checkError(env, L);
        const char *cStr = (*env)->GetStringUTFChars(env, jstr, NULL);
        lua_pushstring(L, NAME);
        name = lua_pushfstring(L, "%s%c", cStr, c);
        lua_rawset(L, -3);

        (*env)->ReleaseStringUTFChars(env, jstr, cStr);
        (*env)->DeleteLocalRef(env, jstr);

        if (c == '@')
            (*env)->DeleteLocalRef(env, cls);
    } else {
        name = lua_tostring(L, -1);
        lua_pop(L, 1);
    }
    return name;
}

/***************************************************************************
*
*  Function: objectIndex
*  ****/

int objectIndex(lua_State *L) {
    jlong stateIndex;
    const char *key;
    const char *tag;
    jint ret = 0;
    jobject *obj;
    jstring str;
    JNIEnv *javaEnv;

    /* Gets the luaState index */
    stateIndex = checkIndex(L);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    /* Gets the object reference */
    obj = checkJavaObject(L, 1);
    /* if key is number get array value, if key is string get object field or
     * method. */
    if (lua_type(L, 2) == LUA_TNUMBER) {
        lua_Number akey = lua_tonumber(L, 2);
        jmethodID method;
        if ((*javaEnv)->IsInstanceOf(javaEnv, *obj, java_lang_class) == JNI_TRUE)
            method = new_array_method;
        else
            method = get_array_method;

        ret = (*javaEnv)->CallStaticIntMethod(javaEnv, luajava_api_class, method,
                                              stateIndex, *obj, (jint) akey);
        checkError(javaEnv, L);
        return 1;
    } else if (lua_type(L, 2) == LUA_TSTRING) {
        key = lua_tostring(L, 2);
        lua_getmetatable(L, 1);
        /* lua stack：1,object;2,key;3,metatable */
        if (lua_rawgeti(L, 3, (int) obj) == LUA_TNIL) {
            lua_pop(L, 1);
            lua_newtable(L);
            lua_pushvalue(L, -1);
            lua_rawseti(L, 3, (int) obj);
        }
        lua_pushvalue(L, 2);
        int mtype = lua_rawget(L, -2);
        //int mtype = lua_type(L, -1);
        if (mtype == LUA_TFUNCTION) {
            lua_pushvalue(L, 1);
            lua_setupvalue(L, -2, 2);
            return 1;
        }
        if (mtype != LUA_TNIL)
            return 1;

        lua_pop(L, 1);
        const char *name = getObjectName(L, javaEnv, *obj);
        //luaL_getsubtable(L, 3, "_CACHE");
        if (lua_rawgeti(L, 3, 0) == LUA_TNIL) {
            lua_pop(L, 1);
            lua_newtable(L);
            lua_pushvalue(L, -1);
            lua_rawseti(L, 3, 0);
        }
        lua_remove(L, 3);
        tag = lua_pushfstring(L, "%s%s", name, key);
        /* lua stack：1,object;2,key;3,objtable;4,cache;5,tag */

        lua_pushvalue(L, -1);
        lua_rawget(L, 4);
        int ctype = lua_type(L, -1);
        int type = 0;
        if (ctype == LUA_TNUMBER)
            type = (int) lua_tointeger(L, -1);

        lua_pop(L, 1);
        //lua_pushstring(L, tag);

        if (type != 2) {
            str = (*javaEnv)->NewStringUTF(javaEnv, key);
            ret = (*javaEnv)->CallStaticIntMethod(javaEnv, luajava_api_class,
                                                  object_index_method,
                                                  stateIndex, *obj, str, type);
            (*javaEnv)->DeleteLocalRef(javaEnv, str);
            checkError(javaEnv, L);
        }

        if (ctype == LUA_TNIL) {
            lua_pushvalue(L, 5);
            //lua_pushstring(L, tag);
            lua_pushinteger(L, ret);
            lua_rawset(L, 4);
        }

        if (ret == 2 || type == 2) {
            //lua_pushinteger(L, (int)obj);
            lua_pushvalue(L, 1);
            lua_pushcclosure(L, &callMethod, 2);
            lua_pushvalue(L, 2);
            lua_pushvalue(L, -2);
            lua_rawset(L, 3);
        } else if (ret == 3 || ret == 5) {
            lua_pushvalue(L, 2);
            lua_pushvalue(L, -2);
            lua_rawset(L, 3);
        } else if (ret == 0) {
            luaL_error(L, "%s is not a field or mothod", tag);
        }

    } else {
        lua_pushstring(L, "Invalid object index. Must be integer or string.");
        lua_error(L);
    }
    return 1;
}

/***************************************************************************
*
*  Function: callMethod
*  ****/

int callMethod(lua_State *L) {
    jlong stateIndex;
    jobject *obj;
    const char *methodName;
    jint ret;
    jstring str;
    JNIEnv *javaEnv;

    /* Gets the luaState index */
    stateIndex = checkIndex(L);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    /* Gets the methodName */
    methodName = lua_tostring(L, lua_upvalueindex(1));

    /* Gets the object reference */
    int udx = lua_upvalueindex(2);
    //obj = checkJavaObject(L, udx);
    //checkJavaObject(L, lua_upvalueindex(1));
    //obj = (jobject*)(int)lua_tointeger(L, lua_upvalueindex(2));
    obj = (jobject *) luaL_testudata(L, udx, LUAJAVAOBJECTMETA);
    if (obj == NULL) {
        luaL_error(L, "can not call the function %s", methodName);
    }

    str = (*javaEnv)->NewStringUTF(javaEnv, methodName);

    ret = (*javaEnv)->CallStaticIntMethod(javaEnv, luajava_api_class, call_method,
                                          stateIndex, *obj, str);
    (*javaEnv)->DeleteLocalRef(javaEnv, str);
    checkError(javaEnv, L);

    /* if no ret, return self */
    if (ret == 0) {
        lua_pushvalue(L, udx);
        ret = 1;
    }

    /* clear upvalue ref */
    lua_pushnil(L);
    lua_replace(L, udx);
    /* pushes new object into lua stack */
    return ret;
}

/***************************************************************************
*
*  Function: objectNewIndex
*  ****/

int objectNewIndex(lua_State *L) {
    jlong stateIndex;
    jobject *obj;
    const char *fieldName;
    const char *tag;
    lua_Number key;
    jstring str;
    jint ret;
    JNIEnv *javaEnv;

    /* Gets the luaState index */
    stateIndex = checkIndex(L);

    /* Gets the object reference */
    obj = checkJavaObject(L, 1);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    /* if key is number set array value, if key is string set object field value.
     */
    if (lua_type(L, 2) == LUA_TNUMBER) {
        key = lua_tonumber(L, 2);
        ret = (*javaEnv)->CallStaticIntMethod(javaEnv, luajava_api_class,
                                              set_array_method, stateIndex,
                                              *obj, (jint) key);
        checkError(javaEnv, L);
    } else if (lua_type(L, 2) == LUA_TSTRING) {
        /* Gets the field Name */
        fieldName = lua_tostring(L, 2);
        lua_getmetatable(L, 1);

        /* lua stack：1,object;2,key;3,value;4,metatable */
        if (lua_rawgeti(L, 4, (int) obj) == LUA_TNIL) {
            lua_pop(L, 1);
            lua_newtable(L);
            lua_pushvalue(L, -1);
            lua_rawseti(L, 4, (int) obj);
        }
        const char *name = getObjectName(L, javaEnv, *obj);
        //luaL_getsubtable(L, 3, "_CACHE");
        if (lua_rawgeti(L, 4, 0) == LUA_TNIL) {
            lua_pop(L, 1);
            lua_newtable(L);
            lua_pushvalue(L, -1);
            lua_rawseti(L, 4, 0);
        }
        lua_remove(L, 4);
        tag = lua_pushfstring(L, "%s->%s", name, fieldName);
        /* lua stack：1,object;2,key;3,value;4,objtable;5,cache;6,tag */

        lua_pushvalue(L, -1);
        lua_rawget(L, 5);
        int ctype = lua_type(L, -1);
        int type = 0;
        if (ctype == LUA_TNUMBER)
            type = (int) lua_tointeger(L, -1);

        lua_pop(L, 1);

        lua_pushvalue(L, 3);
        lua_remove(L, 3);

        str = (*javaEnv)->NewStringUTF(javaEnv, fieldName);

        ret = (*javaEnv)->CallStaticIntMethod(javaEnv, luajava_api_class,
                                              object_newindex_method,
                                              stateIndex, *obj, str, type);
        if (ctype == LUA_TNIL) {
            lua_pushvalue(L, 5);
            //lua_pushstring(L, tag);
            lua_pushinteger(L, ret);
            lua_rawset(L, 4);
        }
        if (ret == 0)
            luaL_error(L, "%s is not a field", fieldName);
        (*javaEnv)->DeleteLocalRef(javaEnv, str);
        checkError(javaEnv, L);
    } else {
        lua_pushstring(L, "Invalid object index. Must be integer or string.");
        lua_error(L);
    }
    return 0;
}

/***************************************************************************
*
*  Function: gc
*  ****/

int gc(lua_State *L) {
    jobject *pObj;
    JNIEnv *javaEnv;

    if (!isJavaObject(L, 1)) {
        return 0;
    }

    pObj = (jobject *) lua_touserdata(L, 1);
    lua_getmetatable(L, 1);
    lua_pushnil(L);
    lua_rawseti(L, -2, (int) pObj);
    lua_pop(L, 1);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);
    /*(*javaEnv)->CallStaticVoidMethod(javaEnv, luajava_api_class,
                                     java_gc_method,
                                     *pObj);
    checkError(javaEnv, L);*/
    (*javaEnv)->DeleteGlobalRef(javaEnv, *pObj);
    *pObj = NULL;
    return 0;
}

/***************************************************************************
*
*  Function: javaBindClass
*  ****/

int javaBindClass(lua_State *L) {
    int top;
    const char *className;
    jstring javaClassName;
    jobject classInstance;
    JNIEnv *javaEnv;

    top = lua_gettop(L);

    if (top != 1) {
        luaL_error(
                L, "Error. Function javaBindClass received %d arguments, expected 1.",
                top);
    }

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    /* get the string parameter */
    className = luaL_checkstring(L, 1);

    javaClassName = (*javaEnv)->NewStringUTF(javaEnv, className);

    classInstance = (*javaEnv)->CallStaticObjectMethod(
            javaEnv, luajava_api_class, bind_class_method, javaClassName);

    (*javaEnv)->DeleteLocalRef(javaEnv, javaClassName);
    checkError(javaEnv, L);

    /* pushes new object into lua stack */
    pushJavaObject(L, classInstance);
    (*javaEnv)->DeleteLocalRef(javaEnv, classInstance);
    return 1;
}

/***************************************************************************
*
*  Function: createProxy
*  ****/
int createProxy(lua_State *L) {
    jint ret;
    jlong stateIndex;
    const char *impl;
    jstring str;
    JNIEnv *javaEnv;

    if (lua_gettop(L) != 2) {
        lua_pushstring(L, "Error. Function createProxy expects 2 arguments.");
        lua_error(L);
    }

    /* Gets the luaState index */
    stateIndex = checkIndex(L);

    luaL_checktype(L, 2, LUA_TTABLE);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    impl = luaL_checkstring(L, 1);

    str = (*javaEnv)->NewStringUTF(javaEnv, impl);

    ret = (*javaEnv)->CallStaticIntMethod(
            javaEnv, luajava_api_class, create_proxy_method, stateIndex, str);

    (*javaEnv)->DeleteLocalRef(javaEnv, str);
    checkError(javaEnv, L);

    return 1;
}

/***************************************************************************
*
*  Function: createProxy
*  ****/
int newArray(lua_State *L) {
    jint ret;
    jlong stateIndex;
    jobject *clazz;
    JNIEnv *javaEnv;

    /* Gets the luaState index */
    stateIndex = checkIndex(L);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    /* Gets the object reference */
    clazz = checkJavaObject(L, 1);

    ret = (*javaEnv)->CallStaticIntMethod(
            javaEnv, luajava_api_class, new_multiarray_method, stateIndex, *clazz);

    checkError(javaEnv, L);

    return 1;
}

/***************************************************************************
*
*  Function: createArray
*  ****/
int createArray(lua_State *L) {
    jint ret;
    jlong stateIndex;
    const char *className;
    jstring str;
    JNIEnv *javaEnv;

    if (lua_gettop(L) != 2) {
        lua_pushstring(L, "Error. Function createProxy expects 2 arguments.");
        lua_error(L);
    }


    /* Gets the luaState index */
    stateIndex = checkIndex(L);

    luaL_checktype(L, 2, LUA_TTABLE);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    className = luaL_checkstring(L, 1);

    str = (*javaEnv)->NewStringUTF(javaEnv, className);

    ret = (*javaEnv)->CallStaticIntMethod(
            javaEnv, luajava_api_class, create_array_method, stateIndex, str);

    (*javaEnv)->DeleteLocalRef(javaEnv, str);
    checkError(javaEnv, L);

    return 1;
}

/***************************************************************************
*
*  Function: javaNew
*  ****/

int javaNew(lua_State *L) {
    int top;
    jint ret;
    jobject *classInstance;
    jlong stateIndex;
    JNIEnv *javaEnv;

    top = lua_gettop(L);

    if (top == 0) {
        lua_pushstring(L, "Error. Invalid number of parameters.");
        lua_error(L);
    }

    /* Gets the luaState index */
    stateIndex = checkIndex(L);

    /* Gets the java Class reference */
    classInstance = checkJavaObject(L, 1);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    if ((*javaEnv)->IsInstanceOf(javaEnv, *classInstance, java_lang_class) ==
        JNI_FALSE) {
        ret = (*javaEnv)->CallStaticIntMethod(javaEnv, luajava_api_class,
                                              object_call_method, stateIndex,
                                              *classInstance);
        checkError(javaEnv, L);
        if (ret == 0) {
            lua_pushstring(L, "Can not call a Java Object.");
            lua_error(L);
        }
    }
        /* if arg is table create array or interface, else create calss instance. */
    else if (lua_type(L, 2) == LUA_TTABLE && top == 2) {
        ret = (*javaEnv)->CallStaticIntMethod(javaEnv, luajava_api_class,
                                              java_create_method, stateIndex,
                                              *classInstance);
        checkError(javaEnv, L);
    } else {
        ret = (*javaEnv)->CallStaticIntMethod(javaEnv, luajava_api_class,
                                              java_new_method, stateIndex,
                                              *classInstance);
        checkError(javaEnv, L);
    }
    return ret;
}

/***************************************************************************
*
*  Function: javaNewInstance
*  ****/

int javaNewInstance(lua_State *L) {
    jint ret;
    const char *className;
    jstring javaClassName;
    jlong stateIndex;
    JNIEnv *javaEnv;

    /* Gets the luaState index */
    stateIndex = checkIndex(L);

    /* get the string parameter */
    className = luaL_checkstring(L, 1);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    javaClassName = (*javaEnv)->NewStringUTF(javaEnv, className);

    ret = (*javaEnv)->CallStaticIntMethod(javaEnv, luajava_api_class,
                                          java_newinstance_method,
                                          stateIndex, javaClassName);

    (*javaEnv)->DeleteLocalRef(javaEnv, javaClassName);
    checkError(javaEnv, L);

    return 1;
}

/***************************************************************************
*
*  Function: javaLoadLib
*  ****/

int javaLoadLib(lua_State *L) {
    jint ret;
    int top;
    const char *className, *methodName;
    jlong stateIndex;
    jmethodID method;
    jstring javaClassName, javaMethodName;
    JNIEnv *javaEnv;

    top = lua_gettop(L);

    if (top != 2) {
        lua_pushstring(L, "Error. Invalid number of parameters.");
        lua_error(L);
    }

    /* Gets the luaState index */
    stateIndex = checkIndex(L);

    className = luaL_checkstring(L, 1);
    methodName = luaL_checkstring(L, 2);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    method =
            (*javaEnv)->GetStaticMethodID(javaEnv, luajava_api_class, "javaLoadLib",
                                          "(ILjava/lang/String;Ljava/lang/String;)I");

    javaClassName = (*javaEnv)->NewStringUTF(javaEnv, className);
    javaMethodName = (*javaEnv)->NewStringUTF(javaEnv, methodName);

    ret = (*javaEnv)->CallStaticIntMethod(javaEnv, luajava_api_class, method,
                                          stateIndex, javaClassName,
                                          javaMethodName);

    (*javaEnv)->DeleteLocalRef(javaEnv, javaClassName);
    (*javaEnv)->DeleteLocalRef(javaEnv, javaMethodName);
    checkError(javaEnv, L);

    return ret;
}

int asTable(lua_State *L) {
    jint ret;
    jobject *obj;
    jlong stateIndex;
    JNIEnv *javaEnv;

    /* Gets the luaState index */
    stateIndex = checkIndex(L);

    /* Gets the java Object reference */
    obj = checkJavaObject(L, 1);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    ret = (*javaEnv)->CallStaticIntMethod(
            javaEnv, luajava_api_class, as_table_method, stateIndex, *obj);

    checkError(javaEnv, L);

    return 1;
}

/***************************************************************************
*
*  Function: javaToString
*  ****/

int javaToString(lua_State *L) {
    jint ret;
    jobject *obj;
    jlong stateIndex;
    JNIEnv *javaEnv;

    /* Gets the luaState index */
    stateIndex = checkIndex(L);

    /* Gets the java Object reference */
    //obj = checkJavaObject(L, 1);
    if (!isJavaObject(L, 1)) {
        luaL_tolstring(L, 1, NULL);
        return 1;
    }

    obj = (jobject *) lua_touserdata(L, 1);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    ret = (*javaEnv)->CallStaticIntMethod(
            javaEnv, luajava_api_class, to_string_method, stateIndex, *obj);

    checkError(javaEnv, L);

    return 1;
}

/***************************************************************************
*
*  Function: javaToString
*  ****/

int javaGetType(lua_State *L) {
    jint ret;
    jobject *obj;
    jlong stateIndex;
    JNIEnv *javaEnv;

    /* Gets the luaState index */
    stateIndex = checkIndex(L);

    /* Gets the java Object reference */
    //obj = checkJavaObject(L, 1);
    if (!isJavaObject(L, 1)) {
        luaL_tolstring(L, 1, NULL);
        return 1;
    }

    obj = (jobject *) lua_touserdata(L, 1);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    ret = (*javaEnv)->CallStaticIntMethod(
            javaEnv, luajava_api_class, get_type_method, stateIndex, *obj);

    checkError(javaEnv, L);

    return 1;
}


/***************************************************************************
*
*  Function: javaEquals
*  ****/

int javaEquals(lua_State *L) {
    jint ret;
    jobject *obj;
    jobject *obj2;
    jlong stateIndex;
    JNIEnv *javaEnv;

    if (!isJavaObject(L, 1) || !isJavaObject(L, 2)) {
        lua_pushboolean(L, lua_rawequal(L, 1, 2));
        return 1;
    }

    /* Gets the luaState index */
    stateIndex = checkIndex(L);

    /* Gets the java Object reference */
    obj = (jobject *) lua_touserdata(L, 1);
    obj2 = (jobject *) lua_touserdata(L, 2);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    ret = (*javaEnv)->CallStaticIntMethod(
            javaEnv, luajava_api_class, object_equals_method, stateIndex, *obj, *obj2);

    checkError(javaEnv, L);

    return 1;
}

/***************************************************************************
*
*  Function: javaObjectLength
*  ****/

int javaObjectLength(lua_State *L) {
    jint ret;
    jobject *obj;
    jlong stateIndex;
    JNIEnv *javaEnv;

    /* Gets the luaState index */
    stateIndex = checkIndex(L);

    /* Gets the java Class reference */
    obj = checkJavaObject(L, 1);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    ret = (*javaEnv)->CallStaticIntMethod(
            javaEnv, luajava_api_class, object_length_method, stateIndex, *obj);

    checkError(javaEnv, L);

    return 1;
}

/***************************************************************************
*
*  Function: javaGetContext
*  ****/

int javaGetContext(lua_State *L) {
    lua_pushstring(L, "_LuaContext");
    lua_gettable(L, LUA_REGISTRYINDEX);
    return 1;
}

int coding(lua_State *L) {
    /* Gets t((he JNI Environment */
    JNIEnv *env = checkEnv(L);

    size_t size = 0;
    const char *str = luaL_checklstring(L, 1, &size);
    const char *srcEncoding = luaL_optstring(L, 2, "GBK");
    const char *destEncoding = luaL_optstring(L, 3, "UTF8");

    jbyteArray arr = (*env)->NewByteArray(env, size);
    jbyte *data = (*env)->GetByteArrayElements(env, arr, 0);
    memcpy(data, str, size);
    (*env)->ReleaseByteArrayElements(env, arr, data, 0);

    jstring strEncoding = (*env)->NewStringUTF(env, srcEncoding);
    jstring newstr = (jstring) (*env)->NewObject(
            env, java_string_class, string_init_method, arr, strEncoding);
    (*env)->DeleteLocalRef(env, arr);
    (*env)->DeleteLocalRef(env, strEncoding);
    checkError(env, L);

    jstring strDestEncoding = (*env)->NewStringUTF(env, destEncoding);
    jbyteArray byteArr = (*env)->CallObjectMethod(
            env, newstr, string_getbytes_method, strDestEncoding);
    (*env)->DeleteLocalRef(env, strDestEncoding);
    (*env)->DeleteLocalRef(env, newstr);
    checkError(env, L);

    jbyte *newArr = (*env)->GetByteArrayElements(env, byteArr, 0);
    jsize newLen = (*env)->GetArrayLength(env, byteArr);

    lua_pushlstring(L, (const char *) newArr, newLen);
    (*env)->ReleaseByteArrayElements(env, byteArr, newArr, 0);
    (*env)->DeleteLocalRef(env, byteArr);

    return 1;
}

int javaIsInstanceOf(lua_State *L) {
    int top;
    jobject *classInstance;
    jclass *clazz;
    JNIEnv *javaEnv;

    top = lua_gettop(L);

    if (top == 0) {
        lua_pushstring(L, "Error. Invalid number of parameters.");
        lua_error(L);
    }

    /* Gets the java Class reference */
    classInstance = checkJavaObject(L, 1);

    clazz = checkJavaObject(L, 2);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    if ((*javaEnv)->IsInstanceOf(javaEnv, *classInstance, *clazz) == JNI_TRUE) {
        lua_pushboolean(L, 1);
    } else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

static const luaL_Reg ljobjectmeta[] = {{"__index",    objectIndex},
                                        {"__newindex", objectNewIndex},
                                        {"__call",     javaNew},
                                        {"__len",      javaObjectLength},
                                        {"__tostring", javaToString},
                                        {"__type",     javaGetType},
                                        {"__gc",       gc},
                                        {"__eq",       javaEquals},
                                        {NULL, NULL}};

/***************************************************************************
*
*  Function: pushJavaObject
*  ****/

int pushJavaObject(lua_State *L, jobject javaObject) {
    jobject *userData, globalRef;

    /* Gets the JNI Environment */
    JNIEnv *javaEnv = checkEnv(L);

    globalRef = (*javaEnv)->NewGlobalRef(javaEnv, javaObject);
    checkError(javaEnv, L);
//LOGD("Java object %d %d",&javaObject,&globalRef);

    userData = (jobject *) lua_newuserdata(L, sizeof(jobject));
    *userData = globalRef;
    luaL_setmetatable(L, LUAJAVAOBJECTMETA);
    return 1;
    /*
    lua_newtable(L);
    luaL_setfuncs(L, ljobjectmeta, 0);
    lua_pushstring(L, LUAJAVAOBJECTIND);
    lua_pushboolean(L, 1);
    lua_rawset(L, -3);

    if (lua_setmetatable(L, -2) == 0) {
      lua_pushstring(L, "Cannot create proxy to java object.");
      lua_error(L);
    }

    return 1;*/
}

/***************************************************************************
*
*  Function: isJavaObject
*  ****/

int inline isJavaObject(lua_State *L, int idx) {
    if (!lua_isuserdata(L, idx))
        return 0;

    if (lua_getmetatable(L, idx) == 0)
        return 0;

    lua_pushstring(L, LUAJAVAOBJECTIND);
    lua_rawget(L, -2);

    if (lua_isnil(L, -1)) {
        lua_pop(L, 2);
        return 0;
    }
    lua_pop(L, 2);
    return 1;
}

/***************************************************************************
*
*  Function: getStateFromCPtr
*  ****/
lua_State *getStateFromCPtr(JNIEnv *env, jlong cptr) {
    lua_State *L;
    L = (lua_State *) cptr;

    pushJNIEnv(env, L);

    return L;
}

/***************************************************************************
*
*  Function: luaJavaFunctionCall
*  ****/

int luaJavaFunctionCall(lua_State *L) {
    jobject *obj;
    int ret;
    JNIEnv *javaEnv;

    if (!isJavaObject(L, 1)) {
        lua_pushstring(L, "Not a java Function.");
        lua_error(L);
    }

    obj = lua_touserdata(L, 1);

    /* Gets the JNI Environment */
    javaEnv = checkEnv(L);

    /* the Object must be an instance of the JavaFunction class */
    if ((*javaEnv)->IsInstanceOf(javaEnv, *obj, java_function_class) ==
        JNI_FALSE) {
        fprintf(stderr, "Called Java object is not a JavaFunction\n");
        return 0;
    }

    ret = (*javaEnv)->CallIntMethod(javaEnv, *obj, java_function_method);

    checkError(javaEnv, L);

    return ret;
}

/***************************************************************************
*
*  Function: luaJavaFunctionCall
*  ****/

JNIEnv *getEnvFromState(lua_State *L) {
    JNIEnv **udEnv;

    lua_pushstring(L, LUAJAVAJNIENVTAG);
    lua_rawget(L, LUA_REGISTRYINDEX);

    if (!lua_isuserdata(L, -1)) {
        lua_pop(L, 1);
        return NULL;
    }

    udEnv = (JNIEnv **) lua_touserdata(L, -1);

    lua_pop(L, 1);

    return *udEnv;
}

/***************************************************************************
*
*  Function: pushJNIEnv
*  ****/

void pushJNIEnv(JNIEnv *env, lua_State *L) {
    JNIEnv **udEnv;

    lua_pushstring(L, LUAJAVAJNIENVTAG);
    lua_rawget(L, LUA_REGISTRYINDEX);

    if (!lua_isnil(L, -1)) {
        udEnv = (JNIEnv **) lua_touserdata(L, -1);
        *udEnv = env;
        lua_pop(L, 1);
    } else {
        lua_pop(L, 1);
        udEnv = (JNIEnv **) lua_newuserdata(L, sizeof(JNIEnv *));
        *udEnv = env;

        lua_pushstring(L, LUAJAVAJNIENVTAG);
        lua_insert(L, -2);
        lua_rawset(L, LUA_REGISTRYINDEX);
    }
}

static const char *luajava_skip_spaces(const char *text) {
    while (*text != '\0' && isspace((unsigned char) *text)) {
        text++;
    }
    return text;
}

static int cppBlock(lua_State *L) {
    const char *block = luaL_checkstring(L, 1);
    const char *cursor = luajava_skip_spaces(block);
    const char *arg_start;
    size_t i = 0;
    size_t len;
    char command[64];

    while (cursor[i] != '\0' && !isspace((unsigned char) cursor[i]) && i < sizeof(command) - 1) {
        command[i] = cursor[i];
        i++;
    }
    command[i] = '\0';
    cursor += i;
    arg_start = luajava_skip_spaces(cursor);

    if (command[0] == '\0') {
        return luaL_error(L, "cppBlock requires command");
    }

    if (strcmp(command, "log") == 0) {
        LOGD("%s", arg_start);
        lua_pushboolean(L, 1);
        return 1;
    }

    if (strcmp(command, "strlen") == 0) {
        lua_pushinteger(L, (lua_Integer) strlen(arg_start));
        return 1;
    }

    if (strcmp(command, "toupper") == 0) {
        char *out;
        size_t j;
        len = strlen(arg_start);
        out = (char *) malloc(len + 1);
        if (out == NULL) {
            return luaL_error(L, "Out of memory in cpp toupper");
        }
        for (j = 0; j < len; j++) {
            out[j] = (char) toupper((unsigned char) arg_start[j]);
        }
        out[len] = '\0';
        lua_pushlstring(L, out, len);
        free(out);
        return 1;
    }

    if (strcmp(command, "add") == 0) {
        char *endptr;
        double left;
        double right;
        left = strtod(arg_start, &endptr);
        if (endptr == arg_start) {
            return luaL_error(L, "cpp add expects: add <number> <number>");
        }
        arg_start = luajava_skip_spaces(endptr);
        right = strtod(arg_start, &endptr);
        if (endptr == arg_start) {
            return luaL_error(L, "cpp add expects: add <number> <number>");
        }
        lua_pushnumber(L, left + right);
        return 1;
    }

    return luaL_error(L, "Unknown cpp command: %s", command);
}

/*
 ** Assumes the table is on top of the stack.
 */
static void set_info(lua_State *L) {
    lua_pushliteral(L, "_COPYRIGHT");
    lua_pushliteral(L, "Copyright (C) 2003-2007 Kepler Project");
    lua_settable(L, -3);
    lua_pushliteral(L, "_DESCRIPTION");
    lua_pushliteral(L, "LuaJava is a script tool for Java");
    lua_settable(L, -3);
    lua_pushliteral(L, "_NAME");
    lua_pushliteral(L, "LuaJava");
    lua_settable(L, -3);
    lua_pushliteral(L, "_MOD");
    lua_pushliteral(L, "by nirenr");
    lua_settable(L, -3);
    lua_pushliteral(L, "_VERSION");
    lua_pushliteral(L, "4.0");
    lua_settable(L, -3);
}

static const luaL_Reg ljlib[] = {{"bindClass",   javaBindClass},
                                 {"new",         javaNew},
                                 {"newInstance", javaNewInstance},
                                 {"loadLib",     javaLoadLib},
                                 {"cppBlock",    cppBlock},
                                 {"createProxy", createProxy},
                                 {"newArray",    newArray},
                                 {"createArray", createArray},
                                 {"astable",     asTable},
                                 {"tostring",    javaToString},
                                 {"coding",      coding},
                                 {"clear",       gc},
                                 {"instanceof",  javaIsInstanceOf},
                                 {"getContext",  javaGetContext},
                                 {NULL, NULL}};

LUALIB_API int luaopen_luajava(lua_State *L) {
    JNIEnv *env;

    luaL_newlib(L, ljlib);
    set_info(L);

    luaL_newmetatable(L, LUAJAVAOBJECTMETA);
    luaL_setfuncs(L, ljobjectmeta, 0);
    lua_pushstring(L, LUAJAVAOBJECTIND);
    lua_pushboolean(L, 1);
    lua_rawset(L, -3);
    lua_pop(L, 1);
    env = checkEnv(L);
    init(env, L);
    return 1;
}

/**************************** JNI FUNCTIONS ****************************/

/************************************************************************
*   JNI Called function
*      LuaJava API Functin
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1openLuajava(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L;


    L = getStateFromCPtr(env, cptr);

    lua_pushstring(L, LUAJAVASTATEINDEX);
    lua_pushinteger(L, (lua_Integer) cptr);
    lua_settable(L, LUA_REGISTRYINDEX);
    pushJNIEnv(env, L);

    // luaopen_luajava( L );
    luaL_requiref(L, "luajava", luaopen_luajava, 1);
}

/************************************************************************
*   JNI Called function
*      LuaJava API Functin
************************************************************************/

JNIEXPORT jobject JNICALL
Java_com_luajava_LuaState__1getObjectFromUserdata(JNIEnv *env, jobject jobj,
                                                  jlong cptr, jint index) {
    /* Get luastate */
    lua_State *L = getStateFromCPtr(env, cptr);
    jobject *obj;

    if (!isJavaObject(L, index)) {
        (*env)->ThrowNew(env, (*env)->FindClass(env, "java/lang/Exception"),
                         "Index is not a java object");
        return NULL;
    }

    obj = (jobject *) lua_touserdata(L, index);

    return *obj;
}

/************************************************************************
*   JNI Called function
*      LuaJava API Functin
************************************************************************/

JNIEXPORT jboolean JNICALL
Java_com_luajava_LuaState__1isObject(JNIEnv *env, jobject jobj, jlong cptr,
                                     jint index) {
    /* Get luastate */
    lua_State *L = getStateFromCPtr(env, cptr);

    return (isJavaObject(L, index) ? JNI_TRUE : JNI_FALSE);
}

/************************************************************************
*   JNI Called function
*      LuaJava API Functin
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1pushJavaObject(JNIEnv *env, jobject jobj,
                                           jlong cptr, jobject obj) {
    /* Get luastate */
    lua_State *L = getStateFromCPtr(env, cptr);

    pushJavaObject(L, obj);
}

/************************************************************************
*   JNI Called function
*      LuaJava API Functin
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1pushJavaFunction(JNIEnv *env, jobject jobj,
                                             jlong cptr, jobject obj) {
    /* Get luastate */
    lua_State *L = getStateFromCPtr(env, cptr);

    jobject *userData, globalRef;

    globalRef = (*env)->NewGlobalRef(env, obj);

    userData = (jobject *) lua_newuserdata(L, sizeof(jobject));
    *userData = globalRef;

    /* Creates metatable */
    lua_newtable(L);

    /* pushes the __call metamethod */
    lua_pushstring(L, LUACALLMETAMETHODTAG);
    lua_pushcfunction(L, &luaJavaFunctionCall);
    lua_rawset(L, -3);

    /* pusher the __gc metamethod */
    lua_pushstring(L, LUAGCMETAMETHODTAG);
    lua_pushcfunction(L, &gc);
    lua_rawset(L, -3);

    /* pushes the __tostring metamethod */
    lua_pushstring(L, LUATOSTRINGMETAMETHODTAG);
    lua_pushcfunction(L, &javaToString);
    lua_rawset(L, -3);

    lua_pushstring(L, LUAJAVAOBJECTIND);
    lua_pushboolean(L, 1);
    lua_rawset(L, -3);

    if (lua_setmetatable(L, -2) == 0) {
        (*env)->ThrowNew(env, (*env)->FindClass(env, "com/luajava/LuaException"),
                         "Index is not a java object");
    }
}

/************************************************************************
*   JNI Called function
*      LuaJava API Functin
************************************************************************/

JNIEXPORT jboolean JNICALL
Java_com_luajava_LuaState__1isJavaFunction(JNIEnv *env, jobject jobj,
                                           jlong cptr, jint idx) {
    /* Get luastate */
    lua_State *L = getStateFromCPtr(env, cptr);
    jobject *obj;

    if (!isJavaObject(L, idx)) {
        return JNI_FALSE;
    }

    obj = (jobject *) lua_touserdata(L, idx);

    return (*env)->IsInstanceOf(env, *obj, java_function_class);
}

/*********************** LUA API FUNCTIONS ******************************/

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jlong JNICALL
Java_com_luajava_LuaState__1newstate(JNIEnv *env, jobject jobj) {
    lua_State *L = luaL_newstate();
    return (jlong) L;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1openBase(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    // luaopen_base( L );
    luaL_requiref(L, "", luaopen_base, 1);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1openTable(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    // luaopen_table( L );
    luaL_requiref(L, LUA_TABLIBNAME, luaopen_table, 1);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1openIo(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    // luaopen_io( L );
    luaL_requiref(L, LUA_IOLIBNAME, luaopen_io, 1);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1openOs(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    // luaopen_os( L );
    luaL_requiref(L, LUA_OSLIBNAME, luaopen_os, 1);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL Java_com_luajava_LuaState__1openString(JNIEnv *env,
                                                              jobject jobj,
                                                              jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    // luaopen_string( L );
    luaL_requiref(L, LUA_STRLIBNAME, luaopen_string, 1);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1openMath(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    // luaopen_math( L );
    luaL_requiref(L, LUA_MATHLIBNAME, luaopen_math, 1);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1openDebug(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    // luaopen_debug( L );
    luaL_requiref(L, LUA_DBLIBNAME, luaopen_debug, 1);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL Java_com_luajava_LuaState__1openPackage(JNIEnv *env,
                                                               jobject jobj,
                                                               jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    // luaopen_package( L );
    luaL_requiref(L, LUA_LOADLIBNAME, luaopen_package, 1);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1openLibs(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    luaL_openlibs(L);
    lua_getglobal(L, "package");
    if (lua_istable(L, -1)) {
        lua_pushcfunction(L, luajava_compat_seeall);
        lua_setfield(L, -2, "seeall");
    }
    lua_pop(L, 1);
    lua_pushcfunction(L, luajava_compat_module);
    lua_setglobal(L, "module");
    lua_pushcfunction(L, luajava_compat_loadstring);
    lua_setglobal(L, "loadstring");
    lua_pushcfunction(L, luajava_compat_unpack);
    lua_setglobal(L, "unpack");
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT void JNICALL
Java_com_luajava_LuaState__1close(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);

    lua_close(L);
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

JNIEXPORT jlong JNICALL
Java_com_luajava_LuaState__1newthread(JNIEnv *env, jobject jobj, jlong cptr) {
    lua_State *L = getStateFromCPtr(env, cptr);
    lua_State *newThread;

    newThread = lua_newthread(L);
    return (jlong) newThread;
}

/************************************************************************
*   JNI Called function
*      Lua Exported Function
************************************************************************/

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

    ret = luaL_loadbuffer(L, (const char *) cBuff, (int) sz, name);

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

    ret = luaL_loadstring(L, fn);

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
