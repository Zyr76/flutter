-- flutter_id示例.lua
-- AndroLua 式 id 句柄：给控件写 id="h"，渲染后会生成同名 Lua 句柄，再 h.onClick = fn 绑定点击。
-- 等价于 loadlayout 里的 id + h.onClick 写法。

local layout = {
  Column, gap = 12, padding = 24,
  { Text, text = "点下面的按钮", fontSize = 16 },
  { Button, text = "4664", id = "h", width = "fill" },
}

activity.setContentView(渲染Flutter(layout))

-- 下面这句和 function h.onClick() ... end 等价
function h.onClick()
  print("哈哈哈")
end
