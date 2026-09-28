package com.androlua.flutter;

import android.content.Context;
import android.graphics.Color;
import android.util.TypedValue;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.Collections;
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
 * <p>原生控件里的按钮点击会回调 Dart 侧（通道 {@code androlua/nativeview}），演示双向通信。
 */
public class NativeWidgetFactory extends PlatformViewFactory {

    static final String NATIVE_CHANNEL = "androlua/nativeview";

    private final BinaryMessenger messenger;

    public NativeWidgetFactory(BinaryMessenger messenger) {
        super(StandardMessageCodec.INSTANCE);
        this.messenger = messenger;
    }

    @Override
    public PlatformView create(Context context, int viewId, Object args) {
        return new NativeWidgetView(context, args, messenger);
    }

    static class NativeWidgetView implements PlatformView {

        private final LinearLayout root;

        NativeWidgetView(Context context, Object args, final BinaryMessenger messenger) {
            Map<?, ?> params = args instanceof Map ? (Map<?, ?>) args : Collections.emptyMap();
            final String text = params.get("text") == null ? "AndroidView 原生控件" : String.valueOf(params.get("text"));

            root = new LinearLayout(context);
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
        }

        @Override
        public View getView() {
            return root;
        }

        @Override
        public void dispose() {
        }

        private static int dp(Context context, int value) {
            return (int) (value * context.getResources().getDisplayMetrics().density + 0.5f);
        }
    }
}
