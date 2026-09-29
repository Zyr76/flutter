-- AndroLua + Flutter 三合一演示
--   1) 原生 UI：loadlayout 建 TextView / FrameLayout / Button
--   2) Flutter UI：flutterRender 用 Lua 表描述 widget 树
--   3) Dart 逻辑：dartCall("getUserInfo", {...}) 拿返回
-- 三者同屏，原生区与 Flutter 区可互发事件。

require "import"
import "android.widget.*"
import "android.view.*"

activity.setTitle("AndroLua + Flutter")

-- 1) 原生布局：中间留一个 FrameLayout 给 FlutterView
--   注意：这里是【原生 loadlayout】布局，控件必须用 Android 类名（Button=android.widget.Button）；
--        Flutter 控件名（如 ElevatedButton）只在下面的 flutterRender spec 里用。
local layout = {
  LinearLayout,
  orientation = "vertical",
  { TextView, id = "hint", text = "↑ 原生 TextView：由 loadlayout 创建" },
  { FrameLayout, id = "flutterHost", layout_width = "fill", layout_height = 0, layout_weight = 1 },
  { Button, id = "nativeBtn", text = "native Button：dartCall('getUserInfo')" },
}
activity.setContentView(loadlayout(layout))
hint.setPadding(24, 24, 24, 24)

-- 2) Flutter 区：widget 描述写成 Lua 表，Java 侧转 JSON 交给 Dart 渲染
--    这里必须用 Flutter 自己的控件名（ElevatedButton / Column / Text ...）
local spec = {
  type = "Column",
  gap = 10,
  padding = 16,
  children = {
    { type = "Text", text = "↓ 以下是 Flutter 自绘 UI", fontSize = 13, color = "#888888" },
    { type = "Text", text = "Flutter 自绘 Text", fontSize = 24, fontWeight = "bold", color = "#3F51B5" },
    {
      type = "ElevatedButton",
      text = "Flutter Button：调 Dart add(3,4)",
      onTap = { call = "add", args = { a = 3, b = 4 } },
    },
    { type = "TextField", hint = "Flutter 输入框（输入会回传事件）" },
    -- Flutter 里再嵌 Android 原生控件（PlatformView）
    {
      type = "AndroidView",
      viewType = "androlua/native",
      text = "这段是 Flutter 里嵌的 Android 原生控件",
      height = 150,
    },
  },
}
flutterRender(spec, flutterHost)

-- 3) Dart -> 原生 事件（Flutter 点按钮、输入、内嵌原生按钮点击都会走到这）
function onFlutterEvent(e)
  local name = e and e.name or "?"
  local data = e and e.data
  local msg = "Flutter 事件：" .. name
  if data then
    if data.action then msg = msg .. " | action=" .. data.action end
    if data.value then msg = msg .. " | value=" .. tostring(data.value) end
    if data.result then
      local r = data.result.result or data.result.text or ""
      msg = msg .. " | result=" .. tostring(r)
    end
  end
  hint.setText(msg)
end

-- 原生按钮 -> Dart 逻辑：dartCall 需要离开主线程（在 thread 里跑）
nativeBtn.onClick = function()
  hint.setText("正在通过 dartCall 调用 Dart getUserInfo ...")
  thread(function()
    local info = dartCall("getUserInfo", { id = 7 })
    activity.runOnUiThread(function()
      if info then
        hint.setText("Dart getUserInfo 返回：name=" .. tostring(info.name)
          .. ", age=" .. tostring(info.age) .. ", vip=" .. tostring(info.vip))
      else
        hint.setText("dartCall 返回 nil")
      end
    end)
  end)
end
