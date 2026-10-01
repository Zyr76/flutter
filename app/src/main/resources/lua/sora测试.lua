-- Sora 编辑器 最小测试：验证 Lua 高亮 + 补全
-- 打开运行本脚本，观察：文字是否彩色、输入字母是否弹出候选。
require "import"
import "io.github.rosemoe.sora.widget.*"
import "com.androlua.*"

activity.setTitle("Sora 测试")

local ed = CodeEditor(activity)

-- 挂 Lua 语言（同时启用高亮分析与补全）
local ok, err = pcall(function()
  ed.setEditorLanguage(LuaLanguage())
end)
-- 看控制台输出：ok 应为 true
print("[Sora测试] setEditorLanguage ok=", ok, "err=", tostring(err))

ed.setText([[
-- Sora 高亮/补全 测试
local function hello(name)
    print("hello, " .. name)   -- 这是一个注释
end
hello("AndroLua")
local n = 123
if n then return nil end
]])

activity.setContentView(ed)
print("[Sora测试] editor =", tostring(ed))
