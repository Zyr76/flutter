-- tools/lua_smoke_test.lua
-- 用 Lua 5.3 跑 app/src/main/resources/lua/flutter应用示例.lua 的逻辑冒烟测试（不需要 Android）。
--
-- 用法（在项目根目录）：
--   lua5.3 tools/lua_smoke_test.lua
--   lua5.3 tools/lua_smoke_test.lua app/src/main/resources/lua/其它示例.lua
--
-- 它做的事：把桥的 Lua 全局（渲染Flutter/调用Dart/显示对话框…）换成本地桩件，
-- 把中文标识符临时改成 ASCII（stock Lua 不认中文标识符，AndroLua 开了 LUA_UCID 才认），
-- 然后加载脚本、模拟事件与异步回调，检查页面 spec 是否按预期生成。

local SCRIPT = arg[1] or "app/src/main/resources/lua/flutter应用示例.lua"

-- ---------- 读取并替换中文标识符 ----------
local fh = assert(io.open(SCRIPT, "r"))
local src = fh:read("*a")
fh:close()

local REPLACEMENTS = {
  { "收到Flutter事件", "ZEVT" },
  { "异步调用Dart", "ZCALLASYNC" },
  { "调用Dart", "ZCALL" },
  { "关闭对话框", "ZCLOSEDLG" },
  { "显示对话框", "ZSHOWDLG" },
  { "显示底部弹窗", "ZSHOWSHEET" },
  { "显示提示", "ZTOAST" },
  { "加载Flutter布局", "ZRENDER" },
  { "渲染Flutter", "ZRENDER" },
  { "flutterDebug", "ZDEBUG" },
  { "Flutter调试", "ZDEBUG" },
  { "Flutter句柄表", "ZHANDLERS" },
}
for _, r in ipairs(REPLACEMENTS) do
  src = src:gsub(r[1], r[2])
end

-- ---------- 桩件 ----------
local captured = { specs = {}, toasts = {}, dialogs = {}, calls = {}, printed = {}, closed = 0 }

function ZRENDER(spec, _container)
  table.insert(captured.specs, spec)
  return { fake = true }
end
function ZDEBUG(_) end
function ZTOAST(msg) table.insert(captured.toasts, tostring(msg)) end
function ZSHOWDLG(spec) table.insert(captured.dialogs, spec) end
function ZCLOSEDLG() captured.closed = captured.closed + 1 end
function ZCALL(name, args, cb)
  table.insert(captured.calls, { name = name, args = args })
  if name == "getUserInfo" then
    cb({ id = 1, name = "张三", age = 28, vip = true, tags = { "flutter", "dart" } }, nil)
  elseif name == "fetchOrders" then
    local size = (args and args.size) or 10
    local page = (args and args.page) or 1
    local list = {}
    for i = 1, size do
      local id = (page - 1) * size + i
      table.insert(list, { id = id, title = "订单 #" .. id, amount = "12.50", status = "待付款" })
    end
    cb({ page = page, size = size, list = list }, nil)
  else
    cb(nil, "no such method")
  end
end
function require(_) end
function import(_) end

-- 控件名：真实环境由 FlutterLuaBridge.installWidgetFallback 提供（读未定义全局时返回控件名）。
-- 这里显式列出示例用到的名字——显式定义还能把「控件名拼错」测出来。
local WIDGETS = {
  "Scaffold", "AppBar", "IconButton", "Container", "Row", "Column", "CircleAvatar",
  "Text", "TextField", "RefreshIndicator", "ListView", "Card", "Expanded", "Center",
  "Icon", "Spacer", "Divider", "ElevatedButton", "TextButton", "BottomNavigationBar",
  "SimpleDialog", "AlertDialog", "ListTile",
}
for _, w in ipairs(WIDGETS) do _G[w] = w end

statusBar = {
  setText = function(s) captured.statusText = s end,
  setPadding = function() end,
  setTextSize = function() end,
}
activity = { setTitle = function() end, setContentView = function() end }
function loadlayout(t) return t end

local realPrint = print
local function say(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  realPrint(table.concat(parts, " "))
end
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  table.insert(captured.printed, table.concat(parts, " "))
end

-- ---------- 加载被测脚本 ----------
local chunk, err = load(src, SCRIPT)
if not chunk then say("加载失败: " .. tostring(err)); os.exit(1) end
local ok, runErr = pcall(chunk)
if not ok then say("运行出错: " .. tostring(runErr)); os.exit(1) end

-- ---------- 断言 ----------
local fails = 0
local function check(cond, label)
  if cond then say("  ✓ " .. label)
  else say("  ✗ " .. label); fails = fails + 1 end
end
local function lastSpec() return captured.specs[#captured.specs] end
local function countOrderCards(spec)
  local n = 0
  for _, c in ipairs(spec.body.children or {}) do
    if type(c) == "table" and c[1] == "RefreshIndicator" then
      for _, item in ipairs(c.child.children or {}) do
        if item.onClick and item.onClick.event == "openOrder" then n = n + 1 end
      end
    end
  end
  return n
end
local function countDialogs()
  local n = 0
  for _, d in ipairs(captured.dialogs) do
    if string.find(d and d[1] or "", "Dialog", 1, true) then n = n + 1 end
  end
  return n
end

say("== 启动阶段 ==")
check(#captured.specs >= 3, "启动渲染了多帧（首屏 + 加载态 + 数据到位），实际 " .. #captured.specs)
check(captured.calls[1] and captured.calls[1].name == "getUserInfo", "调用了 getUserInfo")
check(captured.statusText ~= nil, "更新了原生状态栏文字：" .. tostring(captured.statusText))

local home = captured.specs[1]
check(home[1] == "Scaffold", "首屏根节点是 Scaffold")
check(home.bottomNavigationBar ~= nil, "底部导航存在")
check(home.body ~= nil and home.body[1] == "Column", "body 是 Column")
check(countOrderCards(home) == 0, "首屏（数据未到）列表为空")
check(countOrderCards(lastSpec()) == 10, "数据到位后渲染出 10 条订单卡，实际 " .. countOrderCards(lastSpec()))

say("== 事件分发 ==")
local before = #captured.specs
ZEVT({ name = "switchTab", data = { value = 1 } })
check(#captured.specs == before + 1, "switchTab 触发了重渲染")

ZEVT({ name = "switchTab", data = { value = 0 } })
ZEVT({ name = "openOrder", data = { args = { id = 3 } } })
check(lastSpec().appBar.title.text == "订单详情", "openOrder 打开了详情页")

local dlgBefore = countDialogs()
ZEVT({ name = "cancelOrder" })
check(countDialogs() == dlgBefore + 1, "cancelOrder 弹出了对话框")
local closeBefore = captured.closed
ZEVT({ name = "doCancel" })
check(captured.closed == closeBefore + 1, "doCancel 关闭了对话框")

ZEVT({ name = "back" })
check(lastSpec().appBar.title.text == "订单管理", "back 回到了列表页")

dlgBefore = countDialogs()
ZEVT({ name = "about" })
check(countDialogs() == dlgBefore + 1, "about 弹出了对话框")
ZEVT({ name = "closeDialog" })

ZEVT({ name = "toastTip", data = { args = { text = "来自 args 的参数" } } })
check(captured.toasts[#captured.toasts] == "来自 args 的参数", "toastTip 从 args 取到参数")

local callsBefore = #captured.calls
ZEVT({ name = "refresh" })
check(#captured.calls > callsBefore, "下拉刷新触发了 fetchOrders")

say("== 搜索过滤 ==")
ZEVT({ name = "search", data = { value = "订单 #3" } })
local fcards = countOrderCards(lastSpec())
check(fcards >= 1 and fcards <= 2, "关键词过滤生效，剩余 " .. fcards .. " 条")

say("== 分页 ==")
ZEVT({ name = "search", data = { value = "" } })
callsBefore = #captured.calls
ZEVT({ name = "more" })
check(#captured.calls == callsBefore + 1, "more 触发了下一页请求")
check(captured.calls[#captured.calls].args.page == 2, "请求的是第 2 页")

say("== 未处理事件告警 ==")
local unhandled = 0
for _, line in ipairs(captured.printed) do
  if string.find(line, "未处理的事件", 1, true) then unhandled = unhandled + 1 end
end
check(unhandled == 0, "所有事件都有处理函数，实际告警 " .. unhandled .. " 条")

say("")
if fails == 0 then say("全部通过") else say("失败 " .. fails .. " 项") end
os.exit(fails == 0 and 0 or 1)
