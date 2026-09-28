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
 * 把 Flutter 能力注册成 Lua 全局函数。
 *
 * <p>注册后的 Lua API：
 * <ul>
 *   <li>{@code flutterRender(spec [, container])} —— 用 widget 描述渲染 Flutter UI，返回 FlutterView；
 *       给了 container（ViewGroup）时顺带把 FlutterView 塞进去，实现原生区+Flutter 区同屏。</li>
 *   <li>{@code flutterView()} —— 返回复用的 FlutterView。</li>
 *   <li>{@code dartCall(name [, args])} —— 同步调用 Dart 逻辑方法并拿到返回（须在非主线程使用）。</li>
 *   <li>{@code dartCallAsync(name [, args], callback)} —— 异步调用，主线程可安全使用。</li>
 *   <li>{@code flutterEvent(name [, data])} —— 原生 -&gt; Flutter 事件。</li>
 *   <li>可在脚本里定义 {@code function onFlutterEvent(data) ... end} 接收 Dart -&gt; 原生 事件。</li>
 * </ul>
 *
 * <p>引擎是懒创建的：脚本不用 Flutter 时不会有任何开销。
 */
public final class FlutterLuaBridge {

    private static final Map<LuaContext, LuaState> STATES =
            Collections.synchronizedMap(new WeakHashMap<LuaContext, LuaState>());

    private FlutterLuaBridge() {
    }

    public static void register(final LuaState L, final LuaContext context) throws LuaException {
        STATES.put(context, L);

        JavaFunction flutterRender = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                FlutterLua flutter = flutter(context);
                flutter.render(LuaJson.encode(L, 2));

                LuaObject container = getParam(3);
                View view = flutter.getView();
                attach(container, view);

                L.pushJavaObject(view);
                return 1;
            }
        };
        flutterRender.register("flutterRender");

        JavaFunction flutterView = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                L.pushJavaObject(flutter(context).getView());
                return 1;
            }
        };
        flutterView.register("flutterView");

        JavaFunction dartCall = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                FlutterLua flutter = flutter(context);
                String name = L.toString(2);
                String args = L.isNoneOrNil(3) ? null : LuaJson.encode(L, 3);
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
        dartCall.register("dartCall");

        JavaFunction dartCallAsync = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                final FlutterLua flutter = flutter(context);
                final String name = L.toString(2);

                int callbackIndex;
                String args;
                if (L.isFunction(3)) {
                    callbackIndex = 3;
                    args = null;
                } else {
                    args = L.isNoneOrNil(3) ? null : LuaJson.encode(L, 3);
                    callbackIndex = 4;
                }

                final LuaObject callback = getParam(callbackIndex);
                if (!callback.isFunction()) {
                    throw new LuaException("dartCallAsync: 缺少 callback");
                }

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
        };
        dartCallAsync.register("dartCallAsync");

        JavaFunction flutterEvent = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                String name = L.toString(2);
                String data = L.isNoneOrNil(3) ? "null" : LuaJson.encode(L, 3);
                flutter(context).dispatchEvent(
                        "{\"name\":" + quote(name) + ",\"data\":" + data + "}");
                return 0;
            }
        };
        flutterEvent.register("flutterEvent");
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
