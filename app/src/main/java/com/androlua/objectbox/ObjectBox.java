package com.androlua.objectbox;

import android.content.Context;

import java.util.ArrayList;
import java.util.List;

import io.objectbox.Box;
import io.objectbox.query.Query;
import io.objectbox.query.QueryBuilder.StringOrder;

/**
 * ObjectBox 的静态门面：Lua 侧通过 {@code luajava.bindClass("com.androlua.objectbox.ObjectBox")}
 * 直接调用这里的方法（见 resources/lua/objectbox.lua）。
 *
 * <p>关键设计：主键不是自增 id，而是 <b>hash(space + key)</b>。
 * 因为 ObjectBox 按键查只能建 query（实测约 0.12 ms/次，是 id 直取的 60 倍），
 * 而 {@code Box.get(long)} 只要 0.002 ms。把 key 映射成 id 后：
 * 读/写/删都是 id 直取，热路径上不再出现 query。
 *
 * <p>单条写仍会各自提交一个事务（引擎特性，实测约 0.15 ms/条，比 SQLite 单事务慢），
 * 所以批量场景请用 {@link #putMany}/{@link #getMany}/{@link #removeMany}，一次调用一个事务。
 */
public final class ObjectBox {

    /** 旧数据的自增 id 与 hash id 的迁移标记。 */
    private static final String META_SPACE = "__meta__";
    private static final String META_KEY = "id_scheme";
    private static final String SCHEME = "hash64-v1";

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

    /** FNV-1a 64 位；结果恒为正且非 0（0 在 ObjectBox 表示“新对象”）。 */
    private static long idOf(String space, String key) {
        long h = 0xcbf29ce484222325L;
        String s = space + '\u0000' + key;
        for (int i = 0; i < s.length(); i++) {
            h ^= s.charAt(i);
            h *= 0x100000001b3L;
        }
        h &= Long.MAX_VALUE;
        return h == 0 ? 1 : h;
    }

    private static synchronized Box<LuaObject> box() {
        if (box == null) {
            if (appContext == null) {
                throw new IllegalStateException(
                        "ObjectBox 未初始化：请在 Application 里调用 ObjectBox.init(context)");
            }
            box = MyObjectBox.builder().androidContext(appContext).build().boxFor(LuaObject.class);
            migrateIfNeeded(box);
        }
        return box;
    }

    /** 首次使用时把旧的自增 id 记录重排成 hash id（一次全表扫描，之后靠 meta 标记跳过）。 */
    private static void migrateIfNeeded(Box<LuaObject> b) {
        LuaObject meta = b.get(idOf(META_SPACE, META_KEY));
        if (meta != null && SCHEME.equals(meta.value)) {
            return;
        }
        for (LuaObject o : b.getAll()) {
            if (META_SPACE.equals(o.space)) {
                b.remove(o.id);
                continue;
            }
            long want = idOf(o.space, o.key);
            if (o.id != want) {
                b.remove(o.id);
                o.id = want;
                b.put(o);
            }
        }
        LuaObject m = new LuaObject();
        m.id = idOf(META_SPACE, META_KEY);
        m.space = META_SPACE;
        m.key = META_KEY;
        m.value = SCHEME;
        b.put(m);
    }

    private static boolean same(LuaObject o, String space, String key) {
        return o != null && space.equals(o.space) && key.equals(o.key);
    }

    /** 写入或更新一个值，返回记录 id。 */
    public static long put(String space, String key, String value) {
        LuaObject o = new LuaObject();
        o.id = idOf(space, key);
        o.space = space;
        o.key = key;
        o.value = value;
        o.updatedAt = System.currentTimeMillis();
        box().put(o);
        return o.id;
    }

    /** 读一个值；键不存在返回 null。 */
    public static String get(String space, String key) {
        LuaObject o = box().get(idOf(space, key));
        return same(o, space, key) ? o.value : null;
    }

    /** 删除一个键，返回是否真的删掉了。 */
    public static boolean remove(String space, String key) {
        Box<LuaObject> b = box();
        long id = idOf(space, key);
        if (!same(b.get(id), space, key)) {
            return false;
        }
        b.remove(id);
        return true;
    }

    /**
     * 批量写入：keys 与 values 等长。整批只提交一个事务，比逐条 put 快两个数量级。
     * 返回写入条数。
     */
    public static int putMany(String space, String[] keys, String[] values) {
        if (keys == null || values == null || keys.length != values.length) {
            throw new IllegalArgumentException("putMany: keys 与 values 长度不一致");
        }
        long now = System.currentTimeMillis();
        List<LuaObject> list = new ArrayList<LuaObject>(keys.length);
        for (int i = 0; i < keys.length; i++) {
            LuaObject o = new LuaObject();
            o.id = idOf(space, keys[i]);
            o.space = space;
            o.key = keys[i];
            o.value = values[i];
            o.updatedAt = now;
            list.add(o);
        }
        box().put(list);
        return list.size();
    }

    /** 批量读取：返回与 keys 同序的数组，缺失位置为 null。 */
    public static String[] getMany(String space, String[] keys) {
        String[] out = new String[keys.length];
        if (keys.length == 0) {
            return out;
        }
        long[] ids = new long[keys.length];
        for (int i = 0; i < keys.length; i++) {
            ids[i] = idOf(space, keys[i]);
        }
        // get(long[]) 不保证顺序，按 id 建映射再回填
        java.util.HashMap<Long, String> map = new java.util.HashMap<Long, String>();
        for (LuaObject o : box().get(ids)) {
            map.put(o.id, o.value);
        }
        for (int i = 0; i < keys.length; i++) {
            String v = map.get(ids[i]);
            out[i] = v;
        }
        return out;
    }

    /** 批量删除，整批一个事务；返回删除条数。 */
    public static int removeMany(String space, String[] keys) {
        List<Long> ids = new ArrayList<Long>(keys.length);
        for (String k : keys) {
            ids.add(idOf(space, k));
        }
        if (ids.isEmpty()) {
            return 0;
        }
        box().removeByIds(ids);
        return ids.size();
    }

    /** 某个 space 下的全部键。 */
    public static List<String> keys(String space) {
        Query<LuaObject> q = box().query()
                .equal(LuaObject_.space, space, StringOrder.CASE_SENSITIVE)
                .build();
        try {
            List<LuaObject> list = q.find();
            List<String> out = new ArrayList<String>(list.size());
            for (LuaObject o : list) {
                out.add(o.key);
            }
            return out;
        } finally {
            q.close();
        }
    }

    /** 某个 space 下的记录数。 */
    public static long count(String space) {
        Query<LuaObject> q = box().query()
                .equal(LuaObject_.space, space, StringOrder.CASE_SENSITIVE)
                .build();
        try {
            return q.count();
        } finally {
            q.close();
        }
    }

    /** 清空某个 space，返回删除条数。 */
    public static long clear(String space) {
        Query<LuaObject> q = box().query()
                .equal(LuaObject_.space, space, StringOrder.CASE_SENSITIVE)
                .build();
        try {
            long n = q.count();
            q.remove();
            return n;
        } finally {
            q.close();
        }
    }
}
