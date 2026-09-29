package com.androlua.flutter;

import android.os.Looper;
import android.util.Log;
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
import java.util.regex.Pattern;

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

    private static final String TAG = "FlutterLuaBridge";

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
                try {
                    flutter.setSpec(new JSONObject(json));
                } catch (Exception e) {
                    logError("解析 spec 失败，命令式 h.X=值 暂不可用", e);
                }
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
                                    pcallChecked(L, 2, "dartCall 回调 " + name);
                                } catch (Exception e) {
                                    logError("dartCall 回调异常: " + name, e);
                                }
                            }
                        }
                    });
                    return 0;
                }

                if (Looper.myLooper() == Looper.getMainLooper()) {
                    // 主线程不能同步等待 Dart 应答（会 ANR）。自动异步化，结果通过 dartCallResult 事件回传。
                    warn(L, "dartCall(\"" + name + "\") 在主线程不能同步返回，已自动异步化；"
                            + "结果将作为 dartCallResult 事件回传（可用 function onFlutterEvent(e) 接收），"
                            + "或改用 dartCall(name, args, callback) 拿回调。");
                    flutter.callAsync(name, args, new FlutterLua.ResultCallback() {
                        @Override
                        public void onResult(Object result, String error) {
                            flutter.deliverEvent("dartCallResult", dartCallResultJson(name, result, error));
                        }
                    });
                    L.pushNil();
                    return 1;
                }

                try {
                    LuaJson.pushJava(L, flutter.callSync(name, args));
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    logError("dartCall(" + name + ") 被中断", e);
                    L.pushNil();
                }
                return 1;
            }
        };
        reg(call, "dartCall", "调用Dart", "dartCallAsync", "异步调用Dart", "调用Dart异步");

        // ---- flutterNode(id) / 获取Flutter节点 ----
        // id 与已有全局冲突时（bindIds 会跳过绑定），可用它按名字安全取回节点句柄。
        JavaFunction node = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                if (L.getTop() < 2 || L.isNoneOrNil(2)) {
                    L.pushNil();
                    return 1;
                }
                L.getGlobal("__flutter_node");
                L.pushString(L.toString(2));
                L.pcall(1, 1, 0);
                return 1;
            }
        };
        reg(node, "flutterNode", "Flutter节点", "获取Flutter节点");

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

        // ---- __flutter_apply(id, key, value) ---- 内部：h.Text="..." 这类命令式属性赋值
        JavaFunction apply = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                FlutterLua f = FlutterLua.peek(context);
                if (f == null) {
                    warn(L, "尚未渲染 Flutter 布局，无法通过 id 改属性");
                    return 0;
                }
                String id = L.toString(2);
                String key = L.toString(3);
                Object value;
                try {
                    value = new JSONTokener(LuaJson.encode(L, 4)).nextValue();
                } catch (Exception e) {
                    value = L.isNoneOrNil(4) ? null : L.toString(4);
                }
                if (!f.patchNode(id, key, value)) {
                    warn(L, "未找到 id=\"" + id + "\" 的节点，无法设置 " + key);
                }
                return 0;
            }
        };
        reg(apply, "__flutter_apply");
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
                        + "      if k == 'onClick' or k == 'onTap' or k == 'click'\n"
                        + "         or k == 'onChange' or k == 'onChanged' then\n"
                        + "        local h = __flutter_handlers[id]\n"
                        + "        if not h then h = {}; __flutter_handlers[id] = h end\n"
                        + "        h[k] = v\n"
                        + "      else\n"
                        + "        __flutter_apply(id, k, v)\n"
                        + "      end\n"
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
                if (!isSafeGlobalName(L, id)) {
                    warn(L, "id \"" + id + "\" 会覆盖已有全局变量或不是合法标识符，已跳过绑定；"
                            + "可用 flutterNode(\"" + id + "\") 取该节点句柄。");
                    continue;
                }
                L.getGlobal("__flutter_node");
                L.pushString(id);
                if (L.pcall(1, 1, 0) == 0) {
                    L.setGlobal(id);
                } else {
                    logError("创建 id 句柄失败: " + id + " -> " + L.toString(-1), null);
                    L.pop(1);
                }
            }
        } catch (Exception e) {
            logError("bindIds 解析失败", e);
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

    /**
     * 判断能否安全地把 id 作为全局句柄绑定：
     * <ul>
     *   <li>必须是合法 Lua 标识符；</li>
     *   <li>目标全局为 nil（尚未占用），或已是本机制生成的代理表（重复渲染同一 id）——代理表带 __id 字段。</li>
     * </ul>
     * 否则绑定会覆盖用户已有变量（如 print/_G），因此拒绝。
     */
    private static boolean isSafeGlobalName(LuaState L, String id) {
        if (id == null || !Pattern.matches("[A-Za-z_][A-Za-z0-9_]*", id)) {
            return false;
        }
        L.getGlobal(id);
        int type = L.type(-1);
        boolean ok;
        if (type == LuaState.LUA_TNIL) {
            ok = true;
        } else if (type == LuaState.LUA_TTABLE) {
            L.getField(-1, "__id");
            ok = L.isString(-1) && id.equals(L.toString(-1));
            L.pop(1);
        } else {
            ok = false;
        }
        L.pop(1);
        return ok;
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
                pcallChecked(L, 1, "id 句柄回调 " + id + "." + k);
                return;
            }
        }
    }

    private static void reg(JavaFunction f, String... names) throws LuaException {
        for (String n : names) {
            f.register(n);
        }
    }

    private static void logError(String msg, Throwable t) {
        if (t != null) {
            Log.e(TAG, msg, t);
        } else {
            Log.e(TAG, msg);
        }
    }

    /** 执行 Lua 函数并检查错误，失败时记录（不再静默吞掉）。 */
    private static void pcallChecked(LuaState L, int nargs, String what) {
        if (L.pcall(nargs, 0, 0) != 0) {
            logError(what + " 执行出错: " + L.toString(-1), null);
            L.pop(1);
        }
    }

    /** 把 dartCall 的异步结果序列化成事件 data 的 JSON。 */
    private static String dartCallResultJson(String name, Object result, String error) {
        try {
            JSONObject o = new JSONObject();
            o.put("name", name);
            o.put("error", error == null ? JSONObject.NULL : error);
            Object r;
            if (result == null) {
                r = JSONObject.NULL;
            } else if (result instanceof Map || result instanceof java.util.List
                    || result instanceof Number || result instanceof Boolean || result instanceof String) {
                r = result;
            } else {
                r = LuaJson.toJsonString(result);
            }
            o.put("result", r);
            return o.toString();
        } catch (Exception e) {
            logError("dartCallResult 序列化失败", e);
            return "{\"name\":" + quote(name) + ",\"error\":\"result serialize failed\"}";
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
                            pcallChecked(L, 1, "onFlutterEvent");
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
                            pcallChecked(L, 1, "事件 " + name);
                            return;
                        }
                        // id 句柄回调：h.onClick = fn / h.onChange = fn（由 __flutter_handlers 保存）
                        dispatchNodeHandler(L, name, o);
                    } catch (Exception e) {
                        logError("处理 Flutter 事件失败: " + json, e);
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
        } catch (Exception e) {
            logError("把 FlutterView 加入容器失败", e);
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
