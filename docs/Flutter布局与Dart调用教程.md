# AndroLua · Flutter 布局与 Dart 调用教程

本增强版让 **Lua 脚本**在同一个 Activity 里同时拥有三种能力：

1. **原生 Android UI** —— 沿用 AndroLua 的 `loadlayout{...}`；
2. **Flutter 自绘 UI** —— 用 Lua 表描述 widget 树，交给 Flutter 渲染；
3. **Dart 逻辑层** —— Lua 通过 `dartCall` 调用 Dart 方法并拿返回值，Flutter 控件事件也能回传 Lua。

> 设计取向：**布局用 Flutter 那套英文控件名/属性名**（`Column`/`Text`/`text`/`fontSize`…），
> **渲染入口用中文名** `渲染Flutter`（`flutterRender` 的中文别名）。

---

## 1. 快速开始

```lua
-- 渲染Flutter 返回一个 Android View（FlutterView），交给 setContentView 显示
activity.setContentView(渲染Flutter{
  Column, gap = 12, padding = 16,
  { Text, text = "hello AndroLua + Flutter", fontSize = 22, fontWeight = "bold" },
  { Button, text = "点我", onClick = { call = "ping" } },
})
```

- 整屏 Flutter：`activity.setContentView(渲染Flutter{...})`
- 原生 + Flutter 同屏：把返回的 FlutterView 塞进原生布局的占位里（见第 6 节）。
- 引擎**懒创建**：脚本不用 Flutter 就没有任何开销。
- 渲染入口的可用名：`渲染Flutter` / `加载Flutter布局` / `Flutter布局` / `flutterRender`（等价）。

---

## 2. 布局语法（AndroLua 表风格）

**表的第一个元素是控件，其余数字下标项是子控件**，`属性 = 值` 直接写在表里：

```lua
{
  Column,                    -- 控件名（Flutter 名字）
  gap = 12, padding = 16,    -- 属性
  { Text, text = "标题", fontSize = 20, fontWeight = "bold" },   -- 子控件
  { Button, text = "确定", onClick = { call = "ping" } },
  { Row, gap = 8, { Text, text = "A" }, { Text, text = "B" } },
}
```

也支持直给 `type` 的写法（等价，可混用）：

```lua
{ type = "Column", gap = 12, children = {
    { type = "Text", text = "标题" },
    { type = "Button", text = "确定", onTap = "ping" } } }
```

字符串子节点会被当作 `Text`：`{ Column, "第一行", "第二行" }`。

> 控件名是「兜底全局」：仅当该名字未被定义时才解析为 Flutter 控件名。若脚本
> `import "android.widget.*"` 导入了同名 Android 类（`Button`/`Switch`/`ListView`/`GridView` 等），
> 则同名标识符会解析为那个类，**原生 loadlayout 依旧可用**；Flutter 布局写 `Button` 也会自动映射到 Flutter 的 `Button`。

---

## 3. 控件一览（Flutter 名字）

| 控件 | 说明 |
|---|---|
| `Column` / `Row` | 主轴对齐 mainAxisAlignment、交叉轴对齐 crossAxisAlignment、间距 gap |
| `Stack` | 子控件用 `Positioned` 绝对定位 |
| `Container` | width/height/padding/margin/radius/color/borderWidth/borderColor/alignment |
| `Padding` / `Center` / `Align` / `SafeArea` | 单子节点布局 |
| `Expanded` / `Spacer` | 在 Row/Column 中按 flex 占位 |
| `SizedBox` | width/height |
| `Text` / `SelectableText` | text/fontSize/color/fontWeight/textAlign/maxLines |
| `Button` / `TextButton` / `FilledButton` / `ElevatedButton` | text/onTap |
| `IconButton` / `FloatingActionButton` | icon/onTap |
| `Icon` | icon/color/size（内置：home add delete star favorite settings search check close arrow_forward person） |
| `Image` | url |
| `Card` | elevation/color/padding |
| `ListView` / `GridView` | 列表=children；网格=crossAxisCount/gap |
| `Wrap` | gap/runSpacing（自动换行） |
| `AspectRatio` / `ClipRRect` / `Opacity` | aspectRatio / radius / opacity |
| `Positioned` | left/top/right/bottom/width/height（放在 Stack 内） |
| `CircleAvatar` | radius/color |
| `Chip` | text |
| `Checkbox` / `Switch` / `Slider` | value/onChange；滑块另有 min/max |
| `TextField` | hint/label/onChange |
| `ListTile` | leading/title/subtitle/trailing/onTap |
| `Divider` | — |
| `LinearProgressIndicator` / `CircularProgressIndicator` | value |
| `AndroidView` | viewType（Flutter 里嵌 Android 控件） |
| `OutlinedButton` | 描边按钮 |
| `Scaffold` | 页面骨架（槽：appBar/body/drawer/endDrawer/bottomNavigationBar/floatingActionButton/backgroundColor） |
| `AppBar` | 顶栏（title/leading/actions/elevation/backgroundColor/foregroundColor/centerTitle） |
| `Drawer` / `UserAccountsDrawerHeader` | 抽屉 / 账户头部（accountName/accountEmail/currentAccountPicture/decoration） |
| `BottomNavigationBar` | 底部导航（items=列表；有状态、点选即时生效） |
| `TabBar` / `TabBarView` / `DefaultTabController` | 标签页（tabs=列表，DefaultTabController 提供 length） |
| `SingleChildScrollView` | 可滚动容器（scrollDirection/physics） |
| `InkWell` / `GestureDetector` | 点击响应（onTap/onPressed） |
| `Transform` | 位移变换（translate = {dx, dy}） |
| `FractionallySizedBox` | 按比例占位（widthFactor/heightFactor） |
| `DropdownButton` / `DropdownButtonFormField` | 下拉选择（items/value，有状态） |
| `QrCode` / `QrImage` | 二维码（data/size/color/background） |
| `FlutterMap`（别名 `Map`） | 地图（center={lat,lng}/zoom/markers/tileUrl，默认 OSM 瓦片、无需 Key） |
| `Chart` / `LineChart` / `BarChart` / `PieChart` | 图表（chartType + series，fl_chart） |
| `VideoPlayer`（别名 `Video`） | 视频播放（url/autoPlay/loop/controls，video_player） |
| `AudioPlayer`（别名 `Audio`） | 音频播放（url/title/autoPlay，just_audio，带进度条） |

**统一属性处理器 [Props]**：所有控件都经它读取属性——负责归一化（规范化节点 / AndroLua 表风格）、别名（`onPressed`=`onTap`、`layout_width`=`width`、`gravity`=`alignment`…）、类型转换（颜色/尺寸/边距/对齐/渐变/边框/图标…）与类型化读取（`p.n('gap')`/`p.color('color')`/`p.inset('padding')`）。加新控件时只需在 `renderer.dart` 加一个 case。

**列表（ListView.builder 懒加载）**：
```lua
-- 模板式懒加载：itemTemplate 里的 $index 会替换为下标，按需构建
渲染Flutter{ ListView, itemCount = 1000, itemTemplate =
  { ListTile, title = { Text, text = "第 $index 项" } } }
-- 或直接给 children（也走 builder）
渲染Flutter{ ListView, children = { { Text, text="A" }, { Text, text="B" } } }
```

**Dart 逻辑层**（`flutter_bridge/lib/src/logic.dart`，可自行加）：`ping` `echo` `getUserInfo` `add` `toUpper` `fib` `openDrawer` `closeDrawer` `now` `uuid` `randomInt` `sleep` `jsonEncode` `jsonDecode` `base64Encode` `base64Decode` `httpGet` `httpPost` `login` `fetchOrders` `saveProfile`。handler 可返回 `Future`（经 `dartCall` 自动 await；`onTap` 这类 UI 回调不等异步）。


- `child` 与 `children`、位置子项等价；`appBar`/`body`/`drawer`/`bottomNavigationBar`/`leading`/`title`/`actions`/`items`/`tabs`/`currentAccountPicture` 等插槽自动解析（给 widget 描述就用它，给字符串当 `Text`/`Icon`）。
- `decoration` 支持 `color`/`radius`/`border`/`borderBottom`/`gradient`/`boxShadow`；`style`（按钮背景色/前景色/内边距/高度/圆角）；`onPressed`=`onTap`；`physics`；`shadowColor`。
- **容错**：单个节点构建失败只会在该处显示一行红色提示，不会整屏白；未识别的控件优雅降级（有子项当 `Column`，否则当 `Text`，再无则忽略）。
- **可扩展**：Dart 里 `Renderer.register('MyWidget', (props) => ...)` 可注册自定义/第三方控件。

> `Checkbox` / `Switch` / `Slider` / `TextField` 是**有状态**控件：点击/拖动即时生效并带动效，
> 整页重绘时也会保留选中值/拖动值/输入内容（相同位置会复用状态；需要稳定身份时给控件加 `id`）。

---

## 4. 属性与取值

规范键即 Flutter 属性名；兼容一批 AndroLua 惯用别名：

| 规范键 | 兼容别名 | 备注 |
|---|---|---|
| width / height | layout_width / layout_height | `"fill"`/`"match_parent"` → 填满；数字=像素；不写=自适应 |
| weight | layout_weight / flex | 在 Row/Column 里相当于 Expanded |
| padding / margin | layout_padding / layout_margin | 数字或 `{左,上,右,下}` |
| alignment | layout_gravity / gravity / align | `"center"`/`"topleft"`/`"topright"`/`"bottomleft"`/`"bottomright"` |
| onTap | onClick / click | 见第 5 节 |
| onChange | onChanged | |
| gap | spacing | Row/Column/Wrap/GridView 的间距 |
| radius | borderRadius / cornerRadius | |
| text | value | |
| fontWeight | bold / strong | `bold = true` → `"bold"` |
| backgroundColor | bg | |

其余（`fontSize` `color` `elevation` `opacity` `aspectRatio` `crossAxisCount` `min` `max`
`hint` `label` `icon` `size` `title` `subtitle` `leading` `trailing` `left` `top` `right`
`bottom` `runSpacing` `viewType` `textAlign` `mainAxisAlignment` `crossAxisAlignment` `mainAxisSize` 等）直接写。

---

## 5. 事件与回调

### 5.1 控件属性里的回调（AndroLua 风格）

- **点击**：
  - `onClick = "hello"` —— 只发事件，**事件名就是 `hello`**；
  - `onClick = { call = "getUserInfo", args = { ... } }` —— 调 Dart 方法，**事件名默认 = 方法名**（用 `event`/`事件` 可显式覆盖）；
  - `onClick = { event = "custom" }` —— 只发指定事件名。
- **变化**：`onChange = "事件名"` 或 `onChange = { call = "Dart方法", args = { ... } }`（事件名默认 = 方法名）。

### 5.2 接收事件（两种风格任选）

**A. 同名 Lua 函数（最像 AndroLua，最简洁）**：

```lua
function hello(data)
  print("按钮被点击了", data and data.action)
end
渲染Flutter{ ElevatedButton, onClick = "hello", child = { Text, text = "点我" } }
```

**B. 统一入口 onFlutterEvent / 收到Flutter事件**（优先级高于 A）：

```lua
function onFlutterEvent(e)
  -- e.name 事件名；e.data 数据
  print(e.name, e.data and e.data.action)
end
```

> 若定义了 `onFlutterEvent`，则它优先；否则按事件名找**同名全局 Lua 函数**并调用（参数为 `data`）。

事件数据：

- 点击按钮：`{ action = 方法名, args = 参数, result = Dart返回值 }`
- 输入框 / 开关 / 滑块 / 复选框：`{ value = 当前值, result = Dart返回值 }`
- 内嵌原生控件里的按钮点击：`{ text = 该原生控件的文案 }`（事件名 `nativeViewClick`）

---

## 6. 原生 + Flutter 同屏

```lua
require "import"
import "android.widget.*"
import "android.view.*"

activity.setContentView(loadlayout{
  LinearLayout, orientation = "vertical",
  { TextView, id = "hint", text = "↑ 原生 TextView" },
  { FrameLayout, id = "flutterHost", layout_width = "fill", layout_height = 0, layout_weight = 1 },
  { Button, id = "nativeBtn", text = "native Button：dartCall" },
})

-- 第二个参数是容器：把渲染结果塞进占位
渲染Flutter({
  Column, gap = 10, padding = 16,
  { Text, text = "↓ Flutter 自绘", fontSize = 20, fontWeight = "bold" },
  { Button, text = "Flutter 按钮", onClick = { call = "add", args = { a = 3, b = 4 } } },
}, flutterHost)

function 收到Flutter事件(e)
  hint.setText("Flutter 事件：" .. tostring(e.name))
end
```

> `flutterRender` / `flutterView` 返回同一个 FlutterView 实例；重复调用 `渲染Flutter` 会更新内容。

---

## 7. 调用 Dart

```lua
-- 同步：直接拿返回值（必须在非主线程，如 thread 里）
thread(function()
  local u = dartCall("getUserInfo", { id = 7 })
  activity.runOnUiThread(function()
    hint.setText("name=" .. tostring(u.name))
  end)
end)

-- 异步：主线程可安全用，回调在主线程
调用Dart("getUserInfo", { id = 9 }, function(res, err)
  if res then print(res.name) else print(err) end
end)
```

- 函数名：`dartCall` / `调用Dart` / `dartCallAsync` / `异步调用Dart` 等价。
- **第三参是函数 → 异步；否则同步**。同步在主线程会被拒绝并打印提示（会 ANR），请用 `thread{}` 或改异步。
- 参数 Lua 表 → JSON 传给 Dart；Dart 返回的 Map/List/标量 → 还原成 Lua 表/值。
- **内置 Dart 方法**（`flutter_bridge/lib/src/logic.dart`）：`ping`、`getUserInfo`、`add`、`toUpper`、`fib`。
  加新方法就在 `registerDefaultHandlers` 里加一行，返回值需可 JSON 序列化。
- 反向推送：`flutterEvent("事件名", { 数据 })` 由原生推给 Flutter（Dart 侧用 `FlutterBridge.instance.on(名字, 回调)` 监听）。

---

## 8. Android 控件库（MD3 / AndroidX）

内置 Google Material 3 与常用 AndroidX 依赖。一行引入后，`loadlayout` 里直接写类名：

```lua
require "材料设计"     -- 或 require "md3"

activity.setContentView(loadlayout{
  LinearLayout, orientation = "vertical", padding = "16dp",
  { MaterialButton, text = "MD3 按钮" },
  { TextInputLayout, { TextInputEditText, hint = "MD3 输入框" } },
  { MaterialCardView, layout_width = "fill", { TextView, text = "MD3 卡片" } },
  { RecyclerView, layout_width = "fill", layout_height = 0, layout_weight = 1 },
})
```

可用：`MaterialButton / MaterialCardView / TextInputLayout / Chip / TabLayout / FloatingActionButton /
AppBarLayout / BottomSheetDialog / Snackbar / MaterialSwitch / MaterialCheckBox / MaterialRadioButton /
Slider / BottomNavigationView`，以及 `RecyclerView / ViewPager2 / SwipeRefreshLayout / DrawerLayout /
CoordinatorLayout / ConstraintLayout / AppCompat*` 等。

---

## 9. Flutter 里嵌原生控件

```lua
{ Container, height = 130,
  { AndroidView, viewType = "androlua/native", text = "原生控件文案" } }
```

Flutter 用 `AndroidView(viewType)` + Android 侧注册的 `PlatformViewFactory` 创建真正的原生 View
（内置 `androlua/native`：一个原生 TextView + Button，点按钮回传 `nativeViewClick` 事件给 Lua）。

---

## 10. 构建与打包

Flutter 侧是独立模块 `flutter_bridge/`，通过 AAR 接进 app：

```bash
# 本地（aarch64 容器只出 debug）
./build_flutter_aar.sh    # = cd flutter_bridge && flutter build aar --debug --no-profile --no-release
# 出 release（需 x86_64 主机 / CI）
cd flutter_bridge && flutter build aar --release --no-debug --no-profile --target-platform android-arm64
```

Android 整包（原生 CMake + Chaquopy）用 GitHub Actions 出 release APK：`.github/workflows/build-release-apk.yml`。

---

## 11. 限制与注意事项

- **“自适应”的上限**：Flutter 的 release(AOT) **没有反射**（`dart:mirrors` 不支持 AOT），无法凭字符串创建任意 Flutter 控件；渲染器能覆盖的是**注册过的控件名**（目前为 Material 常用控件），其余会容错降级。要加新控件：Dart 里 `Renderer.register(...)`，或在 `renderer.dart` 加一个 case。
- `渲染Flutter` 是中文标识符，依赖 Lua 词法的 `LUA_UCID`（已在 `app/src/main/cpp/CMakeLists.txt` 打开），
  会重编原生库生效。若不想用中文入口，直接用 `flutterRender` 即可。
- `Checkbox` / `Switch` / `Slider` 为有状态控件，交互与动效正常；列表/表单里建议给稳定 `id`。
- 事件后会按你的脚本决定是否整体 `渲染Flutter(page())` 重绘；重绘会保留交互控件的内部状态，
  但若树结构大幅变化，建议改为局部更新。
- 目前是**单引擎单 FlutterView**；多屏可用同一 `FlutterEngineGroup` 派生更多引擎（共享快照省内存）。
- `dartCall` 同步版不能在主线程调用（会 ANR），用 `thread{}` 或异步。
- 动态 Lua + 动态 dex 与 Flutter release AOT 的合规：上架需 AOT release + 正式签名 + 提 targetSdk。
