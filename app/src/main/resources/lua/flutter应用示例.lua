-- flutter应用示例.lua —— 用 Lua 组织一个完整 App（订单管理）
--
-- 这个文件演示「怎么把脚本写成应用」，结构分七层，照着套就行：
--   1) 配置      APP          —— 常量集中放这里
--   2) 状态      store        —— 唯一数据源；改完状态调 render() 重画
--   3) 数据层    api          —— 把异步 dartCall 封装成 api.loadXxx(cb)
--   4) 事件总线  handlers     —— 所有回调按「名字」集中在一张表里
--   5) UI 片段   xxxView()    —— 返回 spec 片段的小函数，可复用
--   6) 页面      screens.xxx()—— 返回整页 spec
--   7) 路由      stack/push/pop/render —— 页面栈
--
-- 两条约定：
--   * 控件写回调：onClick = "handlers 里的名字"（声明式，最稳，推荐）
--     需要带参数：onClick = { event = "openOrder", args = { id = 12 } }，
--     处理函数里从 data.args 取。也可以给控件写 id 再 function id.onClick() end（句柄式）。
--   * 事件统一汇入 收到Flutter事件，再按名字分发（见第 4 节）。

require "import"
import "android.widget.*"
import "android.view.*"

-- 调试时改成 true：会打印每个事件的 name/命中情况，便于排查
flutterDebug(false)

-- ============================================================
-- 1) 配置
-- ============================================================
local APP = { title = "订单管理", pageSize = 10, primary = "#3F51B5" }

-- ============================================================
-- 2) 状态（唯一数据源）
-- ============================================================
local store = {
  tab = 0,            -- 底部导航当前页：0=订单 1=我的
  user = nil,         -- 来自 dartCall getUserInfo
  orders = {},        -- 订单列表
  loading = false,
  page = 1,
  hasMore = true,
  keyword = "",
  current = nil,      -- 详情页正在看的订单
  updatedAt = "--:--:--",
}

-- 前向声明：这些在下面才会赋值，但 api/handlers 里要先引用到
local render, toast, pushScreen, popScreen

-- ============================================================
-- 3) 工具
-- ============================================================
toast = function(msg)
  显示提示(tostring(msg))
end

local function fmtAmount(v)
  return "¥" .. tostring(v or "0.00")
end

-- ============================================================
-- 4) 数据层：把异步 dartCall 封装成 api.xxx(cb)
--    回调在主 Lua 状态执行，可以直接改 store / 读全局变量
-- ============================================================
local api = {}

function api.loadUser()
  print("[应用] 请求用户信息…")
  调用Dart("getUserInfo", { id = 1 }, function(res, err)
    print("[应用] 用户信息已返回：" .. tostring(res and res.name or err))
    if res and not res.error then store.user = res else toast("获取用户失败：" .. tostring(err)) end
    render()
  end)
end

function api.loadOrders(reset)
  if store.loading then return end
  store.loading = true
  if reset then store.page = 1 end
  render()                                    -- 立刻显示加载态

  print("[应用] 请求订单：page=" .. store.page)
  调用Dart("fetchOrders", { page = store.page, size = APP.pageSize }, function(res, err)
    print("[应用] 订单已返回：" .. tostring(res and res.list and (#res.list .. " 条") or err))
    store.loading = false
    if res and res.list then
      if reset then
        store.orders = res.list
      else
        for _, o in ipairs(res.list) do table.insert(store.orders, o) end
      end
      store.hasMore = (#res.list >= APP.pageSize)
      if store.hasMore then store.page = store.page + 1 end
      store.updatedAt = os.date("%H:%M:%S")
      statusBar.setText("原生区 · 已更新 " .. store.updatedAt)   -- 顺手更新原生控件
    else
      toast("加载失败：" .. tostring(err or (res and res.error)))
    end
    render()
  end)
end

-- ============================================================
-- 5) 事件总线：所有回调按名字集中在这里
-- ============================================================
local handlers = {}

-- 唯一的入口：Java 侧把每个事件都送到这里
function 收到Flutter事件(e)
  local name = e and e.name
  local data = e and e.data or {}
  local fn = name and handlers[name]
  if not fn then
    -- 没注册的名字：打印一行，方便发现拼写错误
    print("[应用] 未处理的事件：" .. tostring(name))
    return
  end
  local ok, err = pcall(fn, data)             -- 单个处理函数出错不影响其它
  if not ok then toast("处理 " .. tostring(name) .. " 出错：" .. tostring(err)) end
end

-- ---- 订单页 ----
handlers.reload = function() api.loadOrders(true) end

handlers.refresh = function()                 -- RefreshIndicator 下拉
  api.loadOrders(true)
end

handlers.openOrder = function(data)           -- 列表项：onClick = { event="openOrder", args={id=…} }
  local id = data and data.args and data.args.id
  for _, o in ipairs(store.orders) do
    if tostring(o.id) == tostring(id) then store.current = o; break end
  end
  pushScreen("detail")
end

handlers.search = function(data)              -- 搜索框回车
  store.keyword = tostring(data and data.value or "")
  render()
end

-- ---- 详情页 ----
handlers.back = function() popScreen() end

handlers.cancelOrder = function()
  显示对话框 {
    AlertDialog,
    title = { Text, text = "取消订单" },
    content = { Text, text = "确定取消订单 #" .. tostring(store.current and store.current.id) .. " 吗？" },
    actions = {
      { TextButton, text = "再想想", onClick = "closeDialog" },
      { TextButton, text = "确定取消", onClick = "doCancel" },
    },
  }
end

handlers.closeDialog = function() 关闭对话框() end

handlers.doCancel = function()
  关闭对话框()
  if store.current then store.current.status = "已取消" end
  toast("已取消（示例）")
  render()
end

-- ---- 我的页 ----
handlers.about = function()
  显示对话框 {
    SimpleDialog,
    title = { Text, text = "关于" },
    children = {
      { ListTile, leading = "info", title = { Text, text = "AndroLua + Flutter 应用示例" } },
      { ListTile, leading = "person", title = { Text, text = "当前用户：" .. tostring(store.user and store.user.name) } },
      { ListTile, leading = "refresh", title = { Text, text = "数据更新于 " .. store.updatedAt }, onTap = "closeDialog" },
    },
  }
end

handlers.switchTab = function(data)           -- 底部导航（data.value = 下标）
  store.tab = tonumber(data and data.value) or 0
  render()
end

handlers.more = function()                    -- 加载下一页
  if store.hasMore then api.loadOrders(false) else toast("没有更多了") end
end

handlers.toastTip = function(data)            -- 演示：从 args 取参数
  toast((data and data.args and data.args.text) or "点了")
end

-- ============================================================
-- 6) UI 片段：返回 spec 的小函数（可复用、可组合）
-- ============================================================
local function sectionTitle(text)
  -- 注意：Text 这类非容器控件不处理 padding，但通用层会处理 margin（四边：左·上·右·下）。
  return { Text, text = text, fontSize = 14, color = "#888888", margin = { 0, 12, 0, 4 } }
end

local function card(children)
  return { Card, margin = { 0, 6 }, child = { Column, gap = 8, children = children } }
end

local function keyValue(label, value)
  return {
    Row,
    children = {
      { Text, text = label, fontSize = 14, color = "#666666" },
      { Spacer },
      { Text, text = tostring(value), fontSize = 14, fontWeight = "bold" },
    },
  }
end

-- 列表项：把订单号随事件带过去
local function orderTile(o)
  return {
    Card,
    margin = { 0, 6 },
    onClick = { event = "openOrder", args = { id = o.id } },
    child = {
      Row, gap = 12,
      { CircleAvatar, radius = 18, backgroundColor = APP.primary,
        child = { Text, text = tostring(o.id), color = "#FFFFFF", fontSize = 14 } },
      { Expanded, child = { Column, gap = 2,
        { Text, text = tostring(o.title), fontSize = 16, fontWeight = "bold" },
        { Text, text = tostring(o.status), fontSize = 12, color = "#888888" },
      } },
      { Text, text = fmtAmount(o.amount), fontSize = 16, color = "#E53935" },
    },
  }
end

local function stateView(text, iconName)
  return { Expanded, child = { Center, child = { Column, gap = 12, children = {
    { Icon, icon = iconName, size = 48, color = "#CCCCCC" },
    { Text, text = text, color = "#999999" },
  } } } }
end

-- ============================================================
-- 7) 页面：返回整页 spec
-- ============================================================
local screens = {}

local function appBar(title, opts)
  opts = opts or {}
  local bar = { AppBar, title = { Text, text = title }, backgroundColor = APP.primary,
                foregroundColor = "#FFFFFF" }
  if opts.back then
    bar.leading = { IconButton, icon = "arrow_back", tooltip = "返回", onClick = "back" }
  end
  if opts.action then
    bar.actions = { { IconButton, icon = opts.action.icon, tooltip = opts.action.tip,
                      onClick = opts.action.handler } }
  end
  return bar
end

-- 订单页
local function ordersPage()
  -- 按关键词过滤（搜索框回车后生效）
  local shown = {}
  for _, o in ipairs(store.orders) do
    local hit = (store.keyword == "")
      or (string.find(tostring(o.id), store.keyword, 1, true) ~= nil)
      or (string.find(tostring(o.title), store.keyword, 1, true) ~= nil)
    if hit then table.insert(shown, o) end
  end

  local list = { ListView, padding = 12, children = {} }
  for _, o in ipairs(shown) do
    table.insert(list.children, orderTile(o))
  end

  -- 注意：用 table.insert 逐个追加，不要写成带 nil 空洞的 {a, b, nil, c}——
  -- Lua 的 ipairs 遇到 nil 会停，后面的元素会被漏掉。
  local body = {}
  table.insert(body, {
    Container, padding = 16, color = APP.primary,
    child = { Row, gap = 12,
      { CircleAvatar, radius = 20, backgroundColor = "#FFFFFF",
        child = { Text, text = store.user and string.sub(tostring(store.user.name), 1, 1) or "?" } },
      { Column, gap = 2,
        { Text, text = store.user and tostring(store.user.name) or "加载中…", fontSize = 16, color = "#FFFFFF" },
        { Text, text = store.user and ("VIP：" .. tostring(store.user.vip)) or "", fontSize = 12, color = "#E8EAF6" },
      },
    },
  })
  table.insert(body, {
    TextField, hint = "输入订单号/标题，回车搜索", margin = { 12, 8 },
    onSubmitted = "search",
  })
  if #shown == 0 then
    -- 空数据：显示占位（占位本身是 Expanded，与下面的列表互斥，避免两个 Expanded 平分空间）
    local tip = "暂无订单"
    if store.loading then tip = "正在加载…"
    elseif store.keyword ~= "" then tip = "没有匹配的订单" end
    table.insert(body, stateView(tip, store.loading and "refresh" or "info"))
  else
    -- 有数据：列表必须包在 Expanded 里！
    -- Column 里的可滚动组件没有确定高度约束，Flutter 会报
    -- "Vertical viewport was given unbounded height"，整块列表渲染不出来。
    table.insert(body, {
      Expanded,
      child = { RefreshIndicator, child = list, onRefresh = "refresh" },
    })
    table.insert(body, {
      Row, mainAxisAlignment = "center", margin = { 0, 12 },
      children = {
        { TextButton, text = store.hasMore and "加载更多" or "没有更多了",
          width = "fill", onClick = "more" },
      },
    })
  end

  return {
    Scaffold,
    backgroundColor = "#F5F5F5",
    appBar = appBar(APP.title, { action = { icon = "refresh", tip = "刷新", handler = "reload" } }),
    body = { Column, children = body },
    bottomNavigationBar = {
      BottomNavigationBar,
      currentIndex = store.tab,
      items = {
        { icon = "dashboard", label = "订单" },
        { icon = "person", label = "我的" },
      },
      onTap = "switchTab",
    },
  }
end

-- 我的页
local function minePage()
  return {
    Scaffold,
    backgroundColor = "#F5F5F5",
    appBar = appBar("我的"),
    body = { ListView, padding = 12, children = {
      card({
        { Row, gap = 12, children = {
          { CircleAvatar, radius = 24, backgroundColor = APP.primary,
            child = { Text, text = store.user and string.sub(tostring(store.user.name), 1, 1) or "?" , color = "#FFFFFF" } },
          { Column, gap = 2, children = {
            { Text, text = store.user and tostring(store.user.name) or "未登录", fontSize = 18, fontWeight = "bold" },
            { Text, text = store.user and ("id=" .. tostring(store.user.id) .. " · tags=" .. table.concat(store.user.tags or {}, "/")) or "", fontSize = 12, color = "#888888" },
          } },
        } },
      }),
      sectionTitle("操作"),
      card({
        { ListTile, leading = "refresh", title = { Text, text = "刷新数据" }, onTap = "reload" },
        { ListTile, leading = "info", title = { Text, text = "关于" }, onTap = "about" },
        { ListTile, leading = "chat", title = { Text, text = "点我弹提示" },
          onTap = { event = "toastTip", args = { text = "来自 args 的参数" } } },
      }),
      card({
        keyValue("订单数", #store.orders),
        keyValue("更新时间", store.updatedAt),
      }),
    } },
    bottomNavigationBar = {
      BottomNavigationBar,
      currentIndex = store.tab,
      items = {
        { icon = "dashboard", label = "订单" },
        { icon = "person", label = "我的" },
      },
      onTap = "switchTab",
    },
  }
end

-- 详情页
local function detailPage()
  local o = store.current
  if not o then
    return { Scaffold, appBar = appBar("详情", { back = true }),
             body = { Center, child = { Text, text = "没有选中订单" } } }
  end
  return {
    Scaffold,
    backgroundColor = "#F5F5F5",
    appBar = appBar("订单详情", { back = true }),
    body = { ListView, padding = 12, children = {
      card({
        { Text, text = tostring(o.title), fontSize = 20, fontWeight = "bold" },
        { Text, text = fmtAmount(o.amount), fontSize = 24, color = "#E53935" },
        { Divider },
        keyValue("订单号", o.id),
        keyValue("状态", o.status),
      }),
      sectionTitle("操作"),
      card({
        { ElevatedButton, text = "取消订单", width = "fill",
          onClick = "cancelOrder",
          style = { backgroundColor = "#E53935", foregroundColor = "#FFFFFF" } },
      }),
    } },
  }
end

-- 注册到路由表
screens.home = function()
  if store.tab == 1 then return minePage() end
  return ordersPage()
end
screens.detail = detailPage

-- ============================================================
-- 8) 路由 + 渲染
-- ============================================================
local stack = { "home" }

render = function()
  local name = stack[#stack] or "home"
  local screen = screens[name] or screens.home
  -- 每次都传容器：桥里做了「已在容器中就跳过」的处理，不会重复添加
  渲染Flutter(screen(), flutterHost)
end

pushScreen = function(name)
  table.insert(stack, name)
  render()
end

popScreen = function()
  if #stack > 1 then table.remove(stack) end
  render()
end

-- ============================================================
-- 启动
-- ============================================================
activity.setTitle(APP.title)

activity.setContentView(loadlayout{
  LinearLayout, orientation = "vertical", backgroundColor = "0xffffffff",
  { TextView, id = "statusBar", text = "原生区 · 准备加载" },          -- 原生控件（同屏演示）
  { FrameLayout, id = "flutterHost", layout_width = "fill", layout_height = 0, layout_weight = 1 },
})
statusBar.setPadding(24, 20, 24, 20)
statusBar.setTextSize(13)

render()          -- 首屏
api.loadUser()    -- 拉用户
api.loadOrders(true)   -- 拉订单
print("[应用] 启动完成")
