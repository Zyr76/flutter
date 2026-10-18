# AndroLua + Flutter 布局与调用教程

在一个 `LuaActivity` 里同时使用两套 UI：

| 能力 | 入口 | 用的是什么 |
|---|---|---|
| 原生 UI | `loadlayout{ ... }` | Android 控件（`Button`/`TextView`/`FrameLayout`…）|
| Flutter UI | `渲染Flutter(spec [, 容器])` | Flutter 自绘控件（`ElevatedButton`/`Column`/`Text`…）|
| Dart 逻辑 | `调用Dart(name, args, cb)` / `dartCall(...)` / `dartCallAsync(...)` | `flutter_bridge` 里的处理方法 |

原生区与 Flutter 区同屏、可互发事件。

---

## 目录

- [0. 先读：五条规则](#0-先读五条规则)
- [1. 快速上手](#1-快速上手)
- [2. spec 语法](#2-spec-语法)
  - [2.1 节点结构、取值与单位](#21-节点结构取值与单位)
  - [2.2 通用属性](#22-通用属性)
  - [2.3 控件速查](#23-控件速查)
  - [2.4 图片：`src`](#24-图片src)
- [3. 事件](#3-事件)
  - [3.1 三种处理器（都会触发）](#31-三种处理器都会触发)
  - [3.2 id 句柄回调表](#32-id-句柄回调表)
  - [3.3 id 的命名规则](#33-id-的命名规则)
  - [3.4 受控控件：属性是唯一真源](#34-受控控件属性是唯一真源)
- [4. 命令式操作](#4-命令式操作)
  - [4.1 改属性：`id.dart.属性 = 值`](#41-改属性iddart属性--值)
  - [4.2 与 Dart 通信](#42-与-dart-通信)
  - [4.3 弹窗命令](#43-弹窗命令)
  - [4.4 HTTP 请求：`okhttp`](#44-http-请求okhttp)
- [5. 列表](#5-列表)
  - [5.1 懒加载](#51-懒加载)
  - [5.2 列表项里的布局注意](#52-列表项里的布局注意)
- [6. 调试与排错](#6-调试与排错)
  - [6.1 `flutter_debug`：一个开关管全部调试](#61-flutter_debug一个开关管全部调试)
  - [6.2 常见问题](#62-常见问题)

---

## 0. 先读：五条规则

1. **两套控件名不能混用**
   - 原生 `loadlayout` 里必须用 Android 类名（`Button`/`TextView`/`FrameLayout`…，需 `import "android.widget.*"`）。
   - Flutter spec 里必须用 **Flutter 自己的控件名**（`ElevatedButton`/`Column`/`Text`…）。
   - 把 `ElevatedButton` 写进原生 `loadlayout` 会得到 `loadlayout.lua attempt to call a string value` 这类难懂的报错。
2. **控件名没有别名**：写 `Button` 不会变成按钮，要写 `ElevatedButton` / `TextButton` / `FilledButton` / `OutlinedButton`。
3. **动态改属性**：`id.dart.属性 = 值`（属性名大小写不敏感）。
4. **事件会同时投递给三种处理器**：`id.onClick`（句柄）、同名全局函数、`收到Flutter事件`（总监听）**都会触发**，互不打断。
5. **受控控件的属性必须回写**：`NavigationBar` / `BottomNavigationBar` / `TabBar` 的选中项、`SearchBar` 的文本等，用户操作**只发事件不改状态**。回调里不把新值写回属性，界面就不会动（详见 [3.4](#34-受控控件属性是唯一真源)）。

---

## 1. 快速上手

> 仓库里有两份示例，按需看：
> * `flutter示例.lua` —— **控件/语法速查**（每个控件怎么用、两种事件写法、弹窗命令）
> * `flutter应用示例.lua` —— **完整应用骨架**（订单管理：分层组织、页面路由、状态驱动渲染、异步数据、搜索/分页/弹窗）。想知道「怎么把脚本写成应用」直接看这份。
>   它有一个不依赖 Android 的冒烟测试：`lua5.3 tools/lua_smoke_test.lua`

```lua
require "import"
import "android.widget.*"
import "android.view.*"
require "flutter"                      -- 使用 Flutter 渲染必须先导入

-- 原生区：顶部提示 + 底部按钮 + 中间占位
activity.setContentView(loadlayout{
  LinearLayout, orientation = "vertical", backgroundColor = "0xffffffff",
  { TextView, id = "hint", text = "↑ 原生 TextView" },
  { FrameLayout, id = "flutterHost", layout_width = "fill", layout_height = 0, layout_weight = 1 },
  { Button, id = "nativeBtn", text = "原生按钮" },
})

-- Flutter 区：第二个参数是容器，把渲染结果塞进去
渲染Flutter({
  Scaffold,
  backgroundColor = "#FFFFFF",
  appBar = { AppBar, title = { Text, text = "标题" } },
  body = {
    Column, gap = 10, padding = 16,
    { Text, text = "Flutter 自绘文字", fontSize = 20, fontWeight = "bold" },
    { ElevatedButton, text = "点我", id = "btn", width = "fill" },
  },
}, flutterHost)

-- 句柄式事件：点击后改自己的文字
function btn.onClick()
  btn.dart.Text = "已点击"
end

-- 总监听：所有 Flutter 事件都会到这里
function 收到Flutter事件(e)
  hint.setText("Flutter 事件：" .. tostring(e.name))
end
```

> **背景色**：Flutter 区根节点如果不是 `Scaffold`（或没有带 `color` 的 `Container`），会露出引擎的**黑色**默认底色；再叠加浅色主题的深色文字就"看不见"了。**建议根节点用 `Scaffold`**。
>
> **中文标识符**：本项目 Lua 开了中文标识符支持，`渲染Flutter`、`function 按钮.onClick()`、`{ 列, 间距 = 8 }` 这类写法都合法。

---

## 2. spec 语法

### 2.1 节点结构、取值与单位

一个节点就是「控件名 + 属性 + 子节点」：

```lua
{ 控件名, 属性 = 值, 属性 = 值, { 子节点1 }, { 子节点2 } }
```

- **控件名**：Flutter 类名（大小写不敏感）。
- **属性名**：优先用 Flutter 原名；同时兼容少量老别名（`layout_width`→`width`、`gravity`→`alignment`、`onPressed`/`onClick`→`onTap`、`bg`→`backgroundColor`…）。
- **取值与单位**：

| 写法 | 含义 |
|---|---|
| `16` / `"16"` / `"16dp"` / `"16sp"` / `"16px"` | 尺寸（dp 为默认） |
| `"fill"` / `"match"` | 撑满可用空间 |
| `"wrap"` | 包裹内容 |
| `"#RRGGBB"` / `"#AARRGGBB"` / `"0xAARRGGBB"` / `"red"` | 颜色（含命名色）|
| `[1, 2]` | 尺寸对（如 `minimumSize`）、`padding` 的两元素写法 = `[垂直, 水平]` |
| `[1,2,3,4]` → `[上,右,下,左]` | `padding` 四元素写法 |
| 表 | 边框/渐变/阴影/约束等复合属性 |

- 未识别的控件名会**静默降级**（有子节点就按 Column 排、有 text 就渲染文本、否则不占位）；开 `flutter_debug(true)` 会告警。
- 未识别的属性名会被忽略（不改默认值）。

### 2.2 通用属性

任何节点都能用：

| 属性 | 说明 |
|---|---|
| `id` | 生成 Lua 句柄，供 `id.onClick` / `id.dart.X = 值` 使用（支持中文 id，如 `id="按钮"`）|
| `width` / `height` | 尺寸；`"fill"` 撑满 |
| `weight` | 在 Row/Column 中占权重（外层自动包 `Expanded`）|
| `margin` | 外边距（自带 margin 语义的控件如 ListTile/AppBar 会跳过）|
| `padding` | 内边距（容器类控件）|
| `visible` | `false` 时隐藏（`Visibility`）|
| `opacity` | 0~1 透明度 |
| `tooltip` | 长按提示 |
| `onClick` / `onTap` | **通用点击**：任何控件都能写（Card/Container/Text/Row…），不只是按钮 |
| `onLongPress` / `onLongClick` | 通用长按 |
| `child` / `children` | 子节点（单个 / 列表）|

> **`padding` 与 `margin` 的区别**：`padding` 只有容器类控件（`Container`/`Card`/`Column`/`Row`/`ListView`…）才处理；其他控件（如 `Text`）想加外边距请用 `margin`（通用层会给几乎所有节点包一层 Padding）。

### 2.3 控件速查

**文本** `Text`：`text`、`fontSize`、`color`、`fontWeight`（`bold`/`400`/`700`）、`fontStyle`（`italic`）、`decoration`（`underline`/`lineThrough`/`overline`）、`decorationColor`、`decorationStyle`（`solid`/`dashed`/`double`/`dotted`/`wavy`）、`fontFamily`、`fontFamilyFallback`、`shadows`、`letterSpacing`、`wordSpacing`、`height`（行高倍数）、`textAlign`、`textDirection`、`maxLines`、`softWrap`、`overflow`、`textScaleFactor`、`textWidthBasis`、`locale`、`selectionColor`、`semanticsLabel`

**容器/布局**：`Column`/`Row`（`mainAxisAlignment`、`crossAxisAlignment`、`mainAxisSize`、`spacing`/`gap`、`textDirection`、`verticalDirection`）、`Container`（`width`/`height`/`alignment`/`padding`/`margin`/`color`/`radius`/`border`/`borderBottom`/`gradient`/`boxShadow`/`constraints`/`transform`/`foregroundDecoration`/`clip`）、`Stack`（`alignment`/`fit`/`clipBehavior`）、`Wrap`、`Align`、`Center`、`Padding`、`SizedBox`、`Expanded`、`Spacer`、`AspectRatio`、`ClipRRect`、`ClipOval`、`ClipRect`、`Opacity`、`SafeArea`、`Positioned`、`FractionallySizedBox`、`SingleChildScrollView`、`Transform`（`translate=[x,y]`）、`Material`、`DecoratedBox`、`ColoredBox`、`ConstrainedBox`、`IntrinsicWidth`/`IntrinsicHeight`、`FittedBox`、`RotatedBox`、`Offstage`、`Visibility`、`AbsorbPointer`、`IgnorePointer`、`Scrollbar`、`IndexedStack`、`Baseline`、`LimitedBox`

**按钮**：`ElevatedButton` / `TextButton` / `FilledButton` / `OutlinedButton` / `MaterialButton` / `CupertinoButton` / `IconButton` / `FloatingActionButton` / `SegmentedButton` / `ToggleButtons` / `PopupMenuButton`
常用：`text`、`icon`、`enabled`、`tooltip`、`width`、`color`/`backgroundColor`、`foregroundColor`、`elevation`、`radius`、`shape`（`rounded`/`circle`/`stadium`/`beveled`）、`side`（`{color,width,style}`）、`minimumSize`/`fixedSize`/`maximumSize`（`[w,h]`）、`padding`

> 按钮的 `padding` 会被应用**一次**：写在外层（控件属性）就是外部间距，写在 `style = { padding = ... }` 就是按钮内部内边距。

**输入/选择**：`TextField`（`text`、`hint`、`label`、`obscure`/`password`、`maxLines`、`maxLength`、`keyboardType`（`text`/`number`/`phone`/`decimal`/`email`/`url`/`multiline`）、`textInputAction`、`textCapitalization`、`autofocus`、`readOnly`、`enabled`、`prefixIcon`/`suffixIcon`、`filled`/`fillColor`、`border`/`focusedBorder`…、`errorText`、`helperText`、`counterText`、`cursorColor`、`onChange`、`onSubmitted`）、`TextFormField`、`Form`、`Checkbox`、`Switch`、`Slider`、`RangeSlider`、`Radio`、`RadioGroup`、`DropdownButton`、`DropdownButtonFormField`、`DropdownMenu`、`SearchBar`、`CupertinoSwitch`、`CupertinoSlider`、`CupertinoDatePicker`、`CupertinoTimerPicker`

**列表/滚动**：`ListView`（`children` 或 `itemCount` + `itemTemplate` 懒加载）、`GridView`（同上，`crossAxisCount`/`childAspectRatio`）、`ReorderableListView`、`CustomScrollView` + `SliverList`/`SliverGrid`/`SliverToBoxAdapter`/`SliverPadding`/`SliverFillRemaining`/`SliverAppBar`、`PageView`、`ListWheelScrollView`、`Scrollbar`

**信息展示**：`Card`、`ListTile`、`SwitchListTile`、`CheckboxListTile`、`RadioListTile`、`ExpansionTile`、`ExpansionPanelList`、`Chip`/`ActionChip`/`FilterChip`/`ChoiceChip`/`InputChip`、`Tooltip`、`Badge`、`Divider`、`VerticalDivider`、`CircleAvatar`、`RichText`、`SelectableText`、`Table`、`DataTable`、`Stepper`、`Placeholder`、`CircularProgressIndicator`、`LinearProgressIndicator`、`CupertinoActivityIndicator`

**Scaffold 体系**：`Scaffold`（`appBar`/`body`/`drawer`/`endDrawer`/`bottomNavigationBar`/`bottomSheet`/`floatingActionButton`/`floatingActionButtonLocation`/`persistentFooterButtons`…）、`AppBar`（`title`/`leading`/`actions`/`bottom`/`elevation`/`backgroundColor`/`foregroundColor`/`centerTitle`/`toolbarHeight`/`titleSpacing`/`leadingWidth`/`shape`）、`Drawer`、`EndDrawer`、`UserAccountsDrawerHeader`、`BottomNavigationBar`、`NavigationBar`、`NavigationRail`、`NavigationDrawer`、`TabBar`/`TabBarView`/`DefaultTabController`、`BottomAppBar`、`MaterialBanner`、`SnackBar`、`CupertinoNavigationBar`

> `SnackBar` 作为节点写进树里也能弹，但**同一份 `text`/`duration`/`behavior` 在 1.5 秒内只会弹一次**（防重渲染刷屏）。
>
> **`RefreshIndicator`** 的回调既支持声明式 `onRefresh = "函数名"`（推荐），也兼容 `id` 写法。

**弹窗（声明式，可直接放进树里）**：`AlertDialog`、`SimpleDialog`、`Dialog`、`BottomSheet`、`CupertinoAlertDialog`

**动画**：`AnimatedOpacity`、`AnimatedContainer`、`AnimatedAlign`、`AnimatedPadding`、`AnimatedScale`、`AnimatedRotation`、`AnimatedSlide`、`AnimatedSwitcher`、`AnimatedDefaultTextStyle`、`AnimatedCrossFade`、`AnimatedPositioned`、`AnimatedSize`、`AnimatedTheme`（都有 `duration` 毫秒、`curve`）

**插件控件**：`QrCode`/`QrImageView`（qr_flutter）、`FlutterMap`（flutter_map，`center`/`zoom`/`markers`/`polylines`/`polygons`/`circles`/`tileUrl`）、`LineChart`/`BarChart`/`PieChart`（fl_chart，`series` 或 `groups`）

### 2.4 图片：`src`

`src` 一个入口，Dart 自动判断来源：

```lua
{ Image, src = "logo.png" }                              -- 文件名 → 项目目录下的绝对路径
{ Image, src = "https://a.com/a.png" }                   -- 网络
{ Image, src = "/storage/emulated/0/DCIM/a.jpg" }        -- 绝对路径
{ Image, src = "data:image/png;base64,iVBORw0K..." }     -- base64
```

其它属性：`width`/`height`/`fit`（`cover`/`contain`/`fill`/…）、`radius`、`alignment`、`repeat`、`imageColor`、`colorBlendMode`、`filterQuality`、`semanticLabel`。
**加载失败会静默不显示**（不弹占位符）。

---

## 3. 事件

### 3.1 三种处理器（都会触发）

同一个事件会**依次投递**给下面三种处理器，任何一个命中都不影响其他两个：

```lua
-- 1) id 句柄（最常用）
function btn.onClick() ... end

-- 2) 同名全局函数：控件写 onClick = "myHandler"，触发时调用 function myHandler(data) end
渲染Flutter{ SwitchListTile, onChange = "onSwChanged" }
function onSwChanged(data) ... end          -- data.value 是新值

-- 3) 总监听：所有事件都会到这里
function 收到Flutter事件(e)
  print(e.name, e.data)
end
```

事件数据 `e.data` 的常见形态：

- 点击：`{ id = "btn", type = "click" }`
- 值变化：`{ type = "change", value = 新值 }`
- `onClick = { call = "add", args = {a=3,b=4} }`：会调用同名 Dart 方法，结果放进 `e.data.result`

### 3.2 id 句柄回调表

| 句柄写法 | 触发时机 | 事件 `type` |
|---|---|---|
| `h.onClick` / `h.onTap` | 点击 | `click` |
| `h.onChange` / `h.onChanged` | 值变化 | `change` |
| `h.onLongPress` / `h.onLongClick` | 长按 | `longPress` |
| `h.onTapDown` / `h.onTapUp` / `h.onTapCancel` | 按下 / 抬起 / 取消 | `tapDown` / `tapUp` / `tapCancel` |
| `h.onDoubleTap` / `h.onSecondaryTap` | 双击 / 次要点按 | `doubleTap` / `secondaryTap` |
| `h.onHover` / `h.onEnter` / `h.onExit` | 悬停 / 进入 / 离开 | `hover` / `enter` / `exit` |
| `h.onFocusChange` | 焦点变化 | `focusChange` |
| `h.onExpansion` / `h.onExpansionChanged` | 展开收起 | `expansion` |
| `h.onRefresh` | 下拉刷新 | `refresh` |
| `h.onStepContinue` / `h.onStepCancel` | Stepper 下一步 / 上一步 | `stepContinue` / `stepCancel` |

> 未在这些列表里的 `type` 一律按 `click` 处理（保持旧脚本兼容）。

### 3.3 id 的命名规则

- 支持中文（`id="按钮"` → `function 按钮.onClick()`）、下划线、数字（非首位）。
- **Lua 保留字不能作 id**（`end`/`function`/`nil`…）。
- id **不能覆盖已有全局变量**（如 `print`），否则会被跳过。
- 两种被拒绝的情况都可以用 `flutterNode("名字")` 取句柄：

```lua
local b = flutterNode("按钮")
function b.onClick() b.dart.Text = "ok" end
```

### 3.4 受控控件：属性是唯一真源

下面这些控件的**选中项/文本完全由属性决定**，用户操作**只回传事件**，不会自己改状态：

| 控件 | 属性 | 事件 | 不回写的后果 |
|---|---|---|---|
| `NavigationBar` | `currentIndex` | `onTap` | 点了**停在原选项**（无视觉反馈） |
| `BottomNavigationBar` | `currentIndex` | `onTap` | 同上 |
| `DefaultTabController` | `index` | `onChange` | 切页后会被拉回属性值 |
| `SearchBar` | `text` | `onChange` | 输入内容不会被外部覆盖（本地仍可输入） |
| `DropdownButtonFormField` | `value` | `onChange` | 外部改 value 不会反映到界面 |

**回调里必须把新值写回属性**——这是声明式 UI 的基本约定：

```lua
-- 反例：点了没反应（回调是空的）
{ NavigationBar, id = "nav", currentIndex = 0, onTap = "navChanged", items = { ... } }
function navChanged(e) end

-- 正例：把用户选的下标写回属性，界面随之切换
function navChanged(e) nav.dart.CurrentIndex = e.value end
```

> 状态也可以放在你自己的 Lua 表里：`我的状态页 = e.value; 重新渲染()`——只要最终让 spec 里的属性等于用户想要的值即可。

---

## 4. 命令式操作

### 4.1 改属性：`id.dart.属性 = 值`

给控件写 `id`，渲染后即可通过句柄改属性——**只刷新该节点，不重建整棵树**：

```lua
function btn.onClick()
  btn.dart.Text = "你好"            -- 属性名大小写不敏感
  btn.dart.backgroundColor = "#4CAF50"
  btn.dart.fontSize = 22
end
```

- `id.onClick = fn` / `id.onChange = fn` → **事件**（见 3.2）
- `id.dart.<属性> = 值` → **改属性**（推荐写法，与事件彻底分开）
- 旧的 `id.<属性> = 值`（非事件名）仍然兼容。

> 改的是原生侧保存的 spec 副本，Lua 里的表不会变；再次 `渲染Flutter(原表)` 会覆盖这些修改。

### 4.2 与 Dart 通信

```lua
-- 推荐：异步调用。回调在主 Lua 状态里执行，能直接访问 hint 等主脚本全局变量
调用Dart("getUserInfo", { id = 7 }, function(info, err)
  if info then hint.setText("name=" .. tostring(info.name)) else hint.setText("失败：" .. tostring(err)) end
end)

-- 同步形式（会阻塞等应答）只能在非主线程用：
-- thread(function() local info = dartCall("getUserInfo", { id = 7 }) end)
```

内置 Dart 方法：`getUserInfo`、`add`、`toUpper`、`fib`、`now`、`uuid`、`randomInt`、`sleep`、`jsonEncode`/`jsonDecode`、`base64Encode`/`base64Decode`、`login`、`fetchOrders`、`saveProfile`。

> 网络请求**不在** Dart 侧：用 Lua 的 [`okhttp`](#44-http-请求okhttp)（异步、支持 HTTPS）。

> **`thread{}` 是独立的 Lua 状态（新的 LuaState）**：主脚本的全局变量（`hint`、`nativeBtn`、id 句柄…）在那边**全是 nil**，直接访问会报 `attempt to index a nil value`。
> 所以**不要在 thread 里直接操作主脚本的控件**，优先用上面的异步回调。
>
> 事件是**广播**的：同一个 Activity 下主脚本与各 thread/task 的状态都会收到 Flutter 事件（谁定义了处理器谁执行），所以调用过 `thread{}` 后，主脚本里的 `h.onClick` / `收到Flutter事件` 依然照常工作。

### 4.3 弹窗命令

```lua
显示对话框 { AlertDialog, title = {...}, content = {...}, actions = {...} }
显示底部弹窗 { Column, ... }
显示提示 "保存成功"                       -- 也可传表：{ text="...", duration=3000, behavior="floating" }
选择日期 { initialDate = "2026-01-01" }   -- 结果通过 datePicked 事件回传
选择时间 { hour = 9, minute = 30 }        -- 结果通过 timePicked 事件回传
关闭对话框()
```

英文名等价：`flutterShowDialog` / `flutterShowBottomSheet` / `flutterShowSnackBar` / `flutterShowDatePicker` / `flutterShowTimePicker` / `flutterCloseDialog`。

> **`显示对话框` 的 spec 语义**：只给一个子节点时**直接渲染那个节点、不包 `AlertDialog` 外壳**
> （`显示对话框 { { Text, "hi" } }` 得到的是一行文字）；否则数字键的子节点收进 content、其余键当属性。

### 4.4 HTTP 请求：`okhttp`

```lua
local ok = require "okhttp"

ok.get("https://api.example.com/ping", function(res)
  if res.ok then print(res.code, res.body) else print("失败：" .. tostring(res.error)) end
end)

ok.post("https://api.example.com/login", {
  headers = { Authorization = "Bearer xxx" },
  json    = { user = "a", pass = "b" },   -- 自动 JSON 编码
  timeout = 8000,                          -- 毫秒，按请求生效
}, function(res)
  if res.ok and res.code == 200 then print(res.body) end
end)
```

- 后端是 **OkHttp**：异步（不阻塞 UI）、**支持 HTTPS**、连接池、每请求超时。
- **回调在主线程执行**，里面可以安全操作控件。
- 结果表：`ok` / `code` / `body` / `headers`（单值）/ `headersAll`（多值，如多个 `Set-Cookie`）/ `canceled` / `error`；
  `ok.decode(res)` 把 `body` 当 JSON 解析。
- **取消**：`local call = ok.get(url, cb)` 返回句柄，页面退出时 `ok.cancel(call)`；被取消的请求回调会带 `canceled = true`。
- **下载 / 上传**：`ok.download(url, path, cb)`（流式写文件，不整体入内存）、`ok.upload(url, "file", path, cb)`（multipart）。
- **会话**：内置内存 Cookie（按 host 累积），同一进程内跨请求保持登录态；`ok.clearCookies()` 可清空。
- **日志**：`ok.debug(true)` 打印请求/响应日志；默认关闭，关闭时完全静默。
- **限制**：响应体超过 8 MB 会直接返回错误（提示改用 `download`），避免 OOM。
- 方法：`get` / `post` / `put` / `patch` / `delete` / `head` / 通用 `request{...}`。
- 对比：`require "http"`（LuaSocket）是**同步**的、**不支持 https**，只适合明文/局域网；脚本里建议一律用 `okhttp`。

---

## 5. 列表

### 5.1 懒加载

```lua
{ ListView,
  itemCount = 1000,
  itemTemplate = { ListTile, id = "row_$i", title = { Text, text = "第 $index 项" } },
}
```

- 模板里的 `$index` / `$i` 会被替换为下标；`$$` 表示字面 `$`。
- 给了 `itemCount` 却没给 `itemTemplate`/`item` 时按静态 `children` 渲染（开 `flutter_debug` 会告警）。
- 想给滚动位置/输入内容等 State 按行保留，**给每行一个 id**（如上例的 `row_$i`）。

### 5.2 列表项里的布局注意

- **列表项内不要写 `Expanded` / `Spacer`**：列表项的父约束不是 Flex，会直接抛 `Incorrect use of ParentDataWidget`。要占满宽度用 `width = "fill"`。
- **不要写 `Positioned`**，除非该列表项本身就是 `Stack` 的子节点。
- **插入/删除行**：渲染器用行 id 作 `KeyedSubtree` 的 key，插入时行内 State 才不会错位。
- **拖拽排序列表**：纯「template × itemCount」是按下标替换的，重排后行身份无法还原。需要行状态随数据走，请改用**静态 children + 每个子节点写 id**。

---

## 6. 调试与排错

### 6.1 `flutter_debug`：一个开关管全部调试

```lua
require "flutter"
flutter_debug(true)     -- 打开；flutter_debug(false) 关闭
                        -- 中文别名 Flutter调试(true) 同样可用
```

一个开关同时控制两侧（事件调试 + UI 调试）。**唯一的别名是 `Flutter调试`**——`flutterDebug` / `调试Flutter事件` / `flutterUI_debug` 已移除，避免出现“两个开关各控一半”：

| 能力 | 表现 |
|---|---|
| 事件日志 | 每个 Flutter→Lua 事件的 `name` / `type` / 命中情况都打印 |
| 未处理告警 | 事件到了却没人为它写回调时提示，并自动打一次句柄表 |
| 未知控件 | 打印 `[Flutter] 未知控件: xxx`，并回传 `flutterUiIssue`（同类只报一次） |
| 构建失败 | **只坏那一块**：该节点显示红框，其余照常渲染；异常经 `flutterError` 回传 |
| 事件名提示 | 开启时列出可用事件：`flutterUiIssue` / `flutterError` / `renderError` / `dialogError` / `bottomSheetError` |

- **关闭时（默认）：完全静默**——不打渲染/改属性诊断、不打句柄表、不打"没有处理器"提示；未知控件静默降级，构建失败渲染成空（不给终端用户看红框）。
  例外：`flutterError` 事件仍会回传（那是错误，不是调试信息），`flutterHandlers()` 手动调用仍会打印。
- **幂等**：重复开/关不重复打印，也不产生副作用。
- 模块表里同样只有 `debug` 一个入口（`flutter.uiDebug` 已移除）。
- **句柄表**：`flutterHandlers()` 可随时单独打印，输出形如
  `sw2 => onChange(function) | btn => onClick(function)`；**某个 id 显示 `(空)`** = 那个回调没写进去（常见原因：它前面的语句报错，后面的赋值没执行）。
- 也可以直接回读：`print(sw.onChange)` —— 是 `function: 0x...` 说明注册成功，`nil` 说明没写进去。

排查套路：

| 现象 | 含义 |
|---|---|
| 看到事件日志，`handled=true` | 回调已执行 |
| 看到事件日志，`handled=false` + "没有任何处理器" | 事件到了，但没人为它写回调（检查 id 拼写、是否写在 `id.onChange` 上）|
| **什么都没打印** | 事件压根没到原生层（检查是否装了新 APK、控件是否真的触发）|

### 6.2 常见问题

| 现象 | 原因 / 解决 |
|---|---|
| Flutter 区一片黑 / 有控件看不见 | 根节点没背景 → 用 `Scaffold` 或 `{Container, color="#FFFFFF", child={...}}` 包一层 |
| `loadlayout.lua: attempt to call a string value` | 原生布局里写了 Flutter 控件名 → 改用 Android 类名 |
| `attempt to index a nil value (global 'xxx')` | 该 id 未成功生成全局句柄（非法/保留字/被占用）→ 看控制台提示，或改用 `flutterNode("xxx")` |
| `attempt to index a nil value (global 'hint')` | 在 `thread{}` 里访问了主脚本的全局变量 → 改用异步 `调用Dart(..., 回调)` |
| 点击后弹出两段 JSON 文本 | 已修复（patch 的 spec 现在解码后再渲染） |
| 报 `[dartCall] ...` 提示 | 那是提示不是错误，用于说明 id 未绑定或主线程同步调用时的替代方案 |
| 调用过 thread 后 id 回调不触发 | 已修复（事件现在广播给该 Activity 下所有 Lua 状态） |
| 事件"没有反应" | 先确认 APK 是最新的；然后 `flutter_debug(true)`：`handled=true` 说明回调已执行，`handled=false` 说明没人处理，什么都没看到说明事件没到原生侧 |
| 导航栏/底栏/标签页点了不动 | 受控控件没有回写属性 → 见 [3.4](#34-受控控件属性是唯一真源) |
| 列表插入一行后输入框内容错位 | 行没有 id → 给 `itemTemplate` 加 `id="row_$i"` |
| 提示条（SnackBar）每次重渲染都弹 | 已按属性指纹去重（1.5 秒内同一条只弹一次） |
| 设置了属性但没生效 | 检查属性名是否为 Flutter 原名；不认识的 Dart 值会退回默认值 |
| 嵌套过深报错 | 控件树超过 200 层会返回占位，通常意味着构造出了循环引用 |
