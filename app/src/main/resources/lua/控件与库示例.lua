-- ============================================================
-- 控件与第三方库 使用示例
-- 在 AndroLua 中直接运行本脚本即可。顶部按钮切换各示例。
--
-- 覆盖：
--   RecyclerAdapter  RecyclerView 适配器（懒加载 / 分页 / 多布局 / 点击）
--   FlexboxLayout    流式布局（FlowLayout）
--   Glide            图片加载（网络 / 本地）
--   OkHttp           网络请求
--   Lottie           矢量动画
--   LuaWebView       网页
--   LuaEditor        代码编辑器
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
    function() return 100000 end,                                   -- 总数
    function(pos) return { title = "第 " .. pos .. " 项", sub = "懒加载 · 点我看看" } end
  )
  -- 分页示例（滚动到底部会回调一次；此处演示，可去掉）
  -- adapter.setOnLoadMore(function() print("到底了，可在这里加载下一页") end)

  adapter.setOnItemClick(function(pos, data)
    activity.showToast("点击：" .. pos .. " · " .. tostring(data.title))
  end)

  rv.setAdapter(adapter)
  return rv
end

-- ============================================================
-- 2) FlexboxLayout 流式布局（FlowLayout）
-- ============================================================
local function pageFlow()
  local scroll = ScrollView(activity)
  local flow = FlexboxLayout(activity)
  flow.setFlexWrap(FlexboxLayout.WRAP)         -- 自动换行
  flow.setPadding(24, 24, 24, 24)
  for i = 1, 30 do
    local t = TextView(activity)
    t.setText("标签 " .. i)
    t.setTextColor(0xffffffff)
    t.setBackgroundColor(0xff3f51b5)
    t.setPadding(28, 14, 28, 14)
    local lp = FlexboxLayout.LayoutParams(-2, -2)
    lp.setMargins(12, 12, 0, 0)
    t.setLayoutParams(lp)
    flow.addView(t)
  end
  scroll.addView(flow, ViewGroup.LayoutParams(-1, -2))
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
-- 4) OkHttp 网络请求（在子线程执行，回主线程更新 UI）
-- ============================================================
local function pageNet()
  local tv = TextView(activity)
  tv.setPadding(24, 24, 24, 24)
  tv.setTextIsSelectable(true)
  tv.setText("请求中…")
  thread(function()
    local ok, res = pcall(function()
      local client = OkHttpClient()
      local req = Request.Builder().url("https://www.baidu.com").build()
      local resp = client.newCall(req).execute()
      local body = resp.body().string()
      resp.close()
      return body
    end)
    activity.runOnUiThread(function()
      if ok then
        tv.setText(("OkHttp 返回 %d 字节：\n\n"):format(#res) .. res:sub(1, 800))
      else
        tv.setText("请求失败：\n" .. tostring(res))
      end
    end)
  end)
  return tv
end

-- ============================================================
-- 5) Lottie 矢量动画（需把一个 lottie json 放到 assets，如 anim.json）
-- ============================================================
local function pageLottie()
  local wrap = LinearLayout(activity)
  wrap.setOrientation(LinearLayout.VERTICAL)
  wrap.setPadding(24, 24, 24, 24)

  local lv = LottieAnimationView(activity)
  lv.setRepeatCount(-1)                          -- 无限循环
  local ok, err = pcall(function() lv.setAnimation("anim.json") end)
  if ok then
    lv.playAnimation()
  end

  local hint = TextView(activity)
  hint.setText(ok and "Lottie 正在播放 assets/anim.json"
    or ("未找到 assets/anim.json，请放入一个 lottie json。\n" .. tostring(err)))

  wrap.addView(lv, LinearLayout.LayoutParams(-1, 0, 1))
  wrap.addView(hint, LinearLayout.LayoutParams(-1, -2))
  return wrap
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
  { "动画", pageLottie },
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
