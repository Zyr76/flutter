package com.androlua.flutter;

import android.view.View;
import android.view.ViewGroup;

import com.androlua.LuaContext;
import com.luajava.JavaFunction;
import com.luajava.LuaException;
import com.luajava.LuaObject;
import com.luajava.LuaState;

import org.json.JSONArray;
import org.json.JSONObject;
import org.json.JSONTokener;

import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
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
 * <p>控件名已注册为全局标识符（Flutter 名字），可直接写进布局表的首位：
 * <pre>
 * 渲染Flutter{
 *   Column, gap = 12, padding = 16,
 *   { Text, text = "hi", fontSize = 20, fontWeight = "bold" },
 *   { Button, text = "点我", onClick = { call = "ping" } },
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

        installWidgetFallback(L);
        installNodeHandlers(L);

        // ---- flutterRender(spec [, container]) ----
        JavaFunction render = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                FlutterLua flutter = flutter(context);
                String json = L.isString(2) ? L.toString(2) : LuaJson.encodeSpec(L, 2);
                flutter.render(json);
                bindIds(L, json);

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

    /**
     * 给 _G 装一个「兜底 __index」：读取未定义的全局时，若是 Flutter 控件名就返回其名字字符串，
     * 让布局表首位可直接写 {@code { Button, ... }}。
     *
     * <p>刻意「不抢占」全局名：只有当该名字在 _G 里不存在时才由这里兜底。这样一旦脚本
     * {@code import "android.widget.*"} 导入了同名 Android 类（Button/Switch/ListView/GridView 等），
     * 原生 loadlayout 依然能拿到真正的类，不会被字符串遮蔽。
     */
    private static void installWidgetFallback(LuaState L) throws LuaException {
        StringBuilder entries = new StringBuilder();
        for (Map.Entry<String, String> e : LuaJson.TYPES.entrySet()) {
            entries.append('[').append('"').append(e.getKey()).append('"').append(']')
                    .append('=').append('"').append(e.getValue()).append('"').append(',');
        }
        String chunk = "local w = {" + entries + "}\n"
                + "local mt = getmetatable(_G)\n"
                + "local prev = (type(mt) == 'table') and mt.__index or nil\n"
                + "setmetatable(_G, { __index = function(t, k)\n"
                + "    local v = w[k]\n"
                + "    if v ~= nil then return v end\n"
                + "    if type(prev) == 'function' then return prev(t, k) end\n"
                + "    if type(prev) == 'table' then return prev[k] end\n"
                + "  end })";
        int ok = L.LdoString(chunk);
        if (ok != 0) {
            throw new LuaException("安装 Flutter 控件名兜底失败: " + L.toString(-1));
        }
    }

    /**
     * 定义 id 句柄机制：
     * <pre>
     * local layout = { Column, { Button, text="4664", id="h" } }
     * activity.setContentView(渲染Flutter(layout))
     * function h.onClick() print("哈哈哈") end   -- 等价 h.onClick = function() ... end
     * </pre>
     * `id` 会在渲染时生成一个 Lua 句柄（代理表），对它的 onClick/onChange 赋值会被存进 __flutter_handlers。
     */
    private static void installNodeHandlers(LuaState L) throws LuaException {
        String chunk =
                "__flutter_handlers = __flutter_handlers or {}\n"
                        + "function __flutter_node(id)\n"
                        + "  return setmetatable({ __id = id }, {\n"
                        + "    __index = function(t, k) local h = __flutter_handlers[id]; return h and h[k] end,\n"
                        + "    __newindex = function(t, k, v)\n"
                        + "      local h = __flutter_handlers[id]\n"
                        + "      if not h then h = {}; __flutter_handlers[id] = h end\n"
                        + "      h[k] = v\n"
                        + "    end\n"
                        + "  })\n"
                        + "end";
        int ok = L.LdoString(chunk);
        if (ok != 0) {
            throw new LuaException("安装 id 句柄机制失败: " + L.toString(-1));
        }
    }

    /** 扫描 spec 里所有 id，并为每个 id 建立/刷新一个 Lua 句柄全局变量（与 loadlayout 一致语义）。 */
    private static void bindIds(LuaState L, String json) {
        try {
            Object root = new JSONTokener(json).nextValue();
            Set<String> ids = new LinkedHashSet<String>();
            collectIds(root, ids);
            for (String id : ids) {
                L.getGlobal("__flutter_node");
                L.pushString(id);
                if (L.pcall(1, 1, 0) == 0) {
                    L.setGlobal(id);
                } else {
                    L.pop(1);
                }
            }
        } catch (Exception ignored) {
        }
    }

    private static void collectIds(Object v, Set<String> out) {
        if (v instanceof JSONObject) {
            JSONObject o = (JSONObject) v;
            Object id = o.opt("id");
            if (id instanceof String && !((String) id).isEmpty()) {
                out.add((String) id);
            }
            for (java.util.Iterator<String> it = o.keys(); it.hasNext(); ) {
                collectIds(o.opt(it.next()), out);
            }
        } else if (v instanceof JSONArray) {
            JSONArray a = (JSONArray) v;
            for (int i = 0; i < a.length(); i++) {
                collectIds(a.opt(i), out);
            }
        }
    }

    /** 把事件分发给对应 id 句柄上注册的回调（onClick / onChange）。 */
    private static void dispatchNodeHandler(LuaState L, String id, JSONObject event) throws LuaException {
        LuaObject handlers = L.getLuaObject("__flutter_handlers");
        if (handlers == null || !handlers.isTable()) {
            return;
        }
        LuaObject entry = handlers.getField(id);
        if (entry == null || !entry.isTable()) {
            return;
        }
        String type = event.optString("type", "");
        String[] keys = "change".equals(type)
                ? new String[]{"onChange", "onChanged"}
                : new String[]{"onClick", "onTap", "click"};
        for (String k : keys) {
            LuaObject fn = entry.getField(k);
            if (fn != null && fn.isFunction()) {
                fn.push();
                LuaJson.pushJava(L, event.opt("data"));
                L.pcall(1, 0, 0);
                return;
            }
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
                            return;
                        }
                        // AndroLua 风格：事件名 -> 同名全局 Lua 函数
                        org.json.JSONObject o = new org.json.JSONObject(json);
                        String name = o.optString("name", null);
                        if (name == null || name.isEmpty()) {
                            return;
                        }
                        LuaObject fn = L.getLuaObject(name);
                        if (fn.isFunction()) {
                            fn.push();
                            LuaJson.pushJava(L, o.opt("data"));
                            L.pcall(1, 0, 0);
                            return;
                        }
                        // id 句柄回调：h.onClick = fn / h.onChange = fn（由 __flutter_handlers 保存）
                        dispatchNodeHandler(L, name, o);
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
