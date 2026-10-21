require "import"
import "com.androlua.LuaX"
import "java.util.zip.ZipOutputStream"
import "android.net.Uri"
import "java.io.File"
import "android.widget.Toast"
import "java.util.zip.CheckedInputStream"
import "java.io.FileInputStream"
import "android.content.Intent"
import "java.util.ArrayList"
import "java.io.FileOutputStream"
import "java.io.BufferedOutputStream"
import "java.util.zip.ZipInputStream"
import "java.io.BufferedInputStream"
import "java.util.zip.ZipEntry"
import "android.app.ProgressDialog"
import "java.util.zip.CheckedOutputStream"
import "java.util.zip.Adler32"

local bin_dlg, error_dlg
local function update(s)
    bin_dlg.setMessage(s)
end

local function callback(s)
    LuaUtil.rmDir(File(activity.getLuaExtDir("bin/.temp")))
    bin_dlg.hide()
    bin_dlg.Message = ""
    if s == nil then
        s = "打包失败：任务返回空结果，请检查日志。"
    else
        s = tostring(s)
        if s == "null" then
            s = "打包失败：任务返回空结果，请检查日志。"
        end
    end
    if not s:find("成功") then
        error_dlg.Message = s
        error_dlg.show()
    end
end

local function create_bin_dlg()
    if bin_dlg then
        return
    end
    bin_dlg = ProgressDialog(activity);
    bin_dlg.setTitle("正在打包");
    bin_dlg.setMax(100);
end

local function create_error_dlg2()
    if error_dlg then
        return
    end
    error_dlg = AlertDialogBuilder(activity)
    error_dlg.Title = "出错"
    error_dlg.setPositiveButton("确定", nil)
end

local function binapk(luapath, apkpath)
    require "import"
    import "console"
    
    
    pcall(compile, "mao")
    pcall(compile, "sign")
    
    import "java.util.zip.*"
    import "java.io.*"
    import "mao.res.*"
    import "apksigner.*"
    local b = byte[2 ^ 16]
    local function copy(input, output)
        LuaUtil.copyFile(input, output)
        input.close()
        --[[local l=input.read(b)
      while l>1 do
        output.write(b,0,l)
        l=input.read(b)
      end]]
    end

    local function copy2(input, output)
        LuaUtil.copyFile(input, output)
    end

    local function copy_compiled_lua(path, output)
        -- 打包时把脚本加密成 LUAX；含 @cpp 预处理块的文件由 LuaX 自动跳过（保持明文）
        LuaX.copyEncrypted(path, output)
    end

    local temp = File(apkpath).getParentFile();
    if (not temp.exists()) then

        if (not temp.mkdirs()) then

            error("create file " .. temp.getName() .. " fail");
        end
    end


    local tmp = luajava.luadir .. "/tmp.apk"
    local info = activity.getApplicationInfo()
    local ver = activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0).versionName
    local code = activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0).versionCode

    --local zip=ZipFile(info.publicSourceDir)
    local zipFile = File(info.publicSourceDir)
    local fis = FileInputStream(zipFile);
    --local checksum = CheckedInputStream(fis, Adler32());
    local zis = ZipInputStream(BufferedInputStream(fis));

    local fot = FileOutputStream(tmp)
    --local checksum2 = CheckedOutputStream(fot, Adler32());

    local out = ZipOutputStream(BufferedOutputStream(fot))
    local f = File(luapath)
    local errbuffer = {}
    local replace = {}
    local checked = {}
    local lualib = {}
    local md5s = {}
    local libs = File(activity.ApplicationInfo.nativeLibraryDir).list()
    libs = luajava.astable(libs)
    for k, v in ipairs(libs) do
        --libs[k]="lib/armeabi/"..libs[k]
        replace[v] = true
    end

    local mdp = activity.Application.MdDir
    local function getmodule(dir)
        local mds = File(activity.Application.MdDir .. dir).listFiles()
        mds = luajava.astable(mds)
        for k, v in ipairs(mds) do
            if mds[k].isDirectory() then
                getmodule(dir .. mds[k].Name .. "/")
            else
                mds[k] = "lua" .. dir .. mds[k].Name
                replace[mds[k]] = true
            end
        end
    end

    getmodule("/")

    local function checklib(path)
        if checked[path] then
            return
        end
        local cp, lp
        checked[path] = true
        local f = io.open(path)
        local s = f:read("*a")
        f:close()
        for m, n in s:gmatch("require *%(? *\"([%w_]+)%.?([%w_]*)") do
            cp = string.format("lib%s.so", m)
            if n ~= "" then
                lp = string.format("lua/%s/%s.lua", m, n)
                m = m .. '/' .. n
            else
                lp = string.format("lua/%s.lua", m)
            end
            if replace[cp] then
                replace[cp] = false
            end
            if replace[lp] then
                checklib(mdp .. "/" .. m .. ".lua")
                replace[lp] = false
                lualib[lp] = mdp .. "/" .. m .. ".lua"
            end
        end
        for m, n in s:gmatch("import *%(? *\"([%w_]+)%.?([%w_]*)") do
            cp = string.format("lib%s.so", m)
            if n ~= "" then
                lp = string.format("lua/%s/%s.lua", m, n)
                m = m .. '/' .. n
            else
                lp = string.format("lua/%s.lua", m)
            end
            if replace[cp] then
                replace[cp] = false
            end
            if replace[lp] then
                checklib(mdp .. "/" .. m .. ".lua")
                replace[lp] = false
                lualib[lp] = mdp .. "/" .. m .. ".lua"
            end
        end
    end

    replace["libluajava.so"] = false

    local function addDir(out, dir, f)
        local entry = ZipEntry("assets/" .. dir)
        out.putNextEntry(entry)
        local ls = f.listFiles()
        for n = 0, #ls - 1 do
            local name = ls[n].getName()
            if name==(".using") then
                checklib(luapath .. dir .. name)
            elseif name:find("%.apk$") or name:find("%.luac$") or name:find("^%.") then
            elseif name:find("%.lua$") then
                checklib(luapath .. dir .. name)
                local path, err = console.build(luapath .. dir .. name)
                if path then
                    if replace["assets/" .. dir .. name] then
                        table.insert(errbuffer, dir .. name .. "/.aly")
                    end
                    local entry = ZipEntry("assets/" .. dir .. name)
                    out.putNextEntry(entry)

                    replace["assets/" .. dir .. name] = true
                    copy_compiled_lua(path, out)
                    table.insert(md5s, LuaUtil.getFileMD5(path))
                    os.remove(path)
                else
                    table.insert(errbuffer, err)
                end
            elseif name:find("%.aly$") then
                local path, err = console.build_aly(luapath .. dir .. name)
                if path then
                    name = name:gsub("aly$", "lua")
                    if replace["assets/" .. dir .. name] then
                        table.insert(errbuffer, dir .. name .. "/.aly")
                    end
                    local entry = ZipEntry("assets/" .. dir .. name)
                    out.putNextEntry(entry)

                    replace["assets/" .. dir .. name] = true
                    copy_compiled_lua(path, out)
                    table.insert(md5s, LuaUtil.getFileMD5(path))
                    os.remove(path)
                else
                    table.insert(errbuffer, err)
                end
            elseif ls[n].isDirectory() then
                addDir(out, dir .. name .. "/", ls[n])
            else
                local entry = ZipEntry("assets/" .. dir .. name)
                out.putNextEntry(entry)
                replace["assets/" .. dir .. name] = true
                copy(FileInputStream(ls[n]), out)
                table.insert(md5s, LuaUtil.getFileMD5(ls[n]))
            end
        end
    end


    this.update("正在编译...");
    if f.isDirectory() then
        require "permission"
        dofile(luapath .. "init.lua")
        if user_permission then
            for k, v in ipairs(user_permission) do
                user_permission[v] = true
            end
        end


        local ss, ee = pcall(addDir, out, "", f)
        if not ss then
            table.insert(errbuffer, ee)
        end
        --print(ee,dump(errbuffer),dump(replace))


        local wel = File(luapath .. "icon.png")
        if wel.exists() then
            local entry = ZipEntry("res/drawable/icon.png")
            out.putNextEntry(entry)
            replace["res/drawable/icon.png"] = true
            copy(FileInputStream(wel), out)
        end
        local wel = File(luapath .. "welcome.png")
        if wel.exists() then
            local entry = ZipEntry("res/drawable/welcome.png")
            out.putNextEntry(entry)
            replace["res/drawable/welcome.png"] = true
            copy(FileInputStream(wel), out)
        end
    else
        return "error"
    end

    --print(dump(lualib))
    for name, v in pairs(lualib) do
        local path, err = console.build(v)
        if path then
            local entry = ZipEntry(name)
            out.putNextEntry(entry)
            copy_compiled_lua(path, out)
            table.insert(md5s, LuaUtil.getFileMD5(path))
            os.remove(path)
        else
            table.insert(errbuffer, err)
        end
    end

    function touint32(i)
        local code = string.format("%08x", i)
        local uint = {}
        for n in code:gmatch("..") do
            table.insert(uint, 1, string.char(tonumber(n, 16)))
        end
        return table.concat(uint)
    end

    this.update("正在打包...");
    local seen_entries = {}
    local max_dex = 0
    local entry = zis.getNextEntry();
    while entry do
        local name = entry.getName()
        if name:match("^classes%d*%.dex$") then
            local idx = tonumber(name:match("^classes(%d*)%.dex$"))
            if idx == nil then
                idx = 1          -- classes.dex
            end
            if idx > max_dex then
                max_dex = idx
            end
        end
        local lib = name:match("([^/]+%.so)$")
        if replace[name] then
        elseif lib and replace[lib] then
            -- 编辑器自带的 .so（luajava/flutter/cjson…）必须随包打进产物，
            -- 否则新包一启动就找不到 native 库直接闪退。
            -- replace 的键来自 nativeLibraryDir.list()，只有文件名没有路径，所以要单独判断再拷贝。
            local lib_entry = ZipEntry(name)
            local lib_ok = pcall(function()
                out.putNextEntry(lib_entry)
            end)
            if lib_ok then
                seen_entries[name] = true
                copy2(zis, out)
            end
        elseif name:find("^assets/") then
        elseif name:find("^lua/") then
        elseif name:find("META%-INF") then
        elseif seen_entries[name] then
        else
            local entry = ZipEntry(name)
            local put_ok = pcall(function()
                out.putNextEntry(entry)
            end)
            if put_ok then
                seen_entries[name] = true
                if entry.getName() == "AndroidManifest.xml" then
                    local decoder_available = false
                    if AXmlDecoder ~= nil then
                        local decoder_name = tostring(AXmlDecoder)
                        if decoder_name ~= "null" then
                            decoder_available = true
                        end
                    end
                    if not decoder_available then
                        copy2(zis, out)
                    else
                        local normalized_path_pattern = ""
                        if path_pattern ~= nil then
                            local raw_pattern = tostring(path_pattern)
                            if raw_pattern ~= "" and raw_pattern ~= "null" then
                                local ext = raw_pattern:match("%w+$")
                                if ext then
                                    normalized_path_pattern = ".*\\\\." .. ext
                                end
                            end
                        end
                        local list = ArrayList()
                        local xml = AXmlDecoder.read(list, zis)
                        local req = {
                            [tostring(activity.getPackageName())] = packagename,
                            [tostring(info.nonLocalizedLabel)] = appname,
                            [tostring(ver)] = appver,
                            [".*\\\\.alp"] = normalized_path_pattern,
                            [".*\\\\.lua"] = "",
                            [".*\\\\.luac"] = "",
                        }
                        for n = 0, list.size() - 1 do
                            local v = list.get(n)
                            if v ~= nil then
                                local value = tostring(v)
                                if value ~= "null" then
                                    if req[value] ~= nil then
                                        list.set(n, req[value])
                                    elseif user_permission then
                                        local p = value:match("%.permission%.([%w_]+)$")
                                        if p and (not user_permission[p]) then
                                            list.set(n, "")
                                        end
                                    end
                                end
                            end
                        end
                        local pt = activity.getLuaPath(".tmp")
                        local fo = FileOutputStream(pt)
                        xml.write(list, fo)
                        local code = activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0).versionCode
                        fo.close()
                        local f = io.open(pt)
                        local s = f:read("a")
                        f:close()
                        s = string.gsub(s, touint32(code), touint32(tointeger(appcode) or 1),1)
                        s = string.gsub(s, touint32(18), touint32(tointeger(appsdk) or 18),1)

                        local f = io.open(pt, "w")
                        f:write(s)
                        f:close()
                        local fi = FileInputStream(pt)
                        copy(fi, out)
                        os.remove(pt)
                    end
                elseif not entry.isDirectory() then
                    copy2(zis, out)
                end
            end
        end
        entry = zis.getNextEntry()
    end
    -- ===== 合并 .fxp 扩展包 =====
    -- 约定：*.fxp 放在 <脚本目录>/libs/flutter/ 下。
    -- 必须是子目录：LuaDexLoader.loadLibs 会把 libs/ 下所有非 .so 文件当 dex 加载，
    -- 放根目录会导致加载失败并让脚本起不来。
    local function merge_fxp(dirpath)
        local d = File(dirpath)
        if not d.exists() or not d.isDirectory() then
            return
        end
        local fs = luajava.astable(d.listFiles())
        for k = 1, #fs do
            local p = fs[k]
            if p.isFile() and p.getName():lower():match("%.fxp$") then
                local ok, err = pcall(function()
                    local zf = ZipFile(p)
                    -- dex：依次改成下一个可用编号，ART 会按 classes.dex、classes2.dex… 顺序加载
                    local dex_names = {}
                    local es = zf.entries()
                    while es.hasMoreElements() do
                        local e = es.nextElement()
                        local n = e.getName()
                        if n:match("^classes%d*%.dex$") then
                            table.insert(dex_names, n)
                        end
                    end
                    table.sort(dex_names)
                    for _, n in ipairs(dex_names) do
                        max_dex = max_dex + 1
                        local target
                        if max_dex == 1 then
                            target = "classes.dex"
                        else
                            target = string.format("classes%d.dex", max_dex)
                        end
                        if not seen_entries[target] then
                            out.putNextEntry(ZipEntry(target))
                            seen_entries[target] = true
                            copy2(zf.getInputStream(zf.getEntry(n)), out)
                        end
                    end
                    -- lib/ 与 assets/ 原样并入
                    local es2 = zf.entries()
                    while es2.hasMoreElements() do
                        local e = es2.nextElement()
                        local n = e.getName()
                        if (not e.isDirectory()) and not seen_entries[n]
                                and (n:find("^lib/") or n:find("^assets/")) then
                            out.putNextEntry(ZipEntry(n))
                            seen_entries[n] = true
                            copy2(zf.getInputStream(e), out)
                        end
                    end
                    zf.close()
                end)
                if not ok then
                    table.insert(errbuffer, "fxp 合并失败 " .. p.getName() .. "：" .. tostring(err))
                end
            end
        end
    end
    merge_fxp(luapath .. "libs/flutter")

    out.setComment(table.concat(md5s))
    --print(table.concat(md5s,"/n"))
    zis.close();
    out.closeEntry()
    out.close()

    if #errbuffer == 0 then
        this.update("正在签名...");
        os.remove(apkpath)
        local signer_impl = Signer
        local signer_lookup_err = nil
        if signer_impl == nil or tostring(signer_impl) == "null" then
            local ok, cls = pcall(luajava.bindClass, "com.androlua.ApkSigner")
            if ok and cls ~= nil and tostring(cls) ~= "null" then
                signer_impl = cls
            else
                signer_lookup_err = tostring(cls)
            end
        end
        if signer_impl == nil or tostring(signer_impl) == "null" then
            local ok, cls = pcall(luajava.bindClass, "apksigner.Signer")
            if ok and cls ~= nil and tostring(cls) ~= "null" then
                signer_impl = cls
            else
                signer_lookup_err = tostring(cls)
            end
        end
        if signer_impl == nil or tostring(signer_impl) == "null" then
            os.remove(tmp)
            return "打包出错:\n 签名器不可用: " .. tostring(signer_lookup_err)
        end
        local sign_ok, sign_err = pcall(function()
            signer_impl.sign(tmp, apkpath)
        end)
        if not sign_ok then
            os.remove(tmp)
            return "打包出错:\n 签名失败: " .. tostring(sign_err)
        end
        os.remove(tmp)
        activity.installApk(apkpath)
        --[[import "android.net.*"
        import "android.content.*"
        i = Intent(Intent.ACTION_VIEW);
        i.setDataAndType(activity.getUriForFile(File(apkpath)), "application/vnd.android.package-archive");
        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        this.update("正在打开...");
        activity.startActivityForResult(i, 0);]]
        return "打包成功:" .. apkpath
    else
        os.remove(tmp)
        this.update("打包出错:\n " .. table.concat(errbuffer, "\n"));
        return "打包出错:\n " .. table.concat(errbuffer, "\n")
    end
end

--luabindir=activity.getLuaExtDir("bin")
--print(activity.getLuaExtPath("bin","a"))
local function bin(path)
    local p = {}
    local e, s = pcall(loadfile(path .. "init.lua", "bt", p))
    if e then
        create_error_dlg2()
        create_bin_dlg()
        bin_dlg.show()
        activity.newTask(binapk, update, callback).execute { path, activity.getLuaExtPath("bin", p.appname .. "_" .. p.appver .. ".apk") }
    else
        Toast.makeText(activity, "工程配置文件错误." .. s, Toast.LENGTH_SHORT).show()
    end
end

--bin(activity.getLuaExtDir("project/demo").."/")
return bin
