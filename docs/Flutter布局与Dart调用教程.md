# AndroLua · Flutter 布局与 Dart 调用教程

本增强版让 **Lua 脚本**同时拥有三种能力，并在同一个 Activity 里同屏使用：

1. **原生 Android UI** —— 沿用 AndroLua 的 `loadlayout{...}`；
2. **Flutter 自绘 UI** —— 用 Lua 表描述 widget 树，交给 Flutter 渲染；
3. **Dart 逻辑层** —— Lua 通过 `dartCall` 调用 Dart 方法并拿返回值，Flutter 控件的事件也能回传 Lua。

三者通过 `FlutterView` 嵌进 `LuaActivity`，原生区与 Flutter 区可以同屏、互发事件。

---

## 1. 快速开始

```lua
-- 最小示例：整屏由 Flutter 画
-- 渲染Flutter 返回一个 Android View（FlutterView），交给 setContentView 显示
activity.setContentView(渲染Flutter{
  列, 间距 = 12, 内边距 = 16,
  { 文本, 文字 = "hello AndroLua + Flutter", 字号 = 22, 加粗 = true },
  { 按钮, 文字 = "点我", 点击 = { call = "ping" } },
})
```

`渲染Flutter` 返回一个 `FlutterView`（一个普通 Android View），所以：

- 想整屏 Flutter：`activity.setContentView(渲染Flutter{...})`
- 想原生 + Flutter 同屏：把 `FlutterView` 塞进原生布局的占位里（见第 6 节）。

> 引擎是**懒创建**的：脚本不用 Flutter 就不会有任何开销。

---

## 2. 布局语法：两种写法都支持

### 2.1 AndroLua 风格（推荐，中文友好）

与 `loadlayout` 一致：**表的第一个元素是控件，其余数字下标项是子控件**，`属性=值` 直接写在表里。

```lua
{
  列,                       -- 控件（可用中文名，也可用 Flutter 原名 Column）
  间距 = 12,                 -- 属性
  内边距 = 16,
  { 文本, 文字 = "标题", 字号 = 20, 加粗 = true },   -- 子控件
  { 按钮, 文字 = "确定", 点击 = { call = "ping" } },
  { 行, 间距 = 8, { 文本, 文字 = "A" }, { 文本, 文字 = "B" } },
}
```

### 2.2 直给 `type` 的写法（等价）

```lua
{ type = "Column", gap = 12, padding = 16,
  children = {
    { type = "Text", text = "标题", fontSize = 20, fontWeight = "bold" },
    { type = "Button", text = "确定", onTap = { call = "ping" } },
  } }
```

两种可以混用；`children` 字段与数字下标子项都会被识别。字符串子节点会被当作 `Text`：

```lua
{ 列, "第一行", "第二行" }         -- 等价于两个 文本
```

---

## 3. 控件速查

| 中文名 | Flutter 原名 | 说明 |
|---|---|---|
| 列 / 行 | Column / Row | 主轴对齐=主轴对齐、交叉轴对齐 |
| 堆叠 | Stack | 子控件用 `定位` 绝对定位 |
| 容器 | Container | 宽/高/内边距/外边距/圆角/颜色/边框 |
| 内边距 | Padding | 内边距 |
| 居中 | Center | 居中 |
| 弹性 | Expanded | 在 行/列 中按 权重 占位 |
| 固定尺寸 / 占位 | SizedBox | 宽/高 |
| 弹簧 | Spacer | 撑开剩余空间 |
| 文本 / 可选文本 | Text / SelectableText | 文字/字号/颜色/加粗/文字对齐/最大行数 |
| 按钮 / 文字按钮 / 填充按钮 / 凸起按钮 | Button / TextButton / FilledButton / ElevatedButton | 文字/点击 |
| 图标按钮 / 悬浮按钮 | IconButton / FloatingActionButton | 图标/点击 |
| 图标 | Icon | 图标/颜色/尺寸 |
| 图片 | Image | 地址 |
| 卡片 | Card | 海拔/颜色/内边距 |
| 列表 / 网格 | ListView / GridView | 列表=children；网格=列数 |
| 流式布局 | Wrap | 间距/行距（自动换行） |
| 对齐容器 | Align | 对齐 |
| 宽高比 | AspectRatio | 宽高比 |
| 圆角裁剪 / 透明 / 安全区 | ClipRRect / Opacity / SafeArea | 圆角 / 不透明度 / 无 |
| 定位 | Positioned | 左/上/右/下（须放在 堆叠 内） |
| 头像 | CircleAvatar | 半径/颜色 |
| 标签 | Chip | 文字 |
| 复选框 / 开关 / 滑块 | Checkbox / Switch / Slider | 值/变化；滑块另有 最小值/最大值 |
| 输入框 | TextField | 提示/变化 |
| 列表项 | ListTile | 左侧/标题/副标题/右侧/点击 |
| 分割线 | Divider | — |
| 进度条 / 圆形进度 | LinearProgressIndicator / CircularProgressIndicator | 值 |
| 原生控件 | AndroidView | 视图类型（Flutter 里嵌 Android 控件） |

图标取自内置表：`home add delete star favorite settings search check close arrow_forward person`（其余回退为通用图标）。

---

## 4. 常用属性（中文 ↔ 规范键）

| 中文 | 规范键 | 备注 |
|---|---|---|
| 文字/文本 | text | |
| 字号 | fontSize | |
| 颜色/背景/背景色 | color | 文本色 / 容器背景色 |
| 加粗 | fontWeight | `加粗=true` → bold |
| 宽 / 高 | width / height | `"充满"`/`"fill"`/`"match_parent"` → 填满；数字为像素；`"自适应"` → 不设 |
| 权重 | weight | 在 行/列 中相当于 Expanded |
| 内边距 / 外边距 | padding / margin | 数字或 `{左,上,右,下}` |
| 圆角 / 半径 | radius | |
| 边框宽 / 边框色 | borderWidth / borderColor | |
| 对齐 | alignment | 居中/左上/右上/左下/右下 |
| 主轴对齐 / 交叉轴对齐 | mainAxisAlignment / crossAxisAlignment | 起始/居中/结束/两端/均匀/拉伸 |
| 文字对齐 | textAlign | 左/居中/右 |
| 间距 / 行距 | gap / runSpacing | |
| 点击 | onTap | 见第 5 节 |
| 变化 | onChange | 输入框/开关/滑块/复选框 |
| 提示 | hint | |
| 图标 | icon | |
| 尺寸 | size | 图标尺寸等 |
| 值 / 最小值 / 最大值 | value / min / max | 开关/滑块/进度 |
| 列数 | crossAxisCount | 网格 |
| 视图类型 | viewType | 原生控件 |

`layout_width` / `layout_height` / `layout_weight` / `layout_gravity` 等 AndroLua 旧键也兼容。

---

## 5. 事件与回调

### 5.1 控件属性里的回调

- **点击**：`点击 = { call="Dart方法名", args={...} }`
  - 会先调用 Dart 方法，再把结果作为事件回传（事件名默认 `onTap`）。
  - 也可 `点击 = "Dart方法名"`（参数为控件属性表）。
  - 只发事件、不调方法：`点击 = { event="自定义事件名" }`。
- **变化**：`变化 = "事件名"` 或 `变化 = { event="事件名", call="Dart方法", args={...} }`。

`call/方法`、`args/参数`、`event/事件` 中英键都认。

### 5.2 接收 Dart → Lua 事件

在脚本里定义：

```lua
function onFlutterEvent(e)      -- 也可写成 function 收到Flutter事件(e)
  -- e.name = 事件名；e.data = 数据（表）
  print(e.name, e.data.value)
end
```

事件数据约定：

- `onTap`（点击按钮）：`{ action=方法名, args=参数, result=Dart返回值 }`
- 输入框/开关/滑块/复选框：`{ value=当前值, result=Dart返回值 }`
- 内嵌原生控件里的按钮点击：`{ text=该原生控件的文案 }`（事件名 `nativeViewClick`）

---

## 6. 原生 + Flutter 同屏

```lua
require "import"
import "android.widget.*"
import "android.view.*"

-- 原生骨架：中间留一个 FrameLayout 给 FlutterView
activity.setContentView(loadlayout{
  LinearLayout, orientation = "vertical",
  { TextView, id = "hint", text = "↑ 原生 TextView" },
  { FrameLayout, id = "flutterHost", layout_width = "fill", layout_height = 0, layout_weight = 1 },
  { Button, id = "nativeBtn", text = "native Button：dartCall" },
})

-- Flutter 区渲染进占位（第二个参数是容器）
渲染Flutter({
  列, 间距 = 10, 内边距 = 16,
  { 文本, 文字 = "↓ Flutter 自绘", 字号 = 20, 加粗 = true },
  { 按钮, 文字 = "Flutter 按钮", 点击 = { call = "add", args = { a = 3, b = 4 } } },
}, flutterHost)

function 收到Flutter事件(e)
  hint.setText("Flutter 事件：" .. tostring(e.name))
end
```

> `flutterRender` / `flutterView` 返回的都是同一个 FlutterView 实例；重复调用 `渲染Flutter` 会更新内容。

---

## 7. 调用 Dart

```lua
-- 同步：直接拿返回值（必须在非主线程，如 thread 里）
thread(function()
  local 用户 = dartCall("getUserInfo", { id = 7 })
  activity.runOnUiThread(function()
    hint.setText("name=" .. tostring(用户.name))
  end)
end)

-- 异步：主线程可安全使用，回调在主线程
调用Dart("getUserInfo", { id = 9 }, function(结果, 错误)
  if 结果 then print(结果.name) else print(错误) end
end)
```

- 函数名：`dartCall` / `调用Dart` / `dartCallAsync` / `异步调用Dart` 都指向同一实现。
- 第三参是函数 → 异步；否则同步。同步在主线程会被拒绝并打印提示（会 ANR），请用 `thread{}` 包起来或改异步。
- 参数是 Lua 表，会转成 JSON 传给 Dart；返回值（Dart 的 Map/List/标量）会还原成 Lua 表/值。
- **内置 Dart 方法**（`flutter_bridge/lib/src/logic.dart`）：`ping`、`getUserInfo`、`add`、`toUpper`、`fib`。
  加新方法在该文件的 `registerDefaultHandlers` 里加一行即可，返回值需可 JSON 序列化。
- 反向：`flutterEvent("事件名", {数据})` 由原生推事件给 Flutter（Dart 侧用 `FlutterBridge.instance.on(名字, 回调)` 监听）。

---

## 8. Android 控件库（MD3 / AndroidX）

已内置 Google Material 3（`com.google.android.material.*`）与常用 AndroidX 控件依赖。用一行引入后，`loadlayout` 里直接写类名：

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

可用范围包括：`MaterialButton / MaterialCardView / TextInputLayout / Chip / TabLayout / FloatingActionButton / AppBarLayout / BottomSheetDialog / Snackbar / MaterialSwitch / MaterialCheckBox / MaterialRadioButton / Slider / BottomNavigationView`，以及 `RecyclerView / ViewPager2 / SwipeRefreshLayout / DrawerLayout / CoordinatorLayout / ConstraintLayout / AppCompat*` 等。

---

## 9. Flutter 里嵌原生控件

```lua
{ 容器, 高 = 130,
  { 原生控件, 视图类型 = "androlua/native", 文字 = "原生控件文案" } }
```

Flutter 用 `AndroidView(viewType)` + Android 侧注册的 `PlatformViewFactory` 创建真正的原生 View（本增强内置 `androlua/native`，里面有一个原生 TextView + Button，点按钮会回传 `nativeViewClick` 事件给 Lua）。

---

## 10. 构建与打包

Flutter 侧是独立模块 `flutter_bridge/`，通过 AAR 接进 app：

```bash
# 本地（aarch64 容器只出 debug）
./build_flutter_aar.sh                 # 等价于 cd flutter_bridge && flutter build aar --debug --no-profile --no-release
# 出 release（需 x86_64 主机 / CI）
cd flutter_bridge && flutter build aar --release --no-debug --no-profile --target-platform android-arm64
```

Android 整包（含原生 CMake + Chaquopy）用 GitHub Actions 出 release APK：`.github/workflows/build-release-apk.yml`。

---

## 11. 限制与注意事项

- **中文标识符**依赖 Lua 词法的 `LUA_UCID`（已在 `app/src/main/cpp/CMakeLists.txt` 打开）。它会**重新编译原生库**才生效。
- `dartCall` 同步版**不能在主线程**调用（Android 需要主线程空闲才能收到 Dart 应答），否则报错并返回 nil。用 `thread{}` 或 `dartCallAsync`。
- 每次事件一般会**整体重绘** Flutter 树（如示例里 `重绘()`），会丢失滚动位置/输入焦点等临时状态；生产项目建议按需局部更新（后续可加 diff/状态层）。
- 目前是**单引擎单 FlutterView**；多屏可用同一 `FlutterEngineGroup` 派生更多引擎（共享快照省内存）。
- 动态 Lua + 动态 dex 与 Flutter release AOT 的合规问题见构建说明；上架需 AOT release + 正式签名 + 提 targetSdk。
