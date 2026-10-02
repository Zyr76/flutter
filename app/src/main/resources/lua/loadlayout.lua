-- 布局加载模块
-- 效率是老 loadlayout 的大概 2 倍多
-- version 1.0.3 (20250905)

local require = require
local luajava = luajava
local table = require "table"
local string = require "string"
luajava.ids = luajava.ids or { id = 0x7f000000 }
local ids = luajava.ids
local _G = _G
local insert = table.insert
local bindClass = luajava.bindClass
local instanceof = luajava.instanceof
local newInstance = luajava.newInstance
local ltrs = {}
local type = type
local pcall = pcall
local tonumber = tonumber
local context = activity or service
local luadir = context.getLuaDir()

-- 局部化常用函数以提高性能
local string_match = string.match
local string_gmatch = string.gmatch
local string_gsub = string.gsub
local string_find = string.find
local string_sub = string.sub
local string_upper = string.upper
local table_unpack = table.unpack
local rawset = rawset
local rawget = rawget
local dump = dump or function(t)
  local s = {}
  for k, v in pairs(t) do s[#s + 1] = tostring(k) .. "=" .. tostring(v) end
  return "{" .. table.concat(s, ",") .. "}"
end

-- 预缓存常用类和方法
local ViewGroup = bindClass("android.view.ViewGroup")
local View = bindClass("android.view.View")
local String = bindClass("java.lang.String")
local OnClickListener = bindClass("android.view.View$OnClickListener")
local OnLongClickListener = bindClass("android.view.View$OnLongClickListener")
local TypedValue = bindClass("android.util.TypedValue")
local LuaDrawable = bindClass("com.androlua.LuaDrawable")
local LuaBitmapDrawable = bindClass("com.androlua.LuaBitmapDrawable")
local Glide = bindClass("com.bumptech.glide.Glide")
local requestManager = Glide.with(context)
local LuaAdapter = bindClass("com.androlua.LuaAdapter")
local ArrayListAdapter = bindClass("android.widget.ArrayListAdapter")
local View = bindClass("android.view.View")
local ArrayPageAdapter = bindClass("android.widget.ArrayPageAdapter")
local AdapterView = bindClass("android.widget.AdapterView")
local ScaleType = bindClass("android.widget.ImageView$ScaleType")
local TruncateAt = bindClass("android.text.TextUtils$TruncateAt")
local Typeface = bindClass("android.graphics.Typeface")
local scaleTypes = ScaleType.values()
local android_R = bindClass("android.R")
local MDC_R = bindClass("com.google.android.material.R")
android = {
  R = android_R,
  material = {
    R = MDC_R -- 没错，我们支持 MDCR
  }
}
local SDK_INT = bindClass("android.os.Build").VERSION.SDK_INT

local ContextThemeWrapper = bindClass("androidx.appcompat.view.ContextThemeWrapper")

local resources = context.getResources()
local dm = resources.getDisplayMetrics()
local W = dm.widthPixels
local H = dm.heightPixels
local density = dm.density
local scaledDensity = dm.scaledDensity

-- 预定义常量映射表（使用表作为快速查找）
local toint = {
  -- android:drawingCacheQuality
  auto = 0,
  low = 1,
  high = 2,

  -- android:importantForAccessibility
  yes = 1,
  no = 2,

  -- android:layerType
  none = 0,
  software = 1,
  hardware = 2,

  -- android:layoutDirection
  ltr = 0,
  rtl = 1,
  inherit = 2,
  locale = 3,

  -- android:scrollbarStyle
  insideOverlay = 0x0,
  insideInset = 0x01000000,
  outsideOverlay = 0x02000000,
  outsideInset = 0x03000000,

  -- android:visibility
  visible = 0,
  invisible = 4,
  gone = 8,

  wrap_content = -2,
  fill_parent = -1,
  match_parent = -1,
  wrap = -2,
  fill = -1,
  match = -1,

  -- android:autoLink
  none = 0x00,
  web = 0x01,
  email = 0x02,
  phone = 0x04,
  map = 0x08,
  all = 0x0f,

  -- android:orientation
  vertical = 1,
  horizontal = 0,

  -- android:gravity
  axis_clip = 8,
  axis_pull_after = 4,
  axis_pull_before = 2,
  axis_specified = 1,
  axis_x_shift = 0,
  axis_y_shift = 4,
  bottom = 80,
  center = 17,
  center_horizontal = 1,
  center_vertical = 16,
  clip_horizontal = 8,
  clip_vertical = 128,
  display_clip_horizontal = 16777216,
  display_clip_vertical = 268435456,
  fill_horizontal = 7,
  fill_vertical = 112,
  horizontal_gravity_mask = 7,
  left = 3,
  no_gravity = 0,
  relative_horizontal_gravity_mask = 8388615,
  relative_layout_direction = 8388608,
  right = 5,
  start = 8388611,
  top = 48,
  vertical_gravity_mask = 112,
  ["end"] = 8388613,

  -- android:textAlignment
  inherit = 0,
  gravity = 1,
  textStart = 2,
  textEnd = 3,
  textCenter = 4,
  viewStart = 5,
  viewEnd = 6,

  -- android:inputType
  none = 0x00000000,
  text = 0x00000001,
  textCapCharacters = 0x00001001,
  textCapWords = 0x00002001,
  textCapSentences = 0x00004001,
  textAutoCorrect = 0x00008001,
  textAutoComplete = 0x00010001,
  textMultiLine = 0x00020001,
  textImeMultiLine = 0x00040001,
  textNoSuggestions = 0x00080001,
  textUri = 0x00000011,
  textEmailAddress = 0x00000021,
  textEmailSubject = 0x00000031,
  textShortMessage = 0x00000041,
  textLongMessage = 0x00000051,
  textPersonName = 0x00000061,
  textPostalAddress = 0x00000071,
  textPassword = 0x00000081,
  textVisiblePassword = 0x00000091,
  textWebEditText = 0x000000a1,
  textFilter = 0x000000b1,
  textPhonetic = 0x000000c1,
  textWebEmailAddress = 0x000000d1,
  textWebPassword = 0x000000e1,
  number = 0x00000002,
  numberSigned = 0x00001002,
  numberDecimal = 0x00002002,
  numberPassword = 0x00000012,
  phone = 0x00000003,
  datetime = 0x00000004,
  date = 0x00000014,
  time = 0x00000024,

  -- android:imeOptions
  normal = 0x00000000,
  actionUnspecified = 0x00000000,
  actionNone = 0x00000001,
  actionGo = 0x00000002,
  actionSearch = 0x00000003,
  actionSend = 0x00000004,
  actionNext = 0x00000005,
  actionDone = 0x00000006,
  actionPrevious = 0x00000007,
  flagNoFullscreen = 0x2000000,
  flagNavigatePrevious = 0x4000000,
  flagNavigateNext = 0x8000000,
  flagNoExtractUi = 0x10000000,
  flagNoAccessoryAction = 0x20000000,
  flagNoEnterAction = 0x40000000,
  flagForceAscii = 0x80000000,

  -- layout_scrollFlags
  noScroll = 0,
  scroll = 1,
  exitUntilCollapsed = 2,
  enterAlways = 4,
  enterAlwaysCollapsed = 8,
  snap = 16,
  snapMargins = 32,

  -- layout_collapseMode
  pin = 1,
  parallax = 2,
}

local scaleType = {
  -- android:scaleType
  matrix = 0,
  fitXY = 1,
  fitStart = 2,
  fitCenter = 3,
  fitEnd = 4,
  center = 5,
  centerCrop = 6,
  centerInside = 7,
}

local rules = {
  layout_above = 2,
  layout_alignBaseline = 4,
  layout_alignBottom = 8,
  layout_alignEnd = 19,
  layout_alignLeft = 5,
  layout_alignParentBottom = 12,
  layout_alignParentEnd = 21,
  layout_alignParentLeft = 9,
  layout_alignParentRight = 11,
  layout_alignParentStart = 20,
  layout_alignParentTop = 10,
  layout_alignRight = 7,
  layout_alignStart = 18,
  layout_alignTop = 6,
  layout_alignWithParentIfMissing = 0,
  layout_below = 3,
  layout_centerHorizontal = 14,
  layout_centerInParent = 13,
  layout_centerVertical = 15,
  layout_toEndOf = 17,
  layout_toLeftOf = 0,
  layout_toRightOf = 1,
  layout_toStartOf = 16
}

local types = {
  px = 0,
  dp = 1,
  sp = 2,
  pt = 3,
  ["in"] = 4,
  mm = 5
}

-- 预定义行为类映射表
local BehaviorClasses = {
  appbar_scrolling_view_behavior = "com.google.android.material.appbar.AppBarLayout$ScrollingViewBehavior",
  bottom_sheet_behavior = "com.google.android.material.bottomsheet.BottomSheetBehavior",
  fab_transformation_scrim_behavior = "com.google.android.material.transformation.FabTransformationScrimBehavior",
  fab_transformation_sheet_behavior = "com.google.android.material.transformation.FabTransformationSheetBehavior",
  hide_bottom_view_on_scroll_behavior = "com.google.android.material.behavior.HideBottomViewOnScrollBehavior"
}

-- 缓存已加载的行为类
local BehaviorCache = {}

-- 尺寸缓存
local dimensionCache = {}

-- 预编译正则表达式模式
local PATTERN_PERCENT = "^(%-?[%.%d]+)%%([wh])$"
local PATTERN_COLOR = "^#(%x+)$"
local PATTERN_TYPE = "^(%-?[%.%d]+)(%a%a)$"
local PATTERN_STRING_REF = "^@string/"
local PATTERN_MATERIAL_STRING_REF = "^android%.material%.R%.string%."
local PATTERN_NINE_PATCH = "%.9%.png$"

-- 字符串处理
local function checkType(v)
  local n, ty = string_match(v, PATTERN_TYPE)
  return tonumber(n), types[ty]
end

local function checkPercent(v)
  local n, ty = string_match(v, PATTERN_PERCENT)
  if not ty then
    return nil
   elseif ty == "w" then
    return tonumber(n) * W / 100
   elseif ty == "h" then
    return tonumber(n) * H / 100
  end
end

local function checkint(s)
  local ret = 0
  for n in string_gmatch(s, "[^|]+") do
    local val = toint[n]
    if val then
      ret = ret | val
     else
      return nil
    end
  end
  return ret
end

-- 数值检查
local function checkNumber(var)
  if type(var) == "string" then
    if var == "true" then
      return true
     elseif var == "false" then
      return false
    end

    -- 检查常量映射
    if toint[var] then
      return toint[var]
    end

    -- 检查百分比
    local p = checkPercent(var)
    if p then
      return p
    end

    -- 检查位运算组合
    local i = checkint(var)
    if i then
      return i
    end

    -- 检查颜色值
    local h = string_match(var, PATTERN_COLOR)
    if h then
      local c = tonumber(h, 16)
      if c then
        if #h <= 6 then
          return c - 0x1000000
         elseif #h <= 8 then
          if c > 0x7fffffff then
            return c - 0x100000000
           else
            return c
          end
        end
      end
    end

    -- 检查尺寸单位
    local n, ty = checkType(var)
    if ty then
      -- 使用缓存避免重复计算
      if dimensionCache[var] then
        return dimensionCache[var]
      end
      local result = TypedValue.applyDimension(ty, n, dm)
      dimensionCache[var] = result
      return result
    end
  end
  return var
end

local function checkValue(var)
  return tonumber(var) or checkNumber(var) or var
end

local function checkValues(...)
  local vars = { ... }
  for n = 1, #vars do
    vars[n] = checkValue(vars[n])
  end
  return table_unpack(vars)
end

local function getattr(s)
  return android_R.attr[s]
end

local function checkattr(s)
  local e, s = pcall(getattr, s)
  if e then
    return s
  end
  return nil
end

local function getIdentifier(name)
  return resources.getIdentifier(name, nil, nil)
end

-- layout_behavior 处理
local function handleLayoutBehavior(v, params)
  local behaviorName

  -- 处理字符串类型的 behavior
  if type(v) == "string" then
    -- 处理 @string/ 格式
    if string_find(v, PATTERN_STRING_REF) then
      behaviorName = string_sub(v, 9) -- 移除 "@string/" 前缀
      -- 处理 android.material.R.string 格式
     elseif string_find(v, PATTERN_MATERIAL_STRING_REF) then
      behaviorName = string_match(v, "^android%.material%.R%.string%.(.+)$")
      -- 处理直接字符串
     else
      behaviorName = v
    end

    -- 尝试从缓存获取行为类
    if BehaviorCache[behaviorName] then
      params.setBehavior(BehaviorCache[behaviorName]())
      return
    end

    -- 检查是否是预定义的行为
    if BehaviorClasses[behaviorName] then
      local className = BehaviorClasses[behaviorName]
      local behavior = newInstance(className)
      BehaviorCache[behaviorName] = function() return behavior end
      params.setBehavior(behavior)
     else
      -- 尝试直接创建实例
      local success, behavior = pcall(newInstance, behaviorName)
      if success then
        BehaviorCache[behaviorName] = function() return behavior end
        params.setBehavior(behavior)
       else
        -- 如果失败，尝试作为类名加载
        local cls = pcall(bindClass, behaviorName)
        if cls then
          local success, behavior = pcall(newInstance, behaviorName)
          if success then
            BehaviorCache[behaviorName] = function() return behavior end
            params.setBehavior(behavior)
           else
            params.setBehavior(v)
          end
         else
          params.setBehavior(v)
        end
      end
    end
   else
    params.setBehavior(v)
  end
end

-- ViewPager 适配器：用项目自带的 ArrayPageAdapter
-- （原文件用的 override()/LuaPagerAdapter 来自另一个 AndroLua 分支，本项目没有）
local function LuaPagerAdapter(pageViews, pageTitles)
  return ArrayPageAdapter(luajava.createArray("android.view.View", pageViews))
end

-- 属性设置器映射表
local attributeSetters = {
  layout_x = function(view, params, v)
    params.x = checkValue(v)
  end,
  layout_y = function(view, params, v)
    params.y = checkValue(v)
  end,
  w = function(view, params, v)
    params.width = checkValue(v)
  end,
  h = function(view, params, v)
    params.height = checkValue(v)
  end,
  layout_weight = function(view, params, v)
    params.weight = checkValue(v)
  end,
  layout_gravity = function(view, params, v)
    params.gravity = checkValue(v)
  end,
  layout_marginStart = function(view, params, v)
    params.setMarginStart(checkValue(v))
  end,
  layout_marginEnd = function(view, params, v)
    params.setMarginEnd(checkValue(v))
  end,
  minHeight = function(view, params, v)
    view.setMinimumHeight(checkValue(v))
  end,
  minWidth = function(view, params, v)
    view.setMinimumWidth(checkValue(v))
  end,
  layout_behavior = function(view, params, v)
    handleLayoutBehavior(v, params)
  end,
  behavior_peekHeight = function(view, params, v)
    local behavior = params.getBehavior()
    if behavior then
      behavior.setPeekHeight(checkValue(v))
     else
      task(1, function()
        behavior.setPeekHeight(checkValue(v))
      end)
    end
  end,
  behavior_hideable = function(view, params, v)
    local behavior = params.getBehavior()
    if behavior then
      behavior.setHideable(checkValue(v))
     else
      task(1, function()
        behavior.setHideable(checkValue(v))
      end)
    end
  end,
  behavior_skipCollapsed = function(view, params, v)
    local behavior = params.getBehavior()
    if behavior then
      behavior.setSkipCollapsed(checkValue(v))
     else
      task(1, function()
        behavior.setSkipCollapsed(checkValue(v))
      end)
    end
  end,
  layout_scrollFlags = function(view, params, v)
    params.setScrollFlags(checkValue(v))
  end,
  layout_collapseMode = function(view, params, v)
    params.setCollapseMode(checkValue(v))
  end,
  layout_collapseParallaxMultiplier = function(view, params, v)
    params.setParallaxMultiplier(checkValue(v))
  end,
  layout_anchor = function(view, params, v, ids)
    params.setAnchorId(ids[v])
  end,
  items = function(view, params, v, ids, root)
    if type(v) == "table" then
      if view.adapter then
        view.adapter.addAll(v)
       else
        local adapter = ArrayListAdapter(context, android_R.layout.simple_list_item_1, String(v))
        view.setAdapter(adapter)
      end
     elseif type(v) == "function" then
      if view.adapter then
        view.adapter.addAll(v())
       else
        local adapter = ArrayListAdapter(context, android_R.layout.simple_list_item_1, String(v()))
        view.setAdapter(adapter)
      end
     elseif type(v) == "string" then
      local v = rawget(root, v) or rawget(_G, v)
      if view.adapter then
        view.adapter.addAll(v())
       else
        local adapter = ArrayListAdapter(context, android_R.layout.simple_list_item_1, String(v()))
        view.setAdapter(adapter)
      end
    end
  end,
  pages = function(view, params, v, ids, root)
    local list = {}
    for n, o in ipairs(v) do
      local tp = type(o)
      if tp == "string" or tp == "table" then
        list[n] = loadlayout(o, root)
       else
        list[n] = o
      end
    end

    view.setAdapter(LuaPagerAdapter(list))
  end,
  pagesWithTitle = function(view, params, v, ids, root)
    local list = {}
    for n, o in ipairs(v[1]) do
      local tp = type(o)
      if tp == "string" or tp == "table" then
        list[n] = loadlayout(o, root)
       else
        list[n] = o
      end
    end
    view.setAdapter(LuaPagerAdapter(list, v[2]))
  end,
  textSize = function(view, params, v)
    if tonumber(v) then
      view.setTextSize(tonumber(v))
     elseif type(v) == "string" then
      local n, ty = checkType(v)
      if ty then
        view.setTextSize(ty, n)
       else
        view.setTextSize(v)
      end
     else
      view.setTextSize(v)
    end
  end,
  textStyle = function(view, params, v)
    if v == "bold" then
      local bold = Typeface.defaultFromStyle(Typeface.BOLD)
      view.setTypeface(bold)
     elseif v == "normal" then
      local normal = Typeface.defaultFromStyle(Typeface.NORMAL)
      view.setTypeface(normal)
     elseif v == "italic" then
      local italic = Typeface.defaultFromStyle(Typeface.ITALIC)
      view.setTypeface(italic)
     elseif v == "italic|bold" or v == "bold|italic" then
      local bold_italic = Typeface.defaultFromStyle(Typeface.BOLD_ITALIC)
      view.setTypeface(bold_italic)
    end
  end,
  textAppearance = function(view, params, v)
    view.setTextAppearance(context, checkattr(v))
  end,
  ellipsize = function(view, params, v)
    view.setEllipsize(TruncateAt[string_upper(v)])
  end,
  url = function(view, params, v)
    view.loadUrl(v)
  end,
  src = function(view, params, v)
    local path = v
    if not path:find("^/") and path:sub(1, 4) ~= "http" then
      local _path = luadir .. "/" .. path
      if (_path ~= nil) then
        path = _path
      end
    end
    requestManager.load(path).into(view)
  end,
  scaleType = function(view, params, v)
    view.setScaleType(scaleTypes[scaleType[v]])
  end,
  background = function(view, params, v, ids, root)
    if type(v) == "string" then
      if string_find(v, "^%?") then
        view.setBackgroundResource(getIdentifier(string_sub(v, 2, -1)))
       elseif string_find(v, "^#") then
        view.setBackgroundColor(checkNumber(v))
       elseif rawget(root, v) or rawget(_G, v) then
        v = rawget(root, v) or rawget(_G, v)
        if type(v) == "function" then
          view.setBackground(LuaDrawable(v))
         elseif type(v) == "userdata" then
          view.setBackground(v)
        end
       else
        if (not string_find(v, "^/")) and luadir then
          v = luadir .. v
        end
        if string_find(v, PATTERN_NINE_PATCH) then
          view.setBackground(NineBitmapDrawable(loadbitmap(v)))
         else
          view.setBackground(LuaBitmapDrawable(context, v))
        end
      end
     elseif type(v) == "userdata" then
      view.setBackground(v)
     elseif type(v) == "number" then
      view.setBackground(v)
    end
  end,
  onClick = function(view, params, v, ids, root)
    local listener
    if type(v) == "function" then
      listener = OnClickListener { onClick = v }
     elseif type(v) == "userdata" then
      listener = v
     elseif type(v) == "string" then
      if ltrs[v] then
        listener = ltrs[v]
       else
        local l = rawget(root, v) or rawget(_G, v)
        if type(l) == "function" then
          listener = OnClickListener { onClick = l }
         elseif type(l) == "userdata" then
          listener = l
         else
          listener = OnClickListener { onClick = function(a) (root[v] or _G[v])(a) end }
        end
        ltrs[v] = listener
      end
    end
    view.setOnClickListener(listener)
  end,
  onLongClick = function(view, params, v, ids, root)
    local listener
    if type(v) == "function" then
      if SDK_INT >= 34 then
        listener = OnLongClickListener {
          onLongClick = v,
          onLongClickUseDefaultHapticFeedback = function()
            return true
          end
        }
       else
        listener = OnLongClickListener {
          onLongClick = v,
        }
      end
     elseif type(v) == "userdata" then
      listener = v
     elseif type(v) == "string" then
      if ltrs[v] then
        listener = ltrs[v]
       else
        local l = rawget(root, v) or rawget(_G, v)
        if type(l) == "function" then
          if SDK_INT >= 34 then
            listener = OnLongClickListener {
              onLongClick = l,
              onLongClickUseDefaultHapticFeedback = function()
                return true
              end
            }
           else
            listener = OnLongClickListener { onLongClick = l }
          end
         elseif type(l) == "userdata" then
          listener = l
         else
          if SDK_INT >= 34 then
            listener = OnLongClickListener {
              onLongClick = function(a) (root[v] or _G[v])(a) end,
              onLongClickUseDefaultHapticFeedback = function()
                return true
              end
            }
           else
            listener = OnLongClickListener { onLongClick = function(a) (root[v] or _G[v])(a) end }
          end
        end
        ltrs[v] = listener
      end
    end
    view.setOnLongClickListener(listener)
  end,
  password = function(view, params, v)
    if v == "true" or v == true then
      view.setInputType(0x81)
    end
  end
}

local function setattribute(root, view, params, k, v, ids)
  -- 检查布局规则
  if rules[k] then
    if v == true or v == "true" then
      params.addRule(rules[k])
     else
      params.addRule(rules[k], ids[v])
    end
    return params
  end

  -- 使用属性设置器
  local setter = attributeSetters[k]
  if setter then
    setter(view, params, v, ids, root)
    return params
  end

  -- 处理通用属性
  if type(k) == "string" and not (string_find(k, "layout_")) and not (string_find(k, "padding")) and k ~= "style" then
    k = string_gsub(k, "^(%w)", function(s) return string_upper(s) end)
    if k == "Text" or k == "Title" or k == "Subtitle" then
      view["set" .. k](v)
     elseif not string_find(k, "^On") and not string_find(k, "^Tag") and type(v) == "table" then
      view["set" .. k](checkValues(table_unpack(v)))
     else
      view["set" .. k](checkValue(v))
    end
  end

  return params
end

local function setstyle(c, t, root, view, params, ids)
  local mt = getmetatable(t)
  if not mt or not mt.__index then
    return
  end
  local m = mt.__index
  if c[m] then
    return
  end
  c[m] = true
  for k, v in pairs(m) do
    if not rawget(c, k) then
      pcall(setattribute, root, view, params, k, v, ids)
    end
    c[k] = true
  end
  setstyle(c, m, root, view, params, ids)
end

local function alyloader(path)
  local alypath = package.path:gsub("%.lua;", ".aly;")
  local path, msg = package.searchpath(path, alypath)
  if msg then
    return msg
  end
  local f = io.open(path)
  local s = f:read("*a")
  f:close()
  if string.sub(s, 1, 4) == "\27Lua" then
    return assert(loadfile(path)), path
   else
    local f, st = loadstring("return " .. s, path:match("[^/]+/[^/]+$"), "bt")
    if st then
      error(st:gsub("%b[]", path, 1), 0)
    end
    return f, st
  end
end
insert(package.searchers, alyloader)

local function loadlayout(t, root, group)
  if type(t) == "string" then
    t = require(t)
   elseif type(t) ~= "table" then
    error(string.format("loadlayout error: First value Must be a table, checked import layout.", 0))
  end
  root = root or _G
  local view, style
  if t.style then
    if type(t.style) == "number" then
      style = t.style
     elseif t.style:find("^%?") then
      style = getIdentifier(t.style:sub(2, -1))
     else
      local st, sty = pcall(require, t.style)
      if st then
        setmetatable(t, { __index = sty })
       else
        style = checkattr(t.style)
      end
    end
  end
  if not t[1] then
    error(string.format("loadlayout error: First value Must be a Class, checked import package.\n\tat %s", dump(t)), 0)
  end

  if instanceof(t[1], View) then
    view = t[1]
   elseif type(t[1]) == "number" then
    view = activity.layoutInflater.inflate(t[1], nil);
   else
    if style then
      view = t[1](ContextThemeWrapper(context, style), nil, style)
     else
      view = t[1](context)
    end
  end

  local params = ViewGroup.LayoutParams(checkValue(t.layout_width) or checkValue(t.w) or -2,
  checkValue(t.layout_height) or checkValue(t.h) or -2)
  if group then
    params = group.LayoutParams(params)
  end

  -- 设置 layout_margin 属性
  if t.layout_margin or t.layout_marginStart or t.layout_marginEnd or t.layout_marginLeft or t.layout_marginTop or t.layout_marginRight or t.layout_marginBottom then
    params.setMargins(checkValues(t.layout_marginLeft or t.layout_margin or 0, t.layout_marginTop or t.layout_margin or 0,
    t.layout_marginRight or t.layout_margin or 0, t.layout_marginBottom or t.layout_margin or 0))
  end

  -- 设置 padding 属性
  if t.padding and type(t.padding) == "table" then
    view.setPadding(checkValues(table_unpack(t.padding)))
   elseif t.padding or t.paddingLeft or t.paddingTop or t.paddingRight or t.paddingBottom then
    view.setPadding(checkValues(t.paddingLeft or t.padding or 0, t.paddingTop or t.padding or 0,
    t.paddingRight or t.padding or 0, t.paddingBottom or t.padding or 0))
  end
  if t.paddingStart or t.paddingEnd then
    view.setPaddingRelative(checkValues(t.paddingStart or t.padding or 0, t.paddingTop or t.padding or 0,
    t.paddingEnd or t.padding or 0, t.paddingBottom or t.padding or 0))
  end

  local c = {}
  setmetatable(c, { __index = t })
  setstyle(c, t, root, view, params, ids)

  for k, v in pairs(t) do
    if tonumber(k) and (type(v) == "table" or type(v) == "string") then
      if instanceof(view, AdapterView) then
        if type(v) == "string" then
          v = require(v)
        end
        view.adapter = LuaAdapter(context, v)
       else
        view.addView(loadlayout(v, root, view.getClass()))
      end
     elseif k == "id" then
      rawset(root, v, view)
      local id = ids.id
      ids.id = ids.id + 1
      view.setId(id)
      ids[v] = id
     else
      local e, s = pcall(setattribute, root, view, params, k, v, ids)
      if not e then
        local _, i = s:find(":%d+:")
        s = s:sub(i or 1, -1)
        local _, du = pcall(dump, t)
        print(
        string.format("loadlayout error %s \n\tat %s\n\tat  key=%s value=%s\n\tat %s", s, view.toString(), k, v,
        du or ""),
        0)
      end
    end
  end

  view.setLayoutParams(params)
  return view
end

return loadlayout