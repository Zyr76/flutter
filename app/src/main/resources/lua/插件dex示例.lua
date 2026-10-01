-- main.lua —— 打开外部 dex 里的页面（一行搞定）
--
-- 宿主已把整套流程（组装 Intent、版本兼容、新开 Task、主线程启动）注册成全局函数：
--
--   打开Dex页面(dex路径, Fragment类名 [, 参数表])
--
--   参数表里除下面几个「控制项」外，其它键都会原样传给 Fragment 的 getArguments()：
--     title / 标题        窗口标题
--     orientation / 方向   0 跟随系统（默认）/ 1 竖屏 / 2 横屏
--     adjacent / 分屏      true 时分屏邻位打开（仅 Android 7.0+，低版本忽略）
--     newTask / 新任务     是否新开 Task（默认 true）
--
-- 别名：加载Dex页面 / dexPage / openDexPage

打开Dex页面("/sdcard/plugin.dex", "com.example.plugin.DemoFragment", {
  title = "插件页面 · 来自 Lua",
  msg   = "你好，我是 Lua 传过来的字符串",
  count = 42,
  ratio = 3.14,
  flag  = true,
})

-- 需要分屏邻位打开时：
-- 打开Dex页面("/sdcard/plugin.dex", "com.example.plugin.DemoFragment",
--   { adjacent = true, msg = "分屏中打开" })
