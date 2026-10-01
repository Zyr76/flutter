package com.androlua;

import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.os.Handler;
import android.os.Message;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.TextView;

import androidx.recyclerview.widget.RecyclerView;

import com.luajava.JavaFunction;
import com.luajava.LuaException;
import com.luajava.LuaFunction;
import com.luajava.LuaJavaAPI;
import com.luajava.LuaObject;
import com.luajava.LuaState;
import com.luajava.LuaTable;

import java.io.IOException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;

/**
 * RecyclerView 的 Lua 适配器。对使用者屏蔽 ViewHolder / Adapter 样板代码，语法与 ListView 的
 * {@link LuaAdapter} 保持一致，但基于 RecyclerView 的回收复用（性能更高），并支持多布局与自定义绑定。
 *
 * <h3>最简用法</h3>
 * <pre>
 * require "材料设计"                 -- import androidx.recyclerview.widget.*
 * local rv = RecyclerView(activity)
 * rv.setLayoutManager(LinearLayoutManager(activity))
 *
 * local adapter = RecyclerAdapter{          -- 单布局：直接给 item 布局表
 *   LinearLayout, orientation = "vertical",
 *   { TextView, id = "title", textSize = "16sp" },
 *   { TextView, id = "sub", textColor = "0xff888888" },
 * }
 * adapter.setData({
 *   { title = "A", sub = "a1" },
 *   { title = "B", sub = "b2" },
 * })
 * adapter.setOnItemClick(function(pos, data) print(pos, data.title) end)
 * rv.setAdapter(adapter)
 * </pre>
 *
 * <h3>传数据 + 布局</h3>
 * <pre>
 * local adapter = RecyclerAdapter(data, layout)
 * </pre>
 *
 * <h3>多布局</h3>
 * <pre>
 * adapter.setLayouts({ layoutA, layoutB })
 * adapter.setTypeOf(function(data, pos) return data.kind end)  -- 返回 1 / 2 …（Lua 从 1 开始）
 * </pre>
 *
 * <h3>自定义绑定（最强）</h3>
 * <pre>
 * adapter.setBinder(function(holder, data, pos)
 *   holder.title.setText(data.title)
 *   holder.sub.setText(pos .. ":" .. tostring(data.sub))
 * end)
 * </pre>
 *
 * <p>数据项里的每个键默认会被当作「item 布局中同名 id 的控件」来赋值：
 * 文本控件直接 setText，图片控件按字符串/位图/资源 id 处理，其它键走同名 setter
 * （如 {@code enabled=false} → setEnabled）。
 */
public class LuaRecyclerAdapter extends RecyclerView.Adapter<LuaRecyclerAdapter.ViewHolder> {

    private final LuaContext mContext;
    private final LuaState L;
    private final Resources mRes;

    private final LuaFunction<View> mLoadLayout;
    private final LuaFunction mInsert;
    private final LuaFunction mRemove;

    /** 单布局。 */
    private LuaTable mLayout;
    /** 多布局（可选）：1-based 布局数组。 */
    private LuaTable<Integer, LuaTable> mLayouts;
    /** 多布局时决定每个位置用哪个布局：function(data, position) -> layoutIndex(1-based)。 */
    private LuaFunction mTypeOf;

    private LuaTable<Integer, LuaTable<String, Object>> mData;
    private LuaTable<Integer, LuaTable<String, Object>> mBaseData;

    private LuaFunction mBinder;
    private LuaFunction mOnClick;
    private LuaFunction mOnLongClick;

    /** 懒加载数据源：count 函数（返回总数） + item 函数（按位置取一行）。设了就不再用数据表。 */
    private LuaFunction mCountFn;
    private LuaFunction mItemFn;
    /** 滚动到末尾时回调（分页/懒加载更多）。 */
    private LuaFunction mOnLoadMore;
    private boolean mLoadingMore;

    private boolean mNotifyOnChange = true;

    private final HashMap<String, Boolean> mLoaded = new HashMap<String, Boolean>();

    @SuppressWarnings("HandlerLeak")
    private final Handler mHandler = new Handler() {
        @Override
        public void handleMessage(Message msg) {
            if (msg.what == 0) {
                notifyDataSetChanged();
            }
        }
    };

    public LuaRecyclerAdapter(LuaContext context, LuaTable layout) throws LuaException {
        this(context, null, layout);
    }

    @SuppressWarnings("unchecked")
    public LuaRecyclerAdapter(LuaContext context, LuaTable data, LuaTable layout) throws LuaException {
        mContext = context;
        mLayout = layout;
        mRes = context.getContext().getResources();
        L = context.getLuaState();
        if (data == null)
            data = new LuaTable<Integer, LuaTable<String, Object>>(L);
        mData = (LuaTable<Integer, LuaTable<String, Object>>) data;
        mBaseData = mData;

        LuaObject ll = L.getLuaObject("loadlayout");
        if (ll == null || !ll.isFunction())
            throw new LuaException("RecyclerAdapter 需要先 require \"layout\"（缺少 loadlayout）");
        mLoadLayout = (LuaFunction<View>) ll.getFunction();
        mInsert = L.getLuaObject("table").getField("insert").getFunction();
        mRemove = L.getLuaObject("table").getField("remove").getFunction();
    }

    /** ViewHolder：携带 item 视图与它的 Lua 句柄表（布局表中 id 绑定的控件）。 */
    public static class ViewHolder extends RecyclerView.ViewHolder {
        final LuaObject holder;

        ViewHolder(View itemView, LuaObject holder) {
            super(itemView);
            this.holder = holder;
        }
    }

    // ============================================================
    // 数据
    // ============================================================

    public LuaTable<Integer, LuaTable<String, Object>> getData() {
        return mData;
    }

    @SuppressWarnings("unchecked")
    public void setData(LuaTable data) {
        mLoadingMore = false;
        mData = data == null ? new LuaTable<Integer, LuaTable<String, Object>>(L)
                : (LuaTable<Integer, LuaTable<String, Object>>) data;
        mBaseData = mData;
        notifyDataSetChanged();
    }

    public void add(LuaTable item) throws LuaException {
        mLoadingMore = false;
        mInsert.call(mBaseData, item);
        if (mNotifyOnChange)
            notifyDataSetChanged();
    }

    public void addAll(LuaTable items) throws LuaException {
        mLoadingMore = false;
        int len = items.length();
        for (int i = 1; i <= len; i++)
            mInsert.call(mBaseData, items.get(i));
        if (mNotifyOnChange)
            notifyDataSetChanged();
    }

    public void insert(int position, LuaTable item) throws LuaException {
        mLoadingMore = false;
        mInsert.call(mBaseData, position + 1, item);
        if (mNotifyOnChange) {
            notifyItemInserted(position);
            notifyItemRangeChanged(position, getItemCount() - position);
        }
    }

    public void remove(int position) throws LuaException {
        mLoadingMore = false;
        mRemove.call(mBaseData, position + 1);
        if (mNotifyOnChange) {
            notifyItemRemoved(position);
            notifyItemRangeChanged(position, getItemCount() - position);
        }
    }

    public void clear() {
        mLoadingMore = false;
        mBaseData.clear();
        if (mNotifyOnChange)
            notifyDataSetChanged();
    }

    public void setNotifyOnChange(boolean notifyOnChange) {
        mNotifyOnChange = notifyOnChange;
    }

    // ============================================================
    // 配置
    // ============================================================

    public void setLayout(LuaTable layout) {
        mLayout = layout;
        notifyDataSetChanged();
    }

    public void setLayouts(LuaTable<Integer, LuaTable> layouts) {
        mLayouts = layouts;
        notifyDataSetChanged();
    }

    public void setTypeOf(LuaFunction typeOf) {
        mTypeOf = typeOf;
        notifyDataSetChanged();
    }

    public void setBinder(LuaFunction binder) {
        mBinder = binder;
        notifyDataSetChanged();
    }

    public void setOnItemClick(LuaFunction listener) {
        mOnClick = listener;
    }

    public void setOnItemLongClick(LuaFunction listener) {
        mOnLongClick = listener;
    }

    // ============================================================
    // 懒加载
    // ============================================================

    /**
     * 懒加载数据源：
     * <pre>
     * adapter.setSource(function() return 100000 end,          -- 总数（每次问）
     *                   function(pos) return { title="第"..pos } end)  -- 按位置取一行（1 起）
     * </pre>
     * 设了之后不再依赖整表数据，适合超大/虚拟列表。
     */
    public void setSource(LuaFunction countFn, LuaFunction itemFn) {
        mCountFn = countFn;
        mItemFn = itemFn;
        mLoadingMore = false;
        notifyDataSetChanged();
    }

    /** 滚动到底部时回调一次，用于分页加载更多（数据就绪后调 finishLoadMore 或任意数据变更方法重置标志）。 */
    public void setOnLoadMore(LuaFunction listener) {
        mOnLoadMore = listener;
    }

    public void setLoadingMore(boolean loadingMore) {
        mLoadingMore = loadingMore;
    }

    public void finishLoadMore() {
        mLoadingMore = false;
        notifyDataSetChanged();
    }

    // ============================================================
    // RecyclerView.Adapter
    // ============================================================

    @Override
    public int getItemCount() {
        if (mCountFn != null) {
            synchronized (L) {
                try {
                    mCountFn.push();
                    if (L.pcall(0, 1, 0) != 0) {
                        String err = L.toString(-1);
                        L.pop(1);
                        throw new LuaException(err);
                    }
                    int n = (int) L.toInteger(-1);
                    L.pop(1);
                    return n < 0 ? 0 : n;
                } catch (Exception e) {
                    mContext.sendError("RecyclerAdapter.count", new LuaException(e));
                    return 0;
                }
            }
        }
        return mData.length();
    }

    @Override
    public long getItemId(int position) {
        return position;
    }

    @Override
    public int getItemViewType(int position) {
        if (mTypeOf == null)
            return 0;
        int type = 1;
        synchronized (L) {
            try {
                mTypeOf.push();
                pushRow(position);
                L.pushInteger(position + 1);
                if (L.pcall(2, 1, 0) != 0) {
                    String err = L.toString(-1);
                    L.pop(1);
                    throw new LuaException(err);
                }
                type = (int) L.toInteger(-1);
                L.pop(1);
            } catch (Exception e) {
                mContext.sendError("RecyclerAdapter.typeOf", new LuaException(e));
            }
        }
        return type > 0 ? type - 1 : 0;
    }

    @Override
    public ViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
        LuaTable layout = mLayout;
        if (mLayouts != null) {
            LuaTable l = mLayouts.get(viewType + 1);
            if (l != null)
                layout = l;
        }
        LuaObject holder;
        View view;
        synchronized (L) {
            L.newTable();
            holder = L.getLuaObject(-1);
            L.pop(1);
            try {
                view = mLoadLayout.call(layout, holder, RecyclerView.class);
            } catch (LuaException e) {
                mContext.sendError("RecyclerAdapter 创建 item 视图", e);
                return new ViewHolder(new View(parent.getContext()), holder);
            }
        }
        final ViewHolder vh = new ViewHolder(view, holder);
        if (mOnClick != null) {
            view.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    int pos = vh.getBindingAdapterPosition();
                    if (pos != RecyclerView.NO_POSITION)
                        callItem(mOnClick, pos, v);
                }
            });
        }
        if (mOnLongClick != null) {
            view.setOnLongClickListener(new View.OnLongClickListener() {
                @Override
                public boolean onLongClick(View v) {
                    int pos = vh.getBindingAdapterPosition();
                    if (pos != RecyclerView.NO_POSITION) {
                        callItem(mOnLongClick, pos, v);
                        return true;
                    }
                    return false;
                }
            });
        }
        return vh;
    }

    @Override
    public void onBindViewHolder(ViewHolder vh, int position) {
        LuaTable row = fetchRowTable(position);
        if (row != null) {
            if (mBinder != null) {
                synchronized (L) {
                    try {
                        mBinder.push();
                        vh.holder.push();
                        row.push();
                        L.pushInteger(position + 1);
                        if (L.pcall(3, 0, 0) != 0) {
                            String err = L.toString(-1);
                            L.pop(1);
                            throw new LuaException(err);
                        }
                    } catch (Exception e) {
                        mContext.sendError("RecyclerAdapter.binder", new LuaException(e));
                    }
                }
            } else {
                synchronized (L) {
                    Set<Map.Entry> sets = row.entrySet();
                    for (Map.Entry entry : sets) {
                        try {
                            LuaObject obj = vh.holder.getField(String.valueOf(entry.getKey()));
                            if (obj != null && obj.isJavaObject())
                                setHelper((View) obj.getObject(), entry.getValue());
                        } catch (Exception e) {
                            Log.i("lua", String.valueOf(e.getMessage()));
                        }
                    }
                }
            }
        }
        if (mOnLoadMore != null && !mLoadingMore) {
            int count = getItemCount();
            if (count > 0 && position >= count - 1) {
                mLoadingMore = true;
                triggerLoadMore();
            }
        }
    }

    // ============================================================
    // 回调辅助
    // ============================================================

    private void pushRow(int position) {
        LuaTable row = fetchRowTable(position);
        if (row != null)
            row.push();
        else
            L.pushNil();
    }

    /** 取某一行的 Lua 表：懒加载模式走 itemFn，否则取数据表。 */
    private LuaTable fetchRowTable(int position) {
        if (mItemFn != null) {
            synchronized (L) {
                try {
                    mItemFn.push();
                    L.pushInteger(position + 1);
                    if (L.pcall(1, 1, 0) != 0) {
                        String err = L.toString(-1);
                        L.pop(1);
                        throw new LuaException(err);
                    }
                    LuaTable<?, ?> t = L.isNoneOrNil(-1) ? null : L.getLuaObject(-1).getTable();
                    L.pop(1);
                    return t;
                } catch (Exception e) {
                    mContext.sendError("RecyclerAdapter.item", new LuaException(e));
                    return null;
                }
            }
        }
        return mData.get(position + 1);
    }

    private void triggerLoadMore() {
        synchronized (L) {
            try {
                mOnLoadMore.push();
                if (L.pcall(0, 0, 0) != 0) {
                    String err = L.toString(-1);
                    L.pop(1);
                    throw new LuaException(err);
                }
            } catch (Exception e) {
                mContext.sendError("RecyclerAdapter.onLoadMore", new LuaException(e));
            }
        }
    }

    private void callItem(LuaFunction f, int position, View v) {
        if (f == null)
            return;
        synchronized (L) {
            try {
                f.push();
                L.pushInteger(position + 1);   // 1) 位置（Lua 从 1 起）
                pushRow(position);             // 2) 数据行
                L.pushJavaObject(v);           // 3) item 视图
                if (L.pcall(3, 0, 0) != 0) {
                    String err = L.toString(-1);
                    L.pop(1);
                    throw new LuaException(err);
                }
            } catch (Exception e) {
                mContext.sendError("RecyclerAdapter 点击回调", new LuaException(e));
            }
        }
    }

    // ============================================================
    // 数据 -> 视图（与 LuaAdapter 一致）
    // ============================================================

    private void setHelper(View view, Object value) {
        try {
            if (value instanceof LuaTable) {
                setFields(view, (LuaTable) value);
            } else if (view instanceof TextView) {
                if (value instanceof CharSequence)
                    ((TextView) view).setText((CharSequence) value);
                else
                    ((TextView) view).setText(String.valueOf(value));
            } else if (view instanceof ImageView) {
                if (value instanceof Bitmap)
                    ((ImageView) view).setImageBitmap((Bitmap) value);
                else if (value instanceof String)
                    ((ImageView) view).setImageDrawable(new AsyncLoader().getBitmap(mContext, (String) value));
                else if (value instanceof Drawable)
                    ((ImageView) view).setImageDrawable((Drawable) value);
                else if (value instanceof Number)
                    ((ImageView) view).setImageResource(((Number) value).intValue());
            }
        } catch (Exception e) {
            mContext.sendError("setHelper", e);
        }
    }

    private void setFields(View view, LuaTable fields) throws LuaException {
        Set<Map.Entry> sets = fields.entrySet();
        for (Map.Entry entry : sets) {
            String key = String.valueOf(entry.getKey());
            Object value = entry.getValue();
            if (key.equalsIgnoreCase("src"))
                setHelper(view, value);
            else
                javaSetter(view, key, value);
        }
    }

    private int javaSetter(Object obj, String methodName, Object value) throws LuaException {
        if (methodName.length() > 2 && methodName.substring(0, 2).equals("on") && value instanceof LuaFunction)
            return javaSetListener(obj, methodName, value);
        return javaSetMethod(obj, methodName, value);
    }

    private int javaSetListener(Object obj, String methodName, Object value) throws LuaException {
        String name = "setOn" + methodName.substring(2) + "Listener";
        ArrayList<Method> methods = LuaJavaAPI.getMethod(obj.getClass(), name, false);
        for (Method m : methods) {
            Class<?>[] tp = m.getParameterTypes();
            if (tp.length == 1 && tp[0].isInterface()) {
                L.newTable();
                L.pushObjectValue(value);
                L.setField(-2, methodName);
                try {
                    Object listener = L.getLuaObject(-1).createProxy(tp[0]);
                    m.invoke(obj, listener);
                    return 1;
                } catch (Exception e) {
                    throw new LuaException(e);
                }
            }
        }
        return 0;
    }

    private int javaSetMethod(Object obj, String methodName, Object value) throws LuaException {
        if (Character.isLowerCase(methodName.charAt(0)))
            methodName = Character.toUpperCase(methodName.charAt(0)) + methodName.substring(1);
        String name = "set" + methodName;
        Class<?> type = value.getClass();
        StringBuilder buf = new StringBuilder();
        ArrayList<Method> methods = LuaJavaAPI.getMethod(obj.getClass(), name, false);
        for (Method m : methods) {
            Class<?>[] tp = m.getParameterTypes();
            if (tp.length != 1)
                continue;
            if (tp[0].isPrimitive()) {
                try {
                    if (value instanceof Double || value instanceof Float)
                        m.invoke(obj, LuaState.convertLuaNumber(((Number) value).doubleValue(), tp[0]));
                    else if (value instanceof Long || value instanceof Integer)
                        m.invoke(obj, LuaState.convertLuaNumber(((Number) value).longValue(), tp[0]));
                    else if (value instanceof Boolean)
                        m.invoke(obj, value);
                    else
                        continue;
                    return 1;
                } catch (Exception e) {
                    buf.append(e.getMessage()).append("\n");
                    continue;
                }
            }
            if (!tp[0].isAssignableFrom(type))
                continue;
            try {
                m.invoke(obj, value);
                return 1;
            } catch (Exception e) {
                buf.append(e.getMessage()).append("\n");
                continue;
            }
        }
        throw new LuaException("Invalid setter " + methodName + ", " + type);
    }

    private class AsyncLoader extends Thread {
        private String mPath;

        Drawable getBitmap(LuaContext context, String path) throws IOException {
            mPath = path;
            if (!path.toLowerCase().startsWith("http://") && !path.toLowerCase().startsWith("https://"))
                return new BitmapDrawable(mRes, LuaBitmap.getBitmap(context, path));
            if (LuaBitmap.checkCache(context, path))
                return new BitmapDrawable(mRes, LuaBitmap.getBitmap(context, path));
            if (!mLoaded.containsKey(mPath)) {
                start();
                mLoaded.put(mPath, true);
            }
            return new LoadingDrawable(mContext.getContext());
        }

        @Override
        public void run() {
            try {
                LuaBitmap.getBitmap(mContext, mPath);
                mHandler.sendEmptyMessage(0);
            } catch (IOException e) {
                mContext.sendError("AsyncLoader", e);
            }
        }
    }

    // ============================================================
    // 注册为 Lua 全局函数：RecyclerAdapter(layout) / RecyclerAdapter(data, layout)
    // ============================================================

    public static void register(final LuaState L, final LuaContext context) throws LuaException {
        JavaFunction ctor = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                LuaTable layout = null;
                LuaTable data = null;
                if (!L.isNoneOrNil(3) && L.isTable(3)) {
                    layout = L.getLuaObject(3).getTable();
                    if (L.isTable(2))
                        data = L.getLuaObject(2).getTable();
                } else if (L.isTable(2)) {
                    layout = L.getLuaObject(2).getTable();
                }
                if (layout == null) {
                    LuaObject print = L.getLuaObject("print");
                    if (print.isFunction()) {
                        print.push();
                        L.pushString("[RecyclerAdapter] 用法: RecyclerAdapter(item布局表) 或 RecyclerAdapter(data表, item布局表)");
                        L.pcall(1, 0, 0);
                    }
                    L.pushNil();
                    return 1;
                }
                LuaRecyclerAdapter adapter = data == null
                        ? new LuaRecyclerAdapter(context, layout)
                        : new LuaRecyclerAdapter(context, data, layout);
                L.pushJavaObject(adapter);
                return 1;
            }
        };
        ctor.register("RecyclerAdapter");
        ctor.register("RecyclerView适配器");
        ctor.register("LuaRecyclerAdapter");
    }
}
