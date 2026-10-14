-- ============================================================
-- 设置.lua —— 基于 mmkv 的配置读写封装（生产用法）
-- 放到 app 的 lua 目录下，其他脚本 require "设置" 即可。
--
-- 设计要点：
--   · 每个"命名空间"一个 MMKV 文件（互不干扰，登出时清一个空间就行）
--   · 所有原生调用都包 pcall：MMKV 出问题只打印告警，绝不带崩脚本
--   · 懒初始化 + 显式初始化两可
--   · 类型明确：取字符串/取整数/取数字/取布尔/取表，或按默认值自动推断
-- ============================================================
local mmkv = require "mmkv"

local 设置 = {}
local 已打开 = {}

local function 空间实例(空间)
  local kv = 已打开[空间]
  if kv then return kv end
  local ok, r = pcall(function() return mmkv.withID("app." .. tostring(空间)) end)
  if not ok or r == nil then
    print("[设置] 打开命名空间失败: " .. tostring(空间) .. " -> " .. tostring(r))
    return nil
  end
  已打开[空间] = r
  return r
end

-- 可选：在脚本开头调一次；不调则在首次读写时自动初始化
function 设置.初始化(rootDir)
  local ok, err = pcall(function()
    if rootDir then mmkv.init(rootDir) else mmkv.init() end
  end)
  if not ok then print("[设置] 初始化失败: " .. tostring(err)) end
  return ok and true or false
end

-- 取一个值：按「默认值」的类型自动决定读法（推荐）
function 设置.取(空间, 键, 默认)
  local kv = 空间实例(空间)
  if not kv then return 默认 end
  local t = type(默认)
  local ok, v = pcall(function()
    if t == "number" then
      if math.type(默认) == "integer" then return kv:getInt(键, 默认) end
      return kv:getNumber(键, 默认)
     elseif t == "boolean" then
      return kv:getBool(键, 默认)
     elseif t == "table" then
      return kv:getTable(键, 默认)
     else
      return kv:getString(键, 默认)
    end
  end)
  if not ok then
    print("[设置] 读 " .. 空间 .. "." .. tostring(键) .. " 失败: " .. tostring(v))
    return 默认
  end
  return v
end

-- 明确类型的读取（当"默认值不好推断"时用）
function 设置.取字符串(空间, 键, 默认) return 设置.取(空间, 键, 默认 or "") end
function 设置.取整数(空间, 键, 默认)   return 设置.取(空间, 键, 默认 or 0) end
function 设置.取数字(空间, 键, 默认)   return 设置.取(空间, 键, 默认 or 0.0) end
function 设置.取布尔(空间, 键, 默认)   return 设置.取(空间, 键, 默认 == true) end
function 设置.取表(空间, 键, 默认)     return 设置.取(空间, 键, 默认 or {}) end

-- 存一个值：nil 表示删除该键；写入即落盘
function 设置.存(空间, 键, 值)
  local kv = 空间实例(空间)
  if not kv then return false end
  local ok, err = pcall(function() kv:set(键, 值) end)
  if not ok then
    print("[设置] 写 " .. 空间 .. "." .. tostring(键) .. " 失败: " .. tostring(err))
    return false
  end
  return true
end

-- 批量存（一次循环写入后统一刷盘）
function 设置.批量存(空间, 表)
  local kv = 空间实例(空间)
  if not kv then return false end
  local ok, err = pcall(function()
    kv:apply(表)
    kv:sync()
  end)
  if not ok then print("[设置] 批量写失败: " .. tostring(err)) return false end
  return true
end

function 设置.有(空间, 键)
  local kv = 空间实例(空间)
  if not kv then return false end
  local ok, v = pcall(function() return kv:contains(键) end)
  if not ok then print("[设置] 判断 " .. 空间 .. "." .. tostring(键) .. " 是否存在失败: " .. tostring(v)) end
  return ok and (v and true or false) or false
end

function 设置.删(空间, 键)
  local kv = 空间实例(空间)
  if not kv then return false end
  local ok, err = pcall(function() kv:remove(键) end)
  if not ok then print("[设置] 删 " .. 空间 .. "." .. tostring(键) .. " 失败: " .. tostring(err)) end
  return ok and true or false
end

-- 列出某空间所有键（便于调试/导出）
function 设置.键列表(空间)
  local kv = 空间实例(空间)
  if not kv then return {} end
  local ok, ks = pcall(function() return kv:allKeys() end)
  if not ok then
    print("[设置] 列键失败: " .. tostring(ks))
    return {}
  end
  if ks == nil then return {} end
  table.sort(ks)
  return ks
end

-- 清空某空间（登出、重置设置时用；只清这一个空间的 MMKV 文件）
function 设置.清空(空间)
  local kv = 空间实例(空间)
  if not kv then return false end
  local ok, err = pcall(function() kv:clear(); kv:sync() end)
  if not ok then print("[设置] 清空 " .. 空间 .. " 失败: " .. tostring(err)) end
  return ok and true or false
end

-- 退出前强制刷盘（正常情况下 MMKV 写入即落盘，这步是保险）
function 设置.落盘(空间)
  local kv = 空间实例(空间)
  if kv then pcall(function() kv:sync() end) end
end

return 设置
