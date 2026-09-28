-- flutter_新控件示例.lua
-- 同屏展示：二维码 / 图表 / 地图 / 视频 / 音频 / 懒加载列表 / Dart 逻辑调用。
-- 用 AndroLua 表风格写 Flutter 布局；渲染入口是中文名 渲染Flutter（= flutterRender）。
-- 需联网（地图瓦片、视频、音频、二维码内容链接）。

local 提示 = "事件会打印到日志（logcat）：点列表项、点按钮都会回传名称与参数"

local function 标题(t)
  return { Text, text = t, fontSize = 18, fontWeight = "bold", color = "#1A237E" }
end

local function 间隔()
  return { SizedBox, height = 8 }
end

local function 页面()
  return {
    Scaffold,
    appBar = {
      AppBar,
      elevation = 0,
      backgroundColor = "#1A237E",
      foregroundColor = "#FFFFFF",
      title = { Text, text = "Flutter 控件示例" },
    },
    body = {
      SingleChildScrollView,
      padding = 16,
      child = {
        Column,
        crossAxisAlignment = "start",
        gap = 16,

        -- 提示条
        { Container, color = "#FFF9C4", radius = 8, padding = 10,
          { Text, text = 提示, fontSize = 12, color = "#795548" } },

        -- ============ 二维码 ============
        标题("二维码 QrCode"),
        间隔(),
        { Center, { QrCode, data = "https://aicode.murk.top", size = 180, color = "#1A237E" } },

        -- ============ 图表 ============
        标题("图表 Chart（折线 / 柱状 / 饼图）"),
        间隔(),
        { Chart, chartType = "line", height = 200, series = {
          { name = "本周", color = "#3F51B5",
            points = { { x = 0, y = 3 }, { x = 1, y = 5 }, { x = 2, y = 2 }, { x = 3, y = 6 }, { x = 4, y = 4 }, { x = 5, y = 7 } } },
        } },
        { Chart, chartType = "bar", height = 200, series = {
          { name = "A", color = "#FF9800", value = 6 },
          { name = "B", color = "#4CAF50", value = 9 },
          { name = "C", color = "#2196F3", value = 4 },
        } },
        { Chart, chartType = "pie", height = 200, series = {
          { name = "安卓", color = "#3F51B5", value = 40 },
          { name = "iOS", color = "#009688", value = 35 },
          { name = "其它", color = "#FF9800", value = 25 },
        } },

        -- ============ 地图 ============
        标题("地图 FlutterMap（OSM 瓦片，无需 Key）"),
        间隔(),
        { Container, height = 260, radius = 12, clip = true,
          { FlutterMap, zoom = 11,
            center = { lat = 39.9042, lng = 116.4074 },
            markers = {
              { lat = 39.9042, lng = 116.4074, icon = "location_on" },
              { lat = 39.9163, lng = 116.3972, icon = "store" },
            } } },

        -- ============ 视频 ============
        标题("视频 VideoPlayer"),
        间隔(),
        { Container, radius = 12, clip = true,
          { VideoPlayer,
            url = "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4",
            autoPlay = false, loop = true, controls = true } },

        -- ============ 音频 ============
        标题("音频 AudioPlayer"),
        间隔(),
        { AudioPlayer,
          url = "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
          title = "示例音乐" },

        -- ============ 懒加载列表 ============
        标题("懒加载列表 ListView.builder（500 项）"),
        间隔(),
        { Container, height = 320, radius = 12, clip = true,
          { ListView,
            itemCount = 500,
            itemTemplate = {
              ListTile,
              leading = "person",
              title = { Text, text = "第 $index 项" },
              subtitle = { Text, text = "滑到才构建（ListView.builder 懒加载）" },
              trailing = "chevron_right",
              onTap = { call = "echo", args = { index = "$index" } },
            } } },

        -- ============ Dart 逻辑 ============
        标题("调用 Dart 逻辑"),
        间隔(),
        { Button, text = "调用 Dart：fetchOrders(page=1, size=5)", width = "fill",
          onClick = { call = "fetchOrders", args = { page = 1, size = 5 } } },
        { Button, text = "调用 Dart：httpGet(https://httpbin.org/get)", width = "fill",
          onClick = { call = "httpGet", args = { url = "https://httpbin.org/get" } } },
        { SizedBox, height = 24 },
      },
    },
  }
end

activity.setContentView(渲染Flutter(页面()))

-- 不在这里整页重绘：否则会重建视频/音频（重载）。事件先打印到日志，需要 UI 反馈时再自行 渲染Flutter(页面())。
function onFlutterEvent(e)
  local name = (e and e.name) or "?"
  local d = (e and e.data) or {}
  local parts = { "事件:", name }
  if d.action and d.action ~= "" then table.insert(parts, "action=" .. tostring(d.action)) end
  if d.value ~= nil then table.insert(parts, "value=" .. tostring(d.value)) end
  if d.result then
    if d.result.status then table.insert(parts, "status=" .. tostring(d.result.status)) end
    if d.result.list then table.insert(parts, "订单数=" .. tostring(#d.result.list)) end
    if d.result.echo ~= nil then table.insert(parts, "echo.index=" .. tostring(d.result.echo.index)) end
    if d.result.error then table.insert(parts, "error=" .. tostring(d.result.error)) end
  end
  print(table.concat(parts, "  "))
end
