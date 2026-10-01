# AndroLua 插件化 Demo —— 加载外部 dex 里的 Fragment 页面

宿主用 AndroLua 写，外部一个 `plugin.dex` 里放 Java 写的 UI（Fragment）。
Lua 端一句话就能把这个页面拉起来，**页面在独立 Task 里打开（类似微信小程序）**，
还能带着字符串 / 数字 / 布尔参数。

---

## 一、整体思路

Android 的 Activity/Service 必须静态注册在 Manifest，外部 dex 无法新增组件。
所以采用「**代理 Activity + 插件 Fragment**」模型：

```
  Lua 脚本
    │  ① 构造 Intent（dex 路径 / Fragment 类名 / 业务参数）
    ▼
  宿主已注册的唯一组件：com.androlua.plugin.ProxyActivity
    │  ② DexClassLoader 加载 plugin.dex
    │  ③ 反射 newInstance() 插件 Fragment
    │  ④ FragmentTransaction 塞进自己的容器
    ▼
  dex 里的 DemoFragment（无需在 Manifest 注册）
```

- **宿主**只声明一个 `ProxyActivity`；
- **插件**只提供 Fragment，随便换类名，宿主不用改 Manifest；
- 参数通过 Intent extra 传入，Fragment 从 `getArguments()` 取。

---

## 二、文件清单与目录结构

```
Androlua/
├── app/src/main/
│   ├── AndroidManifest.xml                         ← ① 宿主 Manifest（新增 ProxyActivity 声明）
│   ├── res/values/ids.xml                          ← 新增：Fragment 容器 id（恢复用）
│   ├── java/com/androlua/plugin/
│   │   ├── ProxyActivity.java                      ← ② 宿主代理 Activity（DexClassLoader + Fragment 容器）
│   │   └── PluginBridge.java                        ← 把「打开Dex页面」注册成 Lua 全局函数（脚本侧一行调用）
│   └── resources/lua/
│       └── 插件dex示例.lua                          ← ④ main.lua：Lua 启动 dex 页面的代码
└── plugin-dex-demo/
    ├── README.md                                    ← 本文件
    ├── build_dex.sh                                 ← ⑤ 把 Fragment 编译成 plugin.dex
    ├── plugin/com/example/plugin/
    │   └── DemoFragment.java                        ← ③ 示例 Fragment（放进 dex，含参数接收与 UI）
    └── out/                                         ← 编译产物（plugin.dex 生成在这里）
```

对应关系（与需求一一对应）：

| 需求 | 文件 |
| --- | --- |
| 1. 宿主 AndroidManifest | `app/src/main/AndroidManifest.xml` |
| 2. ProxyActivity | `app/src/main/java/com/androlua/plugin/ProxyActivity.java` |
| 2b. Lua 全局函数 | `app/src/main/java/com/androlua/plugin/PluginBridge.java` |
| 3. 示例 Fragment | `plugin-dex-demo/plugin/com/example/plugin/DemoFragment.java` |
| 4. main.lua | `app/src/main/resources/lua/插件dex示例.lua` |
| 5. 编译步骤 | `plugin-dex-demo/build_dex.sh` + 本文第五、六节 |

> 宿主新增的 AndroidManifest 片段（已写入真实 Manifest）：

```xml
<activity
    android:name="com.androlua.plugin.ProxyActivity"
    android:exported="false"
    android:label="插件页面"
    android:taskAffinity="com.androlua.plugin"   <!-- 独立 affinity，配合 NEW_TASK 单独成卡片 -->
    android:excludeFromRecents="false"
    android:configChanges="orientation|screenSize|keyboardHidden|screenLayout|uiMode"
    android:theme="@style/app_theme" />
```

---

## 三、关键设计点

### 1. 为什么用 FragmentActivity，而不是宿主已有的 LuaActivity

宿主 `LuaActivity` 继承的是 framework `Activity`，拿不到 `getSupportFragmentManager()`；
本工程已依赖 `androidx.fragment:1.8.5`，因此 `ProxyActivity extends FragmentActivity`，
即可用 support Fragment 事务。

### 2. 类加载器的父必须是宿主 ClassLoader（最容易踩的坑）

```java
new DexClassLoader(dexPath, optDir, null, getClassLoader());
```

`getClassLoader()`（宿主）作为父 → 双亲委派下，dex 里引用的
`androidx.fragment.app.Fragment` 由**宿主**提供，插件类与宿主 FragmentManager 认定的是
**同一个类**，才能被塞进事务。若插件 dex 里也打包了 androidx，会被宿主版本覆盖，反而可能
因版本不一致出 `NoSuchMethodError`。所以：**插件 dex 只放自己的类，不放 androidx**。
（`build_dex.sh` 里 androidx 只作为「编译期 classpath」，不交给 d8。）

### 3. Fragment 必须用 support Fragment

插件 Fragment 要继承 `androidx.fragment.app.Fragment`，不能用已废弃的
`android.app.Fragment`（后者进不了 support 的 FragmentManager）。同时要有**公开无参构造**，
因为宿主是用反射 `newInstance()` 实例化的。

### 4. 容器 id 必须是固定资源 id

`ProxyActivity` 的内容容器 id 取自 `res/values/ids.xml`（`R.id.plugin_container`），
**不能**用 `View.generateViewId()`——屏幕旋转/进程重建时 FragmentManager 要靠这个 id
把已有 Fragment 恢复到同一容器。配合 `savedInstanceState != null` 时跳过重复添加。

### 5. 传参兼容

Intent extra 只支持基本类型。Lua 的数字统一按 `double` 传；插件侧用
`((Number) args.get("count")).intValue()` 兼容 int/long/float，避免 `getInt()` 取不到值。
（注：`PluginBridge` 已把整数按 `int` 存进 Intent，所以直接 `getInt()` 也能取到。）

### 6. Lua 侧只留一行：`打开Dex页面`

组装 Intent、版本兼容（NEW_TASK / LAUNCH_ADJACENT）、主线程启动、异常提示全部收进
`PluginBridge`（在 `LuaActivity.initLua` 里注册），脚本侧只需：

```lua
打开Dex页面(dex路径, Fragment类名 [, 参数表])
```

参数表里 `title/标题`、`orientation/方向`、`adjacent/分屏`、`newTask/新任务` 是控制项，
其余键原样作为业务参数传给 Fragment。别名：`加载Dex页面` / `dexPage` / `openDexPage`。

---

## 四、宿主 Manifest 说明（Android 版本兼容）

- **新开 Task**：调用方加 `FLAG_ACTIVITY_NEW_TASK`，配合上面独立 `taskAffinity`，
  页面会作为独立任务出现在最近任务列表（小程序效果）。若仍希望“一个插件页一张卡片”，
  可再加 `FLAG_ACTIVITY_NEW_DOCUMENT | FLAG_ACTIVITY_MULTIPLE_TASK`。
- **分屏邻位**：`FLAG_ACTIVITY_LAUNCH_ADJACENT` 的值为 `0x1000`，**API 24（Android 7.0）才有**
  这个标志。低版本引用该常量会报错，所以 Lua 里用 `Build.VERSION.SDK_INT >= 24` 判断后
  加字面量 `0x1000`（见 `插件dex示例.lua` 第 5 步）。它要与 `NEW_TASK` 搭配，且设备需支持多窗口。
- **动态加载代码（Android 10+ / targetSdk 34+）**：Android 14 起，targetSdk≥34 的应用
  动态加载的 dex 必须是**只读**文件。本工程 `targetSdk=29`，暂无此限制；若日后提到 34+，
  需先把 dex 复制到应用私有只读目录再加载。
- **存储权限**：dex 放 `/sdcard` 需要读外部存储权限。宿主已声明
  `READ_EXTERNAL_STORAGE` 与 `MANAGE_EXTERNAL_STORAGE`；Android 11+ 上若无“所有文件访问”权限，
  可改用应用私有目录（如 `getFilesDir()`）存放 dex，并把 `dex_path` 指向那里。

---

## 五、把 Fragment 编译成 dex

### 方式 A：用脚本（推荐）

前置：Android SDK（含 build-tools 的 `d8`）、JDK 的 `javac`、`unzip`；
宿主工程 `flutter_bridge`/`:app` 构建过一次，Gradle 缓存里会有 androidx 依赖。

```bash
cd plugin-dex-demo
./build_dex.sh            # 产出 out/plugin.dex
./build_dex.sh --push     # 编译并 adb push 到 /sdcard/plugin.dex
```

脚本做的事（也是手动步骤 A→D）：

```bash
# 变量：AJ=android.jar，CP=编译期 classpath（androidx 各 jar）
AJ=$ANDROID_HOME/platforms/android-36/android.jar
CP=$(ls plugin-dex-demo/out/libs/*.jar | tr '\n' ':')   # 脚本已导出

# A. 编译（-source/-target 8 → class 版本 52，兼容所有 d8）
javac -source 8 -target 8 -bootclasspath "$AJ" -classpath "$CP" \
      -d out/classes $(find plugin -name '*.java') -Xlint:-options

# B. 转 dex（只喂插件自己的 class，不掺 androidx）
$ANDROID_HOME/build-tools/36.0.0/d8 --lib "$AJ" --min-api 24 \
      --output out $(find out/classes -name '*.class')

# C. 产物是 out/classes.dex，改名为 plugin.dex
mv out/classes.dex out/plugin.dex

# D. 推到设备
adb push out/plugin.dex /sdcard/plugin.dex
```

可用环境变量覆盖：`ANDROID_HOME`、`ANDROID_JAR`、`PLUGIN_CLASSPATH`（手动指定编译期 jar）。

### 方式 B：用 Android 工具链（Gradle）

若插件有资源 / 依赖，建议建一个 Android Library 模块，`./gradlew :plugin:assembleRelease`
后从 AAR 里取 `classes.jar`，再 `d8` 转成 dex（或直接改用插件 APK + `PathClassLoader`）。

> 注意：**插件编译所用的 androidx 版本应与宿主一致**（本工程 `fragment:1.8.5`）。
> 脚本从 Gradle 缓存自动收集时可能取到更高版本（如 1.8.9）；只要插件只调用稳定 API
> （`onCreateView` / `getArguments` / `requireContext` 等）就没有问题，运行期实际用的是宿主那份。

---

## 六、运行与测试验证

### 1. 编译宿主 APK

```bash
cd Androlua
./gradlew :app:assembleDebug      # 或走已有 CI：.github/workflows/build-release-apk.yml
```

安装到设备（`com.androlua`）。

### 2. 部署插件 dex

```bash
cd plugin-dex-demo && ./build_dex.sh --push     # 编译并推到 /sdcard/plugin.dex
```

### 3. 运行 Lua 脚本

把 `app/src/main/resources/lua/插件dex示例.lua` 用 AndroLua 打开运行
（它随 APK 发布，首次启动会解压到应用私有 lua 目录；也可直接复制到 `/sdcard` 打开）。

### 4. 预期结果（逐条核对）

| 检查点 | 预期 |
| --- | --- |
| 页面能打开 | 出现标题为「插件页面 · 来自 Lua」的新界面 |
| 独立 Task | 进入最近任务，能看到与宿主主界面**分开**的一张卡片（小程序效果） |
| 字符串传参 | 页面显示「收到字符串 msg：你好，我是 Lua 传过来的字符串」 |
| 数字传参 | 显示「收到数字 count：42」「收到小数 ratio：3.14」（不是 0！） |
| 交互 | 点「点我 +1」计数递增；旋转屏幕后计数**不归零**（状态保持） |
| 缺参数容错 | 不传 `dex_path`/`fragment_class` 时，页面显示**红色异常信息**而不是闪退 |

### 5. 常见问题定位

- **页面显示「插件加载失败」** → 按其上的异常逐条排查：
  `FileNotFoundException` = dex 路径不对（确认 `/sdcard/plugin.dex` 存在、有读权限）；
  `ClassNotFoundException` = 类名写错或没打进 dex；
  `IllegalArgumentException ... 不是 Fragment 的子类` = 插件用了 `android.app.Fragment`。
- **白屏 / 直接闪退** → 看 `logcat` 过滤 tag `ProxyActivity`。
- **数字显示为 0** → 插件用了 `getInt()` 而值被存成 double；用 `Number` 读取（本示例已处理）。
- **想改插件页面**：改 `DemoFragment.java` → 重新 `./build_dex.sh --push` → 重启页面即可，
  **宿主不用重新安装**。

---

## 七、已知限制与扩展方向

- 单文件 dex 里没有资源（res），插件 UI 需纯代码构建；要带资源请改用插件 APK。
- 目前只代理 Fragment（页面）。如需插件提供 Service/广播等，可仿照再加代理壳。
- 插件间隔离较弱（共享宿主 classpath）；要做强隔离需引入独立 ClassLoader + 资源沙箱。
- 宿主 `targetSdk=29`；上架或提到 34+ 时请按第四节处理 dex 只读要求。
