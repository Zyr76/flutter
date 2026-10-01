-- ============================================================
-- Flutter UI 使用示例（完整版）
--
-- 菜单 → 12 个演示页，覆盖常用控件族：
--   布局 / 文本 / 按钮 / 输入与选择 / 列表与网格 / 卡片与信息
--   导航(标签页/抽屉/底栏) / 弹窗与提示 / 动画 / 图表与二维码 / 媒体 / 原生混合
--
-- 三套交互手段都在这里用到：
--   1) 属性：  节点.dart.属性 = 值          （任意带 id 的控件，运行期即时生效）
--   2) 事件：  onClick/onChange="函数名"    （事件名即函数名）；也可用句柄：控件.onClick
--   3) 命令：  dartCall("flutterControl", {id=, action=, ...})  （滚动/文本/媒体/标签页…）
--   4) 总监听：onFlutterEvent(e)             （能收到所有事件）
-- ============================================================

require "import"
import "android.widget.*"
import "android.view.*"

activity.setTitle("Flutter UI 示例")

local host = FrameLayout(activity)
local showMenu, open, render
local DEMOS = {}

-- ============================================================
-- 通用：页面外壳（AppBar + 返回按钮）
-- ============================================================
local function shell(title, body, extra)
  local s = {
    Scaffold,
    backgroundColor = "#F6F6F8",
    appBar = { AppBar, centerTitle = true,
      title = { Text, text = title },
      leading = { IconButton, icon = "arrow_back", onClick = "uiBack" } },
    body = body,
  }
  if extra then
    for k, v in pairs(extra) do s[k] = v end
  end
  return s
end

-- ============================================================
-- 1) 布局基础
-- ============================================================
DEMOS[#DEMOS + 1] = { "布局基础", "Row / Expanded / Stack / Wrap / AspectRatio", function()
  return shell("布局基础", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 12,
      { Card, { Padding, padding = 12, { Column, gap = 8,
          { Text, text = "Row + Expanded（按权重分宽）", fontWeight = "bold" },
          { Row, gap = 8,
            { Expanded, { Container, height = 40, radius = 8, color = "#4caf50", alignment = "center",
                { Text, text = "1", color = "#ffffff" } } },
            { Expanded, flex = 2, { Container, height = 40, radius = 8, color = "#2196f3", alignment = "center",
                { Text, text = "2 (flex=2)", color = "#ffffff" } } },
            { Expanded, { Container, height = 40, radius = 8, color = "#ff9800", alignment = "center",
                { Text, text = "3", color = "#ffffff" } } } } } } },
      { Card, { Padding, padding = 12, { Column, gap = 8,
          { Text, text = "Stack + Positioned（层叠定位）", fontWeight = "bold" },
          { Stack, height = 120,
            { Container, width = "fill", height = 120, color = "#e3f2fd" },
            { Positioned, left = 12, top = 12, { Text, text = "左上" } },
            { Positioned, right = 12, bottom = 12, { Text, text = "右下" } },
            { Positioned, left = 12, bottom = 12, { Text, text = "左下", color = "#888888" } } } } } },
      { Card, { Padding, padding = 12, { Column, gap = 8,
          { Text, text = "Wrap（流式换行）", fontWeight = "bold" },
          { Wrap, gap = 8, runSpacing = 8,
            { Chip, text = "标签 A" }, { Chip, text = "标签 B" }, { Chip, text = "标签 C" },
            { Chip, text = "标签 D" }, { Chip, text = "标签 E" }, { Chip, text = "标签 F" } } } } },
      { Card, { Padding, padding = 12, { Column, gap = 8,
          { Text, text = "AspectRatio（固定比例）", fontWeight = "bold" },
          { AspectRatio, ratio = 16 / 9,
            { Container, color = "#673ab7", radius = 8, alignment = "center",
              { Text, text = "16 : 9", color = "#ffffff" } } } } } },
    },
  })
end }

-- ============================================================
-- 2) 文本与样式
-- ============================================================
DEMOS[#DEMOS + 1] = { "文本与样式", "字号/粗斜体/下划线/行高/字距/省略/对齐", function()
  return shell("文本与样式", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 10, crossAxisAlignment = "start",
      { Text, text = "默认 Text" },
      { Text, text = "18sp 加粗 蓝色", fontSize = 18, fontWeight = "bold", color = "#2196f3" },
      { Text, text = "斜体 + 下划线", fontStyle = "italic", decoration = "underline" },
      { Text, text = "删除线 + 字距 2", decoration = "lineThrough", letterSpacing = 2 },
      { Text, text = "行高 1.8：多行文本的行距会按倍数放大，看起来更松快一些。", height = 1.8 },
      { Text, text = "单行省略：Flutter 由 Lua 描述界面，这行故意写得很长很长很长很长", maxLines = 1, overflow = "ellipsis" },
      { Text, text = "居中文本", textAlign = "center", width = "fill" },
      { Text, text = "阴影文本", fontSize = 20, color = "#333333",
        shadows = { { color = "#999999", blurRadius = 4, offsetX = 2, offsetY = 2 } } },
      { SelectableText, text = "可长按选中的文本（SelectableText）", fontSize = 15 },
      { Row, gap = 12,
        { Icon, icon = "home", color = "#4caf50" },
        { Icon, icon = "settings", color = "#ff9800", size = 28 },
        { Icon, icon = "favorite", color = "#e91e63", size = 32 } },
    },
  })
end }

-- ============================================================
-- 3) 按钮
-- ============================================================
function btnTip(e)
  tip.dart.Text = "刚点了：" .. tostring(e and (e.action or e.id or "按钮"))
end

DEMOS[#DEMOS + 1] = { "按钮", "四种按钮 / 图标按钮 / 悬浮按钮 / 开关组", function()
  return shell("按钮", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 12,
      { ElevatedButton, id = "btn1", text = "ElevatedButton", onClick = "btnTip" },
      { FilledButton, id = "btn2", text = "FilledButton", onClick = "btnTip" },
      { OutlinedButton, id = "btn3", text = "OutlinedButton", onClick = "btnTip" },
      { TextButton, id = "btn4", text = "TextButton", onClick = "btnTip" },
      { ElevatedButton, id = "btn5", text = "禁用状态", enabled = false },
      { Row, gap = 16,
        { IconButton, icon = "favorite", color = "#e91e63", onClick = "btnTip" },
        { IconButton, icon = "share", onClick = "btnTip" },
        { FloatingActionButton, icon = "add", onClick = "btnTip" } },
      { Text, text = "开关组（ToggleButtons）" },
      { ToggleButtons, onChange = "toggleChanged", isSelected = { true, false, false },
        { Icon, icon = "format_bold" }, { Icon, icon = "format_italic" }, { Icon, icon = "format_underlined" } },
      { Text, id = "tip", text = "（点击按钮看这里）", fontSize = 13, color = "#666666" },
    },
  })
end }

function toggleChanged(e)
  tip.dart.Text = "开关组选中项：" .. tostring(e and e.value)
end

-- ============================================================
-- 4) 输入与选择
-- ============================================================
DEMOS[#DEMOS + 1] = { "输入与选择", "TextField / Switch / Checkbox / Radio / Slider / 下拉 / 搜索", function()
  return shell("输入与选择", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 12,
      { TextField, id = "name", label = "姓名", hint = "请输入姓名" },
      { TextField, id = "pwd", label = "密码", obscure = true },
      { TextField, id = "note", label = "备注（多行）", maxLines = 3 },
      { Row, gap = 10, { Text, text = "开关" }, { Switch, id = "sw", value = false, onChange = "swChange" } },
      { Row, gap = 10, { Text, text = "复选" }, { Checkbox, id = "cb", value = false, onChange = "cbChange" } },
      { Text, text = "单选" },
      { Row, gap = 20,
        { Radio, id = "ra", groupValue = "a", value = "a", onChange = "radioChange" },
        { Radio, id = "rb", groupValue = "a", value = "b", onChange = "radioChange" } },
      { Text, text = "滑块" },
      { Slider, id = "sd", value = 40, min = 0, max = 100, divisions = 10, onChange = "sdChange" },
      { Text, text = "区间滑块" },
      -- end 是 Lua 保留字，键名只能写大写 End（引擎会规范化为 end）
      { RangeSlider, start = 20, End = 60, min = 0, max = 100, onChange = "rsChange" },
      { DropdownButton, id = "dd", value = "Lua",
        items = { { value = "Java", text = "Java" }, { value = "Kotlin", text = "Kotlin" }, { value = "Lua", text = "Lua" } },
        onChange = "ddChange" },
      { SearchBar, id = "sb", hint = "搜索点什么…" },
      { Row, gap = 10,
        { ElevatedButton, text = "读取输入框", onClick = "readInput" },
        { OutlinedButton, text = "清空输入框", onClick = "clearInput" } },
      { Text, id = "formTip", text = "改动上面的控件，这里会实时更新", fontSize = 13, color = "#666666" },
    },
  })
end }

function swChange(e) formTip.dart.Text = "开关：" .. (e.value and "开" or "关") end
function cbChange(e) formTip.dart.Text = "复选：" .. (e.value and "选中" or "未选中") end
function sdChange(e) formTip.dart.Text = "滑块：" .. tostring(math.floor((e.value or 0) + 0.5)) end
function rsChange(e) formTip.dart.Text = "区间：" .. tostring(math.floor((e.value or 0) + 0.5)) end
function ddChange(e) formTip.dart.Text = "下拉选择：" .. tostring(e.value) end

function radioChange(e)
  local v = e.value
  formTip.dart.Text = "单选：" .. tostring(v)
  -- 用属性回写选中态（两个 Radio 的 groupValue 都改成新值）
  if ra then ra.dart.GroupValue = v end
  if rb then rb.dart.GroupValue = v end
end

function readInput()
  dartCall("flutterControl", { id = "name", action = "textState" }, function(res, err)
    formTip.dart.Text = err and ("读取失败：" .. err) or ("姓名 = " .. tostring(res and res.text))
  end)
end

function clearInput()
  dartCall("flutterControl", { id = "name", action = "clear" })
  dartCall("flutterControl", { id = "note", action = "clear" })
  sw.dart.Value = false
  formTip.dart.Text = "已清空输入框"
end

-- ============================================================
-- 5) 列表与网格
-- ============================================================
DEMOS[#DEMOS + 1] = { "列表与网格", "懒加载 ListView / GridView / 横向列表 / 滚动控制", function()
  return shell("列表与网格", {
    Column, gap = 0,
      { Expanded, { ListView, id = "lv", itemCount = 200,
          itemTemplate = { ListTile,
            title = { Text, text = "$index 行标题", fontSize = 16 },
            subtitle = { Text, text = "懒加载：只构建可见项", fontSize = 12, color = "#999999" },
            onTap = "rowTap" } } },
      { Text, text = "网格（GridView 3 列）", padding = 8, fontWeight = "bold" },
      { SizedBox, height = 140, { GridView, id = "gv", itemCount = 9, crossAxisCount = 3, gap = 6,
          itemTemplate = { Container, margin = 2, radius = 8, color = "#90caf9", alignment = "center",
            { Text, text = "$index", color = "#0d47a1" } } } },
      { SizedBox, height = 90, { ListView, scrollDirection = "horizontal", padding = 8,
          { Container, width = 120, height = 70, margin = 4, radius = 8, color = "#a5d6a7", alignment = "center", { Text, text = "横向 1" } },
          { Container, width = 120, height = 70, margin = 4, radius = 8, color = "#ffe082", alignment = "center", { Text, text = "横向 2" } },
          { Container, width = 120, height = 70, margin = 4, radius = 8, color = "#ef9a9a", alignment = "center", { Text, text = "横向 3" } } } },
  }, {
    -- 底部按钮：演示 flutterControl 的滚动命令
    bottomNavigationBar = { BottomAppBar, { Row, gap = 8, padding = 6,
        { TextButton, text = "到底", onClick = "lvEnd" },
        { TextButton, text = "回顶", onClick = "lvTop" },
        { TextButton, text = "+800px", onClick = "lvBy" } } },
  })
end }

function rowTap(e) end     -- 列表行点击（总监听里能看到 rowTap 事件）

function lvEnd() dartCall("flutterControl", { id = "lv", action = "scrollToEnd" }) end
function lvTop() dartCall("flutterControl", { id = "lv", action = "scrollToStart" }) end
function lvBy() dartCall("flutterControl", { id = "lv", action = "scrollBy", delta = 800 }) end

-- ============================================================
-- 6) 卡片与信息展示
-- ============================================================
DEMOS[#DEMOS + 1] = { "卡片与信息", "Card / ListTile / Chip / Badge / 头像 / 进度 / 折叠面板", function()
  return shell("卡片与信息", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 12,
      { Card, elevation = 3, radius = 12,
        { ListTile,
          leading = { CircleAvatar, radius = 18, color = "#2196f3", { Text, text = "L", color = "#ffffff" } },
          title = { Text, text = "带头像的列表项" },
          subtitle = { Text, text = "leading / title / subtitle / trailing" },
          trailing = { Icon, icon = "chevron_right" },
          onTap = "rowTap" } },
      { ListTile, leading = { Icon, icon = "wifi" }, title = { Text, text = "另一条 ListTile" } },
      { Row, gap = 8,
        { Chip, text = "标签" }, { Chip, avatar = "star", text = "带头像" },
        { Badge, label = "9", { Icon, icon = "notifications", size = 28 } } },
      { Text, text = "进度指示" },
      { LinearProgressIndicator, value = 0.35 },
      { CircularProgressIndicator, value = 0.6 },
      { ExpansionTile, id = "exp", title = { Text, text = "折叠面板（点击标题展开）" },
        { Padding, padding = 12, { Text, text = "这是折叠面板里的内容。" } } },
      { Row, gap = 10,
        { ElevatedButton, text = "展开面板", onClick = "expOpen" },
        { OutlinedButton, text = "收起面板", onClick = "expClose" } },
    },
  })
end }

function expOpen() exp.dart.Expanded = true end
function expClose() exp.dart.Expanded = false end

-- ============================================================
-- 7) 导航：标签页 + 抽屉 + 底栏
-- ============================================================
DEMOS[#DEMOS + 1] = { "导航", "TabBar / TabBarView / Drawer / NavigationBar", function()
  return shell("导航", {
    DefaultTabController, id = "tabs", length = 3,
    { Column,
      { TabBar, tabs = { { text = "首页" }, { text = "发现", icon = "search" }, { text = "我的", icon = "person" } } },
      { Expanded, { TabBarView,
          { Center, { Text, text = "第 1 个标签页" } },
          { Center, { Text, text = "第 2 个标签页" } },
          { Center, { Text, text = "第 3 个标签页" } } } } },
  }, {
    drawer = { Drawer, { ListView, padding = 8,
        { UserAccountsDrawerHeader, accountName = { Text, text = "AndroLua" },
          accountEmail = { Text, text = "lua@example.com" } },
        { ListTile, leading = { Icon, icon = "home" }, title = { Text, text = "菜单项一" } },
        { ListTile, leading = { Icon, icon = "settings" }, title = { Text, text = "菜单项二" } } } },
    bottomNavigationBar = { NavigationBar, id = "nav", currentIndex = 0,
      onTap = "navChanged",
      items = { { icon = "home", label = "首页" }, { icon = "search", label = "搜索" }, { icon = "person", label = "我的" } } },
  })
end }

function navChanged(e) end

-- 标签页/抽屉的运行期控制
function tabGo(e) end

DEMOS[#DEMOS + 1] = { "导航控制", "运行期切标签页 / 开抽屉 / 切底栏", function()
  return shell("导航控制", {
    Column, gap = 14, padding = 14,
    { Text, text = "下面是同款导航，另配一排按钮做运行期控制：" },
    { Row, gap = 8,
      { ElevatedButton, text = "切到第1页", onClick = "tabTo1" },
      { ElevatedButton, text = "切到第2页", onClick = "tabTo2" } },
    { Row, gap = 8,
      { OutlinedButton, text = "打开抽屉", onClick = "openDrawerNow" },
      { OutlinedButton, text = "关抽屉", onClick = "closeDrawerNow" } },
    { Row, gap = 8,
      { TextButton, text = "底栏选第3项", onClick = "navTo3" } },
    { Expanded, {
        DefaultTabController, id = "tabs2", length = 2,
        { Column,
          { TabBar, tabs = { { text = "A" }, { text = "B" } } },
          { Expanded, { TabBarView,
              { Center, { Text, text = "A 页内容" } },
              { Center, { Text, text = "B 页内容" } } } } } } },
  }, {
    drawer = { Drawer, { ListView, padding = 8,
        { ListTile, title = { Text, text = "抽屉里的内容" } } } },
    bottomNavigationBar = { NavigationBar, id = "nav2", currentIndex = 0,
      items = { { icon = "home", label = "一" }, { icon = "search", label = "二" }, { icon = "person", label = "三" } } },
  })
end }

-- 切页两种写法都行：改属性（复用同一个 controller，带过渡动画），或发命令
function tabTo1() tabs2.dart.Index = 0 end
function tabTo2() dartCall("flutterControl", { id = "tabs2", action = "tabTo", index = 1 }) end
function openDrawerNow() dartCall("flutterControl", { action = "openDrawer", id = "drawer" }) end
function closeDrawerNow() dartCall("flutterControl", { action = "closeDrawer", id = "drawer" }) end
function navTo3() nav2.dart.CurrentIndex = 2 end

-- ============================================================
-- 8) 弹窗与提示
-- ============================================================
DEMOS[#DEMOS + 1] = { "弹窗与提示", "SnackBar / AlertDialog / 底部弹窗 / 日期 / 时间", function()
  return shell("弹窗与提示", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 12,
      { ElevatedButton, text = "弹一个 SnackBar", onClick = "showSnack" },
      { ElevatedButton, text = "弹一个对话框", onClick = "showDialog" },
      { ElevatedButton, text = "弹一个底部弹窗", onClick = "showSheet" },
      { OutlinedButton, text = "选择日期", onClick = "pickDate" },
      { OutlinedButton, text = "选择时间", onClick = "pickTime" },
      { Text, id = "dlgTip", text = "（选择结果会显示在这里）", fontSize = 13, color = "#666666" },
    },
  })
end }

function showSnack()
  显示提示("这是 SnackBar（由 Lua 触发）")
end

function showDialog()
  显示对话框{
    AlertDialog,
    title = { Text, text = "对话框标题" },
    content = { Text, text = "对话框内容也是 Lua 写的布局表。" },
    actions = { { TextButton, text = "关闭", onClick = "closeDlg" } },
  }
end

function closeDlg() 关闭对话框() end

function showSheet()
  显示底部弹窗{
    Container, height = 180, padding = 16, radius = 16, backgroundColor = "#ffffff",
    { Column, gap = 10,
      { Text, text = "底部弹窗", fontSize = 18, fontWeight = "bold" },
      { Text, text = "内容同样是布局表，可以放任意控件。" },
      { ElevatedButton, text = "关闭", onClick = "closeDlg" } },
  }
end

function pickDate()
  选择日期(function() end)
end

function pickTime()
  选择时间(function() end)
end

-- ============================================================
-- 9) 动画
-- ============================================================
DEMOS[#DEMOS + 1] = { "动画", "AnimatedOpacity / AnimatedContainer / AnimatedScale", function()
  return shell("动画", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 16, crossAxisAlignment = "center",
      { Text, text = "点下面的按钮改变属性，动画会自动播放（隐式动画）" },
      { AnimatedOpacity, id = "fade", opacity = 1.0, duration = 400,
        { Container, width = 200, height = 60, radius = 10, color = "#2196f3", alignment = "center",
          { Text, text = "淡入淡出", color = "#ffffff" } } },
      { AnimatedContainer, id = "box", duration = 400, width = 120, height = 120, radius = 16,
        color = "#4caf50", alignment = "center", { Text, text = "变宽变高", color = "#ffffff" } },
      { AnimatedScale, id = "scale", scale = 1.0, duration = 400,
        { Container, width = 120, height = 60, radius = 10, color = "#ff9800", alignment = "center",
          { Text, text = "缩 放", color = "#ffffff" } } },
      { Row, gap = 10,
        { ElevatedButton, text = "切换", onClick = "animToggle" },
        { OutlinedButton, text = "复位", onClick = "animReset" } },
    },
  })
end }

local animOn = false
function animToggle()
  animOn = not animOn
  fade.dart.Opacity = animOn and 0.2 or 1.0
  box.dart.Width = animOn and 240 or 120
  box.dart.Height = animOn and 80 or 120
  box.dart.Color = animOn and "#e91e63" or "#4caf50"
  scale.dart.Scale = animOn and 1.6 or 1.0
end

function animReset()
  animOn = false
  fade.dart.Opacity = 1.0
  box.dart.Width = 120
  box.dart.Height = 120
  box.dart.Color = "#4caf50"
  scale.dart.Scale = 1.0
end

-- ============================================================
-- 10) 图表与二维码
-- ============================================================
DEMOS[#DEMOS + 1] = { "图表与二维码", "PieChart / BarChart / QrCode", function()
  return shell("图表与二维码", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 16,
      { Text, text = "饼图（PieChart）", fontWeight = "bold" },
      { SizedBox, height = 200,
        { PieChart, series = {
            { name = "A", value = 40, color = "#2196f3" },
            { name = "B", value = 25, color = "#4caf50" },
            { name = "C", value = 20, color = "#ff9800" },
            { name = "D", value = 15, color = "#e91e63" } } } },
      { Text, text = "柱状图（BarChart）", fontWeight = "bold" },
      { SizedBox, height = 180,
        { BarChart, series = {
            { value = 30, color = "#2196f3" },
            { value = 55, color = "#4caf50" },
            { value = 42, color = "#ff9800" },
            { value = 70, color = "#e91e63" } } } },
      { Text, text = "二维码（QrCode）", fontWeight = "bold" },
      { Center, { QrCode, data = "https://github.com/Zyr76/flutter", size = 180 } },
    },
  })
end }

-- ============================================================
-- 11) 媒体（视频 / 音频）
-- ============================================================
DEMOS[#DEMOS + 1] = { "媒体", "VideoPlayer / AudioPlayer + 控制命令", function()
  return shell("媒体", {
    Column, gap = 8,
      { Expanded, {
          VideoPlayer, id = "v",
          url = "https://media.w3.org/2010/05/sintel/trailer.mp4",
          controls = false } },
      { Text, id = "mediaTip", text = "视频 / 音频控制演示", fontSize = 13, padding = 8 },
  }, {
    bottomNavigationBar = { BottomAppBar, { Row, gap = 4, padding = 4,
        { TextButton, text = "播放", onClick = "vPlay" },
        { TextButton, text = "暂停", onClick = "vPause" },
        { TextButton, text = "-5s", onClick = "vBack" },
        { TextButton, text = "+5s", onClick = "vFwd" },
        { TextButton, text = "静音", onClick = "vMute" },
        { TextButton, text = "2x", onClick = "vSpeed" } } },
  })
end }

function vPlay() dartCall("flutterControl", { id = "v", action = "play" }, function(r, e) mediaTip.dart.Text = e or ("播放 ok=" .. tostring(r and r.ok)) end) end
function vPause() dartCall("flutterControl", { id = "v", action = "pause" }, function(r, e) mediaTip.dart.Text = e or "已暂停" end) end
function vSpeed() dartCall("flutterControl", { id = "v", action = "speed", speed = 2 }) end
function vMute() dartCall("flutterControl", { id = "v", action = "volume", volume = 0 }) end

function vSeekBy(d)
  dartCall("flutterControl", { id = "v", action = "state" }, function(res, err)
    if err or not res or not res.ok then return end
    local pos = (res.position or 0) + d
    if pos < 0 then pos = 0 end
    dartCall("flutterControl", { id = "v", action = "seek", pos = pos })
  end)
end

function vBack() vSeekBy(-5000) end
function vFwd() vSeekBy(5000) end

-- ============================================================
-- 12) 原生混合
-- ============================================================
DEMOS[#DEMOS + 1] = { "原生混合", "AndroidView：把 Android 原生控件嵌进 Flutter", function()
  -- 原生控件在 Lua 里照常 new，直接写进布局表就行（引擎序列化时自动登记引用）
  local 原生卡 = TextView(activity)
  原生卡.setText("我是 Lua 里 new 出来的原生 TextView")
  原生卡.setTextSize(16)
  原生卡.setPadding(40, 32, 40, 32)
  原生卡.setBackgroundColor(0xffe3f2fd)

  return shell("原生混合", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 12,
      { Text, text = "下面是嵌在 Flutter 里的原生 Android 控件（AndroidView）：" },
      { Container, height = 200, radius = 8, color = "#eeeeee",
        { AndroidView, view = 原生卡 } },
      { Text, text = "只给 params = { text = \"…\" } 则会用内置演示控件；反过来 Flutter 也能塞进原生布局（见 flutter示例.lua 的原生区）。", fontSize = 13, color = "#666666" },
    },
  })
end }

-- ============================================================
-- 菜单 + 路由
-- ============================================================
render = function(spec)
  host.removeAllViews()
  渲染Flutter(spec, host)
end

open = function(i)
  render(DEMOS[i][3]())
end

showMenu = function()
  local rows = {}
  for i, d in ipairs(DEMOS) do
    rows[#rows + 1] = { Card, margin = 6,
      { ListTile, id = "menuRow" .. i,
        title = { Text, text = d[1] },
        subtitle = { Text, text = d[2], fontSize = 12, color = "#888888" },
        trailing = { Icon, icon = "chevron_right" } } }
  end
  render(shell("Flutter UI 示例（共 " .. #DEMOS .. " 页）", {
    ListView, padding = 8, table.unpack(rows),
  }))
  -- 菜单项点击：用 id 句柄挂回调
  for i = 1, #DEMOS do
    local h = _G["menuRow" .. i]
    if h then
      h.onClick = function() open(i) end
    end
  end
end

-- 返回按钮（AppBar leading 的事件名就是它）
function uiBack() showMenu() end

-- 总监听：所有事件都会经过这里（排查问题很有用）
function onFlutterEvent(e)
  if e and e.name then
    print("[ui]", e.name, e.data and e.data.type or "")
  end
end

activity.setContentView(host)
showMenu()
