-- mmkv.lua —— 腾讯 MMKV 的 Lua 封装（基于官方 com.tencent:mmkv:2.4.2）
--
-- 用法：
--   local mmkv = require "mmkv"
--   local kv = mmkv.defaultMMKV()          -- 或 mmkv.withID("user")
--   kv:set("name", "张三")
--   kv:set("age", 30)
--   kv:set("pi", 3.141592653589793)
--   kv:set("cfg", { a = 1, b = "x" })      -- 表自动 JSON 序列化（优先 yyjson，退回 cjson）
--   print(kv:getString("name"), kv:getInt("age"), kv:getNumber("pi"), kv:getTable("cfg").a)
--   kv:contains("name"); kv:remove("name"); kv:allKeys(); kv:clear(); kv:sync()
--
-- 【为什么不用 MMKV 的 encode/decodeX】
-- MMKV 的 encode 有 int/long/float/double/String/byte[]/Set/Parcelable 等十几个重载，
-- LuaJava 的重载匹配（getMethod + compareTypes）在这种规模下会报
-- "Invalid method call. Invalid Parameters."（实测连 encode(String, String) 都匹配不上）。
-- 所以这里改走 MMKV 实现的 SharedPreferences 接口：putString/putLong/putFloat/putBoolean
-- 每个只有一个签名，不存在重载歧义。原生方法仍可直接调（kv:encode(...)、kv:mmapID()）。
--
-- 类型约定：
--   nil      → 删除该键
--   boolean  → putBoolean
--   整数     → putLong（读回 getInt/getLong）
--   非整数   → putString，用 %.17g 格式化（保住 double 全部有效位；读回 getNumber/getDouble）
--   string   → putString
--   table    → JSON 字符串（getTable 解回来）
--
-- 加密：mmkv.withID("私密", nil, "密钥")  或  mmkv.defaultMMKV(nil, "密钥")
--   · 建实例时就带密钥 → 该 id 的 mmkv 文件整体是密文（默认 AES-128）
--   · kv:reKey("新密钥") 换密钥；kv:去加密() 去掉加密；kv:cryptKey() 看当前密钥
--   · 明文已有数据要转密文，用 kv:reKey("密钥")（会把现有数据转过去）
--   · 注意：只有走封装（withID/defaultMMKV/init）才会自动 MMKV.initialize()；
--     直接调 MMKV.mmkvWithID(...) 前必须先 mmkv.init()，否则会报
--     "You should Call MMKV.initialize() first." 

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

-- mmkv.defaultMMKV([mode [, cryptKey]])
function mmkv.defaultMMKV(mode, cryptKey)
  确保初始化()
  if cryptKey ~= nil then
    return 包装(MMKV.defaultMMKV(mode or 单进程模式, tostring(cryptKey)))
  end
  if mode ~= nil then return 包装(MMKV.defaultMMKV(mode, MMKV.getRootDir())) end
  return 包装(MMKV.defaultMMKV())
end
mmkv.default = mmkv.defaultMMKV          -- default 会被 AndroLua 编辑器当关键字上色，故留同名别名

-- mmkv.withID(id [, mode [, cryptKey]])
--   给了 cryptKey 就是加密实例（该 id 的 mmkv 文件整体是密文）
function mmkv.withID(id, mode, cryptKey)
  确保初始化()
  id = tostring(id)
  if cryptKey ~= nil then
    return 包装(MMKV.mmkvWithID(id, mode or 单进程模式, tostring(cryptKey)))
  end
  if mode ~= nil then
    return 包装(MMKV.mmkvWithID(id, mode))
  end
  return 包装(MMKV.mmkvWithID(id))
end
mmkv.open = mmkv.withID                  -- 兼容别名

local 单进程模式 = 1            -- MMKV.SINGLE_PROCESS_MODE

local 缺失串 = "\1__mmkv_missing__\1"
local 缺失整数 = -9223372036854775808

local function 转Lua数组(javaArr)
  -- LuaJava 的 Java 数组：# 会返回 0（不可用），并且越界索引是【抛错】而不是返回 nil。
  -- 所以既不能用 #，也不能"取到 nil 为止"，只能逐个用 pcall 探测：
  -- 抛错或取到 nil 就停止。两种语义（抛错 / 返回 nil）都能安全收尾。
  local t = {}
  if javaArr == nil then return t end
  local i = 0
  while true do
    local ok, v = pcall(function() return javaArr[i] end)
    if not ok or v == nil then break end
    t[i + 1] = v
    i = i + 1
  end
  return t
end


-- 读一个键：不预设类型，按 string → long → bool 逐个试（用哨兵值判断"没这个类型"）
local function 取值(j, k)
  local raw = j.getString(k, 缺失串)
  if raw == nil then return nil, nil end
  local s = tostring(raw)                 -- 兼容 LuaJava 返回 Java String 对象的情况
  if s ~= 缺失串 then return s, "string" end
  local n = j.getLong(k, 缺失整数)
  if n ~= 缺失整数 then return n, "number" end
  if j.containsKey(k) then return j.getBoolean(k, false), "boolean" end
  return nil, nil
end

local KV = {}
KV.__index = function(self, k)
  local f = KV[k]
  if f ~= nil then return f end
  local j = rawget(self, "java")
  if j == nil then return nil end
  local raw = j[k]
  -- LuaJava 调 Java 方法用点号、参数里不含 self；这里把冒号调用 kv:原生方法(...) 的 self 丢掉
  if type(raw) == "function" then
    return function(_, ...) return raw(...) end
  end
  return raw
end

function KV:set(k, v)
  local j = self.java
  local key = tostring(k)
  local t = type(v)
  if v == nil then
    j.removeValueForKey(key)
   elseif t == "boolean" then
    j.putBoolean(key, v)
   elseif t == "number" then
    if math.type(v) == "integer" then
      j.putLong(key, v)
     else
      j.putString(key, string.format("%.17g", v))
    end
   elseif t == "string" then
    j.putString(key, v)
   elseif t == "table" then
    if not json then error("mmkv: 存表需要 yyjson 或 cjson（两者都没有）") end
    j.putString(key, json.encode(v))
   else
    error("mmkv: 不支持的类型 " .. t)
  end
  return v
end

function KV:getString(k, def)
  local v = 取值(self.java, tostring(k))
  if v == nil then return def end
  return tostring(v)
end

function KV:getNumber(k, def)
  local v = 取值(self.java, tostring(k))
  if type(v) == "number" then return v end
  if type(v) == "string" then return tonumber(v) or def end
  return def
end

function KV:getDouble(k, def)
  return self:getNumber(k, def)
end

function KV:getFloat(k, def)
  return self:getNumber(k, def)
end

function KV:getInt(k, def)
  local n = self:getNumber(k, nil)
  if n == nil then return def end
  return math.tointeger(n) or math.floor(n)
end

function KV:getLong(k, def)
  return self:getInt(k, def)
end

function KV:getBool(k, def)
  local v = 取值(self.java, tostring(k))
  if type(v) == "boolean" then return v end
  if v == nil then return def end
  return v == "true" and true or false
end

function KV:getTable(k, def)
  local raw = self.java.getString(tostring(k), 缺失串)
  if raw == nil then return def end
  local s = tostring(raw)
  if s == 缺失串 or s == "" then return def end
  if not json then error("mmkv: 读表需要 yyjson 或 cjson（两者都没有）") end
  local ok, v = pcall(json.decode, s)
  if ok and type(v) == "table" then return v end
  -- 读到了内容但不是表：直接把内容报出来（区分"没写到"和"解不出来"）
  error(string.format("mmkv: 键 %s 的内容不是表（长度 %d，前 80 字符：%s）",
    tostring(k), #s, s:sub(1, 80)))
end

function KV:setTable(k, t)
  if not json then error("mmkv: 存表需要 yyjson 或 cjson（两者都没有）") end
  self.java.putString(tostring(k), json.encode(t))
  return t
end

function KV:apply(data)
  for k, v in pairs(data) do self:set(k, v) end
  return data
end

function KV:contains(k)
  return self.java.containsKey(tostring(k))
end

function KV:remove(k)
  self.java.removeValueForKey(tostring(k))
end

function KV:count()
  return self.java.count()
end

function KV:allKeys()
  return 转Lua数组(self.java.allKeys())
end

function KV:clear()
  self.java.clearAll()
end

function KV:sync()
  self.java.sync()
end

function KV:totalSize()
  return self.java.totalSize()
end

function KV:close()
  self.java.close()
end

-- 换密钥（会把现有数据重新加密）
function KV:reKey(新密钥)
  local ok, r = pcall(function() return self.java.reKey(新密钥) end)
  if not ok then print("[mmkv] reKey 失败: " .. tostring(r)) return false end
  return r
end

-- 去掉加密（reKey(null)：LuaJava 会把显式 nil 传成 Java null）
function KV:去加密()
  local ok, r = pcall(function() return self.java.reKey(nil) end)
  if not ok then print("[mmkv] 去加密失败: " .. tostring(r)) return false end
  return r
end

-- 当前密钥（未加密返回 nil）
function KV:cryptKey()
  return self.java.cryptKey()
end

function 包装(raw)
  if raw == nil then return nil end
  return setmetatable({ java = raw }, KV)
end

mmkv.包装 = 包装

-- ============================================================
-- mmkv.自检()：逐步打印，用于排查"写了读不到"这类问题
--   用法：require("mmkv").自检()
-- ============================================================
function mmkv.自检(空间)
  空间 = 空间 or "selftest"
  local function 试(说明, fn)
    local ok, v = pcall(fn)
    print("[mmkv.自检] " .. 说明 .. " -> " .. (ok and tostring(v) or ("失败: " .. tostring(v))))
    return ok, v
  end
  试("版本", function() return MMKV.version() end)
  试("根目录", function() return MMKV.getRootDir() end)
  local okkv, kv = 试("取实例 " .. 空间, function() return mmkv.withID(空间) end)
  if not okkv or type(kv) ~= "table" then return end
  试("实例 mmapID", function() return kv:mmapID() end)
  试("封装写 封装键=123", function() return kv:set("封装键", 123) end)
  试("封装回读 contains", function() return kv:contains("封装键") end)
  试("封装回读 getInt", function() return kv:getInt("封装键", -1) end)
  local raw = rawget(kv, "java")
  试("原生 encode 原生键=原生值", function() return raw.encode("原生键", "原生值") end)
  试("原生 containsKey", function() return raw.containsKey("原生键") end)
  试("原生 decodeString", function() return raw.decodeString("原生键") end)
  试("封装 allKeys", function()
    local ks = kv:allKeys()
    return #ks .. " 个: " .. table.concat(ks, ", ")
  end)
  试("sync", function() return kv:sync() end)
end

return mmkv
