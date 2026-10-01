-- ============================================================
-- 控件与第三方库 使用示例
-- 在 AndroLua 中直接运行本脚本即可。顶部按钮切换各示例。
--
-- 覆盖：
--   RecyclerAdapter  RecyclerView 适配器（懒加载 / 分页 / 多布局 / 点击）
--   FlexboxLayout    流式布局（FlowLayout）
--   Glide            图片加载（网络 / 本地）
--   OkHttp           网络请求
--   SoraEditor       代码编辑器（io.github.rosemoe.sora.widget.CodeEditor）
--   LuaWebView       网页
--   LuaEditor        内置代码编辑器
--
-- 注意（AndroLua 的 thread）：thread{} 会把函数 dump 到新的 LuaState 执行，
-- 因此 ① 函数里捕获的 upvalue（外部局部变量）会丢失，需要的数据要用参数传入；
--       ② 新状态没有主脚本的 import，需在 thread 内重新 require/import。
-- ============================================================

require "import"
require "材料设计"                 -- 引入 MD3 / AndroidX / flexbox / lottie 等类
import "android.widget.*"
import "android.view.*"
import "com.androlua.*"            -- LuaWebView / LuaEditor
import "com.bumptech.glide.*"      -- Glide
import "okhttp3.*"                 -- OkHttp

activity.setTitle("控件与库示例")

-- ============================================================
-- 1) RecyclerView + RecyclerAdapter（懒加载 10 万条虚拟数据）
-- ============================================================
local function pageList()
  local rv = RecyclerView(activity)
  rv.setLayoutManager(LinearLayoutManager(activity))

  -- item 布局：id 会绑定到行数据的同名字段
  local adapter = RecyclerAdapter{
    LinearLayout, orientation = "vertical", padding = "16dp",
    { TextView, id = "title", textSize = "16sp", textColor = "0xff222222" },
    { TextView, id = "sub", textSize = "12sp", textColor = "0xff888888" },
  }

  -- 懒加载：不构造整表，按位置向 Lua 现取（适合超大 / 虚拟列表）
  adapter.setSource(
    function() return 100000 end,
    function(pos) return { title = "第 " .. pos .. " 项", sub = "懒加载 · 点我看看" } end
  )
  -- 点击回调签名：function(pos, data, view)，pos 从 1 开始
  adapter.setOnItemClick(function(pos, data)
    activity.showToast("点击：" .. pos .. " · " .. tostring(data.title))
  end)

  rv.setAdapter(adapter)
  return rv
end

-- ============================================================
-- 2) FlexboxLayout 流式布局（FlowLayout）—— 用 loadlayout 生成，自动处理 LayoutParams
-- ============================================================
local function pageFlow()
  local t = {
    FlexboxLayout, layout_width = "fill", layout_height = "wrap_content",
    padding = "12dp", flexWrap = 1,        -- 1 = WRAP（自动换行）
  }
  for i = 1, 30 do
    t[#t + 1] = {
      TextView, text = "标签 " .. i,
      textColor = "0xffffffff", backgroundColor = "0xff3f51b5",
      padding = "10dp", layout_margin = "6dp",
    }
  end
  local scroll = ScrollView(activity)
  scroll.addView(loadlayout(t), ViewGroup.LayoutParams(-1, -2))
  return scroll
end

-- ============================================================
-- 3) Glide 加载图片（网络 / 本地文件都支持，自动缓存）
-- ============================================================
local function pageImage()
  local iv = ImageView(activity)
  iv.setScaleType(ImageView.ScaleType.CENTER_CROP)
  Glide.with(activity).load("https://picsum.photos/800/600").into(iv)
  -- 本地文件：Glide.with(activity).load("/sdcard/a.jpg").into(iv)
  -- 圆形：    Glide.with(activity).load(url).circleCrop().into(iv)
  return iv
end

-- ============================================================
-- 4) OkHttp 网络请求
--    thread 内是新 LuaState：需重新 import；view 用参数传入（避免 upvalue 丢失）
-- ============================================================
local function pageNet()
  local tv = TextView(activity)
  tv.setPadding(24, 24, 24, 24)
  tv.setTextIsSelectable(true)
  tv.setText("请求中…")

  thread(function(view)
    require "import"
    import "okhttp3.*"
    local ok, body = pcall(function()
      local client = OkHttpClient()
      local req = Request.Builder().url("https://www.baidu.com").build()
      local resp = client.newCall(req).execute()
      local s = resp.body().string()
      resp.close()
      return s
    end)
    activity.runOnUiThread(function()
      if ok then
        view.setText(("OkHttp 返回 %d 字节：\n\n"):format(#body) .. body:sub(1, 800))
      else
        view.setText("请求失败：\n" .. tostring(body))
      end
    end)
  end, tv)

  return tv
end

-- ============================================================
-- 5) SoraEditor 代码编辑器（io.github.rosemoe.sora.widget.CodeEditor）
-- ============================================================
local function pageSora()
  -- 用 sora.lua 封装：SoraEditor + TextMate 的 Lua 语法高亮
  return require("sora")([[
-- SoraEditor + TextMate Lua 高亮
local function hello(name)
    print("hello, " .. name)   -- 注释
end
hello("AndroLua")
local n = 123
if n then return nil end
]])
end

-- ============================================================
-- 6) LuaWebView 网页
-- ============================================================
local function pageWeb()
  local wv = LuaWebView(activity)
  wv.loadUrl("https://www.baidu.com")
  return wv
end

-- ============================================================
-- 7) LuaEditor 代码编辑器（等宽字体 / 语法高亮 / 行号）
-- ============================================================
local function pageEditor()
  local ed = LuaEditor(activity)
  ed.setText([[
-- 代码编辑器示例
local function hello(name)
    print("hello, " .. name)
end
hello("AndroLua")
]])
  return ed
end

-- ============================================================
-- 顶部按钮 + 内容区
-- ============================================================
local pages = {
  { "列表", pageList },
  { "流式布局", pageFlow },
  { "图片", pageImage },
  { "网络", pageNet },
  { "Sora编辑器", pageSora },
  { "网页", pageWeb },
  { "编辑器", pageEditor },
}

local content = FrameLayout(activity)

local bar = HorizontalScrollView(activity)
local menu = LinearLayout(activity)
menu.setOrientation(LinearLayout.HORIZONTAL)
bar.addView(menu)

local function show(fn)
  content.removeAllViews()
  content.addView(fn(), FrameLayout.LayoutParams(-1, -1))
end

for _, p in ipairs(pages) do
  local b = Button(activity)
  b.setText(p[1])
  b.setOnClickListener(function() show(p[2]) end)
  menu.addView(b)
end

local root = LinearLayout(activity)
root.setOrientation(LinearLayout.VERTICAL)
root.addView(bar, LinearLayout.LayoutParams(-1, -2))
root.addView(content, LinearLayout.LayoutParams(-1, 0, 1))
activity.setContentView(root)

show(pageList)   -- 默认显示列表示例
