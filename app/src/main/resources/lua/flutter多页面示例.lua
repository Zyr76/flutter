-- ============================================================
-- Flutter 多页面示例（Tab 切换）
--
-- 纯 Lua 写的小应用：AppBar 里放 TabBar，下面 TabBarView 装 4 个页面。
--   首页：概览 + 进度条 + 三张统计卡 + 快捷入口 + 下拉刷新
--   订单：SegmentedButton 筛选 + 订单列表（点行弹提示）
--   消息：未读标记，点行即已读，可一键全部已读
--   我的：资料卡 + 通知开关 + 设置项
--
-- 交互手段都用到了：
--   1) 点/滑切页都有指示器过渡动画，切完回调 onChange（"切页完成"）
--   2) 代码切页两种写法：属性 tabs.dart.Index = 1；命令 flutterControl 的 tabTo
--   3) 列表行点击用 id 句柄挂函数：_G["order1"].onClick = function() ... end
--   4) 改完状态整页重渲染：渲染Flutter(界面(), host)（全量重渲染很便宜，逻辑最直白）
-- ============================================================
require "import"
import "android.widget.*"
import "android.view.*"

activity.setTitle("Flutter 多页面（Tab）")

local host = FrameLayout(activity)

-- ---------- 状态（业务数据都放这儿） ----------
local 状态 = {
  页 = 0,           -- 当前标签页（从 0 开始）
  筛选 = "全部",     -- 订单筛选条件
  进度 = 0.62,      -- 首页进度
  未读 = 2,
  通知 = true,
  订单 = {
    { 号 = "A1024", 客户 = "王小二", 金额 = 128.00, 状态 = "待发货" },
    { 号 = "A1025", 客户 = "李小明", 金额 = 66.50, 状态 = "已发货" },
    { 号 = "A1026", 客户 = "赵大文", 金额 = 899.00, 状态 = "已完成" },
    { 号 = "A1027", 客户 = "周小七", 金额 = 23.90, 状态 = "待发货" },
  },
  消息 = {
    { 标题 = "系统通知", 内容 = "订单 A1024 已创建", 时间 = "09:20", 读 = false },
    { 标题 = "物流提醒", 内容 = "订单 A1025 已出库", 时间 = "昨天", 读 = false },
    { 标题 = "活动通知", 内容 = "周末满减活动开始了", 时间 = "周一", 读 = true },
  },
}

local function 金额(v) return string.format("¥%.2f", v) end

local 渲染, 界面, 绑定句柄   -- 前置声明：页面函数和事件函数都要用

-- ============================================================
-- 页面 1：首页
-- ============================================================
local function 首页()
  local 快捷 = { "全部订单", "待付款", "待收货", "退款" }
  local 快捷条 = {}
  for i = 1, #快捷 do
    快捷条[i] = { ActionChip, text = 快捷[i], id = "quick" .. i }
  end
  local function 统计(标题, 数值)
    return { Expanded, { Card, { Column, gap = 4,
      { Text, text = 标题, fontSize = 12, color = "#888888" },
      { Text, text = 数值, fontSize = 20, fontWeight = "bold" } } } }
  end
  local 待发货 = 0
  for _, o in ipairs(状态.订单) do
    if o.状态 == "待发货" then 待发货 = 待发货 + 1 end
  end
  return {
    RefreshIndicator, onRefresh = "下拉刷新", delay = 500,
    { ListView, padding = 12,
      { Card, { Column, gap = 10,
        { Text, text = "今日进度", fontSize = 16, fontWeight = "bold" },
        { LinearProgressIndicator, value = 状态.进度, minHeight = 8, radius = 6 },
        { Text, text = string.format("已完成 %.0f%%", 状态.进度 * 100), fontSize = 12, color = "#666666" } } },
      { Row,
        统计("订单", tostring(#状态.订单)),
        统计("待发货", tostring(待发货)),
        统计("未读", tostring(状态.未读)) },
      { Card, { Column, gap = 8,
        { Text, text = "快捷入口", fontSize = 16, fontWeight = "bold" },
        { Wrap, gap = 8, table.unpack(快捷条) } } },
      { Row, gap = 8,
        { ElevatedButton, text = "去订单页（属性）", onClick = "去订单属性" },
        { OutlinedButton, text = "去订单页（命令）", onClick = "去订单命令" } },
    },
  }
end

-- ============================================================
-- 页面 2：订单
-- ============================================================
local function 订单页()
  local 行 = {}
  for i, o in ipairs(状态.订单) do
    if 状态.筛选 == "全部" or o.状态 == 状态.筛选 then
      行[#行 + 1] = { Card, id = "order" .. i,
        { ListTile,
          leading = { Icon, icon = "shopping_cart" },
          title = { Text, text = o.号 .. " · " .. o.客户 },
          subtitle = { Text, text = o.状态, fontSize = 12, color = "#888888" },
          trailing = { Text, text = 金额(o.金额), fontSize = 14 } } }
    end
  end
  if #行 == 0 then
    行[1] = { Padding, padding = 24, { Text, text = "这个筛选下没有订单", color = "#888888" } }
  end
  return {
    Column, padding = 12,
    { SegmentedButton, selected = { 状态.筛选 }, onChange = "选筛选",
      segments = {
        { value = "全部", label = "全部" },
        { value = "待发货", label = "待发货" },
        { value = "已完成", label = "已完成" } } },
    { SizedBox, height = 8 },
    { Expanded, { ListView, table.unpack(行) } },
  }
end

-- ============================================================
-- 页面 3：消息
-- ============================================================
local function 消息页()
  local 行 = {}
  for i, m in ipairs(状态.消息) do
    行[#行 + 1] = { Card, id = "msg" .. i,
      { ListTile,
        leading = { CircleAvatar, radius = 18,
          color = m.读 and "#cfd8dc" or "#1565c0",
          { Text, text = "信", fontSize = 12, color = "#ffffff" } },
        title = { Text, text = m.标题 .. (m.读 and "" or "（未读）") },
        subtitle = { Text, text = m.内容, fontSize = 12, color = "#888888" },
        trailing = { Text, text = m.时间, fontSize = 12, color = "#999999" } } }
  end
  return {
    Column, padding = 12,
    { Row, gap = 8,
      { Text, text = "未读：" .. tostring(状态.未读), fontSize = 14, color = "#666666" },
      { TextButton, text = "全部已读", onClick = "全部已读" } },
    { Expanded, { ListView, table.unpack(行) } },
  }
end

-- ============================================================
-- 页面 4：我的
-- ============================================================
local function 我的页()
  return {
    ListView, padding = 12,
    { Card, { Row, gap = 12,
      { CircleAvatar, radius = 28, color = "#1565c0",
        { Text, text = "L", fontSize = 20, color = "#ffffff" } },
      { Column, gap = 2,
        { Text, text = "Lua 开发者", fontSize = 16, fontWeight = "bold" },
        { Text, text = "lua@example.com", fontSize = 12, color = "#888888" } } } },
    { Card, { Column,
      { SwitchListTile, title = "通知", subtitle = "接收订单与物流提醒",
        value = 状态.通知, onChange = "切通知" },
      { Divider },
      { ListTile, leading = { Icon, icon = "security" }, title = { Text, text = "账号安全" },
        trailing = { Icon, icon = "arrow_forward" }, onClick = "关于项" },
      { ListTile, leading = { Icon, icon = "delete" }, title = { Text, text = "清理缓存" },
        trailing = { Icon, icon = "arrow_forward" }, onClick = "清缓存" },
      { ListTile, leading = { Icon, icon = "info" }, title = { Text, text = "关于" },
        trailing = { Icon, icon = "arrow_forward" }, onClick = "关于" } } },
  }
end

-- ============================================================
-- 外壳：DefaultTabController 包住 Scaffold（TabBar 在 AppBar.bottom 上）
-- ============================================================
界面 = function()
  return {
    DefaultTabController, id = "tabs", length = 4,
    index = 状态.页, onChange = "切页完成",
    { Scaffold, backgroundColor = "#F6F6F8",
      appBar = { AppBar, centerTitle = true,
        title = { Text, text = "多页面示例" },
        actions = { { IconButton, icon = "refresh", onClick = "下拉刷新" } },
        bottom = { TabBar, indicatorSize = "label",
          labelColor = "#1565c0", unselectedLabelColor = "#666666",
          tabs = {
            { text = "首页", icon = "home" },
            { text = "订单", icon = "description" },
            { text = "消息", icon = "chat" },
            { text = "我的", icon = "person" } } } },
      body = { TabBarView, 首页(), 订单页(), 消息页(), 我的页() } },
  }
end

-- ============================================================
-- 渲染 + 句柄绑定（列表行的回调要知道"是哪一行"，用 id 句柄挂）
-- ============================================================
绑定句柄 = function()
  for i, o in ipairs(状态.订单) do
    local h = _G["order" .. i]
    if h then
      h.onClick = function()
        flutterShowSnackBar(("订单 %s：%s · %s"):format(o.号, o.状态, 金额(o.金额)))
      end
    end
  end
  for i, m in ipairs(状态.消息) do
    local h = _G["msg" .. i]
    if h then
      h.onClick = function()
        if not m.读 then
          m.读 = true
          状态.未读 = math.max(0, 状态.未读 - 1)
          渲染()
        end
      end
    end
  end
  for i = 1, 4 do
    local h = _G["quick" .. i]
    if h then
      h.onClick = function() 状态.页 = 1; 渲染() end
    end
  end
end

渲染 = function()
  渲染Flutter(界面(), host)
  绑定句柄()
end

-- ============================================================
-- 事件（事件名 = 函数名）
-- ============================================================
function 切页完成(e)
  状态.页 = tonumber(e.value) or 0
end

function 选筛选(e)
  local v = e.value
  if type(v) == "table" then v = v[1] end
  状态.筛选 = tostring(v)
  渲染()
end

function 切通知(e)
  状态.通知 = (e.value == true)
  渲染()
end

function 下拉刷新()
  状态.进度 = math.min(1, 状态.进度 + 0.1)
  渲染()
  flutterShowSnackBar("已刷新（进度 +10%）")
end

function 全部已读()
  for _, m in ipairs(状态.消息) do m.读 = true end
  状态.未读 = 0
  渲染()
end

-- 代码切页：属性写法（走 animateTo，指示器平滑滑动）
function 去订单属性() tabs.dart.Index = 1 end

-- 代码切页：命令写法（等价，适合需要拿到结果的场景）
function 去订单命令() dartCall("flutterControl", { id = "tabs", action = "tabTo", index = 1 }) end

function 清缓存() flutterShowSnackBar("缓存已清理（示例）") end
function 关于项() flutterShowSnackBar("账号安全（示例）") end
function 关于() flutterShowSnackBar("Flutter 多页面示例 · Lua 驱动") end

-- 总监听：所有事件都会经过这里，排查问题很有用（可删）
function onFlutterEvent(e)
  if e and e.name then print("[多页面]", e.name, e.data and e.data.type or "") end
end

activity.setContentView(host)
渲染()
