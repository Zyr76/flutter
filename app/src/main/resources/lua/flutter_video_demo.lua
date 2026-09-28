-- flutter_video_demo.lua
-- 视频播放器：界面全部用 Flutter 布局，视频画面是内嵌的 Android 原生 VideoView。
-- 逻辑在 Lua：Flutter 按钮 onTap → dartCall → 通道 androlua/video → 原生播放器。
-- 网络/本地都可：http(s):// 或 file:///sdcard/xxx.mp4

local URL = "https://www.w3schools.com/html/mov_bbb.mp4"  -- 换成本地或自己的视频地址

local status = "就绪 · 点「播放」开始"

local function build()
  return {
    type = "Column",
    gap = 12,
    children = {
      -- 顶部标题（Flutter 画）
      { type = "Container", color = "#3F51B5", padding = { 16, 20, 16, 20 }, children = {
        { type = "Row", gap = 12, children = {
          { type = "Container", width = 40, height = 40, radius = 20, color = "#FFFFFF", children = {
            { type = "Center", children = { { type = "Icon", icon = "arrow_forward", color = "#3F51B5", size = 20 } } } } },
          { type = "Expanded", children = {
            { type = "Column", crossAxisAlignment = "start", gap = 2, children = {
              { type = "Text", text = "视频播放器", fontSize = 18, fontWeight = "bold", color = "#FFFFFF" },
              { type = "Text", text = "Flutter 外壳 + 原生 VideoView 画面", fontSize = 12, color = "#DDDDFF" },
            } } } },
        } },
      } },

      -- 视频画面：内嵌原生 VideoView（自带原生控制条，可拖进度）
      { type = "Container", height = 220, color = "#000000", children = {
        { type = "AndroidView", viewType = "androlua/video",
          params = { url = URL, autoplay = false } },
      } },

      -- 状态（Flutter 文本）
      { type = "Text", text = status, fontSize = 13, color = "#3F51B5" },

      -- 控制按钮（Flutter 按钮 → dartCall → 原生播放器）
      { type = "Row", gap = 8, children = {
        { type = "Expanded", children = { {
            type = "Button", text = "播放", onTap = { call = "videoPlay" } } } },
        { type = "Expanded", children = { {
            type = "Button", text = "暂停", onTap = { call = "videoPause" } } } },
        { type = "Expanded", children = { {
            type = "TextButton", text = "重载", onTap = { call = "videoLoad", args = { url = URL } } } } },
      } },

      { type = "Text", text = "提示：也可以用画面上的原生控制条拖动进度",
        fontSize = 12, color = "#888888" },
    },
  }
end

-- 整页交给 Flutter 布局（注意：不要因事件重新 flutterRender，否则会重建视频视图）
activity.setContentView(flutterRender(build()))

-- 播放器事件 / 按钮结果回传
function onFlutterEvent(e)
  local name = (e and e.name) or "?"
  local d = (e and e.data) or {}

  if name == "videoEvent" then
    local ev = d.event
    local msg = "播放器事件：" .. tostring(ev)
    if ev == "prepared" and d.data then
      msg = msg .. "  时长 " .. tostring(d.data) .. " ms"
    elseif ev == "error" then
      msg = msg .. "  what=" .. tostring(d.data and d.data.what)
    end
    print(msg)
  else
    print("事件：" .. name .. "  action=" .. tostring(d.action))
  end
end
