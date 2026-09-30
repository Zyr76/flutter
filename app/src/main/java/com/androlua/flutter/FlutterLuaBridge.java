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

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.Iterator;
import java.util.LinkedHashSet;
import java.util.List;
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

    private static final String TAG = "FlutterLuaBridge";

    /**
     * 同一个 LuaContext 下可能同时存在多个 LuaState（主脚本 + thread/task/runnable 各自新建的），
     * 所以这里记录的是一个集合：事件要广播给它们。
     *
     * <p>旧实现是 Map&lt;LuaContext, LuaState&gt;（单值），thread/task 注册时会把主脚本的 L 覆盖掉——
     * 典型症状：调用过一次 thread 之后，主脚本里定义的 id 句柄（h.onClick / h.onChange）再也收不到事件。
     * 用弱引用集合，线程结束、LuaState 不再被引用时自然回收。
     */
    private static final Map<LuaContext, Set<LuaState>> STATES =
            Collections.synchronizedMap(new WeakHashMap<LuaContext, Set<LuaState>>());

    private static void rememberState(final LuaState L, final LuaContext context) {
        synchronized (STATES) {
            Set<LuaState> set = STATES.get(context);
            if (set == null) {
                set = Collections.synchronizedSet(
                        Collections.newSetFromMap(new WeakHashMap<LuaState, Boolean>()));
                STATES.put(context, set);
            }
            set.add(L);
        }
    }

    /** 取该 context 下所有仍存活的 LuaState 快照（可能是空列表）。 */
    private static List<LuaState> statesOf(final LuaContext context) {
        Set<LuaState> set = STATES.get(context);
        if (set == null) {
            return Collections.emptyList();
        }
        synchronized (set) {
            return new ArrayList<LuaState>(set);
        }
    }

    private FlutterLuaBridge() {
    }

    public static void register(final LuaState L, final LuaContext context) throws LuaException {
        rememberState(L, context);

        installWidgetFallback(L);
        installNodeHandlers(L);

        // ---- flutterRender(spec [, container]) ----
        JavaFunction render = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                FlutterLua flutter = flutter(context);
                String json = L.isString(2) ? L.toString(2) : LuaJson.encodeSpec(L, 2);
                try {
                    JSONObject root = new JSONObject(json);
                    // 图片 src 支持只写文件名（如 123.png）→ 拼成项目目录下的绝对路径
                    resolveImagePaths(root, context.getLuaDir());
                    json = root.toString();
                    flutter.setSpec(root);
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
                if ("src".equalsIgnoreCase(key) && value instanceof String && isRelativeImagePath((String) value)) {
                    value = context.getLuaDir() + "/" + value;
                }
                if (!f.patchNode(id, key, value)) {
                    warn(L, "未找到 id=\"" + id + "\" 的节点，无法设置 " + key);
                }
                return 0;
            }
        };
        reg(apply, "__flutter_apply");

        // ---- 弹窗类命令 ----
        JavaFunction showDialog = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                FlutterLua f = flutter(context);
                String json = L.isString(2) ? L.toString(2) : LuaJson.encodeSpec(L, 2);
                f.invoke("dialog", json);
                return 0;
            }
        };
        reg(showDialog, "flutterShowDialog", "显示对话框");

        JavaFunction showSheet = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                FlutterLua f = flutter(context);
                String json = L.isString(2) ? L.toString(2) : LuaJson.encodeSpec(L, 2);
                f.invoke("bottomSheet", json);
                return 0;
            }
        };
        reg(showSheet, "flutterShowBottomSheet", "显示底部弹窗");

        JavaFunction showSnack = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                FlutterLua f = flutter(context);
                String json;
                if (L.isString(2)) {
                    json = "{\"text\":" + quote(L.toString(2)) + "}";
                } else if (L.type(2) == LuaState.LUA_TTABLE) {
                    json = LuaJson.encode(L, 2);
                } else {
                    json = "{\"text\":\"\"}";
                }
                f.invoke("snackBar", json);
                return 0;
            }
        };
        reg(showSnack, "flutterShowSnackBar", "显示提示", "flutterSnackBar");

        JavaFunction datePicker = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                FlutterLua f = flutter(context);
                String json = L.isNoneOrNil(2) ? "null" : LuaJson.encode(L, 2);
                f.invoke("datePicker", json);
                return 0;
            }
        };
        reg(datePicker, "flutterDatePicker", "选择日期");

        JavaFunction timePicker = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                FlutterLua f = flutter(context);
                String json = L.isNoneOrNil(2) ? "null" : LuaJson.encode(L, 2);
                f.invoke("timePicker", json);
                return 0;
            }
        };
        reg(timePicker, "flutterTimePicker", "选择时间");

        JavaFunction closeDialog = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                FlutterLua f = flutter(context);
                f.invoke("closeDialog", null);
                return 0;
            }
        };
        reg(closeDialog, "flutterCloseDialog", "关闭对话框");

        // ---- flutterDebug(true/false) ---- 事件调试开关，把每个事件的到达/处理情况打到控制台
        JavaFunction debug = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                DEBUG_EVENTS = !L.isNoneOrNil(2) && L.toBoolean(2);
                luaPrint(L, DEBUG_EVENTS ? "[Flutter] 事件调试：开" : "[Flutter] 事件调试：关");
                return 0;
            }
        };
        reg(debug, "flutterDebug", "Flutter调试", "调试Flutter事件");
    }

    /** src 是否是需要拼成绝对路径的“纯文件名/相对路径”。 */
    private static boolean isRelativeImagePath(String s) {
        if (s == null || s.isEmpty()) return false;
        String low = s.toLowerCase();
        return !(low.startsWith("http://") || low.startsWith("https://") || low.startsWith("data:")
                || low.startsWith("file://") || low.startsWith("/") || low.startsWith("storage/")
                || low.startsWith("assets/") || low.startsWith("asset:") || low.contains("://"));
    }

    /** 递归把所有 src 的相对路径拼成项目目录下的绝对路径。 */
    private static void resolveImagePaths(Object node, String luaDir) {
        if (node instanceof JSONObject) {
            JSONObject o = (JSONObject) node;
            Object src = o.opt("src");
            if (src instanceof String && isRelativeImagePath((String) src)) {
                try {
                    o.put("src", luaDir + "/" + src);
                } catch (Exception e) {
                    logError("拼图片路径失败: " + src, e);
                }
            }
            for (Iterator<String> it = o.keys(); it.hasNext(); ) {
                resolveImagePaths(o.opt(it.next()), luaDir);
            }
        } else if (node instanceof JSONArray) {
            JSONArray a = (JSONArray) node;
            for (int i = 0; i < a.length(); i++) {
                resolveImagePaths(a.opt(i), luaDir);
            }
        }
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
     * function h.onClick() print("哈哈哈") end      -- 事件：h.onClick = fn
     * h.dart.Text = "你好"                          -- 属性：h.dart.<属性名> = 值（推荐）
     * </pre>
     * `id` 会在渲染时生成一个 Lua 句柄（代理表）：h.onClick/h.onChange 存事件回调；
     * h.dart.<k> 一律走属性更新（命令式局部刷新）。
     */
    private static void installNodeHandlers(LuaState L) throws LuaException {
        String chunk =
                "__flutter_handlers = __flutter_handlers or {}\n"
                        + "function __flutter_node(id)\n"
                        + "  local props = setmetatable({}, {\n"
                        + "    __newindex = function(t, k, v) __flutter_apply(id, k, v) end\n"
                        + "  })\n"
                        + "  return setmetatable({ __id = id, dart = props }, {\n"
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
                if (!isLuaIdentifier(id)) {
                    warn(L, "id \"" + id + "\" 不是合法 Lua 标识符（或为 Lua 保留字），无法生成全局句柄；"
                            + "可用 flutterNode(\"" + id + "\") 取该节点句柄。");
                    continue;
                }
                if (!canBindGlobal(L, id)) {
                    warn(L, "id \"" + id + "\" 会覆盖已有全局变量，已跳过绑定；"
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
    /** Lua 保留字：不能作为全局名。 */
    private static final Set<String> LUA_KEYWORDS = new HashSet<String>(java.util.Arrays.asList(
            "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
            "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return",
            "then", "true", "until", "while"));

    /**
     * 是否是合法的 Lua 标识符：首字符为字母或下划线，后续为字母/数字/下划线。
     *
     * <p>刻意用 {@link Character#isLetter}/{@link Character#isLetterOrDigit}（而非只认 ASCII 的正则）：
     * LuaJ 允许非 ASCII 字母（中文等）作标识符，Lua 侧写 {@code function 按钮.onClick() end} 是完全合法的。
     * 排除 Lua 保留字（如 end/function），它们无法作为全局名使用。
     */
    private static boolean isLuaIdentifier(String s) {
        if (s == null || s.isEmpty() || LUA_KEYWORDS.contains(s)) {
            return false;
        }
        char c0 = s.charAt(0);
        if (c0 != '_' && !Character.isLetter(c0)) {
            return false;
        }
        for (int i = 1; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c != '_' && !Character.isLetterOrDigit(c)) {
                return false;
            }
        }
        return true;
    }

    /** 目标全局可用吗：为 nil，或已是本机制生成的代理表（重复渲染同一 id）。 */
    private static boolean canBindGlobal(LuaState L, String id) {
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

    /** 把事件分发给对应 id 句柄上注册的回调（onClick / onChange）。返回是否真的调用了回调。 */
    private static boolean dispatchNodeHandler(LuaState L, String id, JSONObject event) throws LuaException {
        LuaObject handlers = L.getLuaObject("__flutter_handlers");
        if (handlers == null || !handlers.isTable()) {
            return false;
        }
        LuaObject entry = handlers.getField(id);
        if (entry == null || !entry.isTable()) {
            return false;
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
                return true;
            }
        }
        return false;
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

    /** 事件调试开关：Lua 里调 flutterDebug(true) / Flutter调试(true) 打开，会把每个事件的到达与处理情况打到控制台。 */
    private static volatile boolean DEBUG_EVENTS = false;

    /** 把消息打到 Lua 控制台（走 Lua 的 print；失败不影响主流程）。 */
    private static void luaPrint(LuaState L, String msg) {
        if (L == null) return;
        final int top = L.getTop();
        try {
            L.getGlobal("print");
            if (L.isFunction(-1)) {
                L.pushString(msg);
                if (L.pcall(1, 0, 0) != 0) {
                    L.pop(1);
                }
            } else {
                L.pop(1);
            }
        } catch (Throwable ignored) {
            // 诊断输出失败不应影响主流程
        } finally {
            int extra = L.getTop() - top;
            if (extra > 0) L.pop(extra);
        }
    }

    /** 执行 Lua 函数并检查错误，失败时记录到 logcat【和 Lua 控制台】（不再静默吞掉）。 */
    private static void pcallChecked(LuaState L, int nargs, String what) {
        if (L.pcall(nargs, 0, 0) != 0) {
            String err = L.toString(-1);
            L.pop(1);
            logError(what + " 执行出错: " + err, null);
            luaPrint(L, "[Flutter] " + what + " 执行出错: " + err);
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
                final List<LuaState> states = statesOf(context);
                String evtName = null;
                String evtType = null;
                try {
                    org.json.JSONObject probe = new org.json.JSONObject(json);
                    evtName = probe.optString("name", null);
                    org.json.JSONObject d = probe.optJSONObject("data");
                    evtType = d == null ? null : d.optString("type", null);
                } catch (Exception ignored) {
                }
                boolean handled = false;
                // 广播给该 context 下的所有 LuaState：主脚本 + 各 thread/task。
                // 没定义处理器的状态自然什么都不做。
                for (LuaState L : states) {
                    synchronized (L) {
                        try {
                            org.json.JSONObject o = new org.json.JSONObject(json);
                            String name = o.optString("name", null);

                            // 分发顺序：具体回调先走，总监听（onFlutterEvent）最后旁路通知。
                            // 以前定义了就 return，会把 h.onClick / 同名全局函数全吞掉。
                            if (name != null && !name.isEmpty()) {
                                // 1) AndroLua 风格：事件名 -> 同名全局 Lua 函数
                                LuaObject fn = L.getLuaObject(name);
                                if (fn.isFunction()) {
                                    fn.push();
                                    LuaJson.pushJava(L, o.opt("data"));
                                    pcallChecked(L, 1, "事件 " + name);
                                    handled = true;
                                }
                                // 2) id 句柄回调：h.onClick = fn / h.onChange = fn
                                if (dispatchNodeHandler(L, name, o)) {
                                    handled = true;
                                }
                            }

                            // 3) 总监听：定义了 onFlutterEvent / 收到Flutter事件 就会收到所有事件（不再阻断上面）
                            LuaObject any = L.getLuaObject("onFlutterEvent");
                            if (!any.isFunction()) {
                                any = L.getLuaObject("收到Flutter事件");
                            }
                            if (any.isFunction()) {
                                any.push();
                                LuaJson.pushJson(L, json);
                                pcallChecked(L, 1, "onFlutterEvent");
                                handled = true;
                            }
                        } catch (Exception e) {
                            logError("处理 Flutter 事件失败: " + json, e);
                        }
                    }
                }

                // 诊断：开了 flutterDebug(true) 就报告每个事件；否则只在“没人处理”时提示一次，
                // 避免“点了没反应、又没有任何线索”。
                LuaState first = states.isEmpty() ? null : states.get(0);
                if (DEBUG_EVENTS) {
                    luaPrint(first, "[Flutter] 事件 name=" + evtName + " type=" + evtType
                            + " handled=" + handled + " states=" + states.size());
                } else if (!handled && evtName != null && !evtName.isEmpty()) {
                    luaPrint(first, "[Flutter] 事件 \"" + evtName + "\" 没有任何处理器；"
                            + "可在同名全局函数、id 句柄的 onClick/onChange、或 收到Flutter事件 里处理");
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
