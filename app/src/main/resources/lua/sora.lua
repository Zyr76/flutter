-- sora.lua —— 创建带 Lua(TextMate) 语法高亮的 SoraEditor
--
-- 用法：
--   local ed = require "sora"("要显示的 Lua 代码")   -- 返回 CodeEditor（高亮已生效）
--   或 require "sora" 后直接用全局 SoraLuaEditor / Sora编辑器
--
-- 依赖 assets：textmate/languages.json、textmate/lua/...、textmate/quietlight.json
require "import"
import "io.github.rosemoe.sora.widget.*"
import "io.github.rosemoe.sora.langs.textmate.*"
import "io.github.rosemoe.sora.langs.textmate.registry.*"
import "io.github.rosemoe.sora.langs.textmate.registry.model.*"
import "io.github.rosemoe.sora.langs.textmate.registry.provider.*"
import "org.eclipse.tm4e.core.registry.*"

local inited = false

local function ensureInit()
  if inited then return true end
  local ok, err = pcall(function()
    -- 1) 让 TextMate 能从 assets 读取语法/主题文件
    FileProviderRegistry.getInstance().addFileProvider(AssetsFileResolver(activity.getAssets()))
    -- 2) 加载并应用主题
    local p = "textmate/quietlight.json"
    local src = IThemeSource.fromInputStream(
        FileProviderRegistry.getInstance().tryGetInputStream(p), p, nil)
    ThemeRegistry.getInstance().loadTheme(ThemeModel(src, "quietlight"))
    ThemeRegistry.getInstance().setTheme("quietlight")
    -- 3) 加载语言定义（lua -> source.lua）
    GrammarRegistry.getInstance().loadGrammars("textmate/languages.json")
  end)
  if ok then
    inited = true
  else
    print("[sora] 初始化失败: " .. tostring(err))
  end
  return ok
end

local function SoraLuaEditor(code)
  local ed = CodeEditor(activity)
  if ensureInit() then
    local ok, err = pcall(function()
      ed.setEditorLanguage(TextMateLanguage.create("source.lua", true))
      ed.setColorScheme(TextMateColorScheme.create(ThemeRegistry.getInstance()))
    end)
    if not ok then print("[sora] 设置语言失败: " .. tostring(err)) end
  end
  if code then ed.setText(code) end
  return ed
end

_G.SoraLuaEditor = SoraLuaEditor
_G["Sora编辑器"] = SoraLuaEditor
return SoraLuaEditor
