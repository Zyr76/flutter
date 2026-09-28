package com.androlua.flutter;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import com.androlua.LuaContext;

import java.util.Collections;
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

    private final LuaContext luaContext;
    private final Context context;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final FlutterEngine engine;
    private final FlutterView flutterView;
    private final MethodChannel channel;

    private volatile EventSink eventSink;
    private boolean resumed;

    private FlutterLua(LuaContext luaContext) {
        this.luaContext = luaContext;
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

    public FlutterView getView() {
        return flutterView;
    }

    public void setEventSink(EventSink sink) {
        this.eventSink = sink;
    }

    /** 把 widget 描述（JSON）推给 Dart，重建 Flutter UI。 */
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
        try {
            flutterView.detachFromFlutterEngine();
        } catch (Exception ignored) {
        }
        HOLDERS.remove(luaContext);
        engine.destroy();
    }

    private void runOnMain(Runnable r) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            r.run();
        } else {
            mainHandler.post(r);
        }
    }
}
