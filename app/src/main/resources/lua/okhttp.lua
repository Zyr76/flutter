-- okhttp.lua —— OkHttp 的 Lua 封装
--
-- 特点：异步（不阻塞 UI 线程）、支持 HTTPS、每请求超时可配、自带连接池。
-- 请求在 OkHttp 线程池执行，回调统一回到主线程再调 Lua，所以回调里可以安全操作控件。
--
--   local ok = require "okhttp"
--
--   -- 最简
--   ok.get("https://api.example.com/ping", nil, function(res)
--     if res.ok then print(res.code, res.body) else print("失败：" .. tostring(res.error)) end
--   end)
--
--   -- 带请求头 / POST JSON / 超时
--   ok.post("https://api.example.com/login", {
--     headers = { ["Content-Type"] = "application/json", Authorization = "Bearer xxx" },
--     json    = { user = "a", pass = "b" },      -- 自动 encode
--     timeout = 8000,                            -- 毫秒
--   }, function(res)
--     if res.ok and res.code == 200 then
--       print(res.body)
--     end
--   end)
--
-- res 的字段：ok(true/false)、code(HTTP 状态码)、body(响应文本)、headers(表)、error(失败原因)
local OkHttp = luajava.bindClass("com.androlua.net.LuaOkHttp")
local json = require "yyjson"

local M = {}

--- 发起请求（所有方法的通用入口）。
--- @param opts table { url, method?, headers?, body?, json?, contentType?, timeout? }
--- @param cb function 回调，参数是结果表（在主线程执行）
function M.request(opts, cb)
  if type(opts) ~= "table" then
    error("okhttp.request: 第一个参数必须是表", 2)
  end
  if type(cb) ~= "function" then
    error("okhttp.request: 需要回调函数", 2)
  end

  local req = {
    method = string.upper(opts.method or "GET"),
    url = opts.url,
    headers = opts.headers,
    timeout = opts.timeout,
  }
  if opts.json ~= nil then
    req.body = json.encode(opts.json)
    req.contentType = "application/json; charset=utf-8"
  elseif opts.body ~= nil then
    req.body = tostring(opts.body)
    req.contentType = opts.contentType or "text/plain; charset=utf-8"
  end

  OkHttp.request(req, cb)      -- 点号调用：不传 self
end

local function shortcut(method)
  return function(url, opts, cb)
    -- 允许省略 opts：ok.get(url, cb)
    if type(opts) == "function" then
      cb, opts = opts, nil
    end
    opts = opts or {}
    opts.url = url
    opts.method = method
    M.request(opts, cb)
  end
end

M.get = shortcut("GET")
M.post = shortcut("POST")
M.put = shortcut("PUT")
M.patch = shortcut("PATCH")
M.delete = shortcut("DELETE")
M.head = shortcut("HEAD")

--- 把结果体按 JSON 解析（失败返回 nil, err）。
function M.decode(res)
  if type(res) ~= "table" or not res.ok or not res.body then
    return nil, res and res.error or "无响应"
  end
  return json.decode(res.body)
end

return M
