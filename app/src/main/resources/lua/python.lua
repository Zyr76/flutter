require "import"
import "com.androlua.PythonBridge"
local JString = luajava.bindClass("java.lang.String")

local function to_java_args(args)
    if args == nil then
        args = {}
    elseif type(args) ~= "table" then
        args = { args }
    end
    local jargs = luajava.newArray(JString, #args)
    for i = 1, #args do
        jargs[i - 1] = tostring(args[i])
    end
    return jargs
end

local function emit_output(text)
    if text == "" then
        return
    end
    if text:sub(-1) == "\n" then
        io.write(text)
    else
        print(text)
    end
end

local M = {}

function M.run_file(script_path, args)
    if not script_path then
        error("script_path is required", 2)
    end
    local ok, result = pcall(function()
        return PythonBridge.runFile(tostring(script_path), to_java_args(args))
    end)
    if not ok then
        error("Python run_file failed: " .. tostring(result), 2)
    end
    local text = tostring(result or "")
    emit_output(text)
    return text
end

function M.run_code(code, args)
    if code == nil then
        error("code is required", 2)
    end
    local ok, result = pcall(function()
        return PythonBridge.runCode(tostring(code), to_java_args(args))
    end)
    if not ok then
        error("Python run_code failed: " .. tostring(result), 2)
    end
    local text = tostring(result or "")
    emit_output(text)
    return text
end

function M.exec(code, args)
    return M.run_code(code, args)
end

setmetatable(M, {
    __call = function(_, code, args)
        return M.run_code(code, args)
    end
})

return M
