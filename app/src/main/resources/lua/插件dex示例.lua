-- main.lua —— 宿主脚本页（有内容）+ 打开外部 dex 页面
--
-- 打开Dex页面(dex路径, Fragment类名 [, 参数表])   ← 宿主注册的全局函数
--   参数表里 title/标题、orientation/方向、adjacent/分屏、newTask/新任务 是「控制项」，
--   其余键原样传给 Fragment。别名：加载Dex页面 / dexPage / openDexPage
--
-- title 会同时用作「标题栏」和「最近任务卡片」的标题（宿主内部调了 setTaskDescription）。

require "import"
import "android.widget.*"
import "android.view.*"

local DEX_PATH = "/sdcard/plugin.dex"
local FRAGMENT = "com.example.plugin.DemoFragment"

-- 宿主页面上放个按钮，点一下打开插件页（这样从插件页返回时回到的是这个有内容的页面，
-- 而不是一个空白页）。
activity.setTitle("插件演示")
activity.setContentView(loadlayout{
  LinearLayout, orientation = "vertical", padding = "24dp",
  {
    TextView, id = "tip",
    text = "这是宿主脚本页面，点下面按钮打开 dex 里的 Fragment 页面",
    textSize = "16sp",
  },
  {
    Button, id = "openBtn", text = "打开插件页面",
  },
})

openBtn.onClick = function(v)
  打开Dex页面(DEX_PATH, FRAGMENT, {
    title = "插件页面 · 来自 Lua",          -- 标题栏 + 最近任务卡片都用它
    msg   = "你好，我是 Lua 传过来的字符串",
    count = 42,
    ratio = 3.14,
    flag  = true,
  })

  -- 想让「打开插件后宿主页自动关闭、返回时直接回 AndroLua 主界面」，取消下面这行注释：
  -- activity.finish()

  -- 需要分屏邻位打开时，把上面换成：
  -- 打开Dex页面(DEX_PATH, FRAGMENT, { adjacent = true, msg = "分屏中打开" })
end
