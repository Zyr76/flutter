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
local ObjectBox = luajava.bindClass("com.androlua.objectbox.ObjectBox")
local json = require "cjson"

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

M.put, M.get, M.remove, M.keys, M.count, M.clear =
  M.存, M.取, M.删, M.键, M.数量, M.清空

return M
