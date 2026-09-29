package com.androlua.flutter;

import com.luajava.LuaState;

import org.json.JSONArray;
import org.json.JSONObject;
import org.json.JSONTokener;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

/**
 * Lua 值与 JSON 之间的互转，并把「AndroLua 布局表」规范化成 Flutter 渲染器认识的 spec。
 *
 * <p>布局写法与 loadlayout 一致：首个元素是控件，其余数字下标项是子控件，属性写 key=value。
 * 控件名用 Flutter 的名字（Column/Row/Text/Button…），也兼容 Android 类名归一。
 * <pre>
 * 渲染Flutter{
 *   Column, gap = 12, layout_width = "fill",
 *   { Text, text = "hi", fontSize = 20 },
 *   { Button, text = "点我", onClick = { call = "ping" } },
 * }
 * </pre>
 */
public final class LuaJson {

    private LuaJson() {
    }

    /** 原始 Lua 表 -> JSON（用于 dartCall 参数等）。 */
    public static String encode(LuaState L, int idx) {
        return toJsonString(toJava(L, absIndex(L, idx)));
    }

    /** AndroLua 布局表 -> 规范化 spec 的 JSON（用于 flutterRender）。 */
    public static String encodeSpec(LuaState L, int idx) {
        return toJsonString(normalizeNode(toJava(L, absIndex(L, idx))));
    }

    // ============================================================
    // Lua -> Java
    // ============================================================

    private static int absIndex(LuaState L, int idx) {
        return idx > 0 ? idx : L.getTop() + idx + 1;
    }

    private static Object toJava(LuaState L, int abs) {
        switch (L.type(abs)) {
            case LuaState.LUA_TNIL:
                return null;
            case LuaState.LUA_TBOOLEAN:
                return L.toBoolean(abs);
            case LuaState.LUA_TNUMBER:
            case LuaState.LUA_TINTEGER: {
                double d = L.toNumber(abs);
                if (d == Math.floor(d) && !Double.isInfinite(d) && Math.abs(d) < 9.007199254740992E15) {
                    return (long) d;
                }
                return d;
            }
            case LuaState.LUA_TSTRING:
                return L.toString(abs);
            case LuaState.LUA_TTABLE:
                return tableToJava(L, abs);
            case LuaState.LUA_TUSERDATA:
                try {
                    Object o = L.toJavaObject(abs);
                    if (o != null) {
                        return o;
                    }
                } catch (Throwable ignored) {
                }
                return L.toString(abs);
            default:
                return L.toString(abs);
        }
    }

    private static Object tableToJava(LuaState L, int abs) {
        int len = L.rawLen(abs);
        List<Object[]> entries = new ArrayList<Object[]>();
        boolean array = true;
        int intKeys = 0;

        L.pushNil();
        while (L.next(abs) != 0) {
            Object key;
            int kt = L.type(-2);
            if (kt == LuaState.LUA_TNUMBER || kt == LuaState.LUA_TINTEGER) {
                long k = L.toInteger(-2);
                key = k;
                if (k >= 1 && k <= len) {
                    intKeys++;
                } else {
                    array = false;
                }
            } else {
                key = L.toString(-2);
                array = false;
            }
            Object value = toJava(L, absIndex(L, -1));
            entries.add(new Object[]{key, value});
            L.pop(1);
        }

        if (array && intKeys == entries.size()) {
            List<Object> list = new ArrayList<Object>(entries.size());
            Object[] sorted = new Object[entries.size()];
            for (Object[] e : entries) {
                sorted[(int) (((Long) e[0]).longValue() - 1)] = e[1];
            }
            for (Object v : sorted) {
                list.add(v);
            }
            return list;
        }

        Map<String, Object> map = new LinkedHashMap<String, Object>();
        for (Object[] e : entries) {
            map.put(String.valueOf(e[0]), e[1]);
        }
        return map;
    }

    // ============================================================
    // 规范化：AndroLua 布局表 -> 统一 spec
    // ============================================================

    static Object normalizeNode(Object raw) {
        if (raw == null) {
            return null;
        }
        if (raw instanceof String || raw instanceof Number || raw instanceof Boolean) {
            Map<String, Object> text = new LinkedHashMap<String, Object>();
            text.put("type", "Text");
            text.put("text", String.valueOf(raw));
            return text;
        }

        if (raw instanceof List) {
            List<?> list = (List<?>) raw;
            if (list.isEmpty()) {
                return null;
            }
            Map<String, Object> node = new LinkedHashMap<String, Object>();
            node.put("type", widgetType(list.get(0)));
            List<Object> children = new ArrayList<Object>();
            for (int i = 1; i < list.size(); i++) {
                Object c = normalizeNode(list.get(i));
                if (c != null) {
                    children.add(c);
                }
            }
            if (!children.isEmpty()) {
                node.put("children", children);
            }
            return node;
        }

        if (raw instanceof Map) {
            Map<?, ?> map = (Map<?, ?>) raw;
            Map<String, Object> node = new LinkedHashMap<String, Object>();

            Object type = null;
            boolean usedOne = false;
            if (map.containsKey("type")) {
                type = map.get("type");
            } else if (map.containsKey("1")) {
                type = map.get("1");
                usedOne = true;
            }

            List<Object> children = new ArrayList<Object>();

            Object given = map.get("children");
            if (given instanceof List) {
                for (Object c : (List<?>) given) {
                    Object n = normalizeNode(c);
                    if (n != null) {
                        children.add(n);
                    }
                }
            } else if (given instanceof Map) {
                Object n = normalizeNode(given);
                if (n != null) {
                    children.add(n);
                }
            }

            TreeMap<Integer, Object> numeric = new TreeMap<Integer, Object>();
            for (Map.Entry<?, ?> e : map.entrySet()) {
                String k = String.valueOf(e.getKey());
                if (isInt(k)) {
                    int idx = Integer.parseInt(k);
                    if (idx == 1 && usedOne) {
                        continue;
                    }
                    numeric.put(idx, e.getValue());
                    continue;
                }
                if ("type".equals(k) || "children".equals(k)) {
                    continue;
                }
                addProp(node, k, e.getValue());
            }
            for (Object v : numeric.values()) {
                Object n = normalizeNode(v);
                if (n != null) {
                    children.add(n);
                }
            }

            if (type == null && children.isEmpty() && node.containsKey("text")) {
                type = "Text";
            }
            if (type == null) {
                type = children.isEmpty() ? "Container" : "Column";
            }
            Map<String, Object> ret = new LinkedHashMap<String, Object>();
            ret.put("type", widgetType(type));
            ret.putAll(node);
            if (!children.isEmpty()) {
                ret.put("children", children);
            }
            return ret;
        }

        return null;
    }

    private static boolean isInt(String s) {
        if (s == null || s.isEmpty()) {
            return false;
        }
        for (int i = 0; i < s.length(); i++) {
            if (!Character.isDigit(s.charAt(i))) {
                return false;
            }
        }
        return true;
    }

    private static void addProp(Map<String, Object> node, String key, Object value) {
        String k = propKey(key);
        if (k == null) {
            return;
        }
        switch (k) {
            case "width":
            case "height":
                node.put(k, normalizeDim(value));
                break;
            case "fontWeight":
                node.put(k, isTruthy(value) ? "bold" : String.valueOf(value));
                break;
            default:
                node.put(k, value);
        }
    }

    /** 宽/高取值规整："fill"/"match_parent" -> "fill"；"wrap"/"自适应"类 -> 去掉。 */
    private static Object normalizeDim(Object v) {
        if (v instanceof String) {
            String s = ((String) v).trim().toLowerCase();
            if (s.equals("fill") || s.equals("match") || s.equals("match_parent")
                    || s.equals("充满") || s.equals("填充") || s.equals("铺满")) {
                return "fill";
            }
            if (s.equals("wrap") || s.equals("wrap_content") || s.equals("自适应") || s.equals("包裹")) {
                return null;
            }
        }
        return v;
    }

    private static boolean isTruthy(Object v) {
        if (v == null) {
            return false;
        }
        if (v instanceof Boolean) {
            return (Boolean) v;
        }
        if (v instanceof Number) {
            return ((Number) v).doubleValue() != 0;
        }
        return "true".equalsIgnoreCase(String.valueOf(v));
    }

    // ---- 属性键别名（规范键即自身；这里只列与规范键不同的别名） ----
    private static final Map<String, String> PROPS = new HashMap<String, String>();

    static {
        alias("width", "layout_width");
        alias("height", "layout_height");
        alias("weight", "layout_weight", "flex");
        alias("padding", "layout_padding");
        alias("margin", "layout_margin");
        alias("radius", "borderRadius", "cornerRadius");
        alias("alignment", "layout_gravity", "gravity", "align");
        alias("onTap", "onClick", "click", "onPressed");
        alias("onChange", "onChanged");
        alias("gap", "spacing");
        alias("text", "value");
        alias("fontWeight", "bold", "strong");
        alias("textAlign", "text_alignment");
        alias("backgroundColor", "bg");
    }

    private static void alias(String canonical, String... names) {
        for (String n : names) {
            PROPS.put(n, canonical);
        }
    }

    private static String propKey(String key) {
        if (key == null) {
            return null;
        }
        String c = PROPS.get(key);
        return c != null ? c : key;
    }

    // ---- 控件名 ----
    static final Map<String, String> TYPES = new HashMap<String, String>();

    static {
        String[] names = {
                "Column", "Row", "Stack", "Container", "Padding", "Center", "Expanded",
                "SizedBox", "Spacer", "Text", "SelectableText", "Button", "ElevatedButton",
                "TextButton", "FilledButton", "OutlinedButton", "IconButton", "FloatingActionButton",
                "Icon", "Image", "Card", "ListView", "GridView", "Wrap", "Align", "AspectRatio",
                "ClipRRect", "Opacity", "SafeArea", "Positioned", "CircleAvatar", "Chip",
                "Checkbox", "Slider", "Switch", "TextField", "Divider",
                "CircularProgressIndicator", "LinearProgressIndicator", "ListTile", "AndroidView",
                // Scaffold 体系与常用控件
                "Scaffold", "AppBar", "Drawer", "UserAccountsDrawerHeader",
                "BottomNavigationBar", "BottomNavigationBarItem", "TabBar", "Tab", "TabBarView",
                "DefaultTabController", "SingleChildScrollView", "InkWell", "GestureDetector",
                "Transform", "FractionallySizedBox", "DropdownButton", "DropdownButtonFormField",
                // 二维码 / 地图 / 图表 / 媒体
                "QrCode", "QrImage", "FlutterMap", "Map", "Chart", "LineChart", "BarChart", "PieChart",
                "VideoPlayer", "Video", "AudioPlayer", "Audio",
                // 反馈 / 更多 Material 控件 / 日期 / 动画
                "Tooltip", "Badge", "Placeholder", "RefreshIndicator",
                "SwitchListTile", "CheckboxListTile", "RadioListTile", "Radio",
                "ExpansionTile", "Stepper", "DataTable",
                "CalendarDatePicker", "DatePicker",
                "AnimatedOpacity", "AnimatedContainer"
        };
        for (String n : names) {
            TYPES.put(n, n);
        }
        // 少量兼容别名（Android 常用名 -> Flutter 控件）
        TYPES.put("EditText", "TextField");
        TYPES.put("Android", "AndroidView");
    }

    static String widgetType(Object head) {
        if (head == null) {
            return "Container";
        }
        if (head instanceof String) {
            return resolveTypeName(((String) head).trim());
        }
        String name = head instanceof Class ? ((Class<?>) head).getSimpleName() : head.getClass().getSimpleName();
        return resolveTypeName(name);
    }

    /** 控件名归一：全限定类名 / 带 View·Layout 后缀的 Android 类名 -> Flutter 控件名。 */
    private static String resolveTypeName(String s) {
        if (s == null || s.isEmpty()) {
            return "Container";
        }
        if (TYPES.containsKey(s)) {
            return TYPES.get(s);
        }
        String simple = s;
        if (simple.startsWith("class ")) {
            simple = simple.substring(6).trim();
        }
        int dot = simple.lastIndexOf('.');
        if (dot >= 0) {
            simple = simple.substring(dot + 1);
        }
        if (TYPES.containsKey(simple)) {
            return TYPES.get(simple);
        }
        for (String suffix : new String[]{"View", "Layout", "Widget"}) {
            if (simple.endsWith(suffix) && simple.length() > suffix.length()) {
                String base = simple.substring(0, simple.length() - suffix.length());
                if (TYPES.containsKey(base)) {
                    return TYPES.get(base);
                }
            }
        }
        return simple.isEmpty() ? "Container" : simple;
    }

    // ============================================================
    // Java -> JSON
    // ============================================================

    static String toJsonString(Object value) {
        StringBuilder sb = new StringBuilder();
        write(sb, value);
        return sb.toString();
    }

    private static void write(StringBuilder sb, Object value) {
        if (value == null) {
            sb.append("null");
            return;
        }
        if (value instanceof String) {
            writeString(sb, (String) value);
            return;
        }
        if (value instanceof Boolean) {
            sb.append(value.toString());
            return;
        }
        if (value instanceof Number) {
            double d = ((Number) value).doubleValue();
            if (d == Math.floor(d) && !Double.isInfinite(d)) {
                sb.append(((Number) value).longValue());
            } else {
                sb.append(value.toString());
            }
            return;
        }
        if (value instanceof JSONArray) {
            write(sb, jsonToJava((JSONArray) value));
            return;
        }
        if (value instanceof JSONObject) {
            write(sb, jsonToJava((JSONObject) value));
            return;
        }
        if (value instanceof Map) {
            writeObject(sb, (Map<?, ?>) value);
            return;
        }
        if (value instanceof Iterable) {
            writeArray(sb, (Iterable<?>) value);
            return;
        }
        writeString(sb, String.valueOf(value));
    }

    private static void writeObject(StringBuilder sb, Map<?, ?> map) {
        sb.append('{');
        boolean first = true;
        for (Map.Entry<?, ?> e : map.entrySet()) {
            if (!first) {
                sb.append(',');
            }
            first = false;
            writeString(sb, String.valueOf(e.getKey()));
            sb.append(':');
            write(sb, e.getValue());
        }
        sb.append('}');
    }

    private static void writeArray(StringBuilder sb, Iterable<?> list) {
        sb.append('[');
        boolean first = true;
        for (Object v : list) {
            if (!first) {
                sb.append(',');
            }
            first = false;
            write(sb, v);
        }
        sb.append(']');
    }

    private static void writeString(StringBuilder sb, String s) {
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
                case '\b':
                    sb.append("\\b");
                    break;
                case '\f':
                    sb.append("\\f");
                    break;
                default:
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        sb.append('"');
    }

    // ============================================================
    // JSON -> Lua
    // ============================================================

    public static void pushJava(LuaState L, Object value) {
        if (value == null) {
            L.pushNil();
            return;
        }
        if (value instanceof Boolean) {
            L.pushBoolean((Boolean) value);
            return;
        }
        if (value instanceof Number) {
            L.pushNumber(((Number) value).doubleValue());
            return;
        }
        if (value instanceof Map) {
            L.newTable();
            for (Map.Entry<?, ?> e : ((Map<?, ?>) value).entrySet()) {
                L.pushString(String.valueOf(e.getKey()));
                pushJava(L, e.getValue());
                L.setTable(-3);
            }
            return;
        }
        if (value instanceof List) {
            List<?> list = (List<?>) value;
            L.newTable();
            for (int i = 0; i < list.size(); i++) {
                pushJava(L, list.get(i));
                L.rawSetI(-2, i + 1);
            }
            return;
        }
        if (value instanceof JSONObject) {
            pushJava(L, jsonToJava((JSONObject) value));
            return;
        }
        if (value instanceof JSONArray) {
            pushJava(L, jsonToJava((JSONArray) value));
            return;
        }
        L.pushString(String.valueOf(value));
    }

    public static void pushJson(LuaState L, String json) {
        if (json == null) {
            L.pushNil();
            return;
        }
        try {
            Object value = new JSONTokener(json).nextValue();
            pushJava(L, value instanceof JSONObject ? jsonToJava((JSONObject) value)
                    : value instanceof JSONArray ? jsonToJava((JSONArray) value) : value);
        } catch (Exception e) {
            L.pushString(json);
        }
    }

    private static Object jsonToJava(JSONObject obj) {
        Map<String, Object> map = new LinkedHashMap<String, Object>();
        java.util.Iterator<String> it = obj.keys();
        while (it.hasNext()) {
            String k = it.next();
            Object v = obj.opt(k);
            map.put(k, v == JSONObject.NULL ? null : v);
        }
        return map;
    }

    private static Object jsonToJava(JSONArray arr) {
        List<Object> list = new ArrayList<Object>(arr.length());
        for (int i = 0; i < arr.length(); i++) {
            Object v = arr.opt(i);
            list.add(v == JSONObject.NULL ? null : v);
        }
        return list;
    }
}
