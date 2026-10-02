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

# 创建共享库
add_library(luajava SHARED
    luajava.c
    
    ${LUA_SOURCES}
)
add_library(bson SHARED
    bson/lua-bson.c
    ${LUA_SOURCES}
)
add_library(canvas SHARED
    canvas/canvas.c
    ${LUA_SOURCES}
)
add_library(cjson SHARED
    cjson/lua_cjson.c
    cjson/fpconv.c
    cjson/strbuf.c
    ${LUA_SOURCES}
)
add_library(crypt SHARED
    crypt/lcrypt.c
    crypt/lsha1.c
    ${LUA_SOURCES}
)




add_library(md5 SHARED
    md5/md5.c
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

    ${LUA_SOURCES}
)



add_library(xml SHARED
    xml/xml.c
    ${LUA_SOURCES}
)





# yyjson：高性能 JSON 库（yyjson.c 为官方 amalgamation，MIT；lua_yyjson.c 是本项目的绑定）
add_library(yyjson SHARED
    yyjson/lua_yyjson.c
    yyjson/yyjson.c

    ${LUA_SOURCES}
)


# 链接系统库
target_link_libraries(luajava bson cjson canvas crypt md5 xml socket yyjson
    android
    log
    dl
)
