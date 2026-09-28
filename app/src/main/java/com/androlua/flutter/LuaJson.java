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
 * <p>规范化支持两种写法：
 * <pre>
 * -- 1) 直接给 type
 * flutterRender{ type="Column", children={ {type="Text", text="hi"} } }
 *
 * -- 2) AndroLua 布局表风格：首个元素是控件名，子节点是数字下标项
 * flutterRender{
 *   列, 方向="vertical",
 *   { 文本, 文字="hi" },
 *   { 按钮, 文字="点我", 点击=function() end },
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
    // 规范化：AndroLua 布局表 / 中文键 -> 统一 spec
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
            } else if (map.containsKey("控件")) {
                type = map.get("控件");
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
                if ("type".equals(k) || "控件".equals(k) || "children".equals(k)) {
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

    /** 把 key=value 收进规范节点：键做别名映射，值做规整（fill/match、加粗、对齐等）。 */
    private static void addProp(Map<String, Object> node, String key, Object value) {
        String k = propKey(key);

        if ("加粗".equals(key) || "粗体".equals(key) || "粗体字".equals(key)) {
            if (isTruthy(value)) {
                node.put("fontWeight", "bold");
            }
            return;
        }
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
            case "alignment":
                node.put(k, mapAlignment(value));
                break;
            case "textAlign":
                node.put(k, mapTextAlign(value));
                break;
            case "mainAxisAlignment":
                node.put(k, mapMain(value));
                break;
            case "crossAxisAlignment":
                node.put(k, mapCross(value));
                break;
            case "crossAxisCount":
                node.put(k, value);
                break;
            default:
                node.put(k, value);
        }
    }

    private static final Map<String, String> ALIGN = new HashMap<String, String>();
    private static final Map<String, String> CROSS = new HashMap<String, String>();
    private static final Map<String, String> MAIN = new HashMap<String, String>();
    private static final Map<String, String> TEXT_ALIGN = new HashMap<String, String>();

    static {
        ALIGN.put("居中", "center");
        ALIGN.put("中", "center");
        ALIGN.put("左上", "topleft");
        ALIGN.put("右上", "topright");
        ALIGN.put("左下", "bottomleft");
        ALIGN.put("右下", "bottomright");
        ALIGN.put("两端", "spacebetween");
        ALIGN.put("均匀", "spacearound");
        ALIGN.put("环绕", "spaceevenly");

        CROSS.put("居中", "center");
        CROSS.put("起始", "start");
        CROSS.put("开始", "start");
        CROSS.put("结束", "end");
        CROSS.put("拉伸", "stretch");
        CROSS.put("铺满", "stretch");

        MAIN.put("居中", "center");
        MAIN.put("起始", "start");
        MAIN.put("开始", "start");
        MAIN.put("结束", "end");
        MAIN.put("两端", "spaceBetween");
        MAIN.put("均匀", "spaceEvenly");

        TEXT_ALIGN.put("居中", "center");
        TEXT_ALIGN.put("中", "center");
        TEXT_ALIGN.put("左", "left");
        TEXT_ALIGN.put("右", "right");
    }

    private static Object mapAlignment(Object v) {
        if (v instanceof String) {
            String s = ALIGN.get(v);
            return s != null ? s : v;
        }
        return v;
    }

    private static Object mapCross(Object v) {
        if (v instanceof String) {
            String s = CROSS.get(v);
            return s != null ? s : v;
        }
        return v;
    }

    private static Object mapMain(Object v) {
        if (v instanceof String) {
            String s = MAIN.get(v);
            return s != null ? s : v;
        }
        return v;
    }

    private static Object mapTextAlign(Object v) {
        if (v instanceof String) {
            String s = TEXT_ALIGN.get(v);
            return s != null ? s : v;
        }
        return v;
    }

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
        String s = String.valueOf(v);
        return s.equals("1") || s.equalsIgnoreCase("true") || s.equals("是") || s.equals("加粗");
    }

    // ---- 键别名 ----
    private static final Map<String, String> PROPS = new HashMap<String, String>();

    static {
        alias("text", "文字", "文本", "文本内容", "文字内容", "value");
        alias("fontSize", "字号", "字体大小", "字体尺寸");
        alias("color", "颜色", "文字颜色", "背景", "背景色", "backgroundColor", "textColor", "bg");
        alias("fontWeight", "字重", "字体粗细");
        alias("width", "宽", "宽度", "layout_width");
        alias("height", "高", "高度", "layout_height");
        alias("weight", "权重", "layout_weight", "flex");
        alias("padding", "内边距", "内间距");
        alias("margin", "外边距", "外间距");
        alias("radius", "圆角", "半径", "borderRadius");
        alias("borderWidth", "边框宽", "边框宽度");
        alias("borderColor", "边框色", "边框颜色");
        alias("alignment", "对齐", "对齐方式", "layout_gravity", "gravity");
        alias("mainAxisAlignment", "主轴对齐");
        alias("crossAxisAlignment", "交叉轴对齐");
        alias("mainAxisSize", "主轴尺寸");
        alias("gap", "间距", "子间距", "spacing");
        alias("runSpacing", "行距", "换行间距");
        alias("onTap", "点击", "onClick", "点击事件", "单击");
        alias("onChange", "变化", "onChanged", "值变化");
        alias("hint", "提示", "占位");
        alias("label", "标签");
        alias("icon", "图标");
        alias("size", "尺寸");
        alias("url", "地址", "图片地址", "src");
        alias("elevation", "海拔", "阴影");
        alias("opacity", "不透明度", "透明度");
        alias("aspectRatio", "宽高比", "比例");
        alias("crossAxisCount", "列数", "列数count");
        alias("maxLines", "最大行数");
        alias("textAlign", "文字对齐");
        alias("min", "最小值");
        alias("max", "最大值");
        alias("thickness", "粗细");
        alias("title", "标题");
        alias("subtitle", "副标题");
        alias("leading", "左侧");
        alias("trailing", "右侧");
        alias("left", "左");
        alias("top", "上");
        alias("right", "右");
        alias("bottom", "下");
        alias("shrinkWrap", "自适应高度");
        alias("viewType", "视图类型");
        alias("textAlign", "文字对齐");
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

    // ---- 控件名（中文 -> Flutter 控件） ----
    static final Map<String, String> TYPES = new HashMap<String, String>();

    static {
        type("Column", "列", "竖列", "垂直布局", "纵向布局");
        type("Row", "行", "横排", "水平布局", "横向布局");
        type("Stack", "堆叠", "叠加", "层叠");
        type("Container", "容器");
        type("Padding", "内边距", "边距");
        type("Center", "居中");
        type("Expanded", "弹性", "拉伸");
        type("SizedBox", "固定尺寸", "占位", "空白");
        type("Spacer", "弹簧", "挤压");
        type("Text", "文本", "文字");
        type("SelectableText", "可选文本");
        type("Button", "按钮");
        type("ElevatedButton", "凸起按钮");
        type("TextButton", "文字按钮");
        type("FilledButton", "填充按钮");
        type("IconButton", "图标按钮");
        type("FloatingActionButton", "悬浮按钮");
        type("Icon", "图标");
        type("Image", "图片");
        type("Card", "卡片");
        type("ListView", "列表", "列表视图");
        type("GridView", "网格", "网格视图");
        type("Wrap", "流式布局", "自动换行");
        type("Align", "对齐容器");
        type("AspectRatio", "宽高比");
        type("ClipRRect", "圆角裁剪");
        type("Opacity", "透明");
        type("SafeArea", "安全区");
        type("Positioned", "定位", "绝对定位");
        type("CircleAvatar", "头像", "圆头像");
        type("Chip", "标签");
        type("Checkbox", "复选框", "勾选框");
        type("Slider", "滑块", "滑动条");
        type("Switch", "开关");
        type("TextField", "输入框", "编辑框");
        type("Divider", "分割线");
        type("CircularProgressIndicator", "圆形进度", "圆形进度条");
        type("LinearProgressIndicator", "线性进度", "进度条");
        type("ListTile", "列表项");
        type("AndroidView", "原生控件", "安卓控件");
    }

    private static void type(String canonical, String... names) {
        TYPES.put(canonical, canonical);
        for (String n : names) {
            TYPES.put(n, canonical);
        }
    }

    static String widgetType(Object head) {
        if (head == null) {
            return "Container";
        }
        if (head instanceof String) {
            return resolveTypeName(((String) head).trim());
        }
        // Java Class / 实例：取简单类名（可容忍 Android 类名，如 android.widget.Button -> Button）
        String name = head instanceof Class ? ((Class<?>) head).getSimpleName() : head.getClass().getSimpleName();
        return resolveTypeName(name);
    }

    /** 控件名归一：中文名 / 全限定类名 / 带 View 后缀 -> Flutter 控件名。 */
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
    // Java -> JSON（规范化后的 spec）
    // ============================================================

    static String toJsonString(Object value) {
        StringBuilder sb = new StringBuilder();
        write(sb, value, null);
        return sb.toString();
    }

    private static void write(StringBuilder sb, Object value, String key) {
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
        if (value instanceof LuaJsonSerializable) {
            sb.append(((LuaJsonSerializable) value).toJsonString());
            return;
        }
        if (value instanceof JSONArray) {
            write((StringBuilder) sb, jsonToJava((JSONArray) value), key);
            return;
        }
        if (value instanceof JSONObject) {
            write((StringBuilder) sb, jsonToJava((JSONObject) value), key);
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
            write(sb, e.getValue(), String.valueOf(e.getKey()));
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
            write(sb, v, null);
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

    /** 供测试/扩展使用：可自定义 JSON 序列化的值。 */
    interface LuaJsonSerializable {
        String toJsonString();
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
