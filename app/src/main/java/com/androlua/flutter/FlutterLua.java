package com.androlua.flutter;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.androlua.LuaContext;

import org.json.JSONArray;
import org.json.JSONObject;

import java.lang.ref.WeakReference;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.WeakHashMap;
import java.util.concurrent.CountDownLatch;

import io.flutter.embedding.android.FlutterView;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineGroup;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Lua 与 Flutter 引擎之间的运行时桥。
 *
 * <p>职责：
 * <ul>
 *   <li>用 {@link FlutterEngineGroup} 在同一个进程里创建/复用 Flutter 引擎，多个 FlutterView 共享快照，省内存；</li>
 *   <li>暴露一个 {@link FlutterView}，可直接插进 AndroLua 的原生布局，实现原生区 + Flutter 区同屏；</li>
 *   <li>通过 {@link MethodChannel}（名字 {@code androlua/flutter}）实现 Lua -&gt; Dart 渲染、dartCall 逻辑调用，
 *       以及 Dart -&gt; 原生的事件回传。</li>
 * </ul>
 *
 * <p>每个 {@link LuaContext}（Activity/Service）对应一个实例，同一个 context 的多个 Lua 线程共用同一个实例，
 * 从而共用同一个引擎与 FlutterView。
 */
public class FlutterLua {

    public static final String CHANNEL = "androlua/flutter";

    private static final String TAG = "FlutterLua";

    private static final Map<LuaContext, FlutterLua> HOLDERS =
            Collections.synchronizedMap(new WeakHashMap<LuaContext, FlutterLua>());

    /** 进程级共享的引擎组：同组内的引擎共用 Dart VM 快照与堆结构。 */
    private static FlutterEngineGroup sEngineGroup;

    /** Dart -&gt; 原生事件的回调入口（由 Lua 侧注册）。 */
    public interface EventSink {
        void onFlutterEvent(String json);
    }

    /** dartCallAsync 的结果回调。 */
    public interface ResultCallback {
        void onResult(Object result, String error);
    }

    /**
     * 弱引用持有 LuaContext。HOLDERS 是 key=context 的 WeakHashMap，若这里再用强引用持有 context，
     * value 会反向强引用 key，WeakHashMap 永远不会回收条目（经典 WeakHashMap 泄漏陷阱）。
     */
    private final WeakReference<LuaContext> luaContextRef;
    private final Context context;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final FlutterEngine engine;
    private final FlutterView flutterView;
    private final MethodChannel channel;

    private volatile EventSink eventSink;
    private boolean resumed;

    /** id -> 该节点在最近一次 render 的 spec 树中的 JSONObject，patch 时按 id 定点修改。 */
    private final Map<String, JSONObject> specIndex = new HashMap<String, JSONObject>();

    private FlutterLua(LuaContext luaContext) {
        this.luaContextRef = new WeakReference<LuaContext>(luaContext);
        this.context = luaContext.getContext();
        Context app = context.getApplicationContext();

        synchronized (FlutterLua.class) {
            if (sEngineGroup == null) {
                sEngineGroup = new FlutterEngineGroup(app);
            }
        }

        DartExecutor.DartEntrypoint entrypoint = DartExecutor.DartEntrypoint.createDefault();

        engine = sEngineGroup.createAndRunEngine(app, entrypoint);

        engine.getPlatformViewsController().getRegistry()
                .registerViewFactory("androlua/native",
                        new NativeWidgetFactory(engine.getDartExecutor().getBinaryMessenger()));
        engine.getPlatformViewsController().getRegistry()
                .registerViewFactory("androlua/video",
                        new VideoViewFactory(engine.getDartExecutor().getBinaryMessenger()));

        channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this::handleDartCall);

        flutterView = new FlutterView(context);
        flutterView.attachToFlutterEngine(engine);

        // 引擎创建可能晚于 Activity.onResume，这里直接置为 resumed，保证 Flutter 能开始渲染。
        onResume();
    }

    /**
     * 取得（必要时创建）某个 LuaContext 的 FlutterLua。创建 FlutterView/引擎必须在主线程完成，
     * 因此在非主线程调用时会切回主线程创建再返回。
     */
    public static FlutterLua get(final LuaContext context) {
        FlutterLua holder = HOLDERS.get(context);
        if (holder != null) {
            return holder;
        }
        synchronized (HOLDERS) {
            holder = HOLDERS.get(context);
            if (holder == null) {
                holder = createOnMain(context);
                HOLDERS.put(context, holder);
            }
            return holder;
        }
    }

    private static FlutterLua createOnMain(final LuaContext context) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return new FlutterLua(context);
        }
        final FlutterLua[] box = new FlutterLua[1];
        final CountDownLatch latch = new CountDownLatch(1);
        new Handler(Looper.getMainLooper()).post(new Runnable() {
            @Override
            public void run() {
                try {
                    box[0] = new FlutterLua(context);
                } finally {
                    latch.countDown();
                }
            }
        });
        try {
            latch.await();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        if (box[0] == null) {
            throw new IllegalStateException("Flutter 引擎创建失败");
        }
        return box[0];
    }

    /** 若该 context 已创建过 FlutterLua 则返回，否则返回 null（不会创建）。 */
    public static FlutterLua peek(LuaContext context) {
        return HOLDERS.get(context);
    }

    /**
     * 显式销毁某个 context 的 FlutterLua（引擎+FlutterView）并从持有表中移除。
     * Activity/Service 等拥有生命周期钩子的 context 应在 onDestroy 时调用（或调用 {@link #onDestroy()}）。
     */
    public static void destroy(LuaContext context) {
        if (context == null) {
            return;
        }
        FlutterLua holder = HOLDERS.remove(context);
        if (holder != null) {
            holder.teardown();
        }
    }

    public FlutterView getView() {
        return flutterView;
    }

    /** 保存一份可变的 spec 树并重建 id 索引（每次全量 render 时调用）。 */
    public void setSpec(JSONObject root) {
        specIndex.clear();
        if (root != null) {
            indexIds(root);
        }
    }

    private void indexIds(Object node) {
        if (node instanceof JSONObject) {
            JSONObject o = (JSONObject) node;
            Object id = o.opt("id");
            if (id instanceof String && !((String) id).isEmpty()) {
                specIndex.put((String) id, o);
            }
            for (Iterator<String> it = o.keys(); it.hasNext(); ) {
                indexIds(o.opt(it.next()));
            }
        } else if (node instanceof JSONArray) {
            JSONArray a = (JSONArray) node;
            for (int i = 0; i < a.length(); i++) {
                indexIds(a.opt(i));
            }
        }
    }

    /** 通用：向 Dart 发一个带参数的方法调用（弹窗类命令等）。 */
    public void invoke(final String method, final Object args) {
        runOnMain(new Runnable() {
            @Override
            public void run() {
                channel.invokeMethod(method, args);
            }
        });
    }

    /**
     * 命令式改某个 id 节点的属性，并把该节点新 spec 下发给 Dart 定点重建。
     * 返回是否找到了该 id（未找到则不生效）。
     */
    public boolean patchNode(final String id, final String key, Object value) {
        final JSONObject node = specIndex.get(id);
        if (node == null) {
            return false;
        }
        try {
            // 命令式属性名大小写不敏感：若节点已有同名键（如 text），复用它而不是新增一个 Text 键，
            // 否则会与已有键并存，渲染时精确匹配会命中旧值。
            String target = key;
            for (Iterator<String> it = node.keys(); it.hasNext(); ) {
                String k = it.next();
                if (k.equalsIgnoreCase(key)) {
                    target = k;
                    break;
                }
            }
            node.put(target, value);
        } catch (Exception e) {
            Log.w(TAG, "patchNode 写入失败: " + id + "." + key, e);
            return false;
        }
        final String json = node.toString();
        runOnMain(new Runnable() {
            @Override
            public void run() {
                HashMap<String, Object> args = new HashMap<String, Object>();
                args.put("id", id);
                args.put("spec", json);
                channel.invokeMethod("patch", args);
            }
        });
        return true;
    }

    public void setEventSink(EventSink sink) {
        this.eventSink = sink;
    }

    /** 把 widget 描述（JSON）推给 Dart，重建 Flutter UI。 */
    /**
     * 把一条原生 -> Flutter 事件派发给已注册的 EventSink（用于 dartCall 主线程异步化后回传结果等）。
     * dataJson 需为合法 JSON 片段。
     */
    public void deliverEvent(final String name, final String dataJson) {
        final EventSink sink = eventSink;
        if (sink == null) {
            Log.w(TAG, "deliverEvent(" + name + ") 被忽略：尚未注册 EventSink");
            return;
        }
        final String json = "{\"name\":" + quote(name) + ",\"data\":" + (dataJson == null ? "null" : dataJson) + "}";
        runOnMain(new Runnable() {
            @Override
            public void run() {
                sink.onFlutterEvent(json);
            }
        });
    }

    public void render(final String json) {
        runOnMain(new Runnable() {
            @Override
            public void run() {
                channel.invokeMethod("render", json);
            }
        });
    }

    /** 原生 -&gt; Flutter 事件。 */
    public void dispatchEvent(final String json) {
        runOnMain(new Runnable() {
            @Override
            public void run() {
                channel.invokeMethod("dispatch", json);
            }
        });
    }

    /**
     * 同步调用 Dart 逻辑方法并拿到返回。
     *
     * <p>注意：Android 侧要收到 Dart 的应答需要主线程消息循环空闲，因此本方法<b>不能在主线程调用</b>，
     * 否则会死锁/ANR。请在 Lua 的 {@code thread}/{@code task} 里调用，或改用 {@link #callAsync}。
     */
    public Object callSync(final String name, final String argsJson) throws InterruptedException {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IllegalStateException(
                    "dartCall 不能在主线程同步调用：Android 需要主线程空闲才能收到 Dart 应答。"
                            + "请用 thread { ... } 包起来，或改用 dartCallAsync(name, args, callback)。");
        }
        return callSyncBlocking(name, argsJson);
    }

    /** 供内部（主线程异步化路径）复用的阻塞实现；调用方需自行保证不在主线程。 */
    private Object callSyncBlocking(final String name, final String argsJson) throws InterruptedException {
        final CountDownLatch latch = new CountDownLatch(1);
        final Object[] result = new Object[1];
        mainHandler.post(new Runnable() {
            @Override
            public void run() {
                channel.invokeMethod("call", buildArgs(name, argsJson), new MethodChannel.Result() {
                    @Override
                    public void success(Object value) {
                        result[0] = value;
                        latch.countDown();
                    }

                    @Override
                    public void error(String code, String message, Object details) {
                        result[0] = "dartCall error: " + code + " " + message;
                        latch.countDown();
                    }

                    @Override
                    public void notImplemented() {
                        result[0] = null;
                        latch.countDown();
                    }
                });
            }
        });
        latch.await();
        return result[0];
    }

    /** 异步调用 Dart 逻辑方法，主线程也可安全使用。 */
    public void callAsync(final String name, final String argsJson, final ResultCallback callback) {
        runOnMain(new Runnable() {
            @Override
            public void run() {
                channel.invokeMethod("call", buildArgs(name, argsJson), new MethodChannel.Result() {
                    @Override
                    public void success(final Object value) {
                        if (callback != null) {
                            callback.onResult(value, null);
                        }
                    }

                    @Override
                    public void error(String code, String message, Object details) {
                        if (callback != null) {
                            callback.onResult(null, code + ": " + message);
                        }
                    }

                    @Override
                    public void notImplemented() {
                        if (callback != null) {
                            callback.onResult(null, "notImplemented");
                        }
                    }
                });
            }
        });
    }

    private static List<Object> buildArgs(String name, String argsJson) {
        List<Object> args = new java.util.ArrayList<Object>(2);
        args.add(name);
        args.add(argsJson);
        return args;
    }

    private void handleDartCall(MethodCall call, MethodChannel.Result result) {
        if ("nativeEvent".equals(call.method)) {
            final String json = String.valueOf(call.arguments);
            final EventSink sink = eventSink;
            if (sink != null) {
                runOnMain(new Runnable() {
                    @Override
                    public void run() {
                        sink.onFlutterEvent(json);
                    }
                });
            }
            result.success(null);
        } else {
            result.notImplemented();
        }
    }

    public void onResume() {
        if (resumed) {
            return;
        }
        resumed = true;
        engine.getLifecycleChannel().appIsResumed();
    }

    public void onPause() {
        if (!resumed) {
            return;
        }
        resumed = false;
        engine.getLifecycleChannel().appIsInactive();
    }

    public void onDestroy() {
        LuaContext ctx = luaContextRef.get();
        if (ctx != null) {
            HOLDERS.remove(ctx);
        }
        teardown();
    }

    /** 释放引擎与 FlutterView。可重复调用。 */
    private void teardown() {
        try {
            flutterView.detachFromFlutterEngine();
        } catch (Exception e) {
            Log.w(TAG, "detachFromFlutterEngine 失败", e);
        }
        try {
            engine.destroy();
        } catch (Exception e) {
            Log.w(TAG, "engine.destroy 失败", e);
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
                case '"': sb.append("\\\""); break;
                case '\\': sb.append("\\\\"); break;
                case '\n': sb.append("\\n"); break;
                case '\r': sb.append("\\r"); break;
                case '\t': sb.append("\\t"); break;
                default: sb.append(c);
            }
        }
        return sb.append('"').toString();
    }

    private void runOnMain(Runnable r) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            r.run();
        } else {
            mainHandler.post(r);
        }
    }
}
