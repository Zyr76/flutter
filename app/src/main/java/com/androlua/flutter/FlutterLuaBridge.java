package com.androlua.flutter;

import android.view.View;
import android.view.ViewGroup;

import com.androlua.LuaContext;
import com.luajava.JavaFunction;
import com.luajava.LuaException;
import com.luajava.LuaObject;
import com.luajava.LuaState;

import java.util.Collections;
import java.util.Map;
import java.util.WeakHashMap;

/**
 * 把 Flutter 能力注册成 Lua 全局函数，并提供「AndroLua 布局表」风格 + 中文语法的入口。
 *
 * <p>注册后的 Lua API（ASCII 名 / 中文名都可用）：
 * <ul>
 *   <li>{@code flutterRender / 渲染Flutter / 加载Flutter布局} —— 渲染 Flutter UI，返回 FlutterView；
 *       给了第二个参数（ViewGroup）时会顺带把 FlutterView 塞进去，实现原生区+Flutter 区同屏。</li>
 *   <li>{@code flutterView / Flutter视图} —— 返回复用的 FlutterView。</li>
 *   <li>{@code dartCall / 调用Dart} —— 调 Dart 逻辑方法。第三参给了函数则异步回调，否则同步返回
 *       （同步须在非主线程，如 {@code thread{}} 里）。</li>
 *   <li>{@code dartCallAsync / 异步调用Dart} —— 显式异步。</li>
 *   <li>{@code flutterEvent / 发送Flutter事件} —— 原生 -> Flutter 事件。</li>
 *   <li>脚本里定义 {@code function onFlutterEvent(e)/收到Flutter事件(e) ... end} 接收 Dart 事件。</li>
 * </ul>
 *
 * <p>控件名（含中文）已注册为全局标识符，可直接写进布局表的首位，例如：
 * <pre>
 * 渲染Flutter{
 *   列, 间距=12, 内边距=16,
 *   { 文本, 文字="你好", 字号=20, 加粗=true },
 *   { 按钮, 文字="点我", 点击={call="ping"} },
 * }
 * </pre>
 */
public final class FlutterLuaBridge {

    private static final Map<LuaContext, LuaState> STATES =
            Collections.synchronizedMap(new WeakHashMap<LuaContext, LuaState>());

    private FlutterLuaBridge() {
    }

    public static void register(final LuaState L, final LuaContext context) throws LuaException {
        STATES.put(context, L);

        registerWidgetNames(L);

        // ---- flutterRender(spec [, container]) ----
        JavaFunction render = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                FlutterLua flutter = flutter(context);
                String json = L.isString(2) ? L.toString(2) : LuaJson.encodeSpec(L, 2);
                flutter.render(json);

                LuaObject container = getParam(3);
                View view = flutter.getView();
                attach(container, view);

                L.pushJavaObject(view);
                return 1;
            }
        };
        reg(render, "flutterRender", "渲染Flutter", "加载Flutter布局", "Flutter布局");

        // ---- flutterView() ----
        JavaFunction view = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                L.pushJavaObject(flutter(context).getView());
                return 1;
            }
        };
        reg(view, "flutterView", "Flutter视图");

        // ---- dartCall(name [, args] [, callback]) / 调用Dart ----
        JavaFunction call = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                final FlutterLua flutter = flutter(context);
                final String name = L.toString(2);
                int top = L.getTop();

                String args = null;
                int cbIndex = -1;
                if (top >= 4 && L.isFunction(4)) {
                    cbIndex = 4;
                    if (!L.isNoneOrNil(3)) {
                        args = LuaJson.encode(L, 3);
                    }
                } else if (top >= 3 && L.isFunction(3)) {
                    cbIndex = 3;
                } else if (top >= 3 && !L.isNoneOrNil(3)) {
                    args = LuaJson.encode(L, 3);
                }

                if (cbIndex > 0) {
                    final LuaObject callback = getParam(cbIndex);
                    flutter.callAsync(name, args, new FlutterLua.ResultCallback() {
                        @Override
                        public void onResult(Object result, String error) {
                            synchronized (L) {
                                try {
                                    callback.push();
                                    LuaJson.pushJava(L, result);
                                    L.pushString(error);
                                    L.pcall(2, 0, 0);
                                } catch (Exception ignored) {
                                }
                            }
                        }
                    });
                    return 0;
                }

                try {
                    LuaJson.pushJava(L, flutter.callSync(name, args));
                } catch (IllegalStateException e) {
                    warn(L, e.getMessage());
                    L.pushNil();
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    L.pushNil();
                }
                return 1;
            }
        };
        reg(call, "dartCall", "调用Dart", "dartCallAsync", "异步调用Dart", "调用Dart异步");

        // ---- flutterEvent(name [, data]) ----
        JavaFunction event = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                String name = L.toString(2);
                String data = L.isNoneOrNil(3) ? "null" : LuaJson.encode(L, 3);
                flutter(context).dispatchEvent(
                        "{\"name\":" + quote(name) + ",\"data\":" + data + "}");
                return 0;
            }
        };
        reg(event, "flutterEvent", "发送Flutter事件", "原生发送事件");
    }

    /** 把控件名（含中文别名）注册成全局标识符，供布局表首位直接使用。 */
    private static void registerWidgetNames(LuaState L) throws LuaException {
        for (Map.Entry<String, String> e : LuaJson.TYPES.entrySet()) {
            L.pushString(e.getValue());
            L.setGlobal(e.getKey());
        }
    }

    private static void reg(JavaFunction f, String... names) throws LuaException {
        for (String n : names) {
            f.register(n);
        }
    }

    private static FlutterLua flutter(final LuaContext context) {
        FlutterLua flutter = FlutterLua.get(context);
        flutter.setEventSink(new FlutterLua.EventSink() {
            @Override
            public void onFlutterEvent(String json) {
                LuaState L = STATES.get(context);
                if (L == null) {
                    return;
                }
                synchronized (L) {
                    try {
                        LuaObject callback = L.getLuaObject("onFlutterEvent");
                        if (!callback.isFunction()) {
                            callback = L.getLuaObject("收到Flutter事件");
                        }
                        if (callback.isFunction()) {
                            callback.push();
                            LuaJson.pushJson(L, json);
                            L.pcall(1, 0, 0);
                        }
                    } catch (Exception ignored) {
                    }
                }
            }
        });
        return flutter;
    }

    private static void attach(LuaObject container, View view) {
        if (container == null || container.isNil()) {
            return;
        }
        try {
            Object obj = container.getObject();
            if (obj instanceof ViewGroup) {
                ViewGroup group = (ViewGroup) obj;
                group.addView(view,
                        new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                                ViewGroup.LayoutParams.MATCH_PARENT));
            }
        } catch (Exception ignored) {
        }
    }

    private static void warn(LuaState L, String message) throws LuaException {
        LuaObject print = L.getLuaObject("print");
        if (print.isFunction()) {
            print.push();
            L.pushString("[dartCall] " + message);
            L.pcall(1, 0, 0);
        }
    }

    private static String quote(String s) {
        if (s == null) {
            return "null";
        }
        StringBuilder sb = new StringBuilder(s.length() + 2);
        sb.append('"');
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"':
                    sb.append("\\\"");
                    break;
                case '\\':
                    sb.append("\\\\");
                    break;
                case '\n':
                    sb.append("\\n");
                    break;
                case '\r':
                    sb.append("\\r");
                    break;
                case '\t':
                    sb.append("\\t");
                    break;
                default:
                    sb.append(c);
            }
        }
        return sb.append('"').toString();
    }
}
