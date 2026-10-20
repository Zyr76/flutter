cmake_minimum_required(VERSION 4.1.2)
project(luajava)

enable_language(C)

# 允许中文标识符（Lua 词法 lctype.c 的 LUA_UCID 开关）：让 Lua 脚本能用
# { 列, 文字="hi" }、渲染Flutter(...) 这类中文语法。
#
# LUA_USE_DLOPEN：打开 package.loadlib 的 dlopen 实现，这样 require "cjson" / "yyjson"
# 这类 C 扩展模块才能加载（安卓上靠 LuaApplication 把 package.cpath 设成
# nativeLibraryDir + "/lib?.so"）。不开的话 require 会报 “dynamic libraries not enabled”。
# LUA_USE_POSIX：启用 POSIX 化的实现——主要目的是让 `io.popen` 真正可用
# （不开时 liolib.c 把 l_popen 定义成报错宏，io.popen 调用即报 "'popen' not supported"）。
# 附带：gmtime_r/localtime_r（线程安全）、l_inspectstat 正确解析退出码、
# l_getc 用 getc_unlocked、ldo.c 用 _setjmp/_longjmp（bionic 已提供）。
add_compile_definitions(LUA_UCID LUA_USE_DLOPEN LUA_USE_POSIX)

# 包含 Lua 头文件
include_directories(lua)

# 收集 lua/ 目录下所有 .c 文件
file(GLOB LUA_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/lua/*.c
)

# 排除可执行程序入口（避免 multiple definition of `main`）
list(REMOVE_ITEM LUA_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/lua/lua.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/lua/luac.c"
)

# LUAX 加密脚本支持。lua/lauxlib.c 的 luaL_loadfilex 引用了 luax_loadfile，
# 所以凡是编译 LUA_SOURCES 的目标都必须带上这两个文件，否则链接报
# undefined symbol: luax_loadfile。每个 .so 各自持有一份实现（密钥也随之重复）。
set(LUA_EXTRA_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/chacha20.c
    ${CMAKE_CURRENT_SOURCE_DIR}/luax.c
)

# 创建共享库
add_library(luajava SHARED
    luajava.c
    ${LUA_EXTRA_SOURCES}
    ${LUA_SOURCES}
)
add_library(bson SHARED
    bson/lua-bson.c
    ${LUA_EXTRA_SOURCES}
    ${LUA_SOURCES}
)
add_library(canvas SHARED
    canvas/canvas.c
    ${LUA_EXTRA_SOURCES}
    ${LUA_SOURCES}
)
add_library(cjson SHARED
    cjson/lua_cjson.c
    cjson/fpconv.c
    cjson/strbuf.c
    ${LUA_EXTRA_SOURCES}
    ${LUA_SOURCES}
)
add_library(crypt SHARED
    crypt/lcrypt.c
    crypt/lsha1.c
    ${LUA_EXTRA_SOURCES}
    ${LUA_SOURCES}
)




add_library(md5 SHARED
    md5/md5.c
    ${LUA_EXTRA_SOURCES}
    ${LUA_SOURCES}
)

add_library(socket SHARED
    socket/luasocket.c
    socket/timeout.c
    socket/buffer.c
    socket/io.c
    socket/auxiliar.c
    socket/options.c
    socket/inet.c
    socket/tcp.c
    socket/udp.c
    socket/except.c
    socket/select.c
    socket/usocket.c

    ${LUA_EXTRA_SOURCES}
    ${LUA_SOURCES}
)



add_library(xml SHARED
    xml/xml.c
    ${LUA_EXTRA_SOURCES}
    ${LUA_SOURCES}
)





# yyjson：高性能 JSON 库（yyjson.c 为官方 amalgamation，MIT；lua_yyjson.c 是本项目的绑定）
add_library(yyjson SHARED
    yyjson/lua_yyjson.c
    yyjson/yyjson.c

    ${LUA_EXTRA_SOURCES}
    ${LUA_SOURCES}
)


# 链接系统库
target_link_libraries(luajava bson cjson canvas crypt md5 xml socket yyjson
    android
    log
    dl
)

# ---- LUAX 加密容器模块 ----
# app/src/main/luaxso/*.lua 中每个模块都被加密后放进独立的 .so 数据段，
# .so 文件名为 lib<模块名>.so，模块名 = 原文件名 base64url（去填充）。
# 运行时 require "<模块名>" 由 lua 侧的 LUAX searcher 接管：dlopen 取数据段、
# 解密、执行模块体。容器本身不含任何 Lua 代码，只有 luax_blob/luax_blob_len 两个符号。
set(LUAXSO_TOOL     ${CMAKE_CURRENT_SOURCE_DIR}/../../../tools/luaxso.py)
set(LUAXSO_SRC_DIR  ${CMAKE_CURRENT_SOURCE_DIR}/luaxso)
set(LUAXSO_GEN_DIR  ${CMAKE_CURRENT_BINARY_DIR}/luaxso_containers)
file(MAKE_DIRECTORY ${LUAXSO_GEN_DIR})
file(GLOB LUAXSO_MODULES ${LUAXSO_SRC_DIR}/*.lua)
foreach(lua_file ${LUAXSO_MODULES})
    execute_process(
        COMMAND python3 ${LUAXSO_TOOL} gen ${lua_file} -o ${LUAXSO_GEN_DIR}
        OUTPUT_VARIABLE luax_mod_name
        ERROR_VARIABLE luax_mod_log
        RESULT_VARIABLE luax_gen_rc
    )
    if(NOT luax_gen_rc EQUAL 0)
        message(FATAL_ERROR "luaxso 生成失败: ${lua_file}\n${luax_mod_log}")
    endif()
    string(STRIP "${luax_mod_name}" luax_mod_name)
    string(REPLACE "-" "_" luax_target "luaxso_${luax_mod_name}")
    add_library(${luax_target} SHARED ${LUAXSO_GEN_DIR}/luax_blob_${luax_mod_name}.c)
    set_target_properties(${luax_target} PROPERTIES OUTPUT_NAME "${luax_mod_name}")
    message(STATUS "LUAX 容器: lib${luax_mod_name}.so <- ${lua_file}")
endforeach()
