-- ============================================================
-- yyjson 使用示例（yyjson 是高性能 JSON 库，这里通过项目的 C 绑定使用）
--
-- 用法和项目里的 cjson 基本一致，脚本可以直接换过来：
--   local yyjson = require "yyjson"
--   yyjson.encode(表 [, 选项])       -- 编码，失败抛错
--   yyjson.decode(字符串 [, 选项])   -- 解码，失败返回 nil, 错误, 位置
--   yyjson.null                      -- JSON null 的哨兵
--   yyjson.version()                 -- 底层 yyjson 版本
--
-- 跑一遍看日志即可（不需要界面）。
-- ============================================================
local yyjson = require "yyjson"
local cjson = pcall(require, "cjson") and require "cjson" or nil

local function 标题(s) print("\n== " .. s .. " ==") end

print("yyjson 版本:", yyjson.version())
if cjson then print("（本项目同时还带 cjson，两者用法可互换）") end

标题("基本编解码")
local 数据 = {
  名称 = "张三",
  年龄 = 30,
  会员 = true,
  标签 = { "a", "b", "c" },
  地址 = { 城市 = "北京", 邮编 = "100000" },
  备注 = yyjson.null,          -- 想输出 JSON null 就写 yyjson.null
}
local 文本 = yyjson.encode(数据)
print("编码:", 文本)

local 还原 = yyjson.decode(文本)
print("解码回来:", 还原.名称, 还原.年龄, 还原.标签[2], 还原.地址.城市)
print("null 还原成哨兵:", 还原.备注 == yyjson.null)

标题("选项")
print("美化：\n" .. yyjson.encode({ a = 1, b = { c = 2 } }, { indent = 2 }))
print("键排序:", yyjson.encode({ b = 1, a = 2, c = 3 }, { sortKeys = true }))
print("空表默认对象:", yyjson.encode({}), " 转数组:", yyjson.encode({}, { emptyArray = true }))
print("数组空洞补 null:", yyjson.encode({ [1] = "x", [3] = "z" }))
print("转义成 \\u:", yyjson.encode("中", { escapeUnicode = true }))

标题("解码扩展语法")
local 松散 = yyjson.decode([[{
  // 注释
  "a": 1,
  "b": [1, 2, 3,],
}]], { comments = true, trailingCommas = true })
print("带注释/尾逗号也能解:", 松散.a, #松散.b)

标题("错误处理")
local 坏, 错, 位置 = yyjson.decode('{"a": }')
print("坏 JSON:", 坏, 错, "位置=" .. tostring(位置))

local ok, err = pcall(yyjson.encode, { f = function() end })
print("编码 function 会抛错:", ok, err)

local 循环 = {}
循环.自己 = 循环
local ok2, err2 = pcall(yyjson.encode, 循环)
print("循环引用安全报错:", ok2, err2)

if cjson then
  标题("和 cjson 对比：同样数据，两边都能解")
  local a = yyjson.decode(文本)
  local b = cjson.decode(文本)
  print("yyjson:", a.名称, "| cjson:", b.name or b.名称)
end
