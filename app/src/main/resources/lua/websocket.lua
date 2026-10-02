-- ============================================================
-- websocket.lua —— 基于 OkHttp 的 WebSocket 客户端（纯 Lua，无需额外 Java 代码）
--
-- OkHttp 自带完整的 WebSocket 实现（ws/wss、分片、自动 TLS），
-- 这里用 luajava 的「抽象类表式覆写」把它接过来：
--   luajava.new(WebSocketListener, { onOpen=…, onMessage=…, … })
--
-- 用法：
--   local websocket = require "websocket"
--   local ws = websocket.connect("wss://example.com/ws", {
--     headers   = { Authorization = "Bearer xxx" },   -- 握手请求头（可选）
--     onOpen    = function(ws, response) end,
--     onMessage = function(ws, textOrTable, isBinary) end,
--     onClose   = function(ws, code, reason) end,
--     onError   = function(ws, err) end,
--     reconnect        = true,     -- 断线自动重连（默认 false）
--     reconnectDelay   = 2000,     -- 首次重连延时（毫秒），失败后翻倍
--     maxReconnectDelay= 30000,
--     pingInterval     = 20,       -- 心跳间隔（秒），>0 才启用（OkHttp 内置 ping）
--     connectTimeout   = 15,       -- 连接超时（秒）
--     json             = false,    -- true 时 onMessage 自动 json.decode（解析失败给原文）
--   })
--
--   ws.send("hello")          -- 发文本（返回 true/false）
--   ws.sendBinary(原始字节)   -- 发二进制（参数是 Lua 字符串，按字节原样发）
--   ws.sendJson{ type = "hi" }-- 发 JSON
--   ws.readyState()           -- "connecting" / "open" / "closing" / "closed"
--   ws.close()                -- 正常关闭（1000）
--   ws.close(4001, "bye")     -- 自定义关闭码
--   ws.cancel()               -- 直接掐断（不握手）
--
--   onMessage 的第三个参数 isBinary 为 true 时，第二个参数就是「原始字节字符串」
--   （可用 string.byte 遍历，或自己转 hex；文本消息不受影响）
--
--   Chinese 别名：发送 / 发送二进制 / 发送JSON / 关闭 / 取消 / 状态
--
-- ⚠ 回调跑在 OkHttp 的网络线程上：要改界面请用 activity.runOnUiThread(function() … end)
-- ============================================================
local M = {}

local 客户端池 = {}

-- Lua 字符串 <-> okio.ByteString（走 hex 转换：不依赖 Java 数组下标，最稳）
local function 字节串(数据)
  return luajava.bindClass("okio.ByteString").decodeHex((数据:gsub(".", function(c)
    return string.format("%02x", string.byte(c))
  end)))
end

local function 从字节串(bs)
  return (bs.hex():gsub("(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end))
end

local function 取客户端(心跳秒, 超时秒)
  local key = tostring(心跳秒) .. "/" .. tostring(超时秒)
  local c = 客户端池[key]
  if c then
    return c
  end
  local b = luajava.newInstance("okhttp3.OkHttpClient$Builder")
  if 心跳秒 and 心跳秒 > 0 then
    b.pingInterval(心跳秒, luajava.bindClass("java.util.concurrent.TimeUnit").SECONDS)
  end
  if 超时秒 and 超时秒 > 0 then
    b.connectTimeout(超时秒, luajava.bindClass("java.util.concurrent.TimeUnit").SECONDS)
  end
  c = b.build()
  客户端池[key] = c
  return c
end

-- 在主线程延时执行（重连用，指数退避）
local function 延时执行(毫秒, 函数)
  local handler = luajava.newInstance("android.os.Handler",
      luajava.bindClass("android.os.Looper").getMainLooper())
  handler.postDelayed(luajava.createProxy("java.lang.Runnable", { run = 函数 }), 毫秒)
end

--- 连接一个 WebSocket；返回操作用的 ws 句柄
function M.connect(url, opts)
  opts = opts or {}
  local ws, sock              -- 前置声明：回调里要用
  local 状态 = "connecting"
  local 主动关闭 = false
  local 重试延时 = opts.reconnectDelay or 2000
  local 客户端 = 取客户端(opts.pingInterval, opts.connectTimeout or 15)
  local 请求头 = opts.headers or {}
  local jsonLib = opts.json and require("json") or nil
  local 排重连                  -- 前置声明

  local function 通知(名, ...)
    local f = opts[名]
    if f then
      f(ws, ...)
    end
  end

  local function 建监听()
    return luajava.new(luajava.bindClass("okhttp3.WebSocketListener"), {
      onOpen = function(s, response)
        状态 = "open"
        重试延时 = opts.reconnectDelay or 2000
        通知("onOpen", response)
      end,
      onMessage = function(s, data)
        local 文本, 二进制
        if type(data) == "userdata" then
          二进制 = true
          文本 = 从字节串(data)     -- 原始字节，不做 UTF-8 解释
        else
          二进制 = false
          文本 = tostring(data)
        end
        local 值 = 文本
        if jsonLib and not 二进制 then
          local ok, v = pcall(jsonLib.decode, 文本)
          if ok then 值 = v end
        end
        通知("onMessage", 值, 二进制)
      end,
      onClosing = function(s, code, reason)
        状态 = "closing"
      end,
      onClosed = function(s, code, reason)
        状态 = "closed"
        通知("onClose", code, reason)
        if opts.reconnect and not 主动关闭 then
          排重连()
        end
      end,
      onFailure = function(s, t, response)
        状态 = "closed"
        通知("onError", tostring(t))
        if opts.reconnect and not 主动关闭 then
          排重连()
        end
      end,
    })
  end

  local function 连接()
    local rb = luajava.newInstance("okhttp3.Request$Builder")
    rb.url(url)
    for k, v in pairs(请求头) do
      rb.addHeader(tostring(k), tostring(v))
    end
    sock = 客户端.newWebSocket(rb.build(), 建监听())
    状态 = "connecting"
  end

  排重连 = function()
    延时执行(重试延时, function()
      if 主动关闭 then
        return
      end
      连接()
    end)
    重试延时 = math.min(重试延时 * 2, opts.maxReconnectDelay or 30000)
  end

  local function 发送(内容)
    if not sock then
      return false
    end
    return sock.send(tostring(内容))
  end

  local function 关闭(code, reason)
    主动关闭 = true
    if sock then
      sock.close(code or 1000, reason or "normal")
    end
  end

  ws = {
    url = url,
    send = 发送,
    发送 = 发送,
    sendBinary = function(数据)
      if not sock then
        return false
      end
      return sock.send(字节串(tostring(数据)))
    end,
    发送二进制 = function(数据)
      if not sock then
        return false
      end
      return sock.send(字节串(tostring(数据)))
    end,
    sendJson = function(t)
      return 发送((jsonLib or require("json")).encode(t))
    end,
    发送JSON = function(t)
      return 发送((jsonLib or require("json")).encode(t))
    end,
    close = 关闭,
    关闭 = 关闭,
    cancel = function()
      主动关闭 = true
      if sock then
        sock.cancel()
      end
    end,
    取消 = function()
      主动关闭 = true
      if sock then
        sock.cancel()
      end
    end,
    readyState = function()
      return 状态
    end,
    状态 = function()
      return 状态
    end,
    raw = function()
      return sock
    end,
    重连 = 连接,
    reconnect = 连接,
  }

  连接()
  return ws
end

return M
