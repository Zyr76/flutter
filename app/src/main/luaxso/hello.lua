-- 示例：本文件会被 tools/luaxso.py 加密后放进 lib<aGVsbG8>.so 的数据段
-- 运行时用 require "aGVsbG8" 加载（aGVsbG8 = "hello" 的 base64url）
local M = {}

function M.greet(name)
    return "你好，" .. tostring(name) .. "（来自加密 so 容器）"
end

return M
