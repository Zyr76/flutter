-- Flutter UI 使用示例（用 Lua 描述界面，Flutter 渲染）
--
-- 演示：
--   1) 基础布局：Scaffold / AppBar / Card / Row / Column / Icon / Container(渐变) / 按钮
--   2) 表单与状态：TextField / Switch / Slider 的事件回调 + 命令式改属性 + 控制命令
--   3) 列表：懒加载 500 项 + 滚动控制（flutterControl）
--   4) 弹窗：SnackBar / AlertDialog（命令式）
--
-- 关键点：
--   * 布局表就是 Lua 表：{ 控件名, 属性=值, { 子控件 }, ... }
--   * `id` 会生成同名的 Lua 句柄： 节点.onClick / 节点.onChange，以及 节点.dart.属性 = 值
--   * 命令类操作（滚动/文本框/媒体…）用 dartCall("flutterControl", {id=, action=, ...})
--   * onFlutterEvent(e) 是总监听，能收到所有事件

require "import"
import "android.widget.*"
import "android.view.*"

activity.setTitle("Flutter UI 示例")

local host = FrameLayout(activity)
local page = 1

-- ============================================================
-- 页面 1：基础布局
-- ============================================================
local function pageBasic()
  return {
    Scaffold,
    backgroundColor = "#F6F6F8",
    appBar = { AppBar, centerTitle = true, title = { Text, text = "基础布局" } },
    body = {
      SingleChildScrollView, padding = 12,
      { Column, gap = 12,
        -- 卡片
        { Card, elevation = 2, radius = 12,
          { Padding, padding = 14,
            { Column, crossAxisAlignment = "start", gap = 6,
              { Text, text = "Card / Text / Row", fontSize = 18, fontWeight = "bold" },
              { Text, text = "界面由 Lua 描述、Flutter 渲染", fontSize = 13, color = "#888888" },
              { Row, gap = 8,
                { Icon, icon = "favorite", color = "#e91e63", size = 18 },
                { Text, text = "图标 + 行布局" } } } } },
        -- 渐变容器
        { Container, height = 80, radius = 12, alignment = "center",
          gradient = { colors = { "#4facfe", "#00f2fe" } },
          { Text, text = "Container + 渐变", color = "#ffffff", fontSize = 16 } },
        -- 按钮：横排要能滑动必须套横向的 SingleChildScrollView
        -- （Row 自身不可滚动，超宽只会溢出/裁剪）
        { SingleChildScrollView, scrollDirection = "horizontal",
          { Row, gap = 10,
            { ElevatedButton, id = "btnA", text = "改上面的文字" },
            { FilledButton, id = "btnB", text = "弹 SnackBar" },
            { OutlinedButton, id = "btnC", text = "弹对话框" },
            { TextButton, id = "btnD", text = "再一个按钮" } } },
        { Text, id = "tip", text = "等待操作…", fontSize = 13, color = "#666666" },
      },
    },
  }
end

local function bindBasic()
  function btnA.onClick(e)
    tip.dart.Text = "按钮 A 被点了（Lua 改的属性）"
  end
  function btnB.onClick(e)
    显示提示("这是 Flutter 的 SnackBar，由 Lua 触发")
  end
  function btnC.onClick(e)
    显示对话框{
      AlertDialog,
      title = { Text, text = "来自 Lua 的弹窗" },
      content = { Text, text = "内容也是 Lua 写的布局表。" },
      actions = { { TextButton, text = "关闭", onClick = "closeDlg" } },
    }
  end
end

function closeDlg()
  关闭对话框()
end

-- ============================================================
-- 页面 2：表单与状态（事件 + 命令）
-- ============================================================
local function pageForm()
  return {
    Scaffold,
    backgroundColor = "#F6F6F8",
    appBar = { AppBar, centerTitle = true, title = { Text, text = "表单与状态" } },
    body = {
      SingleChildScrollView, padding = 12,
      { Column, gap = 14,
        { TextField, id = "name", hint = "输入名字", label = "名字" },
        { TextField, id = "pwd", hint = "输入密码", label = "密码", obscure = true },
        { Row, gap = 10,
          { Text, text = "开关", fontSize = 15 },
          { Switch, id = "sw", value = false, onChange = "swChange" } },
        { Text, id = "swTip", text = "开关：关", fontSize = 13, color = "#666666" },
        { Text, text = "音量", fontSize = 15 },
        { Slider, id = "sld", value = 30, min = 0, max = 100, divisions = 10, onChange = "sldChange" },
        { Text, id = "sldTip", text = "音量：30", fontSize = 13, color = "#666666" },
        { Row, gap = 10,
          { ElevatedButton, id = "readBtn", text = "读取输入" },
          { OutlinedButton, id = "clearBtn", text = "清空输入" },
          { TextButton, id = "focusBtn", text = "聚焦" } },
      },
    },
  }
end

-- Switch / Slider 的变化：用 spec 里的 onChange="函数名" 指定回调（最稳）
-- （也可以不写 onChange，改用句柄：function sw.onChange(e) …，事件名就是 id）
function swChange(e)
  swTip.dart.Text = "开关：" .. (e.value and "开" or "关")
end

function sldChange(e)
  sldTip.dart.Text = "音量：" .. tostring(math.floor((e.value or 0) + 0.5))
end

local function bindForm()
  -- 命令：读文本 / 清空 / 聚焦（flutterControl）
  function readBtn.onClick(e)
    dartCall("flutterControl", { id = "name", action = "textState" }, function(res, err)
      if err then print("[ui] 读取失败:", err) return end
      local t = res and res.text or ""
      local shown = #t > 0 and t or "(空)"
      name.dart.Hint = "你说的是：" .. shown     -- 命令式改属性（改 hint）
      print("[ui] 输入框内容 =", shown)
    end)
  end
  function clearBtn.onClick(e)
    dartCall("flutterControl", { id = "name", action = "clear" })
    name.dart.Hint = "输入名字"
  end
  function focusBtn.onClick(e)
    dartCall("flutterControl", { id = "name", action = "focus" })
  end
end

-- ============================================================
-- 页面 3：懒加载列表 + 滚动控制
-- ============================================================
local function pageList()
  return {
    Scaffold,
    backgroundColor = "#F6F6F8",
    appBar = { AppBar, centerTitle = true, title = { Text, text = "列表（懒加载 500 项）" } },
    body = {
      ListView, id = "list", itemCount = 500,
      itemTemplate = {
        ListTile,
        title = { Text, text = "$index 行标题", fontSize = 16 },
        subtitle = { Text, text = "只构建可见项，滚动才懒加载", fontSize = 12, color = "#999999" },
        onTap = "rowTap",
      },
    },
  }
end

-- 任意行被点 → 总监听收到 rowTap
function rowTap(e)
  print("[ui] 点到了列表行")
end

-- ============================================================
-- 页切换 + 事件总线
-- ============================================================
local PAGES = { pageBasic, pageForm, pageList }
local BINDS = { bindBasic, bindForm, nil }

-- 注意：这两个要在 show 之前先声明（Lua 没有变量提升，否则 show 里会当成全局 nil）
local bar
local scrollBar

local function show(p)
  page = p
  host.removeAllViews()
  渲染Flutter(PAGES[p](), host)
  if BINDS[p] then BINDS[p]() end
  -- 滚动控制只对列表页有意义
  scrollBar.setVisibility(p == 3 and 0 or 8)
end

-- 总监听：能收到所有 Flutter 事件（这里只打印，方便观察）
function onFlutterEvent(e)
  if e and e.name then
    print("[ui] 事件:", e.name, e.data and e.data.type or "")
  end
end

-- 底部页切换（原生按钮）
bar = LinearLayout(activity)
bar.setOrientation(LinearLayout.HORIZONTAL)
local function tabBtn(name, idx)
  local b = Button(activity)
  b.setText(name)
  b.setOnClickListener(function() show(idx) end)
  bar.addView(b)
end
tabBtn("布局", 1)
tabBtn("表单", 2)
tabBtn("列表", 3)

scrollBar = LinearLayout(activity)
scrollBar.setOrientation(LinearLayout.HORIZONTAL)
local function sBtn(name, action, extra)
  local b = Button(activity)
  b.setText(name)
  b.setOnClickListener(function()
    local a = { id = "list", action = action }
    if extra then for k, v in pairs(extra) do a[k] = v end end
    dartCall("flutterControl", a)
  end)
  scrollBar.addView(b)
end
sBtn("列表:到底", "scrollToEnd")
sBtn("列表:回顶", "scrollToStart")
sBtn("列表:+800", "scrollBy", { delta = 800 })

local root = LinearLayout(activity)
root.setOrientation(LinearLayout.VERTICAL)
root.addView(host, LinearLayout.LayoutParams(-1, 0, 1))
root.addView(scrollBar, LinearLayout.LayoutParams(-1, -2))
root.addView(bar, LinearLayout.LayoutParams(-1, -2))
activity.setContentView(root)

show(1)
