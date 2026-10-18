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
-- res 的字段：ok、code、body、headers(单值)、headersAll(多值，Set-Cookie 等)、canceled、error
--
-- 取消 / 下载 / 上传 / 调试：
--   local call = ok.get(url, cb)        -- 返回可取消的句柄
--   ok.cancel(call)                      -- 页面退出时中止在途请求（回调会带 canceled=true）
--   ok.download(url, "/sdcard/a.apk", cb)-- 流式下载，不整体入内存（res.path / res.size）
--   ok.upload(url, "file", "/sdcard/a.jpg", cb)  -- multipart 上传
--   ok.debug(true)                       -- 打印请求/响应日志；ok.clearCookies() 清内存 Cookie
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

  return OkHttp.request(req, cb)   -- 点号调用：不传 self；返回可取消的 Call
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
    return M.request(opts, cb)
  end
end

M.get = shortcut("GET")
M.post = shortcut("POST")
M.put = shortcut("PUT")
M.patch = shortcut("PATCH")
M.delete = shortcut("DELETE")
M.head = shortcut("HEAD")

--- 取消在途请求（传 request/get/post 的返回值）。
function M.cancel(call)
  if call ~= nil then
    call.cancel()          -- Java 方法，点号
  end
end

--- 流式下载到本地文件。回调结果：{ ok, path, size, error }
function M.download(url, path, cb)
  if type(cb) ~= "function" then
    error("okhttp.download: 需要回调函数", 2)
  end
  return OkHttp.download(url, path, cb)
end

--- multipart 上传单个文件。回调结果同 request。
function M.upload(url, field, filePath, cb)
  if type(cb) ~= "function" then
    error("okhttp.upload: 需要回调函数", 2)
  end
  return OkHttp.upload(url, field or "file", filePath, cb)
end

--- 打开/关闭请求日志（打到 Lua 控制台）。
function M.debug(on)
  OkHttp.setDebug(on and true or false)
end

--- 清空内存 Cookie。
function M.clearCookies()
  OkHttp.clearCookies()
end

--- 把结果体按 JSON 解析（失败返回 nil, err）。
function M.decode(res)
  if type(res) ~= "table" or not res.ok or not res.body then
    return nil, res and res.error or "无响应"
  end
  return json.decode(res.body)
end

return M
