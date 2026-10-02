-- ============================================================
-- Flutter 全组件示例（121 个控件 · 全属性速查）
--
-- 两条线：
--   1) 分类示例页：布局/文本/按钮/输入/列表/导航/展示/弹窗/动画/媒体，每个控件都有一份能跑的示例
--   2) 属性速查页：内置从渲染器自动抽取的「控件 -> 支持属性」表，带搜索框，写脚本时直接查
--
-- 通用约定（对所有控件生效，不用记在每个控件上）：
--   尺寸/外观：id / width / height / weight / margin / padding / visible / opacity / tooltip
--   交互反馈：noSplash（去水波纹）/ splashColor / highlightColor / hoverColor / focusColor /
--             splash = false（等价 noSplash）/ cursor（click/text/grab…）
--   手势事件：onTap / onLongPress / onTapDown / onTapUp / onTapCancel / onDoubleTap / onSecondaryTap /
--             onHover / onEnter / onExit / onFocusChange / autofocus
--   事件写法：值写成字符串 = 调同名全局函数；写成 { event="名", args={...} } 也可以；
--             也能用句柄：_G["节点id"].onClick = function() … end
--   密度：visualDensity = "compact"/"comfortable"，tapTargetSize = "padded"/"shrinkWrap"
-- ============================================================
require "import"
import "android.widget.*"
import "android.view.*"

activity.setTitle("Flutter 全组件示例")

local host = FrameLayout(activity)
local DEMOS = {}
local render

local function shell(title, body, extra)
  local s = {
    Scaffold,
    backgroundColor = "#F7F7F9",
    appBar = { AppBar, centerTitle = true,
      title = { Text, text = title },
      leading = { IconButton, icon = "arrow_back", onClick = "uiBack" } },
    body = body,
  }
  if extra then
    for k, v in pairs(extra) do s[k] = v end
  end
  return s
end

-- ============================================================
-- 属性速查数据：由渲染器源码自动抽取（121 个控件）
-- 格式：{ "控件名", "支持的属性（逗号分隔）" }
-- ============================================================
local 属性表 = {
  { "actionchip", "avatar, label, onChange, onDeleted, selected, text" },
  { "alertdialog", "actions, actionsPadding, alignment, backgroundColor, color, content, elevation, icon, insetPadding, radius, scrollable, shadowColor, shape, surfaceTintColor, text, title" },
  { "align", "alignment" },
  { "animatedalign", "alignment, duration" },
  { "animatedcontainer", "alignment, backgroundColor, borderRadius, boxShadow, color, decoration, duration, gradient, radius, shadows, shape" },
  { "animatedcrossfade", "duration" },
  { "animateddefaulttextstyle", "duration" },
  { "animatedopacity", "duration" },
  { "animatedpadding", "duration" },
  { "animatedpositioned", "bottom, curve, duration, left, right, top" },
  { "animatedrotation", "duration, turns" },
  { "animatedscale", "duration, scale" },
  { "animatedsize", "alignment, curve, duration" },
  { "animatedslide", "duration, offset" },
  { "animatedswitcher", "duration" },
  { "animatedtheme", "brightness, colorSchemeSeed, duration" },
  { "appbar", "actions, backgroundColor, bottom, centerTitle, color, elevation, foregroundColor, leading, leadingWidth, radius, scrolledUnderElevation, shadowColor, shape, surfaceTintColor, title, titleSpacing, toolbarHeight" },
  { "aspectratio", "aspectRatio, ratio" },
  { "audioplayer", "autoPlay, src, text, title, url" },
  { "badge", "alignment, backgroundColor, color, label, largeSize, offset, smallSize, text, textColor" },
  { "barchart", "barWidth, color, colors, groups, series, value, values" },
  { "baseline", "baseline, baselineType" },
  { "bottomappbar", "backgroundColor, clipBehavior, color, elevation, notchMargin, shadowColor, surfaceTintColor" },
  { "bottomnavigationbar", "currentIndex, icon, items, label, selectedItemColor, text, unselectedItemColor" },
  { "bottomsheet", "backgroundColor, clipBehavior, color, dragHandleColor, dragHandleSize, elevation, onClosing, radius, shadowColor, shape, showDragHandle" },
  { "calendardatepicker", "firstDate, initialDate, lastDate, onChange" },
  { "card", "backgroundColor, borderRadius, boxShadow, clipBehavior, color, decoration, elevation, gradient, radius, shadowColor, shadows, shape, surfaceTintColor" },
  { "checkbox", "activeColor, checkColor, isError, onChange, radius, semanticLabel, shape, side, tristate, value" },
  { "checkboxlisttile", "onChange, subtitle, text, title, value" },
  { "chip", "avatar, backgroundColor, color, deleteIcon, elevation, label, labelPadding, onDeleted, radius, shadowColor, shape, side, surfaceTintColor, text" },
  { "circleavatar", "backgroundColor, color, radius, size" },
  { "circularprogressindicator", "backgroundColor, color, semanticsLabel, strokeCap, strokeWidth, value" },
  { "cliprrect", "radius" },
  { "coloredbox", "color" },
  { "column", "crossAxisAlignment, gap, gravity, mainAxisAlignment, mainAxisSize, spacing, textBaseline, textDirection, verticalDirection" },
  { "container", "alignment, backgroundColor, borderRadius, boxShadow, clip, color, decoration, foregroundDecoration, gradient, maxHeight, maxWidth, minHeight, minWidth, radius, shadows, shape, transform, transformAlignment" },
  { "cupertinoalertdialog", "actions, content, title" },
  { "cupertinobutton", "alignment, borderRadius, color, disabledColor, minSize, minimumSize, pressedOpacity, radius, text" },
  { "cupertinodatepicker", "initialDateTime, maximumDate, minimumDate, minuteInterval, mode, onChange, value" },
  { "cupertinonavigationbar", "backgroundColor, border, color, leading, middle, title, trailing" },
  { "cupertinoslider", "activeColor, divisions, max, min, onChange, thumbColor, value" },
  { "cupertinoswitch", "activeTrackColor, applyTheme, inactiveTrackColor, onChange, thumbColor, trackColor, value" },
  { "cupertinotimerpicker", "alignment, initialSeconds, mode, onChange" },
  { "customscrollview", "physics, reverse, shrinkWrap" },
  { "datatable", "clipBehavior, columnSpacing, columns, dataRowMaxHeight, dataRowMinHeight, dataTextStyle, dividerThickness, headingRowHeight, headingTextStyle, horizontalMargin, rows, showBottomBorder" },
  { "decoratedbox", "backgroundColor, borderRadius, boxShadow, color, decoration, gradient, radius, shadows, shape" },
  { "defaulttabcontroller", "index, initialIndex, length, onChange" },
  { "dialog", "backgroundColor, clipBehavior, color, elevation, insetPadding, radius, shape" },
  { "dismissible", "direction, onDismiss" },
  { "divider", "color, endIndent, indent, thickness" },
  { "drawer", "backgroundColor, clipBehavior, color, elevation, radius, shadowColor, shape, surfaceTintColor" },
  { "dropdownbutton", "alignment, borderRadius, decoration, dropdownColor, elevation, hint, icon, iconDisabledColor, iconEnabledColor, iconSize, isDense, isExpanded, itemHeight, items, onChange, radius, value" },
  { "dropdownmenu", "enabled, errorText, helperText, hint, hintText, initialSelection, items, label, menuHeight, onChange, requestFocusOnTap, text, value" },
  { "elevatedbutton", "animationDuration, backgroundColor, borderRadius, elevation, fixedSize, foregroundColor, icon, label, maximumSize, minimumSize, overlayColor, radius, shadowColor, shape, side, style, surfaceTintColor, text, textStyle" },
  { "expanded", "flex" },
  { "expansiontile", "backgroundColor, childrenPadding, collapsedBackgroundColor, collapsedIconColor, collapsedRadius, collapsedShape, collapsedTextColor, controlAffinity, dense, expanded, expandedAlignment, expandedCrossAxisAlignment, iconColor, initiallyExpanded, leading, maintainState, onChange, onExpansionChanged, radius, shape, subtitle, text, textColor, tilePadding, title" },
  { "fittedbox", "fit" },
  { "floatingactionbutton", "backgroundColor, color, elevation, foregroundColor, heroTag, highlightElevation, icon, mini, name, radius, shape" },
  { "fluttermap", "borderColor, borderStrokeWidth, center, circles, color, icon, lat, latitude, lng, longitude, markers, maxZoom, minZoom, points, polygons, polylines, strokeWidth, tileUrl, userAgent, zoom" },
  { "fractionallysizedbox", "alignment, heightFactor, widthFactor" },
  { "gridview", "childAspectRatio, columns, crossAxisCount, crossAxisSpacing, gap, item, itemCount, itemTemplate, mainAxisSpacing, physics, reverse, shrinkWrap" },
  { "icon", "color, fill, grade, icon, iconSize, name, opticalSize, semanticsLabel, shadows, size, textDirection" },
  { "iconbutton", "alignment, color, disabledColor, icon, iconColor, iconSize, name, size, splashRadius" },
  { "image", "alignment, asset, borderRadius, colorBlendMode, file, filterQuality, fit, imageColor, radius, repeat, semanticLabel, src, url" },
  { "indexedstack", "index" },
  { "limitedbox", "maxHeight, maxWidth" },
  { "linearprogressindicator", "backgroundColor, borderRadius, color, minHeight, radius, semanticsLabel, value" },
  { "linechart", "barWidth, color, colors, groups, series, value, values" },
  { "listtile", "contentPadding, dense, iconColor, isThreeLine, leading, minVerticalPadding, radius, selected, selectedTileColor, shape, subtitle, text, textColor, tileColor, title, trailing" },
  { "listview", "cacheExtent, item, itemCount, itemExtent, itemTemplate, keyboardDismissBehavior, physics, reverse, shrinkWrap" },
  { "listwheelscrollview", "borderColor, borderStrokeWidth, cacheExtent, center, circles, color, diameterRatio, groups, icon, item, itemCount, itemExtent, itemTemplate, keyboardDismissBehavior, lat, latitude, lng, longitude, magnification, markers, maxZoom, minZoom, offAxisFraction, perspective, physics, points, polygons, polylines, reverse, series, shrinkWrap, squeeze, strokeWidth, text, tileUrl, useMagnifier, userAgent, zoom" },
  { "material", "backgroundColor, color, elevation, radius" },
  { "materialbanner", "actions, backgroundColor, color, elevation, leading" },
  { "materialbutton", "backgroundColor, color, text" },
  { "navigationbar", "animationDuration, backgroundColor, color, currentIndex, destinations, elevation, icon, indicatorColor, indicatorRadius, indicatorShape, items, label, labelBehavior, onChange, onDestinationSelected, selectedIndex, shadowColor, surfaceTintColor, text" },
  { "navigationdrawer", "backgroundColor, color, currentIndex, elevation, onChange, selectedIndex, surfaceTintColor" },
  { "navigationrail", "backgroundColor, color, currentIndex, elevation, extended, groupAlignment, icon, items, label, labelType, minExtendedWidth, minWidth, onChange, selectedIcon, selectedIndex, text" },
  { "pageview", "initialPage, onChange, page, physics, reverse" },
  { "placeholder", "color, fallbackHeight, fallbackWidth, strokeWidth" },
  { "popupmenubutton", "icon, items, label, onChange, text, value" },
  { "positioned", "bottom, left, right, top" },
  { "qrcode", "background, color, data, size, text" },
  { "radio", "group, groupValue, onChange, value" },
  { "radiolisttile", "group, groupValue, onChange, subtitle, text, title, value" },
  { "rangeslider", "end, max, min, onChange, start" },
  { "refreshindicator", "backgroundColor, color, delay, displacement, edgeOffset, elevation, onRefresh, strokeWidth, triggerMode" },
  { "reorderablelistview", "item, itemCount, itemTemplate, onReorder, physics, shrinkWrap" },
  { "richtext", "spans, text" },
  { "rotatedbox", "quarterTurns, turns" },
  { "row", "crossAxisAlignment, gap, gravity, mainAxisAlignment, mainAxisSize, spacing, textBaseline, textDirection, verticalDirection" },
  { "scaffold", "appBar, backgroundColor, body, bottomNavigationBar, bottomSheet, drawer, drawerEdgeDragWidth, drawerScrimColor, endDrawer, extendBody, extendBodyBehindAppBar, floatingActionButton, floatingActionButtonLocation, persistentFooterAlignment, persistentFooterButtons, resizeToAvoidBottomInset" },
  { "searchbar", "backgroundColor, elevation, hint, hintText, leading, onChange, onSubmitted, trailing" },
  { "segmentedbutton", "icon, label, onChange, segments, selected, text, value" },
  { "selectabletext", "cursorColor, maxLines, selectionColor, text, textAlign, textDirection, value" },
  { "simpledialog", "backgroundColor, color, elevation, radius, shape, title" },
  { "singlechildscrollview", "physics" },
  { "slider", "activeColor, divisions, inactiveColor, label, max, min, onChange, secondaryActiveColor, thumbColor, value" },
  { "sliverappbar", "actions, backgroundColor, centerTitle, color, elevation, expandedHeight, flexibleSpace, floating, foregroundColor, leading, pinned, snap, title, toolbarHeight" },
  { "slivergrid", "childAspectRatio, columns, crossAxisCount, crossAxisSpacing, gap, mainAxisSpacing" },
  { "snackbar", "action, actionLabel, backgroundColor, behavior, color, duration, elevation" },
  { "spacer", "flex" },
  { "stack", "alignment, clip, clipBehavior, fit" },
  { "stepper", "content, currentStep, steps, subtitle, title" },
  { "switch", "activeColor, activeThumbColor, activeTrackColor, inactiveThumbColor, inactiveTrackColor, onChange, value" },
  { "switchlisttile", "onChange, subtitle, text, title, value" },
  { "tabbar", "color, dividerColor, dividerHeight, icon, indicator, indicatorColor, indicatorSize, indicatorWeight, insets, isScrollable, label, labelColor, labelPadding, labelStyle, overlayColor, tabs, text, unselectedLabelColor, unselectedLabelStyle" },
  { "table", "border, rows" },
  { "text", "data, locale, maxLines, overflow, selectionColor, semanticsLabel, softWrap, text, textAlign, textDirection, textScaleFactor, textScaler, textWidthBasis, value" },
  { "textfield", "alignLabelWithHint, autofillHints, clipBehavior, contentPadding, counterText, cursorColor, cursorErrorColor, cursorHeight, cursorRadius, cursorWidth, dragStartBehavior, enableInteractiveSelection, errorMaxLines, errorText, expands, fillColor, filled, floatingLabelBehavior, helperMaxLines, helperText, hint, hintMaxLines, hintText, inputType, isDense, keyboardAppearance, keyboardType, label, labelText, maxLength, maxLengthEnforcement, maxLines, minLines, obscure, obscureText, onChange, onSubmit, onSubmitted, password, prefixIcon, prefixText, readOnly, scrollPadding, showCursor, suffixIcon, suffixText, text, textAlign, textAlignVertical, textCapitalization, textInputAction" },
  { "togglebuttons", "isSelected, onChange" },
  { "tooltip", "message, text" },
  { "transform", "translate" },
  { "useraccountsdrawerheader", "accountEmail, accountName, backgroundColor, borderRadius, boxShadow, color, currentAccountPicture, decoration, gradient, otherAccountsPictures, radius, shadows, shape" },
  { "verticaldivider", "color, endIndent, indent, thickness" },
  { "videoplayer", "autoPlay, loop, src, url" },
  { "wrap", "alignment, gap, runSpacing" },
}

-- ============================================================
-- 12 个分类示例页
-- ============================================================

-- 1) 布局与容器 -------------------------------------------------
DEMOS[#DEMOS + 1] = { "布局与容器", "Column/Row/Stack/Wrap/Container/Positioned/Sliver…", function()
  return shell("布局与容器", {
    SingleChildScrollView, padding = 10,
    { Column, gap = 8,
      { Text, text = "Column / Row / Expanded / Spacer", fontSize = 12, color = "#888888" },
      { Row, gap = 8,
        { Expanded, { Container, height = 36, color = "#c5cae9", { Center, { Text, text = "Expanded 1" } } } },
        { Spacer },
        { Container, height = 36, width = 90, color = "#b39ddb", { Center, { Text, text = "固定宽" } } } },
      { Text, text = "Stack + Positioned + Align", fontSize = 12, color = "#888888" },
      { Stack, height = 90,
        { Container, color = "#e8eaf6" },
        { Positioned, left = 8, top = 8, { Container, width = 40, height = 40, color = "#7986cb" } },
        { Align, alignment = "bottomright", { Container, width = 60, height = 24, color = "#5c6bc0" } } },
      { Text, text = "Wrap（自动换行）", fontSize = 12, color = "#888888" },
      { Wrap, gap = 6, runSpacing = 6,
        { Chip, text = "Wrap 1" }, { Chip, text = "Wrap 2" }, { Chip, text = "Wrap 3" },
        { Chip, text = "Wrap 4" }, { Chip, text = "Wrap 5" } },
      { Text, text = "尺寸/比例/裁剪", fontSize = 12, color = "#888888" },
      { Row, gap = 8,
        { AspectRatio, aspectRatio = 1.5, { Container, color = "#ffcc80" } },
        { FractionallySizedBox, widthFactor = 0.3, heightFactor = 0.5,
          { Container, color = "#a5d6a7", { Center, { Text, text = "Fractionally" } } } } },
      { Row, gap = 8,
        { ClipRRect, radius = 10, { Container, width = 60, height = 40, color = "#ef9a9a" } },
        { ClipOval, { Container, width = 40, height = 40, color = "#90caf9" } },
        { Opacity, opacity = 0.4, { Container, width = 60, height = 40, color = "#ce93d8" } },
        { RotatedBox, quarterTurns = 1, { Container, width = 60, height = 24, color = "#80cbc4" } },
        { Transform, translate = { 8, 6 }, { Container, width = 50, height = 30, color = "#ffe082" } } },
      { Text, text = "其它容器：Padding / SizedBox / Center / ConstrainedBox / LimitedBox / IntrinsicWidth / FittedBox / DecoratedBox / ColoredBox / Material / Visibility / Offstage / IndexedStack / Baseline / SafeArea / Table", fontSize = 12, color = "#888888" },
      { Row, gap = 8,
        { Padding, padding = 6, { Container, width = 40, height = 40, color = "#b0bec5" } },
        { SizedBox, width = 40, height = 40, { Container, color = "#cfd8dc" } },
        { Center, { Container, width = 30, height = 30, color = "#b0bec5" } },
        { ConstrainedBox, maxWidth = 70, { Container, height = 40, color = "#e0e0e0", { Text, text = "Constrained" } } },
        { LimitedBox, maxWidth = 70, maxHeight = 40, { Text, text = "LimitedBox" } },
        { IntrinsicWidth, { Container, color = "#d1c4e9", { Text, text = "Intrinsic" } } },
        { FittedBox, fit = "contain", { Container, width = 40, height = 40, color = "#c8e6c9" } } },
      { Row, gap = 8,
        { DecoratedBox, radius = 8, gradient = { "#ff8a65", "#ffd54f" }, { Padding, padding = 10, { Text, text = "DecoratedBox" } } },
        { ColoredBox, color = "#b2dfdb", { Padding, padding = 10, { Text, text = "ColoredBox" } } },
        { Material, elevation = 3, radius = 8, { Padding, padding = 10, { Text, text = "Material" } } },
        { Visibility, visible = true, { Text, text = "Visibility" } },
        { Offstage, offstage = true, { Text, text = "Offstage 隐藏" } },
        { Baseline, baseline = 20, baselineType = "alphabetic", { Text, text = "Baseline" } } },
      { Row, gap = 8,
        { IndexedStack, index = 0, { Text, text = "IndexedStack[0]" }, { Text, text = "IndexedStack[1]" } },
        { SafeArea, { Text, text = "SafeArea" } },
        { IntrinsicHeight, { Text, text = "IntrinsicHeight" } } },
      { Table, border = true,
        rows = {
          { { Text, text = "表头 A" }, { Text, text = "表头 B" } },
          { { Text, text = "数据 1" }, { Text, text = "数据 2" } } } },
    },
  })
end }

-- 2) 文本与图标 -------------------------------------------------
DEMOS[#DEMOS + 1] = { "文本与图标", "Text/SelectableText/RichText/Icon/Image", function()
  return shell("文本与图标", {
    ListView, padding = 12,
    { Card, { Column, gap = 8,
      { Text, text = "Text：fontSize/color/fontWeight/fontStyle/decoration/letterSpacing/lineHeight/maxLines/overflow/textAlign", fontSize = 12, color = "#888888" },
      { Text, text = "普通文本", fontSize = 16 },
      { Text, text = "加粗 + 斜体 + 下划线", fontSize = 15, fontWeight = "bold", fontStyle = "italic", decoration = "underline" },
      { Text, text = "字距 2、行高 1.6 —— 这段文字用来说明 lineHeight 是倍数而不是像素", fontSize = 13, letterSpacing = 2, lineHeight = 1.6, color = "#3949ab" },
      { Text, text = "最多两行，超出省略……" .. string.rep("很长", 20), maxLines = 2, overflow = "ellipsis", fontSize = 13 } } },
    { Card, { Column, gap = 8,
      { Text, text = "SelectableText（可选中复制）", fontSize = 12, color = "#888888" },
      { SelectableText, text = "这段文字可以长按选中复制", selectionColor = "#ffe082" } } },
    { Card, { Column, gap = 8,
      { Text, text = "RichText（每段可单独设样式）", fontSize = 12, color = "#888888" },
      { RichText, spans = {
          { text = "红色粗体  ", color = "#e53935", fontWeight = "bold" },
          { text = "蓝色下划线", color = "#1e88e5", decoration = "underline" },
          { text = "  普通" } } } } },
    { Card, { Column, gap = 8,
      { Text, text = "Icon / Image", fontSize = 12, color = "#888888" },
      { Row, gap = 14,
        { Icon, icon = "home" }, { Icon, icon = "favorite", color = "#e91e63", size = 30 },
        { Icon, icon = "settings", color = "#607d8b" }, { Icon, icon = "not_a_name" } },
      { Text, text = "未知名会变问号并在 debug 日志提醒；图片支持 src（网络/文件）/asset/file/url", fontSize = 11, color = "#999999" },
      { Row, gap = 8,
        { Image, src = "https://picsum.photos/80", width = 80, height = 60, radius = 8, fit = "cover" },
        { Image, asset = "icon.png", width = 60, height = 60, fit = "contain" } } } },
  })
end }

-- 3) 按钮 -------------------------------------------------------
DEMOS[#DEMOS + 1] = { "按钮", "Elevated/Text/Filled/Outlined/Material/Icon/FAB/Cupertino/PopupMenu", function()
  return shell("按钮", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 10,
      { Text, text = "四种 Material 按钮 + 图标 + 圆角/颜色/阴影", fontSize = 12, color = "#888888" },
      { Wrap, gap = 8, runSpacing = 8,
        { ElevatedButton, text = "Elevated", onClick = "btnTap" },
        { TextButton, text = "Text", onClick = "btnTap" },
        { FilledButton, text = "Filled", onClick = "btnTap" },
        { OutlinedButton, text = "Outlined", onClick = "btnTap" },
        { ElevatedButton, text = "带图标", icon = "add", onClick = "btnTap" },
        { ElevatedButton, text = "圆角/自定义色", radius = 20, backgroundColor = "#43a047",
          foregroundColor = "#ffffff", elevation = 6, onClick = "btnTap" },
        { OutlinedButton, text = "noSplash（无波纹）", noSplash = true, onClick = "btnTap" } },
      { Text, text = "IconButton / FloatingActionButton / MaterialButton", fontSize = 12, color = "#888888" },
      { Row, gap = 10,
        { IconButton, icon = "favorite_border", tooltip = "收藏", onClick = "btnTap" },
        { IconButton, icon = "share", color = "#1e88e5", iconSize = 28, onClick = "btnTap" },
        { MaterialButton, text = "MaterialButton", color = "#e8eaf6", radius = 6, onClick = "btnTap" },
        { FloatingActionButton, icon = "add", mini = true, onClick = "btnTap" } },
      { Text, text = "PopupMenuButton（点开菜单）", fontSize = 12, color = "#888888" },
      { Row, gap = 10,
        { PopupMenuButton, label = "菜单", icon = "more_vert", onChange = "菜单选择",
          items = { { value = "a", text = "选项 A" }, { value = "b", text = "选项 B" } } },
        { CupertinoButton, text = "Cupertino", onClick = "btnTap" } },
      { Text, text = "点击回调：onClick=\"函数名\"，也支持句柄 _G[\"节点id\"].onClick = function() … end", fontSize = 11, color = "#999999" } },
  })
end }

-- 4) 选择控件 ---------------------------------------------------
DEMOS[#DEMOS + 1] = { "选择控件", "Checkbox/Switch/Radio/Slider/Range/分段/切片/下拉", function()
  return shell("选择控件", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 10,
      { Text, text = "Checkbox / Switch / Radio / Cupertino 版", fontSize = 12, color = "#888888" },
      { Row, gap = 16,
        { Checkbox, id = "cbx", value = true, onChange = "开关回显" },
        { Switch, id = "swx", value = false, activeTrackColor = "#66bb6a", onChange = "开关回显" },
        { CupertinoSwitch, id = "csw", value = false, activeColor = "#ff9800", onChange = "开关回显" },
        { Radio, groupValue = "a", value = "a", onChange = "单选回显" },
        { Radio, groupValue = "a", value = "b", onChange = "单选回显" } },
      { Text, text = "Slider / RangeSlider / CupertinoSlider", fontSize = 12, color = "#888888" },
      { Slider, value = 40, min = 0, max = 100, divisions = 10, label = "40", onChange = "滑块回显" },
      { RangeSlider, start = 20, End = 60, min = 0, max = 100, onChange = "区间回显" },
      { CupertinoSlider, value = 30, min = 0, max = 100, onChange = "滑块回显" },
      { Text, text = "SegmentedButton / ToggleButtons / DropdownButton / DropdownMenu", fontSize = 12, color = "#888888" },
      { SegmentedButton, selected = { "全部" }, onChange = "分段回显",
        segments = { { value = "全部", label = "全部" }, { value = "待办", label = "待办" }, { value = "完成", label = "完成" } } },
      { ToggleButtons, isSelected = { true, false, false }, onChange = "多选回显",
        { Text, text = "左" }, { Text, text = "中" }, { Text, text = "右" } },
      { DropdownButton, value = "Lua", onChange = "下拉回显",
        items = { { value = "Java", text = "Java" }, { value = "Kotlin", text = "Kotlin" }, { value = "Lua", text = "Lua" } } },
      { DropdownMenu, label = "DropdownMenu", initialSelection = "Lua", onChange = "下拉回显",
        items = { { value = "Java", text = "Java" }, { value = "Lua", text = "Lua" } } },
      { Text, text = "Chip 家族（Chip/ActionChip/FilterChip/InputChip）", fontSize = 12, color = "#888888" },
      { Wrap, gap = 8, runSpacing = 8,
        { Chip, text = "Chip", avatar = "home" },
        { ActionChip, text = "ActionChip", avatar = "add", onClick = "btnTap" },
        { FilterChip, text = "FilterChip", selected = true, onChange = "分段回显" },
        { InputChip, text = "InputChip", onDeleted = "btnTap" } },
      { Text, text = "带开关的列表项", fontSize = 12, color = "#888888" },
      { Card, { Column,
        { SwitchListTile, title = "SwitchListTile", subtitle = "带开关的列表项", value = true, onChange = "开关回显" },
        { CheckboxListTile, title = "CheckboxListTile", value = false, onChange = "开关回显" },
        { RadioListTile, title = "RadioListTile", value = "x", groupValue = "x", onChange = "单选回显" } } },
      { Text, id = "choiceEcho", text = "（这里回显上面控件的变化）", fontSize = 12, color = "#3949ab" } },
  })
end }

-- 5) 输入与表单 -------------------------------------------------
DEMOS[#DEMOS + 1] = { "输入与表单", "TextField/Form/SearchBar/日期时间选择", function()
  return shell("输入与表单", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 10,
      { Text, text = "TextField（密码/多行/数字键盘/前缀后缀/计数器）", fontSize = 12, color = "#888888" },
      { TextField, id = "f1", label = "用户名", hint = "请输入", prefixIcon = "person",
        helperText = "会实时回显", onChange = "输入回显" },
      { TextField, id = "f2", label = "密码", obscure = true, suffixIcon = "lock" },
      { TextField, id = "f3", label = "金额（只允许数字）", keyboardType = "number",
        formatter = "number", prefixText = "¥ " },
      { TextField, id = "f4", label = "备注", maxLines = 3, counterText = "最多 3 行",
        filled = true, fillColor = "#f5f5f5" },
      { Text, text = "Form：校验 + 提交", fontSize = 12, color = "#888888" },
      { Form,
        { Column, gap = 8,
          { TextField, id = "f5", label = "邮箱", keyboardType = "emailAddress", errorText = "示例错误提示" },
          { Row, gap = 8,
            { ElevatedButton, text = "提交", onClick = "表单提交" },
            { OutlinedButton, text = "读取输入", onClick = "读取输入" } } } },
      { Text, id = "inputEcho", text = "（输入回显）", fontSize = 12, color = "#3949ab" },
      { Text, text = "SearchBar / 日期选择", fontSize = 12, color = "#888888" },
      { SearchBar, id = "sb2", hint = "搜索点什么…", onChange = "搜索回显" },
      { CalendarDatePicker, initialDate = "2026-10-02", firstDate = "2020-01-01", lastDate = "2030-12-31", onChange = "日期回显" },
      { Row, gap = 8,
        { OutlinedButton, text = "命令式：日期对话框", onClick = "弹日期" },
        { OutlinedButton, text = "命令式：时间对话框", onClick = "弹时间" } },
      { CupertinoDatePicker, mode = "date", onChange = "日期回显" },
      { CupertinoTimerPicker, mode = "hms", onChange = "时间回显" } },
  })
end }

-- 6) 列表与滚动 -------------------------------------------------
DEMOS[#DEMOS + 1] = { "列表与滚动", "ListView/GridView/PageView/Reorderable/Stepper/DataTable/Sliver", function()
  return shell("列表与滚动", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 10,
      { Text, text = "ListView：静态子项 / 模板懒加载（itemCount+itemTemplate）", fontSize = 12, color = "#888888" },
      { Container, height = 150, { ListView, id = "lv2", padding = 6,
          { ListTile, title = { Text, text = "静态项 1" }, subtitle = { Text, text = "直接写子节点" } },
          { ListTile, title = { Text, text = "静态项 2" } } } },
      { Container, height = 150, { ListView, itemCount = 200, gap = 0,
          itemTemplate = { Card, { ListTile, title = { Text, text = "模板项 $index" },
            subtitle = { Text, text = "两万个也能滚得动" } } } } },
      { Row, gap = 8,
        { OutlinedButton, text = "滚到顶", onClick = "lvTop" },
        { OutlinedButton, text = "滚到底", onClick = "lvEnd" },
        { OutlinedButton, text = "当前滚动状态", onClick = "lvState" } },
      { Text, text = "GridView（模板 + 列数）", fontSize = 12, color = "#888888" },
      { Container, height = 160, { GridView, crossAxisCount = 3, gap = 6, itemCount = 12,
          itemTemplate = { Card, { Center, { Text, text = "$index" } } } } },
      { Text, text = "PageView（可翻页，id 可用于 pageTo）", fontSize = 12, color = "#888888" },
      { Container, height = 120, { PageView, id = "pv", onChange = "翻页回显",
          { Center, { Text, text = "第 1 页" } }, { Center, { Text, text = "第 2 页" } }, { Center, { Text, text = "第 3 页" } } } },
      { Row, gap = 8,
        { OutlinedButton, text = "下一页", onClick = "pvNext" },
        { OutlinedButton, text = "回到第 1 页", onClick = "pvFirst" } },
      { Text, text = "下拉刷新 / 可滑动删除 / 长按拖动排序", fontSize = 12, color = "#888888" },
      { Container, height = 120, { RefreshIndicator, onRefresh = "下拉刷新", delay = 600,
          { ListView, padding = 6, { ListTile, title = { Text, text = "下拉试试刷新" } } } } },
      { Dismissible, direction = "endToStart", onDismiss = "滑掉一条",
        { Card, { ListTile, title = { Text, text = "← 往左滑可以删除" } } } },
      { Container, height = 140, { ReorderableListView, itemCount = 4, onReorder = "拖动排序",
          itemTemplate = { Card, { ListTile, title = { Text, text = "长按拖动排序 #$index" } } } } },
      { Text, text = "Stepper / DataTable / ListWheel", fontSize = 12, color = "#888888" },
      { Stepper, currentStep = 1,
        steps = {
          { title = { Text, text = "第一步" }, subtitle = { Text, text = "填资料" }, content = { Text, text = "步骤内容 1" } },
          { title = { Text, text = "第二步" }, content = { Text, text = "步骤内容 2" } } } },
      { DataTable, showBottomBorder = true, headingRowColor = "#e8eaf6",
        columns = { { Text, text = "订单" }, { Text, text = "客户" }, { Text, text = "金额" } },
        rows = {
          { { Text, text = "A1024" }, { Text, text = "王小二" }, { Text, text = "¥128" } },
          { { Text, text = "A1025" }, { Text, text = "李小明" }, { Text, text = "¥66" } } } },
      { Container, height = 120, { ListWheelScrollView, itemExtent = 40, itemCount = 20,
          itemTemplate = { Text, text = "滚轮项 $index", fontSize = 16 } } },
      { Text, text = "Sliver 家族：CustomScrollView + SliverAppBar + SliverList/Grid/ToBoxAdapter/Padding/FillRemaining", fontSize = 12, color = "#888888" },
      { Container, height = 260, {
        CustomScrollView,
        { SliverAppBar, title = { Text, text = "SliverAppBar" }, pinned = true, expandedHeight = 90, floating = true,
          flexibleSpace = { Container, color = "#3949ab" } },
        { SliverToBoxAdapter, { Padding, padding = 10, { Text, text = "SliverToBoxAdapter：任意普通控件" } } },
        { SliverPadding, padding = 10,
          { SliverList, itemCount = 6, itemTemplate = { Card, { ListTile, title = { Text, text = "SliverList 项 $index" } } } } } } },
      { Container, height = 180, {
        CustomScrollView,
        { SliverAppBar, title = { Text, text = "SliverGrid" }, pinned = true },
        { SliverGrid, crossAxisCount = 3, gap = 6, itemCount = 9,
          itemTemplate = { Card, { Center, { Text, text = "$index" } } } },
        { SliverFillRemaining, { Center, { Text, text = "SliverFillRemaining" } } } } },
      { Card, { ExpansionTile, title = { Text, text = "ExpansionTile（可展开/收起，声明式）" },
          expanded = true, initiallyExpanded = true, iconColor = "#1565c0",
          { Padding, padding = 12, { Text, text = "展开后的内容（tile.dart.Expanded = true/false 控制）" } } } },
      { Text, id = "listEcho", text = "（列表交互回显）", fontSize = 12, color = "#3949ab" } },
  })
end }

-- 7) 导航与框架 -------------------------------------------------
DEMOS[#DEMOS + 1] = { "导航与框架", "TabBar/Drawer/BottomNavigationBar/NavigationBar/Rail/BottomAppBar", function()
  return shell("导航与框架", {
    Column,
    { NavigationBar, currentIndex = 0, onChange = "底栏切换",
      items = { { icon = "home", label = "首页" }, { icon = "person", label = "我的" } } },
    { MaterialBanner, leading = { Icon, icon = "info" },
      content = { Text, text = "MaterialBanner：重要提示条" },
      actions = { { TextButton, text = "知道了" } } },
    { CupertinoNavigationBar, title = { Text, text = "CupertinoNavigationBar" },
      leading = { Icon, icon = "arrow_back" } },
    { DefaultTabController, id = "tabs", length = 3, index = 0, onChange = "切页完成",
      { Column,
        { TabBar, noSplash = true, indicatorSize = "label", labelColor = "#1565c0",
          indicator = { color = "#1565c0", weight = 3, radius = 2 },
          tabs = {
            { text = "标签一", icon = "home" },
            { text = "标签二", icon = "search" },
            { text = "标签三", icon = "person" } } },
        { Expanded, { TabBarView,
            { Center, { Text, text = "TabBarView 第 1 页（点标签或左右滑，指示器有动画）" } },
            { Center, { Text, text = "TabBarView 第 2 页" } },
            { Center, { Text, text = "TabBarView 第 3 页" } } } } } },
  }, {
    drawer = { Drawer, width = 260,
      { ListView, padding = 0,
        { UserAccountsDrawerHeader,
          accountName = { Text, text = "AndroLua" },
          accountEmail = { Text, text = "lua@example.com" },
          currentAccountPicture = { CircleAvatar, radius = 24, { Text, text = "L" } },
          backgroundColor = "#3949ab" },
        { ListTile, leading = { Icon, icon = "home" }, title = { Text, text = "菜单项（Drawer）" } },
        { Divider },
        { NavigationDrawer,
          { ListTile, leading = { Icon, icon = "settings" }, title = { Text, text = "NavigationDrawer 项" } } } } },
    bottomNavigationBar = { BottomNavigationBar, currentIndex = 0, selectedItemColor = "#1565c0",
      onChange = "底栏切换",
      items = { { icon = "home", label = "首页" }, { icon = "search", label = "搜索" }, { icon = "person", label = "我的" } } },
    bottomAppBar = { BottomAppBar, elevation = 4,
      { Row, gap = 16, { Text, text = "BottomAppBar" },
        { NavigationRail, currentIndex = 0, labelType = "none", onChange = "侧栏切换",
          items = { { icon = "home" }, { icon = "settings" } } } } },
  })
end }

-- 8) 展示与提示 -------------------------------------------------
DEMOS[#DEMOS + 1] = { "展示与提示", "Card/ListTile/Badge/Tooltip/进度/分隔线/占位", function()
  return shell("展示与提示", {
    ListView, padding = 12,
    { Card, elevation = 3, radius = 12, padding = 14,
      { ListTile,
        leading = { CircleAvatar, radius = 20, color = "#3949ab", { Text, text = "L", color = "#ffffff" } },
        title = { Text, text = "ListTile 标题" },
        subtitle = { Text, text = "副标题 + leading/trailing" },
        trailing = { Badge, label = "3", { Icon, icon = "notifications" } } } },
    { Card, { Column, gap = 10,
      { Text, text = "Badge / Tooltip / Placeholder / Cupertino 转圈", fontSize = 12, color = "#888888" },
      { Row, gap = 20,
        { Badge, label = "9+", offset = { -4, 4 }, { Icon, icon = "mail", size = 26 } },
        { Badge, isLabelVisible = false, backgroundColor = "#43a047", { Icon, icon = "chat", size = 26 } },
        { Tooltip, message = "长按/悬停看到这行提示", { Icon, icon = "help", size = 26 } },
        { Placeholder, width = 70, height = 40 },
        { CupertinoActivityIndicator } } } },
    { Card, { Column, gap = 10,
      { Text, text = "进度条 / 分隔线", fontSize = 12, color = "#888888" },
      { LinearProgressIndicator, value = 0.4, minHeight = 8, radius = 4 },
      { LinearProgressIndicator, minHeight = 4 },
      { Row, gap = 20, { CircularProgressIndicator, value = 0.7, size = 28 }, { CircularProgressIndicator } },
      { Divider, thickness = 1, indent = 0, endIndent = 0 },
      { Row, height = 40, gap = 10, { Text, text = "左" }, { VerticalDivider, width = 1 }, { Text, text = "右" } } } },
    { Text, text = "SnackBar 两种用法：命令式（底部弹出）", fontSize = 12, color = "#888888" },
    { Row, gap = 8,
      { OutlinedButton, text = "弹提示", onClick = "弹提示" },
      { OutlinedButton, text = "弹对话框", onClick = "弹对话框" },
      { OutlinedButton, text = "弹底部弹窗", onClick = "弹底部弹窗" } },
    { SnackBar, behavior = "floating", duration = 2000, actionLabel = "知道了", onTap = "btnTap",
      { Text, text = "这是内联放置的 SnackBar（也可以命令式弹）" } },
  })
end }

-- 9) 弹窗 -------------------------------------------------------
DEMOS[#DEMOS + 1] = { "弹窗", "AlertDialog/SimpleDialog/Dialog/BottomSheet/Cupertino", function()
  return shell("弹窗", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 12,
      { Text, text = "命令式（推荐）：flutterShowDialog / flutterShowSnackBar / flutterShowBottomSheet", fontSize = 12, color = "#888888" },
      { Row, gap = 8,
        { ElevatedButton, text = "对话框", onClick = "弹对话框" },
        { OutlinedButton, text = "底部弹窗", onClick = "弹底部弹窗" },
        { TextButton, text = "提示条", onClick = "弹提示" } },
      { Text, text = "声明式（直接放进树里）", fontSize = 12, color = "#888888" },
      { AlertDialog, title = { Text, text = "AlertDialog" }, icon = { Icon, icon = "info" },
        content = { Text, text = "声明式弹窗内容，actions 放按钮" },
        actions = { { TextButton, text = "取消" }, { TextButton, text = "确定" } },
        shape = "rounded", radius = 14 },
      { SimpleDialog, title = { Text, text = "SimpleDialog" },
        { ListTile, title = { Text, text = "选项一" } },
        { ListTile, title = { Text, text = "选项二" } } },
      { Dialog, { Padding, padding = 20, { Column, gap = 10,
          { Text, text = "Dialog 自定义内容" },
          { TextField, label = "弹窗里的输入框" } } } },
      { BottomSheet, showDragHandle = true, elevation = 8, onClosing = "弹窗关闭",
        { Padding, padding = 16, { Text, text = "BottomSheet（声明式，带拖拽手柄）" } } },
      { CupertinoAlertDialog, title = { Text, text = "CupertinoAlertDialog" },
        content = { Text, text = "iOS 风格弹窗" },
        actions = { { CupertinoButton, text = "好" } } } },
  })
end }

-- 10) 动画 ------------------------------------------------------
DEMOS[#DEMOS + 1] = { "动画", "Animated* 全家桶（duration + curve）", function()
  return shell("动画", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 10,
      { Text, text = "改属性即触发动画（同页演示：点按钮切换状态）", fontSize = 12, color = "#888888" },
      { Row, gap = 8, { OutlinedButton, text = "切换动画状态", onClick = "切动画" } },
      { AnimatedOpacity, opacity = 动画暗, duration = 500, curve = "easeInOut",
        { Container, height = 44, color = "#90caf9", { Center, { Text, text = "AnimatedOpacity" } } } },
      { AnimatedContainer, duration = 400, curve = "easeOut", height = 动画高, radius = 动画圆角,
        backgroundColor = "#a5d6a7", { Center, { Text, text = "AnimatedContainer" } } },
      { AnimatedPadding, duration = 400, padding = 动画内外, color = "#fff59d",
        { Text, text = "AnimatedPadding" } },
      { AnimatedAlign, duration = 400, alignment = 动画对齐, heightFactor = 1,
        { Container, width = 40, height = 30, color = "#ce93d8" } },
      { AnimatedScale, duration = 400, scale = 动画缩放,
        { Container, height = 40, width = 80, color = "#ffab91", { Center, { Text, text = "AnimatedScale" } } } },
      { AnimatedRotation, duration = 400, turns = 动画转动,
        { Icon, icon = "refresh", size = 32 } },
      { AnimatedSlide, duration = 400, offset = 动画位移,
        { Container, height = 36, width = 90, color = "#80cbc4", { Center, { Text, text = "AnimatedSlide" } } } },
      { AnimatedDefaultTextStyle, duration = 400, fontSize = 动画字号,
        color = "#3949ab", fontWeight = "bold", { Text, text = "AnimatedDefaultTextStyle" } },
      { AnimatedSwitcher, duration = 500, curve = "bounceOut",
        { Text, text = "切换计数：" .. tostring(动画计数) } },
      { Container, height = 120, { Stack,
          { AnimatedPositioned, duration = 400, left = 动画左, top = 10,
            { Container, width = 36, height = 36, radius = 18, color = "#f06292" } } } },
      { AnimatedSize, duration = 400, { Container, width = 动画宽, height = 40, color = "#b39ddb" } },
      { AnimatedCrossFade, duration = 400, crossFadeState = 动画交叉,
        firstChild = { Container, height = 40, color = "#4db6ac", { Center, { Text, text = "第一面" } } },
        secondChild = { Container, height = 40, color = "#ffb74d", { Center, { Text, text = "第二面" } } } },
      { AnimatedTheme, duration = 400, colorSchemeSeed = "#1565c0",
        { ElevatedButton, text = "AnimatedTheme", onClick = "切动画" } } },
  })
end }

-- 11) 媒体 / 图表 / 其它 -----------------------------------------
DEMOS[#DEMOS + 1] = { "媒体与图表", "Video/Audio/二维码/地图/图表/手势", function()
  return shell("媒体与图表", {
    SingleChildScrollView, padding = 12,
    { Column, gap = 10,
      { Text, text = "VideoPlayer / AudioPlayer（把 src 换成你自己的路径或链接）", fontSize = 12, color = "#888888" },
      { VideoPlayer, id = "v1", src = "/sdcard/Download/demo.mp4", autoPlay = false, controls = true },
      { Row, gap = 8,
        { OutlinedButton, text = "播放", onClick = "视频播放" },
        { OutlinedButton, text = "暂停", onClick = "视频暂停" },
        { OutlinedButton, text = "状态", onClick = "视频状态" } },
      { AudioPlayer, id = "a1", title = "示例音频", src = "/sdcard/Download/demo.mp3" },
      { QrCode, data = "https://github.com/Zyr76/flutter", size = 140, color = "#1565c0" },
      { Text, text = "FlutterMap（换成你自己的瓦片服务更稳）", fontSize = 12, color = "#888888" },
      { Container, height = 200, radius = 10, { FlutterMap,
          lat = 39.9087, lng = 116.3975, zoom = 12,
          tileUrl = "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
          markers = { { lat = 39.9087, lng = 116.3975, text = "北京" } } } },
      { Text, text = "图表（fl_chart）：series/values/groups", fontSize = 12, color = "#888888" },
      { LineChart, height = 160, series = { { text = "访问量", values = { 12, 30, 22, 45, 38, 60 } } } },
      { BarChart, height = 160, series = { { text = "销量", values = { 8, 16, 12, 20 } } } },
      { Container, height = 160, { PieChart, values = { 35, 25, 20, 20 },
          colors = { "#1565c0", "#43a047", "#fb8c00", "#e53935" } } },
      { Text, text = "手势：InkWell / GestureDetector（点击/长按/双击）", fontSize = 12, color = "#888888" },
      { Row, gap = 8,
        { InkWell, onClick = "btnTap", { Padding, padding = 12, { Text, text = "InkWell（有点击反馈）" } } },
        { GestureDetector, onTap = "btnTap", onLongPress = "长按了", onDoubleTap = "双击了",
          { Container, padding = 12, color = "#e8eaf6", { Text, text = "GestureDetector" } } } },
      { Text, id = "mediaEcho", text = "（媒体/手势回显）", fontSize = 12, color = "#3949ab" } },
  })
end }

-- 12) 属性速查 ---------------------------------------------------
DEMOS[#DEMOS + 1] = { "属性速查", "116 个控件各自支持哪些属性（带搜索）", function()
  return shell("属性速查（搜索控件名或属性名）", {
    Column, padding = 10,
    { SearchBar, id = "sb3", hint = "如：noSplash / TabBar / slider", onChange = "速查搜索" },
    { SizedBox, height = 8 },
    { Expanded, { ListView, table.unpack(速查行()) } },
  })
end }

-- ============================================================
-- 速查过滤 + 事件回显
-- ============================================================
local 速查词 = ""
local 页名 = ""

function 速查行()
  local 行 = {}
  local 词 = 速查词:lower()
  for _, e in ipairs(属性表) do
    if 词 == "" or e[1]:lower():find(词, 1, true) or e[2]:lower():find(词, 1, true) then
      行[#行 + 1] = { Card, margin = 4,
        { ListTile,
          title = { Text, text = e[1], fontSize = 14, fontWeight = "bold" },
          subtitle = { Text, text = e[2], fontSize = 11, color = "#666666" } } }
    end
  end
  if #行 == 0 then
    行[1] = { Padding, padding = 20, { Text, text = "没有匹配的控件/属性", color = "#888888" } }
  end
  return 行
end

local function 回显(文本)
  local 映射 = { ["选择控件"] = "choiceEcho", ["输入与表单"] = "inputEcho",
                 ["列表与滚动"] = "listEcho", ["媒体与图表"] = "mediaEcho" }
  local id = 映射[页名]
  if not id then return end
  local h = _G[id]
  if h then h.dart.Text = 文本 end
end

function 速查搜索(e)
  速查词 = tostring(e.value or "")
  render(DEMOS[#DEMOS][3]())
end

function btnTap() 回显("按钮被点了）") end
function 菜单选择(e) 回显("菜单选择：" .. tostring(e.value)) end
function 开关回显(e) 回显("开关：" .. tostring(e.value)) end
function 单选回显(e) 回显("单选：" .. tostring(e.value)) end
function 滑块回显(e) 回显("滑块：" .. tostring(e.value)) end
function 区间回显(e) 回显("区间：" .. tostring(e.value[1]) .. " ~ " .. tostring(e.value[2])) end
function 分段回显(e) local v = e.value; if type(v) == "table" then v = v[1] end 回显("分段/切片：" .. tostring(v)) end
function 多选回显(e) 回显("多选：" .. tostring(e.value)) end
function 下拉回显(e) 回显("下拉：" .. tostring(e.value)) end
function 输入回显(e) 回显("输入：" .. tostring(e.value)) end
function 搜索回显(e) 回显("搜索：" .. tostring(e.value)) end
function 日期回显(e) 回显("日期：" .. tostring(e.value)) end
function 时间回显(e) 回显("时间：" .. tostring(e.value)) end
function 翻页回显(e) 回显("第 " .. tostring((e.value or 0) + 1) .. " 页") end
function 底栏切换(e) 回显("底栏：" .. tostring(e.value)) end
function 侧栏切换(e) 回显("侧栏：" .. tostring(e.value)) end
function 切页完成(e) end
function 弹窗关闭() 回显("弹窗已关闭") end
function 长按了() 回显("长按了") end
function 双击了() 回显("双击了") end

-- 命令式操作
function 弹提示() flutterShowSnackBar("这是一条命令式提示") end
function 弹对话框() flutterShowDialog{ title = "命令式对话框", { Text, text = "内容由 Lua 传进来" },
  actions = { { TextButton, text = "知道了" } } } end
function 弹底部弹窗() flutterShowBottomSheet{ { Padding, padding = 20, { Text, text = "命令式底部弹窗" } } } end
function 弹日期() flutterDatePicker{ onChange = "日期回显" } end
function 弹时间() flutterTimePicker{ onChange = "时间回显" } end

-- 表单 / 列表 / 翻页 / 媒体控制（都走 dartCall 的 flutterControl）
function 读取输入()
  dartCall("flutterControl", { id = "f1", action = "textState" }, function(res, err)
    回显(err or ("用户名 = " .. tostring(res and res.text)))
  end)
end
function 表单提交()
  回显("表单已提交（示例）")
  flutterShowSnackBar("提交成功")
end
function lvTop() dartCall("flutterControl", { id = "lv2", action = "scrollToStart" }) end
function lvEnd() dartCall("flutterControl", { id = "lv2", action = "scrollToEnd" }) end
function lvState()
  dartCall("flutterControl", { id = "lv2", action = "scrollState" }, function(res, err)
    回显(err or string.format("滚动 %.0f / %.0f", res and res.offset or 0, res and res.max or 0))
  end)
end
function pvNext() dartCall("flutterControl", { id = "pv", action = "nextPage" }) end
function pvFirst() dartCall("flutterControl", { id = "pv", action = "pageTo", index = 0 }) end
function 下拉刷新() 回显("已刷新（" .. os.date("%H:%M:%S") .. "）") end
function 滑掉一条() 回显("滑掉一条（示例）") end
function 拖动排序(e) 回显("拖动排序：" .. tostring(e.value)) end
function 视频播放() dartCall("flutterControl", { id = "v1", action = "play" }) end
function 视频暂停() dartCall("flutterControl", { id = "v1", action = "pause" }) end
function 视频状态()
  dartCall("flutterControl", { id = "v1", action = "state" }, function(res, err)
    回显(err or ("视频：" .. tostring(res and res.isPlaying)))
  end)
end

-- 动画状态（点按钮切换）
动画暗, 动画高, 动画圆角, 动画内外, 动画对齐, 动画缩放, 动画转动, 动画位移, 动画字号, 动画计数, 动画左, 动画宽, 动画交叉 = 1, 44, 6, 6, "center", 1, 0, 0, 14, 0, 10, 90, "first"
function 切动画()
  local 开 = (动画暗 == 1)
  动画暗 = 开 and 0.25 or 1
  动画高 = 开 and 70 or 44
  动画圆角 = 开 and 22 or 6
  动画内外 = 开 and 16 or 6
  动画对齐 = 开 and "centerright" or "center"
  动画缩放 = 开 and 1.25 or 1
  动画转动 = 开 and 0.5 or 0
  动画位移 = 开 and 0.25 or 0
  动画字号 = 开 and 20 or 14
  动画计数 = 动画计数 + 1
  动画左 = 开 and 120 or 10
  动画宽 = 开 and 150 or 90
  动画交叉 = 开 and "second" or "first"
  render(DEMOS[#DEMOS - 1][3]())  -- 倒数第二个是动画页
end

-- ============================================================
-- 菜单 / 路由 / 渲染入口
-- ============================================================
render = function(spec)
  渲染Flutter(spec, host)
end

local function openDemo(i)
  页名 = DEMOS[i][1]
  render(DEMOS[i][3]())
end

local menuRows

local function showMenu()
  页名 = ""
  menuRows = {}
  for i, d in ipairs(DEMOS) do
    menuRows[#menuRows + 1] = { Card, margin = 5, id = "menuRow" .. i,
      { ListTile,
        leading = { Icon, icon = "folder" },
        title = { Text, text = i .. ". " .. d[1] },
        subtitle = { Text, text = d[2], fontSize = 12, color = "#888888" },
        trailing = { Icon, icon = "chevron_right" } } }
  end
  render(shell("Flutter 全组件示例（" .. #DEMOS .. " 页）", {
    ListView, padding = 8, table.unpack(menuRows),
  }))
  for i = 1, #DEMOS do
    local h = _G["menuRow" .. i]
    if h then h.onClick = function() openDemo(i) end end
  end
end

function uiBack() showMenu() end

function onFlutterEvent(e)
  if e and e.name then print("[全组件]", e.name, e.data and e.data.type or "") end
end

activity.setContentView(host)
showMenu()
