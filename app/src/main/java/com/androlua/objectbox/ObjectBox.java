package com.androlua.objectbox;

import android.content.Context;

import java.util.ArrayList;
import java.util.List;

import io.objectbox.Box;
import io.objectbox.query.Query;
// ObjectBox 5.x 的字符串条件必须显式指定匹配方式
import io.objectbox.query.QueryBuilder.StringOrder;

/**
 * ObjectBox 的静态门面：Lua 侧通过 {@code luajava.bindClass("com.androlua.objectbox.ObjectBox")}
 * 直接调用这里的方法（见 resources/lua/objectbox.lua）。
 *
 * <p>库在首次使用时才打开（{@link #box()} 懒加载），避免拖慢应用启动。
 */
public final class ObjectBox {

    private static Context appContext;
    private static Box<LuaObject> box;

    private ObjectBox() {
    }

    /** 由 LuaApplication 在启动时调用，只记录 Application 上下文，不打开库。 */
    public static void init(Context context) {
        if (appContext == null && context != null) {
            appContext = context.getApplicationContext();
        }
    }

    private static synchronized Box<LuaObject> box() {
        if (box == null) {
            if (appContext == null) {
                throw new IllegalStateException(
                        "ObjectBox 未初始化：请在 Application 里调用 ObjectBox.init(context)");
            }
            box = MyObjectBox.builder().androidContext(appContext).build().boxFor(LuaObject.class);
        }
        return box;
    }

    private static Query<LuaObject> one(String space, String key) {
        return box().query()
                .equal(LuaObject_.space, space, StringOrder.CASE_SENSITIVE)
                .and()
                .equal(LuaObject_.key, key, StringOrder.CASE_SENSITIVE)
                .build();
    }

    /** 写入或更新一个值，返回该条记录的 id。 */
    public static long put(String space, String key, String value) {
        LuaObject obj = one(space, key).findUnique();
        if (obj == null) {
            obj = new LuaObject();
            obj.space = space;
            obj.key = key;
        }
        obj.value = value;
        obj.updatedAt = System.currentTimeMillis();
        box().put(obj);
        return obj.id;
    }

    /** 读一个值；键不存在返回 null。 */
    public static String get(String space, String key) {
        LuaObject obj = one(space, key).findUnique();
        return obj == null ? null : obj.value;
    }

    /** 删除一个键，返回是否真的删掉了。 */
    public static boolean remove(String space, String key) {
        Query<LuaObject> q = one(space, key);
        if (q.count() == 0) {
            return false;
        }
        q.remove();
        return true;
    }

    /** 某个 space 下的全部键。 */
    public static List<String> keys(String space) {
        List<LuaObject> list = box().query()
                .equal(LuaObject_.space, space, StringOrder.CASE_SENSITIVE)
                .build()
                .find();
        List<String> out = new ArrayList<String>(list.size());
        for (LuaObject o : list) {
            out.add(o.key);
        }
        return out;
    }

    /** 某个 space 下的记录数。 */
    public static long count(String space) {
        return box().query()
                .equal(LuaObject_.space, space, StringOrder.CASE_SENSITIVE)
                .build()
                .count();
    }

    /** 清空某个 space，返回删除的条数。 */
    public static long clear(String space) {
        Query<LuaObject> q = box().query()
                .equal(LuaObject_.space, space, StringOrder.CASE_SENSITIVE)
                .build();
        long n = q.count();
        q.remove();
        return n;
    }
}
