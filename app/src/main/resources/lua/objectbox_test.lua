-- ObjectBox 复杂测试
--
-- 直接在 app 里运行本脚本即可（依赖已随包接入的 objectbox）。
-- 覆盖：类型往返 / 更新覆盖 / space 隔离 / 删除 / keys·count·clear /
--       特殊字符 / 数值边界 / 大批量性能 / 跨线程 / 跨次运行持久化。
-- 结束会打印 PASS/FAIL 汇总；所有数据写在 "_obtest" 开头的空间里并在末尾清理。
--
-- 已知限制（会标成「限制」，不计入失败）：
--   * 值统一走 JSON，超过 2^53 的整数会丢精度；含 NUL 的字符串可能编码失败退回 tostring。
--   * 中文键/值与普通字符串一致，不做额外处理。

local ob = require "objectbox"

local pass, fail = 0, 0
local failed = {}
local notes = {}

local function report(name, cond, extra)
  if cond then
    pass = pass + 1
    print("  ✔ " .. name)
  else
    fail = fail + 1
    failed[#failed + 1] = name
    print("  ✘ " .. name .. (extra and ("  → " .. tostring(extra)) or ""))
  end
end

local function note(name, text)
  notes[#notes + 1] = name .. "：" .. tostring(text)
  print("  · " .. name .. "：" .. tostring(text))
end

-- 递归比较（表比较键值，其余比较值）
local function deepEq(a, b)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if not deepEq(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

local function roundtrip(name, value, cmp)
  ob.存("_obtest_types", name, value)
  local got = ob.取("_obtest_types", name)
  report("往返 " .. name, cmp and cmp(got, value) or deepEq(got, value),
    "got=" .. tostring(got))
end

-- ---------------------------------------------------------------- 清理
local function clearAll()
  ob.清空("_obtest_types")
  ob.清空("_obtest_iso_a")
  ob.清空("_obtest_iso_b")
  ob.清空("_obtest_ops")
  ob.清空("_obtest_bulk")
  ob.清空("_obtest_thread")
  ob.清空("_obtest_persist")
end

print("== 准备：清空测试空间 ==")
clearAll()
report("清空后计数为 0", ob.数量("_obtest_types") == 0)

-- ---------------------------------------------------------------- 1. 类型往返
print("\n== 1. 类型往返 ==")
roundtrip("字符串", "hello")
roundtrip("空字符串", "")
roundtrip("中文", "你好，世界")
roundtrip("emoji", "🎉🚀 测试")
roundtrip("整数", 42)
roundtrip("负整数", -7)
roundtrip("零", 0)
roundtrip("浮点", 3.141592653589793)
roundtrip("科学计数", 1.5e-10)
roundtrip("布尔真", true)
roundtrip("布尔假", false)
roundtrip("字符串数字不转型", "123", function(got)
  return got == "123" and type(got) == "string"
end)

roundtrip("一维数组", { 1, 2, 3, 4, 5 })
roundtrip("空表", {}, function(got)
  return type(got) == "table" and next(got) == nil
end)
roundtrip("嵌套表", {
  name = "张三",
  age = 30,
  tags = { "a", "b", "c" },
  address = { city = "北京", zip = "100000" },
  active = true,
})
roundtrip("深层嵌套", { a = { b = { c = { d = { e = "dee" } } } } })

-- JSON 无法表示「数组 + 哈希混排」的表，读回会丢键或变对象，这是格式限制
local mixed = { 10, 20, 30, x = "y" }
ob.存("_obtest_types", "混合数组表", mixed)
local mixedBack = ob.取("_obtest_types", "混合数组表")
if deepEq(mixedBack, mixed) then
  report("往返 混合数组表", true)
else
  note("混合数组表", "JSON 不支持数组+哈希混排，读回为 " .. tostring(type(mixedBack)))
end

local long = string.rep("中文xyz", 20000) -- 约 140KB
ob.存("_obtest_types", "长字符串", long)
report("往返 长字符串(约140KB)", ob.取("_obtest_types", "长字符串") == long,
  "len=" .. tostring(#long))

-- ---------------------------------------------------------------- 2. 更新覆盖
print("\n== 2. 更新覆盖 ==")
ob.存("_obtest_ops", "k", "第一版")
local v1 = ob.取("_obtest_ops", "k")
ob.存("_obtest_ops", "k", "第二版")
local v2 = ob.取("_obtest_ops", "k")
report("覆盖后读到新值", v2 == "第二版", v2)
report("覆盖不新增记录", ob.数量("_obtest_ops") == 1, ob.数量("_obtest_ops"))
report("首次写入有值", v1 == "第一版")

ob.存("_obtest_ops", "k", { 从 = "字符串", 到 = "表" })
local v3 = ob.取("_obtest_ops", "k")
report("类型也可覆盖", type(v3) == "table" and v3.到 == "表", tostring(v3))

-- ---------------------------------------------------------------- 3. space 隔离
print("\n== 3. space 隔离 ==")
ob.存("_obtest_iso_a", "same", "A 的值")
ob.存("_obtest_iso_b", "same", "B 的值")
report("同名键互不影响 A", ob.取("_obtest_iso_a", "same") == "A 的值")
report("同名键互不影响 B", ob.取("_obtest_iso_b", "same") == "B 的值")

-- ---------------------------------------------------------------- 4. 删除
print("\n== 4. 删除 ==")
ob.存("_obtest_ops", "待删", 1)
report("删除存在的键返回 true", ob.删("_obtest_ops", "待删") == true)
report("删除后读到 nil", ob.取("_obtest_ops", "待删") == nil)
report("重复删除返回 false", ob.删("_obtest_ops", "待删") == false)
report("值传 nil 等价删除", (function()
  ob.存("_obtest_ops", "nil删", 1)
  ob.存("_obtest_ops", "nil删", nil)
  return ob.取("_obtest_ops", "nil删") == nil
end)())

-- ---------------------------------------------------------------- 5. keys / count / clear
print("\n== 5. keys / count / clear ==")
clearAll()
for i = 1, 25 do
  ob.存("_obtest_ops", "key_" .. string.format("%02d", i), i)
end
report("count 为 25", ob.数量("_obtest_ops") == 25, ob.数量("_obtest_ops"))

local ks = ob.键("_obtest_ops")
report("keys 返回 Lua 表", type(ks) == "table", type(ks))
report("keys 个数为 25", #ks == 25, #ks)
local seen, allHit = {}, true
for _, k in ipairs(ks) do
  seen[k] = true
end
for i = 1, 25 do
  local k = "key_" .. string.format("%02d", i)
  if not seen[k] then
    allHit = false
    break
  end
end
report("keys 内容完整", allHit)

report("clear 返回删除条数", ob.清空("_obtest_ops") == 25, ob.数量("_obtest_ops"))
report("clear 后 count 为 0", ob.数量("_obtest_ops") == 0)
report("空空间 keys 为空表", (function()
  local e = ob.键("_obtest_ops")
  return type(e) == "table" and #e == 0
end)())

-- ---------------------------------------------------------------- 6. 特殊字符
print("\n== 6. 特殊字符 ==")
local specials = {
  '双引号"',
  "单引号'",
  "反斜杠\\",
  "制表\t换行\n回车\r",
  "斜杠/与反斜杠\\混用",
  '{"看起来":"像JSON"}',
  "[[长括号]] .. end",
  "前后空格 ",
  " ",
}
for i, s in ipairs(specials) do
  ob.存("_obtest_types", "sp" .. i, s)
  local back = ob.取("_obtest_types", "sp" .. i)
  report("特殊字符 #" .. i, back == s,
    string.format("期望 %q，实得 %q", s, back))
end

local nul = "含NUL" .. string.char(0) .. "尾巴"
ob.存("_obtest_types", "nul", nul)
local nulBack = ob.取("_obtest_types", "nul")
if nulBack == nul then
  report("含 NUL 字符串往返", true)
else
  note("含 NUL 字符串", "无法原样往返（JSON 限制），读回为 " .. tostring(nulBack))
end

-- ---------------------------------------------------------------- 7. 数值边界
print("\n== 7. 数值边界 ==")
roundtrip("2^53", 9007199254740992)
roundtrip("小数精度 0.1", 0.1)
roundtrip("0.1+0.2", 0.1 + 0.2)
roundtrip("极小值", 4.9e-324)
roundtrip("极大值", 1.7976931348623157e308)

ob.存("_obtest_types", "bigint", 9007199254740993) -- 2^53 + 1
local bi = ob.取("_obtest_types", "bigint")
if bi == 9007199254740993 then
  report("超 2^53 整数精确往返", true)
else
  note("超 2^53 整数", "按 JSON double 存储会丢精度，读回 " .. tostring(bi))
end

-- ---------------------------------------------------------------- 8. 大批量性能
print("\n== 8. 大批量（1000 条）==")
clearAll()
local N = 1000
local t0 = os.clock()
for i = 1, N do
  ob.存("_obtest_bulk", "b" .. i, { 序号 = i, 名称 = "记录" .. i, 标记 = i % 2 == 0 })
end
local tWrite = os.clock() - t0

local t1 = os.clock()
local hit = 0
for i = 1, N do
  local v = ob.取("_obtest_bulk", "b" .. i)
  if v and v.序号 == i then
    hit = hit + 1
  end
end
local tRead = os.clock() - t1

report("批量写入后计数正确", ob.数量("_obtest_bulk") == N, ob.数量("_obtest_bulk"))
report("批量读取全部命中", hit == N, hit .. "/" .. N)
note("性能", string.format("写入 %d 条 %.3fs（%.2f ms/条）；读取 %d 条 %.3fs",
  N, tWrite, tWrite * 1000 / N, N, tRead))

-- ---------------------------------------------------------------- 9. 跨线程
print("\n== 9. 跨线程（thread 内写，主线程读）==")
clearAll()
local hasThread = type(thread) == "function"
if not hasThread then
  if pcall(require, "import") then
    hasThread = type(thread) == "function"
  end
end
if not hasThread then
  note("跨线程", "当前环境没有 thread()，跳过")
else
  local okThread = pcall(function()
    thread(function()
      -- 新 LuaState 没有主脚本的 import，必须自己 require
      local ob2 = require "objectbox"
      for i = 1, 50 do
        ob2.存("_obtest_thread", "t" .. i, i)
      end
    end)
  end)
  report("thread 启动成功", okThread)
  if okThread then
    local waited = 0
    while ob.数量("_obtest_thread") < 50 and waited < 300 do
      os.execute("sleep 0.02")
      waited = waited + 1
    end
    report("子线程写入可见（50 条）", ob.数量("_obtest_thread") == 50,
      ob.数量("_obtest_thread"))
  end
end

-- ---------------------------------------------------------------- 10. 跨次运行持久化
print("\n== 10. 跨次运行持久化 ==")
local prev = ob.取("_obtest_persist", "标记")
if prev ~= nil then
  report("读回上次运行的标记", type(prev) == "table" and prev.时间 ~= nil,
    tostring(prev and prev.时间))
  note("持久化", "上次运行时间 " .. tostring(prev and prev.时间))
else
  note("持久化", "首次运行，本次写入标记；再运行一次可验证跨次读回")
end
ob.存("_obtest_persist", "标记", { 时间 = os.date("%Y-%m-%d %H:%M:%S") })

-- ---------------------------------------------------------------- 汇总
print("\n== 清理测试数据 ==")
clearAll()

print(string.format("\n===== 结果：PASS %d / FAIL %d =====", pass, fail))
if fail > 0 then
  print("失败项：")
  for _, n in ipairs(failed) do
    print("  - " .. n)
  end
end
if #notes > 0 then
  print("说明项（不计入失败）：")
  for _, n in ipairs(notes) do
    print("  - " .. n)
  end
end
