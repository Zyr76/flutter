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

-- 统一 UI 调试开关：flutterUI_debug(true) 打开后
--   * 未知控件/属性名会打日志并通过 flutterUiIssue 事件回传（同类只报一次）
--   * 构建失败显示红框占位（关闭时渲染成空，异常仍通过 flutterError 事件回传）
--   * Flutter 层异常通过 flutterError 事件回传
function flutterUI_debug(on)
  on = not not on
  _G.__flutter_ui_debug = on
  调用Dart("flutterUIDebug", { enabled = on })
  return on
end

-- 顺手把常用接口收成一个表，方便 require 后按名取用
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
  debug       = flutterDebug,       -- flutterDebug(true) 打开事件日志
  uiDebug     = flutterUI_debug,    -- flutterUI_debug(true) 统一 UI 调试开关
  handlers    = flutterHandlers,    -- 打印已注册的 id 与回调
}
