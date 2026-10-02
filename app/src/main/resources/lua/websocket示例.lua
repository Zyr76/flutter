-- ============================================================
-- WebSocket 示例（基于 websocket.lua / OkHttp）
--
-- 改下面对应的地址即可连你自己的服务（ws:// 和 wss:// 都支持）。
-- 界面：顶部状态栏 + 输入框 + 发送/断开/重连按钮 + 事件日志
--
-- 说明：
--   * 回调跑在 OkHttp 线程，本示例直接改 Lua 状态并重渲染（引擎内部已加锁），
--     但不要在回调里做耗时运算——会占住连接线程。
--   * 断线自动重连已开（指数退避 2s → 4s → 8s…），日志里能看到重连过程。
-- ============================================================
require "import"
import "android.widget.*"
import "android.view.*"

local websocket = require "websocket"

activity.setTitle("WebSocket 示例")

-- ⚠ 换成你自己的 WebSocket 地址
local 地址 = "wss://你的服务器/ws"

local host = FrameLayout(activity)
local 日志 = {}
local 状态 = { 连接 = "连接中", ws = nil }

local 渲染                      -- 前置声明

local function 加日志(行)
  日志[#日志 + 1] = os.date("%H:%M:%S ") .. 行
  if #日志 > 300 then
    table.remove(日志, 1)
  end
  渲染()
end

local function 界面()
  local 行 = {}
  for i = 1, #日志 do
    行[i] = { ListTile, dense = true, title = { Text, text = 日志[i], fontSize = 12 } }
  end
  if #行 == 0 then
    行[1] = { Text, text = "（等待事件…）", fontSize = 12, color = "#888888" }
  end
  return {
    Scaffold,
    appBar = { AppBar, centerTitle = true,
      title = { Text, text = "WebSocket · " .. 状态.连接 } },
    body = { Column, padding = 10, gap = 8,
      { Row, gap = 8,
        { Expanded, { TextField, id = "msg", hint = "输入内容，回车或点发送", onSubmitted = "发送" } },
        { ElevatedButton, text = "发送", onClick = "发送" },
        { OutlinedButton, text = "断开", onClick = "断开连接" },
        { OutlinedButton, text = "重连", onClick = "重连" } },
      { Expanded, { ListView, table.unpack(行) } } },
  }
end

渲染 = function()
  渲染Flutter(界面(), host)
end

local function 连接()
  if 状态.ws then
    状态.ws.close()
    状态.ws = nil
  end
  状态.连接 = "连接中"
  状态.ws = websocket.connect(地址, {
    reconnect = true,
    reconnectDelay = 2000,
    maxReconnectDelay = 30000,
    pingInterval = 20,          -- OkHttp 内置心跳
    connectTimeout = 15,
    -- json = true,             -- 想自动解析 JSON 就把这行打开
    onOpen = function(ws, response)
      状态.连接 = "已连接"
      加日志("已连接：" .. tostring(ws.url))
    end,
    onMessage = function(ws, 数据, 二进制)
      加日志((二进制 and "[二进制] " or "收到：") .. tostring(数据))
    end,
    onClose = function(ws, code, reason)
      状态.连接 = "已断开"
      加日志(string.format("已关闭 code=%s reason=%s", tostring(code), tostring(reason)))
    end,
    onError = function(ws, err)
      状态.连接 = "出错（会自动重连）"
      加日志("错误：" .. tostring(err))
    end,
  })
  渲染()
end

-- ---------------- 事件 ----------------
function 发送(e)
  local 文本 = type(e) == "table" and e.value or nil
  local function 真发送(t)
    if t and t ~= "" and 状态.ws then
      状态.ws.send(t)
      加日志("发送：" .. t)
    end
  end
  if 文本 and 文本 ~= "" then
    真发送(文本)
  else
    -- 从按钮进来：先把输入框里的内容读出来
    dartCall("flutterControl", { id = "msg", action = "textState" }, function(res, err)
      真发送(res and res.text)
    end)
  end
end

function 断开连接()
  if 状态.ws then
    状态.ws.close()
  end
end

function 重连()
  加日志("手动重连…")
  连接()
end

function onFlutterEvent(e)
  if e and e.name and e.name ~= "buttonClick" then
    print("[ws示例]", e.name)
  end
end

activity.setContentView(host)
渲染()
连接()
