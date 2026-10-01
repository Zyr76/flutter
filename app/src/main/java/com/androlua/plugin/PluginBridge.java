package com.androlua.plugin;

import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.Toast;

import com.androlua.LuaContext;
import com.luajava.JavaFunction;
import com.luajava.LuaException;
import com.luajava.LuaState;

/**
 * 把「打开外部 dex 页面」注册成 Lua 全局函数，让脚本一行就能拉起插件页面。
 *
 * <p>注册后 Lua 侧用法（{@code title} 等是控制项，其余键原样传给 Fragment）：
 * <pre>
 * 打开Dex页面("/sdcard/plugin.dex", "com.example.plugin.DemoFragment", {
 *   title = "插件页面",        -- 窗口标题
 *   icon = "/sdcard/pic.png",  -- 最近任务图标（可选，图片文件路径）
 *   adjacent = false,          -- true 时分屏邻位打开（仅 Android 7.0+）
 *   orientation = 0,           -- 0 跟随系统 / 1 竖屏 / 2 横屏
 *   newTask = true,            -- 是否新开 Task（默认 true）
 *   msg = "hi", count = 42,    -- 业务参数：原样转交给 Fragment
 * })
 * </pre>
 *
 * <p>相比让脚本自己 new Intent / 加 flag 的写法，这里把「Intent 组装 + 版本兼容 +
 * 主线程启动 + 异常提示」都收进 Java，脚本侧只留一行。
 */
public final class PluginBridge {

    private static final String TAG = "PluginBridge";

    /** 非 Activity 上下文启动需要该标志；保证页面出现在最近任务里、与主界面分开。 */
    private static final int FLAG_NEW_TASK = Intent.FLAG_ACTIVITY_NEW_TASK;
    /** FLAG_ACTIVITY_LAUNCH_ADJACENT：分屏邻位启动，API 24 起才有（低版本忽略）。 */
    private static final int FLAG_LAUNCH_ADJACENT = 0x00001000;

    /** 参数表里的「控制项」键名（含中文别名）；除此之外的键都作为业务参数原样传给 Fragment。 */
    private static final String[] KEY_TITLE = {"title", "标题"};
    private static final String[] KEY_ORIENTATION = {"orientation", "方向"};
    private static final String[] KEY_ADJACENT = {"adjacent", "分屏"};
    private static final String[] KEY_NEW_TASK = {"newTask", "新任务"};
    private static final String[] KEY_ICON = {"icon", "图标"};

    private PluginBridge() {
    }

    /** 在指定 LuaState 上注册全局函数。 */
    public static void register(final LuaState L, final LuaContext context) throws LuaException {
        JavaFunction open = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                if (!L.isString(2) || !L.isString(3)) {
                    warn(L, "用法: 打开Dex页面(dex路径, Fragment类名 [, 参数表])");
                    return 0;
                }
                final String dexPath = L.toString(2);
                final String fragmentClass = L.toString(3);

                final Context ctx = context.getContext();
                Intent intent = new Intent();
                intent.setClassName(ctx.getPackageName(), ProxyActivity.class.getName());

                // 控制项（从第 4 个参数表读取，缺省用默认值）
                intent.putExtra(ProxyActivity.EXTRA_DEX_PATH, dexPath);
                intent.putExtra(ProxyActivity.EXTRA_FRAGMENT_CLASS, fragmentClass);
                String title = optString(L, 4, KEY_TITLE);
                if (title != null && title.length() > 0) {
                    intent.putExtra(ProxyActivity.EXTRA_TITLE, title);
                }
                int orientation = (int) optNumber(L, 4, 0, KEY_ORIENTATION);
                if (orientation != 0) {
                    intent.putExtra(ProxyActivity.EXTRA_ORIENTATION, orientation);
                }
                String iconPath = optString(L, 4, KEY_ICON);
                if (iconPath != null && iconPath.length() > 0) {
                    intent.putExtra(ProxyActivity.EXTRA_ICON, iconPath);
                }
                if (optBoolean(L, 4, true, KEY_NEW_TASK)) {
                    intent.addFlags(FLAG_NEW_TASK);
                }
                if (optBoolean(L, 4, false, KEY_ADJACENT) && Build.VERSION.SDK_INT >= 24) {
                    intent.addFlags(FLAG_LAUNCH_ADJACENT);
                }

                // 业务参数：第 4 个表里除控制项外的所有键
                if (L.getTop() >= 4 && L.isTable(4)) {
                    copyExtras(L, 4, intent);
                }

                startOnMain(ctx, intent);
                return 0;
            }
        };

        open.register("打开Dex页面");
        open.register("加载Dex页面");
        open.register("dexPage");
        open.register("openDexPage");
    }

    // ============================================================
    // 参数读取
    // ============================================================

    private static boolean isTableAt(LuaState L, int idx) {
        return idx > 0 && idx <= L.getTop() && L.isTable(idx);
    }

    /** 从表中按候选键名取字符串，取不到返回 null。 */
    private static String optString(LuaState L, int idx, String... keys) {
        if (!isTableAt(L, idx)) {
            return null;
        }
        for (String k : keys) {
            L.getField(idx, k);
            boolean hit = !L.isNil(-1);
            String v = hit ? L.toString(-1) : null;
            L.pop(1);
            if (hit) {
                return v;
            }
        }
        return null;
    }

    /** 从表中按候选键名取数字，取不到返回默认值。 */
    private static double optNumber(LuaState L, int idx, double def, String... keys) {
        if (!isTableAt(L, idx)) {
            return def;
        }
        for (String k : keys) {
            L.getField(idx, k);
            boolean hit = L.isNumber(-1);
            double v = hit ? L.toNumber(-1) : def;
            L.pop(1);
            if (hit) {
                return v;
            }
        }
        return def;
    }

    /** 从表中按候选键名取布尔，取不到返回默认值。 */
    private static boolean optBoolean(LuaState L, int idx, boolean def, String... keys) {
        if (!isTableAt(L, idx)) {
            return def;
        }
        for (String k : keys) {
            L.getField(idx, k);
            boolean hit = !L.isNil(-1);
            boolean v = hit ? L.toBoolean(-1) : def;
            L.pop(1);
            if (hit) {
                return v;
            }
        }
        return def;
    }

    private static boolean isControlKey(String key) {
        String[][] groups = {KEY_TITLE, KEY_ORIENTATION, KEY_ADJACENT, KEY_NEW_TASK, KEY_ICON};
        for (String[] group : groups) {
            for (String k : group) {
                if (k.equalsIgnoreCase(key)) {
                    return true;
                }
            }
        }
        return false;
    }

    /** 遍历第 tableIdx 个 Lua 表，把非控制项作为 Intent extra 写入。 */
    private static void copyExtras(LuaState L, int tableIdx, Intent intent) {
        int abs = tableIdx > 0 ? tableIdx : L.getTop() + tableIdx + 1;
        L.pushNil();
        while (L.next(abs) != 0) {
            // 栈顶：key(-2) value(-1)
            String key = null;
            if (L.isString(-2)) {
                key = L.toString(-2);
            } else if (L.isNumber(-2)) {
                key = L.toString(-2);
            }
            if (key != null && !isControlKey(key)) {
                putExtra(L, -1, key, intent);
            }
            L.pop(1); // 弹掉 value，保留 key 供 next 继续
        }
    }

    /** 把 Lua 值按类型写入 Intent；Intent extra 只支持基本类型，表/函数等跳过。 */
    private static void putExtra(LuaState L, int idx, String key, Intent intent) {
        switch (L.type(idx)) {
            case LuaState.LUA_TBOOLEAN:
                intent.putExtra(key, L.toBoolean(idx));
                break;
            case LuaState.LUA_TNUMBER:
            case LuaState.LUA_TINTEGER: {
                double d = L.toNumber(idx);
                if (!Double.isInfinite(d) && d == Math.floor(d)
                        && d >= Integer.MIN_VALUE && d <= Integer.MAX_VALUE) {
                    intent.putExtra(key, (int) d);
                } else if (!Double.isInfinite(d) && d == Math.floor(d)) {
                    intent.putExtra(key, (long) d);
                } else {
                    intent.putExtra(key, d);
                }
                break;
            }
            case LuaState.LUA_TSTRING:
                intent.putExtra(key, L.toString(idx));
                break;
            default:
                break;
        }
    }

    // ============================================================
    // 启动
    // ============================================================

    private static void startOnMain(final Context ctx, final Intent intent) {
        new Handler(Looper.getMainLooper()).post(new Runnable() {
            @Override
            public void run() {
                try {
                    ctx.startActivity(intent);
                } catch (Exception e) {
                    Log.e(TAG, "启动插件页面失败", e);
                    Toast.makeText(ctx, "启动插件页面失败: " + e.getMessage(), Toast.LENGTH_LONG).show();
                }
            }
        });
    }

    private static void warn(LuaState L, String message) {
        try {
            L.getGlobal("print");
            if (L.isFunction(-1)) {
                L.pushString("[打开Dex页面] " + message);
                if (L.pcall(1, 0, 0) != 0) {
                    L.pop(1);
                }
            } else {
                L.pop(1);
            }
        } catch (Throwable ignored) {
            // 提示失败不影响主流程
        }
    }
}
