# AndroLua + Flutter 布局与调用教程

在同一个 `LuaActivity` 里同时使用：

- **原生 UI**：`loadlayout`（Android 控件）
- **Flutter UI**：`渲染Flutter(spec[, 容器])`（Flutter 自绘控件）
- **Dart 逻辑**：`dartCall(name, args)` / `dartCallAsync(name, args, cb)`

原生区与 Flutter 区同屏、可互发事件。

---

## 0. 四条规则（务必先读）

1. **两套控件名不能混用**
   - 原生 `loadlayout` 里必须用 Android 类名（`Button`/`TextView`/`FrameLayout`…，需 `import "android.widget.*"`）。
   - Flutter spec 里必须用 **Flutter 自己的控件名**（`ElevatedButton`/`Column`/`Text`…）。
   - 把 `ElevatedButton` 写进原生 loadlayout 会得到 `loadlayout.lua attempt to call a string value` 这类难懂的报错。
2. **控件名没有别名**：写 `Button` 不会变成按钮，要写 `ElevatedButton` / `TextButton` / `FilledButton` / `OutlinedButton`。
3. **动态改属性**：`id.dart.属性 = 值`（属性名大小写不敏感）。
4. **事件两种写法都会触发**：`id.onClick`（具体回调）与 `收到Flutter事件`（总监听）**同时**生效，互不打断。

---

## 1. 快速上手

> 仓库里有两份示例，按需看：
> * `flutter示例.lua` —— **控件/语法速查**（每个控件怎么用、两种事件写法、弹窗命令）
> * `flutter应用示例.lua` —— **完整应用骨架**（订单管理：分层组织、页面路由、状态驱动渲染、
>   异步数据、搜索/分页/弹窗）。想知道「怎么把脚本写成应用」直接看这份。
>   它有一个不依赖 Android 的冒烟测试：`lua5.3 tools/lua_smoke_test.lua`

```lua
require "import"
import "android.widget.*"
import "android.view.*"

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

function btn.onClick()
  btn.dart.Text = "已点击"
end

function 收到Flutter事件(e)
  hint.setText("Flutter 事件：" .. tostring(e.name))
end
```

> **背景色**：Flutter 区如果根节点不是 `Scaffold`（或没有带 `color` 的 `Container`），会露出 Flutter 引擎的**黑色**默认底色；再叠加浅色主题的深色文字就"看不见"了。**建议 Flutter 根节点用 `Scaffold`**。

---

## 2. 控件与属性

- 控件名：Flutter 类名（大小写不敏感）。
- 属性名：优先用 Flutter 原名；同时也兼容少量老别名（`layout_width`→`width`、`gravity`→`alignment`、`onPressed`/`onClick`→`onTap`、`bg`→`backgroundColor`…）。
- 单位：`dim`/`inset` 支持 `16`、`"16"`、`"16dp"`、`"16sp"`、`"16px"`、`"fill"`/`"match"`（撑满）。

**通用属性（任何节点都能用）**

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
| `child` / `children` | 子节点（单个 / 列表）|

**文本 `Text`**：`text`、`fontSize`、`color`、`fontWeight`（`bold`/`400`/`700`）、`fontStyle`（`italic`）、`decoration`（`underline`/`lineThrough`/`overline`）、`decorationColor`、`decorationStyle`（`solid`/`dashed`/`double`/`dotted`/`wavy`）、`fontFamily`、`fontFamilyFallback`、`shadows`、`letterSpacing`、`wordSpacing`、`height`（行高倍数）、`textAlign`、`textDirection`、`maxLines`、`softWrap`、`overflow`、`textScaleFactor`、`textWidthBasis`、`locale`、`selectionColor`、`semanticsLabel`

**容器/布局**：`Column`/`Row`（`mainAxisAlignment`、`crossAxisAlignment`、`mainAxisSize`、`spacing`/`gap`、`textDirection`、`verticalDirection`）、`Container`（`width`/`height`/`alignment`/`padding`/`margin`/`color`/`radius`/`border`/`borderBottom`/`gradient`/`boxShadow`/`constraints`/`transform`/`foregroundDecoration`/`clip`）、`Stack`（`alignment`/`fit`/`clipBehavior`）、`Wrap`、`Align`、`Center`、`Padding`、`SizedBox`、`Expanded`、`Spacer`、`AspectRatio`、`ClipRRect`、`ClipOval`、`ClipRect`、`Opacity`、`SafeArea`、`Positioned`、`FractionallySizedBox`、`SingleChildScrollView`、`Transform`（`translate=[x,y]`）、`Material`、`DecoratedBox`、`ColoredBox`、`ConstrainedBox`、`IntrinsicWidth`/`IntrinsicHeight`、`FittedBox`、`RotatedBox`、`Offstage`、`Visibility`、`AbsorbPointer`、`IgnorePointer`、`Scrollbar`、`IndexedStack`、`Baseline`、`LimitedBox`

**按钮**：`ElevatedButton` / `TextButton` / `FilledButton` / `OutlinedButton` / `MaterialButton` / `CupertinoButton` / `IconButton` / `FloatingActionButton` / `SegmentedButton` / `ToggleButtons` / `PopupMenuButton`
常用：`text`、`icon`、`enabled`、`tooltip`、`width`、`color`/`backgroundColor`、`foregroundColor`、`elevation`、`radius`、`shape`（`rounded`/`circle`/`stadium`/`beveled`）、`side`（`{color,width,style}`）、`minimumSize`/`fixedSize`/`maximumSize`（`[w,h]`）、`padding`

**输入/选择**：`TextField`（`text`、`hint`、`label`、`obscure`/`password`、`maxLines`、`maxLength`、`keyboardType`、`textInputAction`、`textCapitalization`、`autofocus`、`readOnly`、`enabled`、`prefixIcon`/`suffixIcon`、`filled`/`fillColor`、`border`/`focusedBorder`…、`errorText`、`helperText`、`counterText`、`cursorColor`、`onChange`、`onSubmitted`）、`TextFormField`、`Form`、`Checkbox`、`Switch`、`Slider`、`RangeSlider`、`Radio`、`RadioGroup`、`DropdownButton`、`DropdownMenu`、`SearchBar`、`CupertinoSwitch`、`CupertinoSlider`、`CupertinoDatePicker`、`CupertinoTimerPicker`

**列表/滚动**：`ListView`（`children` 或 `itemCount` + `itemTemplate` 懒加载）、`GridView`（同上，`crossAxisCount`/`childAspectRatio`）、`ReorderableListView`、`CustomScrollView` + `SliverList`/`SliverGrid`/`SliverToBoxAdapter`/`SliverPadding`/`SliverFillRemaining`/`SliverAppBar`、`PageView`、`ListWheelScrollView`、`Scrollbar`

**信息展示**：`Card`、`ListTile`、`SwitchListTile`、`CheckboxListTile`、`RadioListTile`、`ExpansionTile`、`ExpansionPanelList`、`Chip`/`ActionChip`/`FilterChip`/`ChoiceChip`/`InputChip`、`Tooltip`、`Badge`、`Divider`、`VerticalDivider`、`CircleAvatar`、`RichText`、`SelectableText`、`Table`、`DataTable`、`Stepper`、`Placeholder`、`CircularProgressIndicator`、`LinearProgressIndicator`、`CupertinoActivityIndicator`

**Scaffold 体系**：`Scaffold`（`appBar`/`body`/`drawer`/`endDrawer`/`bottomNavigationBar`/`bottomSheet`/`floatingActionButton`/`floatingActionButtonLocation`/`persistentFooterButtons`…）、`AppBar`（`title`/`leading`/`actions`/`bottom`/`elevation`/`backgroundColor`/`foregroundColor`/`centerTitle`/`toolbarHeight`/`titleSpacing`/`leadingWidth`/`shape`）、`Drawer`、`EndDrawer`、`UserAccountsDrawerHeader`、`BottomNavigationBar`、`NavigationBar`、`NavigationRail`、`NavigationDrawer`、`TabBar`/`TabBarView`/`DefaultTabController`、`BottomAppBar`、`MaterialBanner`、`SnackBar`、`CupertinoNavigationBar`

> **`RefreshIndicator`** 的回调既支持声明式 `onRefresh = "函数名"`（推荐），也兼容 `id` 写法。

> **padding 与 margin 的区别**：`padding` 只有容器类控件（`Container`/`Card`/`Column`/`Row`/`ListView`…）才处理；
> 其他控件（如 `Text`）想加外边距请用 `margin`（通用层会给几乎所有节点包一层 Padding）。

**弹窗（声明式，可直接放进树里）**：`AlertDialog`、`SimpleDialog`、`Dialog`、`BottomSheet`、`CupertinoAlertDialog`

**动画**：`AnimatedOpacity`、`AnimatedContainer`、`AnimatedAlign`、`AnimatedPadding`、`AnimatedScale`、`AnimatedRotation`、`AnimatedSlide`、`AnimatedSwitcher`、`AnimatedDefaultTextStyle`、`AnimatedCrossFade`、`AnimatedPositioned`、`AnimatedSize`、`AnimatedTheme`（都有 `duration` 毫秒、`curve`）

**插件控件**：`QrCode`/`QrImageView`（qr_flutter）、`FlutterMap`（flutter_map，`center`/`zoom`/`markers`/`polylines`/`polygons`/`circles`/`tileUrl`）、`LineChart`/`BarChart`/`PieChart`（fl_chart，`series` 或 `groups`）、`VideoPlayer`、`AudioPlayer`

**原生/混合**：`AndroidView`（`viewType`，Flutter 里嵌 Android 原生控件）

---

## 3. 动态改属性：`id.dart.属性 = 值`

给控件写 `id`，渲染后即可通过句柄改属性——**只刷新该节点，不重建整棵树**：

```lua
function btn.onClick()
  btn.dart.Text = "你好"            -- 属性名大小写不敏感
  btn.dart.backgroundColor = "#4CAF50"
  btn.dart.fontSize = 22
end
```

- `id.onClick = fn` / `id.onChange = fn` → **事件**
- `id.dart.<属性> = 值` → **改属性**（推荐写法，与事件彻底分开）
- 旧的 `id.<属性> = 值`（非事件名）仍然兼容。

> 改的是原生侧保存的 spec 副本，Lua 里的表不会变；再次 `渲染Flutter(原表)` 会覆盖这些修改。

---

## 4. 事件

两种写法，任选（也可同时用，**两个都会触发**）：

```lua
-- A) 句柄式：控件写 id
--    function btn.onClick() ... end / function sw.onChange(v) ... end
-- B) 声明式：控件里直接写回调名（不依赖 id 句柄）
--    渲染Flutter{ SwitchListTile, onChange = "onSwChanged" }
--    function onSwChanged(data) ... end   -- data.value 是新值
```

三种处理器**都会**被触发（不再互相屏蔽）：

```lua
-- 1) id 句柄（最常用）
function btn.onClick() ... end

-- 2) 同名全局函数：控件写 onClick = "myHandler"，点击时调用 function myHandler(data) end
-- 3) 总监听：所有事件都会到这里
function 收到Flutter事件(e)
  print(e.name, e.data)
end
```

- 点击按钮：事件名 = `id`（用 id 句柄时）。`e.data` 形如 `{id=..., type="click"}`。
- 开关/复选/滑动变化：`type="change"`，`e.data.value` 是新值。
- `onClick = { call = "add", args = {a=3,b=4} }` 形式会调用 Dart 方法并把结果放进 `e.data.result`。

---

## 5. 图片：`src`

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

## 6. 弹窗命令（命令式）

```lua
显示对话框 { AlertDialog, title = {...}, content = {...}, actions = {...} }
显示底部弹窗 { Column, ... }
显示提示 "保存成功"                       -- 也可传表：{ text="...", duration=3000, behavior="floating" }
选择日期 { initialDate = "2026-01-01" }   -- 结果通过 datePicked 事件回传
选择时间 { hour = 9, minute = 30 }        -- 结果通过 timePicked 事件回传
关闭对话框()
```

英文名等价：`flutterShowDialog` / `flutterShowBottomSheet` / `flutterShowSnackBar` / `flutterShowDatePicker` / `flutterShowTimePicker` / `flutterCloseDialog`。

## 6.5 事件调试

```lua
flutterDebug(true)    -- 打开后每个事件都打印：name / type / handled / 状态数
flutterHandlers()     -- 打印 __flutter_handlers 里已注册的 id 与回调
```

`flutterHandlers()` 输出形如 `sw2 => onChange(function) | btn => onClick(function)；`
**某个 id 显示 `(空)`** = 那个回调压根没写进去（常见原因：它前面的语句报错，后面的赋值没执行）。

输出形如 `[Flutter] 事件 name=sw type=change handled=true states=1`。
`handled=false` 且控制台还会额外提示“没有任何处理器”，说明事件到了但没人为它写回调（检查 id 拼写、是否写在 `id.onChange` 上）。
**什么都没打印** = 事件压根没到原生层（检查是否装了新 APK、控件是否真的触发）。

另外可以随时回读句柄上的回调：`print(sw.onChange)`，是 `function: ...` 说明注册成功。

---

## 7. 与 Dart 通信

```lua
-- 推荐：异步调用。回调在主 Lua 状态里执行，能直接访问 hint 等主脚本全局变量
调用Dart("getUserInfo", { id = 7 }, function(info, err)
  if info then hint.setText("name=" .. tostring(info.name)) else hint.setText("失败：" .. tostring(err)) end
end)

-- 同步形式（会阻塞等应答）只能在非主线程用：
-- thread(function() local info = dartCall("getUserInfo", { id = 7 }) end)
```

> **`thread{}` 是独立的 Lua 状态（新的 LuaState）**：主脚本的全局变量（`hint`、`nativeBtn`、id 句柄…）在那边**全是 nil**，
> 直接访问会报 `attempt to index a nil value`。所以：**不要在 thread 里直接操作主脚本的控件**，优先用上面的异步回调。
>
> 事件是**广播**的：同一个 Activity 下主脚本与各 thread/task 的状态都会收到 Flutter 事件（谁定义了处理器谁执行），
> 所以即使调用过 `thread{}`，主脚本里的 `h.onClick` / `收到Flutter事件` 依然照常工作。

内置 Dart 方法：`getUserInfo`、`add`、`toUpper`、`fib`、`now`、`uuid`、`randomInt`、`sleep`、`jsonEncode`/`jsonDecode`、`base64Encode`/`base64Decode`、`httpGet`/`httpPost`、`login`、`fetchOrders`、`saveProfile`。

---

## 8. 列表懒加载

```lua
{ ListView,
  itemCount = 1000,
  itemTemplate = { ListTile, title = { Text, text = "第 $index 项" } },  -- $index / $i
}
```

---

## 9. 同一节点可被"具体回调"与"总监听"同时收到；`id` 需是合法 Lua 标识符

- `id` 支持中文（如 `id="按钮"` → `function 按钮.onClick()`），也支持 `_` 与数字（非首位）。
- Lua 保留字（`end`/`function`/`nil`…）不能作 id；会提示改用 `flutterNode("名字")` 取句柄。
- 若 id 会覆盖已有全局变量（如 `print`），会被跳过并提示，可用 `flutterNode("名字")` 取句柄。

---

## 10. 常见问题

| 现象 | 原因 / 解决 |
|---|---|
| 点击后弹出两段 JSON 文本 | 已修复（patch 的 spec 现在是解码后再渲染） |
| Flutter 区一片黑 / 有控件看不见 | 根节点没背景 → 用 `Scaffold` 或 `{Container, color="#FFFFFF", child={...}}` 包一层 |
| `loadlayout.lua: attempt to call a string value` | 原生布局里写了 Flutter 控件名 → 改用 Android 类名 |
| `attempt to index a nil value (global 'xxx')` | 该 id 未成功生成全局句柄（非法/保留字/被占用）→ 看控制台提示，或改用 `flutterNode("xxx")` |
| 报 `[dartCall] ...` 提示 | 那是提示不是错误，用于说明 id 未绑定或主线程同步调用的替代方案 |
| 事件“没有反应” | 先确认 APK 是最新的；然后 `flutterDebug(true)` 打开事件日志：看到 `handled=true` 说明回调已执行；看到 `handled=false` 说明事件到了但没人处理；什么都没看到说明事件没到原生侧 |
| 想看 id 回调到底注册上没有 | `print(sw.onChange)` —— 是 `function: 0x...` 说明注册成功，`nil` 说明没写进去 |
| `attempt to index a nil value (global 'hint')` | 在 `thread{}` 里访问了主脚本的全局变量——thread 是独立 Lua 状态。改用异步 `调用Dart(..., 回调)` |
| 调用过 thread 后 id 回调不触发 | 已修复（事件现在广播给该 Activity 下所有 Lua 状态）|
| 设置了属性但没生效 | 检查属性名是否为 Flutter 原名；不认识的 Dart 值会退回默认值 |
| 嵌套过深报错 | 控件树超过 200 层会返回占位，通常意味着构造出了循环引用 |
