-- ============================================================
-- flutter.lua —— Flutter 渲染模块
--
-- 用法（脚本开头一行）：
--   require "flutter"
--
-- 为什么要这一行：渲染接口默认是「上锁」的，没导入就调用会直接报错：
--   Flutter 渲染需要先导入：请在脚本开头写 require "flutter"
-- 这样就不会出现“调了但悄悄不生效、界面只剩引擎占位”这种难查的情况。
--
-- 调试只有一个入口：flutter_debug(on)（中文别名 Flutter调试）。
-- 它同时打开事件调试与 UI 调试，不再有“两个开关各控一半”的历史名字。
-- ============================================================
_G.__flutter_loaded = true

-- Java 侧暴露的内部开关（__ 前缀，不参与 require 守卫）
local _eventDebug = __flutter_event_debug
local _handlers = flutterHandlers
local _debugOn = false

--- 统一调试开关：事件调试 + UI 调试一起开关。
--- @param on boolean|nil  true 打开，false/nil 关闭
--- @return boolean 当前状态
--- @note 幂等：状态未变化时直接返回，不重复打印、不产生副作用。
function flutter_debug(on)
  on = on and true or false
  if on == _debugOn then
    return on
  end
  _debugOn = on
  _G.__flutter_debug = on

  if _eventDebug then _eventDebug(on) end                    -- Java：事件到达/处理、句柄表
  调用Dart("flutterSetDebug", { enabled = on })               -- Dart：未知控件/错误红框/异常回传

  if on then
    if _handlers then _handlers() end
    print("[Flutter] 调试开；事件名：flutterUiIssue / flutterError / " ..
        "renderError / dialogError / bottomSheetError")
    local prev = rawget(_G, "收到Flutter事件")
    _G.__flutter_debug_prev = prev
    rawset(_G, "收到Flutter事件", function(e)
      local data = e and e.data
      print("[Flutter] 事件 " .. tostring(e and e.name) ..
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

-- 唯一别名（中文习惯写法）。其余历史名字（flutterDebug / 调试Flutter事件 /
-- flutterUI_debug）已移除，避免出现互不相同的开关。
Flutter调试 = flutter_debug

return {
  -- 渲染与句柄
  render      = 渲染Flutter,     -- 渲染Flutter(spec [, 容器])
  renderEn    = flutterRender,
  view        = flutterView,
  node        = flutterNode,     -- flutterNode("名字") 取句柄
  -- 与 Dart 通信
  call        = 调用Dart,        -- 调用Dart(方法, 参数, 回调)
  callAsync   = dartCallAsync,
  -- 弹窗
  dialog      = 显示对话框,
  bottomSheet = 显示底部弹窗,
  snackBar    = 显示提示,
  pickDate    = 选择日期,
  pickTime    = 选择时间,
  closeDialog = 关闭对话框,
  -- 诊断
  debug       = flutter_debug,   -- flutter_debug(true)：唯一的调试入口
  handlers    = flutterHandlers, -- 打印已注册的 id 与回调
}
