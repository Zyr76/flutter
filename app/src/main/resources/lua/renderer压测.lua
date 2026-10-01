-- Flutter UI 渲染器 压测脚本
--
-- 目的：实测「Lua -> Flutter」这条链路的成本，以及大列表的滚动体感。
-- 说明：这里测的是 Lua/原生侧发起渲染 / 更新的耗时（跨 MethodChannel 的派发成本），
--       Flutter 真正的绘制帧率需肉眼或 perfetto 看；这些数字用于横向对比。
--
-- 用法：在 AndroLua 里运行本脚本，点顶部按钮，观察控制台 [压测] 输出与列表滚动顺滑度。

require "import"
import "android.widget.*"
import "android.view.*"
import "java.lang.System"

local function now() return System.currentTimeMillis() end
local function log(s) print("[压测] " .. s) end

activity.setTitle("Flutter 渲染器 压测")

local COUNT = 20000   -- 大列表项数（懒加载，只构建可见项）

-- 页面 spec：一个可命令式更新的 counter + 一个 2 万项的 ListView
local function spec()
  return {
    Scaffold,
    backgroundColor = "#FFFFFF",
    body = {
      Column,
      { Text, id = "counter", text = "counter=0", fontSize = 14, padding = 8 },
      { Text, id = "note",
        text = "列表 " .. COUNT .. " 项（懒加载），上下滚动看是否顺滑",
        fontSize = 12, color = "#888888", padding = 8 },
      { Expanded, {
          ListView,
          itemCount = COUNT,
          itemTemplate = {
            ListTile,
            title = { Text, text = "$index 行", fontSize = 16 },
            subtitle = { Text, text = "第 $index 项 · 压测", fontSize = 12, color = "#888888" },
          },
        } },
    },
  }
end

local host = FrameLayout(activity)

-- 1) 首次渲染
local t = now()
渲染Flutter(spec(), host)
log("首次渲染（列表 " .. COUNT .. " 项）派发耗时 " .. (now() - t) .. " ms")

-- 顶部按钮
local bar = LinearLayout(activity)
bar.setOrientation(LinearLayout.HORIZONTAL)
local function btn(text, fn)
  local b = Button(activity)
  b.setText(text)
  b.setOnClickListener(fn)
  bar.addView(b)
  return b
end

-- 2) 全量重渲染：连续 render 30 次，测单次派发成本
btn("全量重渲染 x30", function()
  local s = now()
  for _ = 1, 30 do 渲染Flutter(spec(), host) end
  local d = now() - s
  log(string.format("全量重渲染 x30：共 %d ms，平均 %.1f ms/次", d, d / 30))
end)

-- 3) 命令式 patch：改一个节点的属性 2000 次
btn("patch x2000", function()
  if counter == nil then log("counter 未绑定，先等首次渲染完成") return end
  local s = now()
  for i = 1, 2000 do counter.dart.Text = "counter=" .. i end
  log("patch(命令式改属性) x2000：共 " .. (now() - s) .. " ms")
end)

-- 4) 高频局部刷新：每 50ms 更新一次 counter（模拟实时刷新）
-- 不能用 timer{}：它会把函数 dump 到新 LuaState，upvalue 会丢（首个 upvalue 变全局表，
-- 报 "arithmetic on a table value"）。改用主线程 postDelayed 循环，回调仍在主 LuaState。
local hbRunning = false
local hbI = 0
local hbTick
hbTick = function()
  if not hbRunning then return end
  hbI = hbI + 1
  if counter then counter.dart.Text = "counter=" .. hbI .. "  (每50ms)" end
  host.postDelayed(hbTick, 50)
end

btn("高频刷新 开/关", function()
  if hbRunning then
    hbRunning = false
    log("已停止高频刷新")
  else
    hbRunning = true
    log("开始高频刷新（每 50 ms 更新 counter）")
    hbTick()
  end
end)

local root = LinearLayout(activity)
root.setOrientation(LinearLayout.VERTICAL)
root.addView(bar, LinearLayout.LayoutParams(-1, -2))
root.addView(host, LinearLayout.LayoutParams(-1, 0, 1))
activity.setContentView(root)
