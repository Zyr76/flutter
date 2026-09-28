package com.androlua.flutter;

import com.luajava.LuaState;

import org.json.JSONArray;
import org.json.JSONObject;
import org.json.JSONTokener;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Lua 值与 JSON 之间的互转。
 *
 * <p>Lua 侧把布局描述/参数写成表（table），这里转成 JSON 交给 Flutter 引擎；
 * Dart 返回的 JSON 结果再还原成 Lua 表。
 */
public final class LuaJson {

    private LuaJson() {
    }

    /** 把栈上 idx 处的 Lua 值编码成 JSON 字符串。 */
    public static String encode(LuaState L, int idx) {
        Object value = toJava(L, absIndex(L, idx));
        if (value == null) {
            return "null";
        }
        if (value instanceof JSONArray || value instanceof JSONObject) {
            return value.toString();
        }
        if (value instanceof Boolean || value instanceof Number) {
            return String.valueOf(value);
        }
        return JSONObject.quote(String.valueOf(value));
    }

    /** 把 Java 结果（Map/List/基本类型）压成 Lua 值。 */
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

    /** 把 JSON 字符串压成 Lua 值。 */
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
        Map<String, Object> map = new java.util.LinkedHashMap<String, Object>();
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
            JSONArray arr = new JSONArray();
            Object[] sorted = new Object[entries.size()];
            for (Object[] e : entries) {
                sorted[(int) (((Long) e[0]).longValue() - 1)] = e[1];
            }
            for (Object v : sorted) {
                arr.put(v == null ? JSONObject.NULL : v);
            }
            return arr;
        }

        JSONObject obj = new JSONObject();
        for (Object[] e : entries) {
            try {
                obj.put(String.valueOf(e[0]), e[1] == null ? JSONObject.NULL : e[1]);
            } catch (Exception ignored) {
            }
        }
        return obj;
    }
}
