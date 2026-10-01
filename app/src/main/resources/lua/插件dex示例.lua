-- main.lua —— 从 Lua 端启动 dex 里的 Fragment 页面
--
-- 工作原理（配合宿主 com.androlua.plugin.ProxyActivity）：
--   Lua 只是构造一个 Intent，告诉「代理 Activity」：dex 在哪、加载哪个 Fragment、传什么参数；
--   真正的 dex 加载 / Fragment 实例化都在 ProxyActivity 里完成（见其源码注释）。
--
-- 运行前提：
--   1) 宿主已安装（含 ProxyActivity）；2) /sdcard/plugin.dex 已就位（见 build_dex.sh --push）。
--
require "import"
import "android.content.Intent"
import "android.os.Build"
import "android.widget.Toast"

-- ============================================================
-- 配置：默认路径与类名，可按需改
-- ============================================================
local DEX_PATH       = "/sdcard/plugin.dex"
local FRAGMENT_CLASS = "com.example.plugin.DemoFragment"
local PROXY_ACTIVITY = "com.androlua.plugin.ProxyActivity"

-- ============================================================
-- 启动 dex 页面
--   opts = {
--     dexPath       = "/sdcard/plugin.dex",                  -- dex 路径
--     fragmentClass = "com.example.plugin.DemoFragment",     -- Fragment 全限定名
--     title         = "我的插件页",                            -- 窗口标题（可选）
--     newTask       = true,                                  -- 新开 Task（默认 true）
--     adjacent      = false,                                 -- 分屏邻位启动（仅 API24+，默认 false）
--     orientation   = 0,                                     -- 0 跟随系统 / 1 竖屏 / 2 横屏
--     args          = { msg = "hi", count = 42 },            -- 任意业务参数，原样转交给 Fragment
--   }
-- ============================================================
local function 启动dex页面(opts)
  opts = opts or {}

  -- 1) 宿主里唯一需要注册的组件就是 ProxyActivity，这里显式指定它
  local intent = Intent()
  intent.setClassName(activity.getPackageName(), PROXY_ACTIVITY)

  -- 2) 控制参数：告诉 ProxyActivity 加载什么
  intent.putExtra("dex_path", opts.dexPath or DEX_PATH)
  intent.putExtra("fragment_class", opts.fragmentClass or FRAGMENT_CLASS)
  if opts.title then
    intent.putExtra("title", opts.title)
  end
  if opts.orientation then
    intent.putExtra("orientation", opts.orientation)
  end

  -- 3) 业务参数：原样转交给 Fragment（Fragment 里从 getArguments() 取）
  local args = opts.args
  if args then
    for k, v in pairs(args) do
      if type(v) == "string" then
        intent.putExtra(k, v)
      elseif type(v) == "number" then
        -- Lua 数字统一按 double 传；Fragment 侧用 Number 读取即可兼容 int/long/float
        intent.putExtra(k, v + 0.0)
      elseif type(v) == "boolean" then
        intent.putExtra(k, v)
      end
      -- 其它类型（表/函数）跳过：Intent extra 只支持基本类型
    end
  end

  -- 4) 新开 Task：让它和宿主主界面分开，出现在最近任务里（类似小程序）
  --    仅在需要时添加，避免和调用方的启动模式意外交互
  if opts.newTask ~= false then
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
  end

  -- 5) 分屏邻位启动（FLAG_ACTIVITY_LAUNCH_ADJACENT）只在 Android 7.0 (API 24) 及以上存在。
  --    低版本没有这个常量，直接引用会报错，所以用版本判断 + 字面量 0x1000。
  --    该标志要与 FLAG_ACTIVITY_NEW_TASK 搭配才有意义（且设备需支持多窗口）。
  if opts.adjacent and Build.VERSION.SDK_INT >= 24 then
    intent.addFlags(0x1000) -- FLAG_ACTIVITY_LAUNCH_ADJACENT
  end

  -- 6) 启动（在 AndroLua 主线程里调用是安全的）
  activity.startActivity(intent)
end

-- ============================================================
-- 演示：直接启动，并传字符串 / 数字 / 布尔参数
-- ============================================================
启动dex页面{
  title = "插件页面 · 来自 Lua",
  args = {
    msg   = "你好，我是 Lua 传过来的字符串",
    count = 42,
    ratio = 3.14,
    flag  = true,
  },
}

-- 需要分屏邻位启动时改成：
-- 启动dex页面{ adjacent = true, args = { msg = "分屏中打开" } }
