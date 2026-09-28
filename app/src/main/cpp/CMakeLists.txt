cmake_minimum_required(VERSION 4.1.2)
project(luajava)

enable_language(C)

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





# 链接系统库
target_link_libraries(luajava bson cjson canvas crypt md5 xml socket
    android
    log
    
)
