-- ObjectBox（嵌入式对象数据库）的 Lua 封装。
--
-- 数据按「空间(space) + 键(key)」组织，值统一编码成 JSON 存进库，
-- 所以字符串/数字/布尔/表都能直接存，读出来还是原来的类型。
--
--   local ob = require "objectbox"
--   ob.存("配置", "主题", { 夜间 = true, 颜色 = "#333" })
--   print(ob.取("配置", "主题").夜间)      --> true
--   print(ob.数量("配置"))                 --> 1
--   print(table.concat(ob.键("配置"), ",")) --> 主题
--   ob.删("配置", "主题")
--   ob.清空("配置")
--   -- 批量（整批只提交一个事务，比逐条快一到两个数量级）
--   ob.存多("缓存", { a = 1, b = 2 })
--   local vals = ob.取多("缓存", { "a", "b" })
--   ob.删多("缓存", { "a", "b" })
local ObjectBox = luajava.bindClass("com.androlua.objectbox.ObjectBox")

-- 用 yyjson 而不是 cjson：自带 cjson 把数字精度硬限制在 1~14 位（DEFAULT_ENCODE_NUMBER_PRECISION=14，
-- 改不了），浮点和大整数往返会丢值；yyjson 输出最短可往返表示，2^53+1 也能原样回来。
local json = require "yyjson"

local M = {}

local function encode(v)
  local ok, s = pcall(json.encode, v)
  if ok then
    return s
  end
  return json.encode(tostring(v))
end

local function decode(s)
  if s == nil then
    return nil
  end
  local ok, v = pcall(json.decode, s)
  if not ok then
    return s
  end
  if v == json.null then
    return nil
  end
  return v
end

-- Java List → Lua 数组：LuaJava 下 Java 数组的 # 恒为 0、越界索引还会抛错，只能逐个 get
local function toLuaArray(list)
  local out = {}
  if list == nil then
    return out
  end
  for i = 0, list.size() - 1 do
    out[#out + 1] = list.get(i)
  end
  return out
end

--- 写入/更新一个值；value 传 nil 等于删除。返回记录 id（删除时返回是否删掉了）。
function M.存(space, key, value)
  if value == nil then
    return ObjectBox.remove(tostring(space), tostring(key))
  end
  return ObjectBox.put(tostring(space), tostring(key), encode(value))
end

--- 读一个值；不存在返回 nil。
function M.取(space, key)
  return decode(ObjectBox.get(tostring(space), tostring(key)))
end

--- 删除一个键，返回是否删掉了。
function M.删(space, key)
  return ObjectBox.remove(tostring(space), tostring(key))
end

--- 某个空间下的所有键（Lua 数组）。
function M.键(space)
  return toLuaArray(ObjectBox.keys(tostring(space)))
end

--- 某个空间下的记录数。
function M.数量(space)
  return tonumber(ObjectBox.count(tostring(space)))
end

--- 清空某个空间，返回删除的条数。
function M.清空(space)
  return tonumber(ObjectBox.clear(tostring(space)))
end

--- 批量写入：tbl 是 { 键 = 值 } 的表，整批一个事务。返回写入条数。
function M.存多(space, tbl)
  local ks, vs = {}, {}
  for k, v in pairs(tbl) do
    ks[#ks + 1] = tostring(k)
    vs[#vs + 1] = encode(v)
  end
  if #ks == 0 then
    return 0
  end
  return ObjectBox.putMany(tostring(space),
    luajava.createArray("java.lang.String", ks),
    luajava.createArray("java.lang.String", vs))
end

--- 批量读取：keys 为数组，返回同序结果（缺失位置为 nil）。
function M.取多(space, keys)
  if #keys == 0 then
    return {}
  end
  local res = ObjectBox.getMany(tostring(space), luajava.createArray("java.lang.String", keys))
  local out = {}
  for i = 1, #keys do
    -- LuaJava 下 Java 数组越界会抛错，而不是返回 nil
    local okk, raw = pcall(function() return res[i - 1] end)
    out[i] = okk and decode(raw) or nil
  end
  return out
end

--- 批量删除，整批一个事务。返回处理的键数。
function M.删多(space, keys)
  if #keys == 0 then
    return 0
  end
  return ObjectBox.removeMany(tostring(space), luajava.createArray("java.lang.String", keys))
end

M.put, M.get, M.remove, M.keys, M.count, M.clear =
  M.存, M.取, M.删, M.键, M.数量, M.清空
M.putMany, M.getMany, M.removeMany = M.存多, M.取多, M.删多

return M
