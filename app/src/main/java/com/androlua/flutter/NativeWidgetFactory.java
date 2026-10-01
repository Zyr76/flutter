package com.androlua.flutter;

import android.content.Context;
import android.graphics.Color;
import android.util.TypedValue;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewParent;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

/**
 * Flutter 里用 {@code AndroidView(viewType: "androlua/native")} 时，由这个工厂创建真正的
 * Android 原生控件 —— 也就是「Flutter 里再嵌原生控件」的落地方式。
 *
 * <p>两种写法：
 * <ul>
 *   <li>{@code { AndroidView, view = 原生控件 }} —— 直接嵌 Lua 侧 new 出来的控件：布局表序列化时
 *       控件对象会被登记成内部引用（{@link #putRef}），这里按引用取回并挂上去；</li>
 *   <li>只给 {@code params = { text = "..." }} —— 退回内置演示控件（TextView + Button）。</li>
 * </ul>
 *
 * <p>原生控件里的按钮点击会回调 Dart 侧（通道 {@code androlua/nativeview}），演示双向通信。
 */
public class NativeWidgetFactory extends PlatformViewFactory {

    static final String NATIVE_CHANNEL = "androlua/nativeview";

    /** 控件引用在 spec 里的键名，由 {@link LuaJson} 写入。 */
    static final String REF_KEY = "__viewRef";

    /**
     * 「控件对象 -> 内部引用」表：Lua 布局表里直接写控件时登记，整棵布局重渲染时清空
     * （新布局会在序列化阶段重新登记，旧引用已无人使用）。
     */
    private static final Map<String, View> REFS = new LinkedHashMap<String, View>();
    private static int refSeq;

    private final BinaryMessenger messenger;

    public NativeWidgetFactory(BinaryMessenger messenger) {
        super(StandardMessageCodec.INSTANCE);
        this.messenger = messenger;
    }

    static synchronized String putRef(View view) {
        String ref = "v" + (++refSeq);
        REFS.put(ref, view);
        return ref;
    }

    static synchronized void clearRefs() {
        REFS.clear();
    }

    private static synchronized View refView(Object ref) {
        return ref instanceof String ? REFS.get((String) ref) : null;
    }

    @Override
    public PlatformView create(Context context, int viewId, Object args) {
        return new NativeWidgetView(context, args, messenger);
    }

    static class NativeWidgetView implements PlatformView {

        private final View root;

        NativeWidgetView(Context context, Object args, final BinaryMessenger messenger) {
            Map<?, ?> params = args instanceof Map ? (Map<?, ?>) args : Collections.emptyMap();
            View given = givenView(params);
            root = given != null ? given : demoView(context, params, messenger);
        }

        @Override
        public View getView() {
            return root;
        }

        @Override
        public void dispose() {
        }

        /** params.view 给了引用就解析成控件；控件可能还挂在别的容器上，先摘下来。 */
        private static View givenView(Map<?, ?> params) {
            Object raw = params.get("view");
            Object ref = raw instanceof Map ? ((Map<?, ?>) raw).get(REF_KEY) : raw;
            View view = refView(ref);
            if (view == null) {
                return null;
            }
            ViewParent parent = view.getParent();
            if (parent instanceof ViewGroup) {
                ((ViewGroup) parent).removeView(view);
            }
            return view;
        }

        private static View demoView(Context context, Map<?, ?> params, final BinaryMessenger messenger) {
            final String text = params.get("text") == null
                    ? "AndroidView 原生控件" : String.valueOf(params.get("text"));

            LinearLayout root = new LinearLayout(context);
            root.setOrientation(LinearLayout.VERTICAL);
            root.setPadding(dp(context, 16), dp(context, 12), dp(context, 16), dp(context, 12));

            TextView label = new TextView(context);
            label.setText(text);
            label.setTextColor(Color.parseColor("#222222"));
            label.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
            root.addView(label);

            Button button = new Button(context);
            button.setText("原生 Button（点我回传 Dart）");
            button.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    new MethodChannel(messenger, NATIVE_CHANNEL).invokeMethod("click", text);
                }
            });
            root.addView(button);
            return root;
        }

        private static int dp(Context context, int value) {
            return (int) (value * context.getResources().getDisplayMetrics().density + 0.5f);
        }
    }
}
