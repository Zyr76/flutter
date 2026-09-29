-- flutter_命令式更新示例.lua
-- 演示：
--   1) 渲染后用 id 句柄改属性：h.dart.<属性名> = 值（只局部刷新该节点，不重建整棵树）
--   2) 图片 src 只写文件名（如 shiguang_check.png），原生侧会用项目目录自动拼成绝对路径
--   3) 弹窗：显示对话框 / 显示底部弹窗 / 显示提示

local layout = {
  Column, gap = 12, padding = 24,
  { Text, text = "点按钮改下面这行文字", fontSize = 16 },
  { Text, text = "", id = "tv", fontSize = 20, color = "#3F51B5" },
  { ElevatedButton, text = "改成「你好」", id = "btn", width = "fill" },
  { ElevatedButton, text = "弹个对话框", id = "dlg", width = "fill" },
  { ElevatedButton, text = "弹底部弹窗", id = "sheet", width = "fill" },
  { ElevatedButton, text = "弹个提示", id = "snack", width = "fill" },
  -- src 只写文件名（相对项目目录），也可以写网络地址 / /storage/... 绝对路径 / data:base64
  { Image, src = "shiguang_check.png", width = 64, height = 64 },
  { SwitchListTile, title = "开关示例", value = false, id = "sw" },
}

activity.setContentView(渲染Flutter(layout))

-- h.onClick = fn          -> 事件
-- h.dart.<属性> = 值       -> 命令式改属性（属性名大小写不敏感）
function btn.onClick()
  tv.dart.Text = "你好"
  sw.dart.title = "已切换"
end

function dlg.onClick()
  显示对话框 {
    AlertDialog,
    title = { Text, text = "提示" },
    content = { Text, text = "这是 Flutter 对话框，按钮事件走同名全局函数。" },
    actions = {
      { TextButton, text = "关闭", onClick = "closeDlg" },
    },
  }
end

function closeDlg()
  关闭对话框()
end

function sheet.onClick()
  显示底部弹窗 {
    Column, gap = 8, padding = 16,
    { ListTile, title = { Text, text = "选项一" } },
    { ListTile, title = { Text, text = "选项二" } },
  }
end

function snack.onClick()
  显示提示("这是一条 SnackBar")
end
