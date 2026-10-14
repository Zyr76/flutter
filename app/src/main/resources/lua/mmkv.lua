-- mmkv.lua —— 腾讯 MMKV 的 Lua 封装（基于官方 com.tencent:mmkv:2.4.2）
--
-- 用法：
--   local mmkv = require "mmkv"
--   local kv = mmkv.defaultMMKV()          -- 或 mmkv.withID("user")
--   kv:set("name", "张三")
--   kv:set("age", 30)
--   kv:set("cfg", { a = 1, b = "x" })      -- 表自动 JSON 序列化（优先 yyjson，退回 cjson）
--   print(kv:getString("name"), kv:getInt("age"), kv:getTable("cfg").a)
--   kv:contains("name"); kv:remove("name"); kv:allKeys(); kv:clear(); kv:sync()
--
-- 也可以直接调 MMKV 原生方法（同一个对象，Lua 友好层只是多包了一层）：
--   kv:encode("k", 1); kv:decodeInt("k"); kv:mmapID()
--
-- 数字约定：Lua 友好层的 set() 把数字统一按 double 存（避免 LuaJava 在
-- int/long/float/double 重载间挑错），getInt/getLong/getFloat 都从 double 读回；
-- 需要精确控制类型（int/long/byte[]/StringSet/Parcelable）时用原生 encode/decodeX。

local mmkv = {}

local activity = activity
local MMKV = luajava.bindClass("com.tencent.mmkv.MMKV")

local json
do
  local ok, m = pcall(require, "yyjson")
  if ok then
    json = { encode = m.encode, decode = m.decode }
  else
    local ok2, c = pcall(require, "cjson")
    if ok2 then json = { encode = c.encode, decode = c.decode } end
  end
end

local 已初始化 = false
local function 确保初始化(rootDir)
  if 已初始化 then return end
  if rootDir ~= nil then
    MMKV.initialize(activity, tostring(rootDir))
  else
    MMKV.initialize(activity)
  end
  已初始化 = true
end

--[[ 模块级：与 ULTRIUMA 那份 LuaMMKV 的接口保持一致 ]]
function mmkv.init(rootDir)
  已初始化 = false
  确保初始化(rootDir)
  return true
end

function mmkv.version()
  确保初始化()
  return MMKV.version()
end

function mmkv.rootDir()
  确保初始化()
  return MMKV.getRootDir()
end

function mmkv.defaultMMKV(mode)
  确保初始化()
  if mode ~= nil then return 包装(MMKV.defaultMMKV(mode, MMKV.getRootDir())) end
  return 包装(MMKV.defaultMMKV())
end
mmkv.default = mmkv.defaultMMKV          -- default 是 AndroLua 编辑器关键字高亮，别名同名

function mmkv.withID(id, mode)
  确保初始化()
  if mode ~= nil then
    return 包装(MMKV.mmkvWithID(tostring(id), mode))
  end
  return 包装(MMKV.mmkvWithID(tostring(id)))
end
mmkv.open = mmkv.withID                  -- 兼容别名

local function 转Lua数组(javaArr)
  local t = {}
  if javaArr == nil then return t end
  local n = #javaArr
  for i = 0, n - 1 do t[i + 1] = javaArr[i] end
  return t
end

--[[ 实例：Lua 友好方法 + 原生方法回落 ]]
local KV = {}
KV.__index = function(self, k)
  local f = KV[k]
  if f ~= nil then return f end
  local j = rawget(self, "java")
  if j ~= nil then return j[k] end
  return nil
end

function KV:set(k, v)
  local j = self.java
  local t = type(v)
  if v == nil then
    j:removeValueForKey(tostring(k))
   elseif t == "boolean" then
    j:encode(tostring(k), v)
   elseif t == "number" then
    j:encode(tostring(k), v + 0.0)         -- 强制走 double 重载，避免重载歧义
   elseif t == "string" then
    j:encode(tostring(k), v)
   elseif t == "table" then
    if not json then error("mmkv: 存表需要 yyjson 或 cjson（两者都没有）") end
    j:encode(tostring(k), json.encode(v))
   else
    error("mmkv: 不支持的类型 " .. t)
  end
  return v
end

function KV:getString(k, def)
  return self.java:decodeString(tostring(k), def)
end

function KV:getInt(k, def)
  return math.tointeger(self.java:decodeDouble(tostring(k), def or 0)) or (def or 0)
end

function KV:getLong(k, def)
  return math.tointeger(self.java:decodeDouble(tostring(k), def or 0)) or (def or 0)
end

function KV:getFloat(k, def)
  return self.java:decodeDouble(tostring(k), def or 0)
end

function KV:getDouble(k, def)
  return self.java:decodeDouble(tostring(k), def or 0)
end

function KV:getBool(k, def)
  return self.java:decodeBool(tostring(k), def or false)
end

function KV:getNumber(k, def)
  return self.java:decodeDouble(tostring(k), def or 0)
end

function KV:getTable(k, def)
  local s = self.java:decodeString(tostring(k))
  if s == nil then return def end
  if not json then error("mmkv: 读表需要 yyjson 或 cjson（两者都没有）") end
  local ok, v = pcall(json.decode, s)
  if ok and type(v) == "table" then return v end
  return def
end

function KV:setTable(k, t)
  if not json then error("mmkv: 存表需要 yyjson 或 cjson（两者都没有）") end
  self.java:encode(tostring(k), json.encode(t))
  return t
end

function KV:apply(data)
  for k, v in pairs(data) do self:set(k, v) end
  return data
end

function KV:contains(k)
  return self.java:containsKey(tostring(k))
end

function KV:remove(k)
  self.java:removeValueForKey(tostring(k))
end

function KV:count()
  return self.java:count()
end

function KV:allKeys()
  return 转Lua数组(self.java:allKeys())
end

function KV:clear()
  self.java:clearAll()
end

function KV:sync()
  self.java:sync()
end

function KV:totalSize()
  return self.java:totalSize()
end

function KV:close()
  self.java:close()
end

function 包装(raw)
  if raw == nil then return nil end
  return setmetatable({ java = raw }, KV)
end

mmkv.包装 = 包装

return mmkv
