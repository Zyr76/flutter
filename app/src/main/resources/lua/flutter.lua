-- flutter.lua —— 显式导入 Flutter 渲染能力
--
-- 用法（脚本开头一行）：
--   require "flutter"
--
-- 为什么要这一行：Flutter 的渲染接口（渲染Flutter / flutterRender / dartCall /
-- 显示对话框 / flutterNode …）默认是「上锁」的——没导入就调用会直接报错：
--   Flutter 渲染需要先导入：请在脚本开头写 require "flutter"
-- 这样就不会出现"调了但悄悄不生效、界面只剩引擎占位"这种难查的情况。

_G.__flutter_loaded = true

-- ============================================================
-- 统一调试开关：flutter_debug(true) / Flutter调试(true)
--
-- 一个入口同时控制两侧：
--   * Java 侧事件调试：每个 Flutter→Lua 事件的到达、命中处理器、首次无处理器时打句柄表
--   * Dart 侧 UI 调试：未知控件告警、构建失败红框、flutterUiIssue 回传
-- 开启时还会：打印一次句柄表、列出可用事件名、把事件流打到控制台（保留你原有的处理器）。
-- 关闭即静默；两侧都只是布尔开关，没有常驻监听/定时器，不会残留开销。
-- 幂等：重复开/关不会重复打印，也不产生副作用。
-- ============================================================
local _nativeEventDebug = flutterDebug    -- 保存 Java 注册的原始入口（下面会被覆盖）
local _nativeHandlers = flutterHandlers
local debugOn = false

function flutter_debug(on)
  on = not not on
  if on == debugOn then
    return on
  end
  debugOn = on
  _G.__flutter_debug = on

  if _nativeEventDebug then _nativeEventDebug(on) end       -- Java 侧事件调试
  调用Dart("flutterUIDebug", { enabled = on })               -- Dart 侧 UI 调试

  if on then
    if _nativeHandlers then _nativeHandlers() end
    print("[Flutter] 调试开；事件名：flutterUiIssue / flutterError / " ..
        "renderError / dialogError / bottomSheetError（全部会打印在下面）")
    local prev = rawget(_G, "收到Flutter事件")
    _G.__flutter_debug_prev = prev
    rawset(_G, "收到Flutter事件", function(e)
      local name = e and e.name or "?"
      local data = e and e.data
      print("[Flutter] 事件 " .. tostring(name) ..
          " type=" .. tostring(type(data) == "table" and data.type or nil))
      if prev then prev(e) end
    end)
  else
    rawset(_G, "收到Flutter事件", _G.__flutter_debug_prev)
    _G.__flutter_debug_prev = nil
    print("[Flutter] 调试关")
  end
  return on
end

-- 旧入口全部变成别名，行为完全一致（不再出现“两个开关各控一半”）
flutterDebug, Flutter调试, 调试Flutter事件, flutterUI_debug = flutter_debug, flutter_debug, flutter_debug, flutter_debug

return {
  render      = 渲染Flutter,        -- 渲染Flutter(spec [, 容器])
  renderEn    = flutterRender,
  view        = flutterView,
  node        = flutterNode,        -- flutterNode("名字") 取句柄
  call        = 调用Dart,           -- 调用Dart(方法, 参数, 回调)
  callAsync   = dartCallAsync,
  dialog      = 显示对话框,
  bottomSheet = 显示底部弹窗,
  snackBar    = 显示提示,
  pickDate    = 选择日期,
  pickTime    = 选择时间,
  closeDialog = 关闭对话框,
  debug       = flutter_debug,      -- flutter_debug(true) 统一调试开关
  uiDebug     = flutter_debug,      -- 同上（旧名别名）
  handlers    = flutterHandlers,    -- 打印已注册的 id 与回调
}
