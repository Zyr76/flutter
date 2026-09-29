-- flutter_命令式更新示例.lua
-- 演示两类能力：
--   1) 渲染后直接用 id 句柄改属性（h.Text = "..."），只局部刷新该节点，不重建整棵树；
--   2) 图片控件统一用 src，Dart 端自动判断 网络 / 本地文件 / base64(data URI) / asset。

local layout = {
  Column, gap = 12, padding = 24,
  { Text, text = "点按钮改下面这行文字", fontSize = 16 },
  { Text, text = "", id = "tv", fontSize = 20, color = "#3F51B5" },
  { Button, text = "改成「你好」", id = "btn", width = "fill" },
  -- src 填网络地址 / 本地路径 / data:image/...;base64,... 都行
  { Image, src = "https://aicode.murk.top/favicon.ico", width = 64, height = 64 },
  { SwitchListTile, title = "开关示例", value = false, id = "sw" },
}

activity.setContentView(渲染Flutter(layout))

-- 命令式改属性：属性名大小写不敏感（tv.Text 等价 tv.text）
function btn.onClick()
  tv.Text = "你好"
  sw.title = "已切换"
end
