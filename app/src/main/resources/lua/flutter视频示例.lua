-- Flutter 视频播放器 控制示例
--
-- 演示「Lua 端完全控制 Flutter 的 VideoPlayer」：
--   播放 / 暂停 / 切换 / 快进后退 / 按百分比跳转 / 音量 / 倍速 / 循环 / 查状态 / 事件
--
-- 控制方式：dartCall("flutterControl", { id="v", action=..., ... }, callback)
-- 事件方式：定义 onFlutterEvent(e)，e.name == "flutterVideoEvent"
-- 语法与全部动作见 renderer.dart 里 FlutterControl 的注释。

require "import"
import "android.widget.*"
import "android.view.*"

-- 可改成 /sdcard/xxx.mp4（本地文件）或 assets 里的文件名
local URL = "https://media.w3.org/2010/05/sintel/trailer.mp4"

activity.setTitle("Flutter 视频控制示例")

-- Flutter 界面：状态文字 + 视频（都带 id，Lua 可控制）
local host = FrameLayout(activity)
渲染Flutter({
  Scaffold,
  backgroundColor = "#FFFFFF",
  body = {
    Column,
    { Text, id = "status", text = "状态：准备中…", fontSize = 14, padding = 8 },
    { Expanded, {
        VideoPlayer, id = "v", url = URL,
        controls = true,        -- 自带一个播放/暂停按钮
        -- autoPlay = true,     -- 想自动播放就打开
        -- loop = true,         -- 想循环就打开
      } },
  },
}, host)

local function show(s)
  print("[video] " .. s)
  if status then status.dart.Text = "状态：" .. s end
end

-- 统一控制封装
local function ctl(action, extra, cb)
  local a = { id = "v", action = action }
  if extra then for k, v in pairs(extra) do a[k] = v end end
  dartCall("flutterControl", a, cb or function(res, err)
    show(action .. " -> " .. (err or tostring(res)))
  end)
end

-- 取当前进度后按偏移跳转（seek 需要绝对位置，所以先查再算）
local function seekBy(deltaMs)
  ctl("state", nil, function(res, err)
    if err or not res or not res.ok then
      show("取状态失败: " .. tostring(err))
      return
    end
    local pos = (res.position or 0) + deltaMs
    if pos < 0 then pos = 0 end
    ctl("seek", { pos = pos })
  end)
end

-- Flutter -> Lua 事件（ready / state / completed / error）
function onFlutterEvent(e)
  if e and e.name == "flutterVideoEvent" then
    local d = e.data or {}
    show(string.format("%s  %d/%d ms%s", tostring(d.type),
      d.position or 0, d.duration or 0, d.isPlaying and "  ▶ 播放中" or ""))
  end
end

-- 底部按钮
local bar = LinearLayout(activity)
bar.setOrientation(LinearLayout.HORIZONTAL)
local function btn(txt, fn)
  local b = Button(activity)
  b.setText(txt)
  b.setOnClickListener(fn)
  bar.addView(b)
  return b
end

btn("播放", function() ctl("play") end)
btn("暂停", function() ctl("pause") end)
btn("切换", function() ctl("toggle") end)
btn("-5s", function() seekBy(-5000) end)
btn("+5s", function() seekBy(5000) end)
btn("25%", function() ctl("seekPercent", { percent = 25 }) end)
btn("静音", function() ctl("volume", { volume = 0 }) end)
btn("有声", function() ctl("volume", { volume = 1 }) end)
btn("2x", function() ctl("speed", { speed = 2 }) end)
btn("1x", function() ctl("speed", { speed = 1 }) end)
btn("循环开", function() ctl("loop", { loop = true }) end)
btn("循环关", function() ctl("loop", { loop = false }) end)
btn("查状态", function()
  ctl("state", nil, function(res, err)
    show("state -> " .. (err or tostring(res)))
  end)
end)

local root = LinearLayout(activity)
root.setOrientation(LinearLayout.VERTICAL)
root.addView(host, LinearLayout.LayoutParams(-1, 0, 1))
root.addView(bar, LinearLayout.LayoutParams(-1, -2))
activity.setContentView(root)
