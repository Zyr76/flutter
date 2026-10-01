package com.androlua.plugin;

import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.os.Bundle;
import android.util.Log;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentActivity;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;

import dalvik.system.DexClassLoader;

/**
 * 通用「代理 Activity」——宿主里唯一需要在 AndroidManifest 注册的组件。
 *
 * <p>插件侧只需要写一个 {@link Fragment}（打进独立的 dex/apk），不用在 Manifest 里注册任何东西：
 * <ol>
 *   <li>Lua（或任何宿主代码）构造一个 {@link Intent} 指向本 Activity，
 *       通过 extra 告诉它：dex 在哪、要加载哪个 Fragment、以及任意业务参数；</li>
 *   <li>本 Activity 运行起来后用 {@link DexClassLoader} 动态加载 dex；</li>
 *   <li>反射实例化目标 Fragment，塞进自己的内容容器；</li>
 *   <li>Intent 里的业务参数原样转交给 Fragment（{@code getArguments()} 可取）。</li>
 * </ol>
 *
 * <p>为什么要「代理」：Android 的组件（Activity/Service）必须静态注册在 Manifest 里，
 * 外部 dex 无法新增组件。所以宿主预先注册一个「万能壳」Activity，插件只提供 Fragment，
 * 由壳负责把它们装进来——这和小程序「一个宿主容器 + 一份远程页面」的模型一致。
 *
 * <p><b>关键点：类加载器的父必须传宿主的 ClassLoader。</b>
 * dex 里引用的 {@code androidx.fragment.app.Fragment} 由宿主提供（双亲委派 parent-first），
 * 这样插件 Fragment 与 {@link FragmentActivity#getSupportFragmentManager()} 认定的是<b>同一个类</b>，
 * 才能被塞进宿主的 Fragment 事务里。插件 dex 里不要打包 androidx，否则会被宿主版本覆盖。
 *
 * <p><b>兼容性</b>：
 * <ul>
 *   <li>新开 Task 由调用方设置 {@code FLAG_ACTIVITY_NEW_TASK}（见 Lua 示例）；本 Activity 在
 *       Manifest 里配置了独立的 {@code taskAffinity}，因此会出现在最近任务里、与主 App 分开，
 *       达不到「独立卡片」效果时再加 {@code FLAG_ACTIVITY_NEW_DOCUMENT|FLAG_ACTIVITY_MULTIPLE_TASK}。</li>
 *   <li>{@code FLAG_ACTIVITY_LAUNCH_ADJACENT}（API 24+，值 0x1000）用于分屏邻位启动，
 *       低版本只会被忽略，需在调用方按 {@code Build.VERSION.SDK_INT} 判断后添加。</li>
 *   <li>Android 10+ 从可写目录动态加载 dex 在 <b>targetSdk 34+</b> 上会被拒绝（要求只读）；
 *       本项目 targetSdk=29，暂无此限制。若日后提到 34+，需把 dex 复制到应用私有只读目录再加载。</li>
 * </ul>
 */
public class ProxyActivity extends FragmentActivity {

    private static final String TAG = "ProxyActivity";

    /** 参数：插件 dex 的绝对路径，例如 {@code /sdcard/plugin.dex}。 */
    public static final String EXTRA_DEX_PATH = "dex_path";
    /** 参数：目标 Fragment 的全限定类名，例如 {@code com.example.plugin.DemoFragment}。 */
    public static final String EXTRA_FRAGMENT_CLASS = "fragment_class";
    /** 参数（可选）：窗口标题。 */
    public static final String EXTRA_TITLE = "title";
    /** 参数（可选）：屏幕方向，0=跟随系统（默认）、1=竖屏、2=横屏。 */
    public static final String EXTRA_ORIENTATION = "orientation";

    /** 内部键：以上这些是「控制参数」，不会作为业务参数转交给 Fragment。 */
    private static final String[] CONTROL_KEYS = {
            EXTRA_DEX_PATH, EXTRA_FRAGMENT_CLASS, EXTRA_TITLE, EXTRA_ORIENTATION
    };

    /**
     * 内容容器 id。Fragment 在进程/配置重建时要靠这个 id 把已有 Fragment 恢复到同一容器，
     * 所以必须是稳定值（定义在 res/values/ids.xml），不能用 {@code View.generateViewId()}。
     */
    private static final int CONTAINER_ID = com.androlua.R.id.plugin_container;

    private String dexPath;
    private String fragmentClassName;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        Intent intent = getIntent();
        dexPath = intent.getStringExtra(EXTRA_DEX_PATH);
        fragmentClassName = intent.getStringExtra(EXTRA_FRAGMENT_CLASS);

        CharSequence title = intent.getStringExtra(EXTRA_TITLE);
        if (title != null && title.length() > 0) {
            setTitle(title);
        }
        applyOrientation(intent.getIntExtra(EXTRA_ORIENTATION, 0));

        // 建内容容器。setContentView 必须在 super.onCreate 之后立即调用，
        // 否则 FragmentManager 恢复 Fragment 时找不到容器。
        FrameLayout container = new FrameLayout(this);
        container.setId(CONTAINER_ID);
        container.setLayoutParams(new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        setContentView(container);

        // 重建场景（旋转屏幕、被系统回收后恢复）：FragmentManager 已自动把 Fragment 恢复进容器，
        // 此时不要重新加载 dex，否则会得到两个 Fragment。
        if (savedInstanceState != null) {
            return;
        }

        if (dexPath == null || dexPath.length() == 0
                || fragmentClassName == null || fragmentClassName.length() == 0) {
            showError(new IllegalArgumentException(
                    "缺少参数：" + EXTRA_DEX_PATH + " / " + EXTRA_FRAGMENT_CLASS));
            return;
        }

        try {
            Fragment fragment = createFragment(dexPath, fragmentClassName);
            fragment.setArguments(buildFragmentArguments(intent));
            getSupportFragmentManager()
                    .beginTransaction()
                    .replace(CONTAINER_ID, fragment, "plugin_fragment")
                    .commit();
        } catch (Throwable t) {
            Log.e(TAG, "加载插件 Fragment 失败: " + fragmentClassName, t);
            showError(t);
        }
    }

    /**
     * 用 {@link DexClassLoader} 加载 dex 并实例化 Fragment。
     *
     * @param dexPathStr dex 文件路径
     * @param className  目标 Fragment 全限定类名
     * @return 已实例化的 Fragment（尚未初始化参数）
     */
    private Fragment createFragment(String dexPathStr, String className) throws Exception {
        File dexFile = new File(dexPathStr);
        if (!dexFile.isFile()) {
            throw new FileNotFoundException("dex 文件不存在或不是文件: " + dexPathStr);
        }

        // 优化产物（odex/vdex）目录：放在应用私有 code cache 下。
        // 不放 /sdcard（不可写且会污染），也不用 getDir（那是持久数据目录）。
        File optDir = new File(getCodeCacheDir(), "plugin_opt");
        if (!optDir.isDirectory() && !optDir.mkdirs()) {
            throw new IOException("无法创建 dex 优化目录: " + optDir);
        }

        // 父加载器传 getClassLoader()（宿主）：androidx / Android framework 类都由宿主提供。
        // nativeLibraryDir 传 null：插件若不自带 .so 就不需要。
        DexClassLoader loader = new DexClassLoader(
                dexFile.getAbsolutePath(),
                optDir.getAbsolutePath(),
                null,
                getClassLoader());

        Class<?> clazz = Class.forName(className, true, loader);

        if (!Fragment.class.isAssignableFrom(clazz)) {
            throw new IllegalArgumentException(className
                    + " 不是 androidx.fragment.app.Fragment 的子类（请用 support Fragment，不要用 android.app.Fragment）");
        }

        // 用 public 无参构造实例化——插件 Fragment 必须有公开无参构造函数。
        return (Fragment) clazz.getDeclaredConstructor().newInstance();
    }

    /** 把 Intent 里的业务参数（除去控制键）打包成 Bundle 交给 Fragment。 */
    private Bundle buildFragmentArguments(Intent intent) {
        Bundle extras = intent.getExtras();
        Bundle args = extras == null ? new Bundle() : new Bundle(extras);
        for (String key : CONTROL_KEYS) {
            args.remove(key);
        }
        return args;
    }

    private void applyOrientation(int orientation) {
        switch (orientation) {
            case 1:
                setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
                break;
            case 2:
                setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE);
                break;
            default:
                // 跟随系统，无需设置
        }
    }

    /** 出错时把异常信息铺满屏幕，方便在真机上一眼看到问题（而不是白屏/闪退）。 */
    private void showError(Throwable t) {
        StringBuilder sb = new StringBuilder(512);
        sb.append("插件加载失败\n\n");
        sb.append(t.getClass().getName()).append(": ").append(t.getMessage()).append("\n\n");
        StackTraceElement[] trace = t.getStackTrace();
        for (int i = 0; i < trace.length && sb.length() < 4000; i++) {
            sb.append("    at ").append(trace[i]).append('\n');
        }

        TextView tv = new TextView(this);
        tv.setText(sb.toString());
        tv.setTextSize(12f);
        tv.setTextIsSelectable(true);
        int pad = (int) (getResources().getDisplayMetrics().density * 16);
        tv.setPadding(pad, pad, pad, pad);

        ScrollView sv = new ScrollView(this);
        sv.addView(tv);
        setContentView(sv);
    }
}
