-- flutter示例.lua —— AndroLua + Flutter 桥使用示例（唯一示例）
--
-- 四条规则：
--   1) 原生 loadlayout 用 Android 类名（Button / TextView / FrameLayout…）；
--      Flutter spec 用 Flutter 自己的控件名（ElevatedButton / Column / Text…）。两者不能混用。
--   2) 控件名就是 Flutter 的类名，没有别名（不要写 Button，要写 ElevatedButton）。
--   3) 动态改属性：id.dart.属性 = 值    例：btn.dart.Text = "已点击"
--   4) 事件：h.onClick（具体回调）与 收到Flutter事件（总监听）【都会】触发。

require "import"
import "android.widget.*"
import "android.view.*"

activity.setTitle("AndroLua + Flutter")

-- ---------- 原生区（顶部提示 + 底部按钮）----------
activity.setContentView(loadlayout{
  LinearLayout, orientation = "vertical", backgroundColor = "0xffffffff",
  { TextView, id = "hint", text = "↑ 原生 TextView" },
  { FrameLayout, id = "flutterHost", layout_width = "fill", layout_height = 0, layout_weight = 1 },
  { Button, id = "nativeBtn", text = "原生按钮：dartCall('getUserInfo')" },
})
hint.setPadding(24, 24, 24, 24)

-- ---------- Flutter 区（第二个参数是容器）----------
渲染Flutter({
  Scaffold,
  backgroundColor = "#FFFFFF",
  appBar = { AppBar, title = { Text, text = "Flutter 示例" } },
  body = {
    ListView, padding = 16,
    children = {
      { Text, text = "文本与属性", fontSize = 18, fontWeight = "bold" },
      { Text, text = "颜色 / 字号 / 粗体 / 下划线", color = "#3F51B5", decoration = "underline" },
      { Text, text = "这一行会被省略号截断，很长的很长很长很长很长很长很长", maxLines = 1 },

      { Divider },

      { Text, text = "交互控件", fontSize = 18, fontWeight = "bold" },
      { SwitchListTile, title = "开关", value = false, id = "sw" },
      { CheckboxListTile, title = "复选", value = true },
      { Slider, min = 0, max = 100, value = 30 },
      { ElevatedButton, text = "点我改文字", id = "btn", width = "fill" },
      { OutlinedButton, text = "弹个对话框", id = "dlg", width = "fill" },

      { Divider },

      { Text, text = "图片：src 写文件名会自动拼项目目录", fontSize = 18, fontWeight = "bold" },
      -- 也可以写 http 地址 / /storage/... 绝对路径 / data:image/png;base64,xxx
      { Image, src = "shiguang_check.png", width = 64, height = 64, radius = 8 },

      { Divider },

      { Text, text = "更多控件", fontSize = 18, fontWeight = "bold" },
      { QrCode, data = "7891", width = 100, height = 100, color = "#007000" },
      { SegmentedButton,
        segments = { { value = "日", label = "日" }, { value = "周", label = "周" }, { value = "月", label = "月" } },
        selected = { "周" }, id = "seg" },
      { LineChart, height = 180, series = {
          { name = "A", color = "#3F51B5", points = { { x = 0, y = 1 }, { x = 1, y = 3 }, { x = 2, y = 2 } } },
      } },
      { CupertinoButton, text = "Cupertino 按钮", color = "#3F51B5" },
      { SearchBar, hint = "搜索框…" },
    },
  },
}, flutterHost)

-- ---------- 具体回调：id 句柄 ----------

-- h.onClick = fn（等价于 function h.onClick() ... end）
function btn.onClick()
  btn.dart.Text = "已点击"              -- 命令式改属性（只刷新这一个节点）
  btn.dart.backgroundColor = "#4CAF50"
end

-- 开关变化
function sw.onChange(v)
  hint.setText("开关：" .. tostring(v))
end

-- 弹对话框：按钮点击事件名 = 字符串 "doClose"，会调用同名全局函数
function dlg.onClick()
  显示对话框 {
    AlertDialog,
    title = { Text, text = "提示" },
    content = { Text, text = "这是 Flutter 对话框，点关闭试试。" },
    actions = {
      { TextButton, text = "关闭", onClick = "doClose" },
    },
  }
end

function doClose()
  关闭对话框()
end

-- ---------- 总监听：所有事件都会到这里（不会打断上面的具体回调）----------
function 收到Flutter事件(e)
  local name = e and e.name or "?"
  hint.setText("Flutter 事件：" .. name)
end

-- ---------- 原生按钮 -> Dart 逻辑 ----------
-- 用【异步】dartCall：回调在主 Lua 状态里执行，可以直接访问 hint / 其它主脚本全局变量。
-- 注意：thread{...} 里是另一个 Lua 状态（新 LuaState），主脚本的全局变量（如 hint、内置控件句柄）
--       在那边都是 nil——所以不要在 thread 里直接操作主脚本的控件。若必须同步调用，
--       请用 activity.runOnUiThread 回主线程后，通过 activity.call("函数名") 之类的方式转交。
nativeBtn.onClick = function()
  hint.setText("正在调用 Dart getUserInfo …")
  调用Dart("getUserInfo", { id = 7 }, function(info, err)
    if info then
      hint.setText("Dart 返回：name=" .. tostring(info.name) .. ", age=" .. tostring(info.age))
    else
      hint.setText("dartCall 失败：" .. tostring(err))
    end
  end)
end
