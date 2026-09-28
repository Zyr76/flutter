-- flutter_布局示例.lua
-- 用 AndroLua 布局表风格写 Flutter 布局：首元素是控件、数字下标项是子控件、属性 key=value。
-- 控件名/属性名沿用 Flutter 的英文名；渲染入口用中文名 渲染Flutter（等价 flutterRender）。

local hint = "提示：点按钮 / 输入 / 拖动滑块，事件会显示在这里"

-- ============ 可复用的小块 ============
local function statCard(num, label, color)
  return { Expanded, {
    Card, elevation = 0, color = "#E8EAF6", padding = 12,
    { Column, crossAxisAlignment = "center", gap = 4,
      { Text, text = num, fontSize = 20, fontWeight = "bold", color = color },
      { Text, text = label, fontSize = 12, color = "#8A8A8A" } },
  } }
end

local function entry(icon, label, color)
  return { Column, crossAxisAlignment = "center", gap = 6,
    { Container, width = 44, height = 44, radius = 12, color = color, alignment = "center",
      { Icon, icon = icon, color = "#FFFFFF", size = 22 } },
    { Text, text = label, fontSize = 12, color = "#333333" } }
end

local function orderRow(title, sub, status, sColor)
  return { ListTile, leading = "star", title = title, subtitle = sub, trailing = status,
           color = sColor, onTap = { call = "ping" } }
end

-- ============ 整页 ============
local function page()
  return {
    Column,
    -- 顶部：头像 + 昵称 + 签到
    { Container, color = "#3F51B5", padding = { 20, 28, 20, 28 },
      { Row, gap = 16,
        { CircleAvatar, radius = 32, color = "#FFFFFF",
          { Text, text = "张", fontSize = 26, fontWeight = "bold", color = "#3F51B5" } },
        { Expanded, { Column, crossAxisAlignment = "start", gap = 4,
          { Text, text = "张三", fontSize = 22, fontWeight = "bold", color = "#FFFFFF" },
          { Text, text = "VIP 会员 · 已实名", fontSize = 13, color = "#DDDDFF" } } },
        { Button, text = "签到", onClick = { call = "ping" } } } },

    -- 事件横幅
    { Container, color = "#FFF9C4", padding = { 16, 10, 16, 10 },
      { Row, gap = 8,
        { Icon, icon = "arrow_forward", color = "#F9A825", size = 18 },
        { Expanded, { Text, text = hint, fontSize = 12, color = "#795548" } } } },

    -- 主体（可滚动）
    { Expanded, { ListView, padding = 16,
      { Row, gap = 12,
        statCard("12", "本月订单", "#3F51B5"),
        statCard("3", "待收货", "#FF9800"),
        statCard("88", "积分", "#4CAF50") },

      { Text, text = "快捷入口", fontSize = 16, fontWeight = "bold" },
      { GridView, crossAxisCount = 4, gap = 10,
        entry("home", "首页", "#3F51B5"), entry("star", "收藏", "#FF9800"),
        entry("person", "好友", "#4CAF50"), entry("settings", "设置", "#607D8B"),
        entry("search", "搜索", "#009688"), entry("add", "发布", "#E91E63"),
        entry("favorite", "喜欢", "#F44336"), entry("check", "待办", "#795548") },

      { Wrap, gap = 8, runSpacing = 8,
        { Chip, text = "Flutter" }, { Chip, text = "Lua" }, { Chip, text = "AndroLua" },
        { Chip, text = "Dart" }, { Chip, text = "AOT" } },

      { Divider },
      { Text, text = "我的订单", fontSize = 16, fontWeight = "bold" },
      { Card, elevation = 1, {
        Column,
        orderRow("订单 #1001", "2026-09-20 · 2 件", "已完成", "#4CAF50"),
        { Divider },
        orderRow("订单 #1002", "2026-09-21 · 1 件", "待付款", "#FF9800"),
        { Divider },
        orderRow("订单 #1003", "2026-09-22 · 5 件", "已发货", "#2196F3") } },

      { Divider },
      { Text, text = "设置", fontSize = 16, fontWeight = "bold" },
      { TextField, hint = "昵称（输入会回传事件）", onChange = "输入昵称" },
      { Row, gap = 12,
        { Expanded, { Text, text = "接收推送", fontSize = 14 } },
        { Switch, value = true, onChange = "切换推送" } },
      { Row, gap = 12,
        { Expanded, { Text, text = "同意协议", fontSize = 14 } },
        { Checkbox, value = true, color = "#3F51B5", onChange = "勾选同意" } },
      { Text, text = "音量", fontSize = 14 },
      { Slider, min = 0, max = 100, value = 50, onChange = "调整音量" },

      { Divider },
      { Text, text = "进度 / 堆叠 / 内嵌原生", fontSize = 16, fontWeight = "bold" },
      { LinearProgressIndicator, value = 0.6 },
      { CircularProgressIndicator, value = 0.3 },
      { Stack, height = 80,
        { Container, width = "fill", height = 80, radius = 12, color = "#E3F2FD" },
        { Positioned, left = 12, top = 12,
          { Text, text = "Stack + Positioned", fontSize = 14, color = "#1565C0" } } },
      { Container, height = 130,
        { AndroidView, viewType = "androlua/native", text = "Flutter 里嵌的 Android 原生控件" } },

      { Divider },
      { Text, text = "调用 Dart", fontSize = 16, fontWeight = "bold" },
      { Button, text = "同步：getUserInfo({id=7})", width = "fill",
        onClick = { call = "getUserInfo", args = { id = 7 } } },
      { Button, text = "异步：add(3,4) 后取用户", width = "fill",
        onClick = { event = "异步加", call = "add", args = { a = 3, b = 4 } } },
    } },

    -- 底部操作栏
    { Container, color = "#FAFAFA", padding = 12,
      { Row, gap = 12,
        { Expanded, { TextButton, text = "退出登录", onClick = "ping" } },
        { Expanded, { Button, text = "立即下单",
          onClick = { call = "toUpper", args = { text = "订单已创建" } } } } } },
  }
end

-- ============ 渲染 + 事件 ============
local function refresh()
  渲染Flutter(page())
end

activity.setContentView(渲染Flutter(page()))

function onFlutterEvent(e)
  local name = (e and e.name) or "?"
  local d = (e and e.data) or {}

  if name == "输入昵称" then
    print("输入：" .. tostring(d.value))
    return   -- 输入时不重绘，避免打断输入
  end

  local msg = "事件：" .. name
  if d.action and d.action ~= "" then msg = msg .. "  action=" .. d.action end
  if d.value ~= nil then msg = msg .. "  value=" .. tostring(d.value) end
  if d.result then
    if d.result.name then msg = msg .. "  name=" .. tostring(d.result.name) end
    if d.result.result then msg = msg .. "  result=" .. tostring(d.result.result) end
    if d.result.pong ~= nil then msg = msg .. "  pong=" .. tostring(d.result.pong) end
    if d.result.text then msg = msg .. "  text=" .. tostring(d.result.text) end
  end
  hint = msg

  -- 异步 dartCall 演示：回调在主线程，可安全刷新 UI
  if name == "异步加" then
    调用Dart("getUserInfo", { id = 9 }, function(res, err)
      if res then
        hint = "异步返回：name=" .. tostring(res.name)
      else
        hint = "异步出错：" .. tostring(err)
      end
      refresh()
    end)
    return
  end

  refresh()
end
