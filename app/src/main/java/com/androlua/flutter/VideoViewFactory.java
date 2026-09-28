package com.androlua.flutter;

import android.content.Context;
import android.net.Uri;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.MediaController;
import android.widget.VideoView;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

/**
 * 在 Flutter 里嵌一个 Android 原生 {@link VideoView}：viewType = {@code androlua/video}。
 *
 * <p>画面与播放由原生 VideoView 负责（自带原生 MediaController 控制条），外层界面由 Flutter 画。
 * Dart/Lua 通过通道 {@code androlua/video} 控制播放（load/play/pause/seek/seekPercent），
 * 原生的 prepared / completion / error 事件也会回传给 Dart。
 */
public class VideoViewFactory extends PlatformViewFactory {

    static final String CHANNEL = "androlua/video";

    private final BinaryMessenger messenger;
    private MethodChannel channel;
    private VideoPlatformView current;

    public VideoViewFactory(BinaryMessenger messenger) {
        super(StandardMessageCodec.INSTANCE);
        this.messenger = messenger;
    }

    private MethodChannel channel() {
        if (channel == null) {
            channel = new MethodChannel(messenger, CHANNEL);
            channel.setMethodCallHandler(this::onMethodCall);
        }
        return channel;
    }

    private void onMethodCall(MethodCall call, MethodChannel.Result result) {
        VideoView vv = current == null ? null : current.video;
        if (vv == null) {
            result.error("no_view", "还没有创建视频视图", null);
            return;
        }
        switch (call.method) {
            case "load": {
                Object a = call.arguments;
                String url = null;
                if (a instanceof String) {
                    url = (String) a;
                } else if (a instanceof Map && ((Map<?, ?>) a).get("url") != null) {
                    url = String.valueOf(((Map<?, ?>) a).get("url"));
                }
                if (url != null && !url.isEmpty()) {
                    vv.setVideoURI(Uri.parse(url));
                }
                result.success(null);
                break;
            }
            case "play":
                vv.start();
                result.success(null);
                break;
            case "pause":
                vv.pause();
                result.success(null);
                break;
            case "seek":
                vv.seekTo(call.arguments instanceof Number ? ((Number) call.arguments).intValue() : 0);
                result.success(null);
                break;
            case "seekPercent": {
                int duration = vv.getDuration();
                int percent = call.arguments instanceof Number ? ((Number) call.arguments).intValue() : 0;
                if (duration > 0) {
                    vv.seekTo(duration * percent / 100);
                }
                result.success(null);
                break;
            }
            case "isPlaying":
                result.success(vv.isPlaying());
                break;
            default:
                result.notImplemented();
        }
    }

    @Override
    public PlatformView create(Context context, int viewId, Object args) {
        channel();
        current = new VideoPlatformView(context, args);
        return current;
    }

    private void emit(String event, Object data) {
        channel().invokeMethod(event, data);
    }

    class VideoPlatformView implements PlatformView {

        final FrameLayout root;
        final VideoView video;

        VideoPlatformView(Context context, Object args) {
            Map<?, ?> params = args instanceof Map ? (Map<?, ?>) args : Collections.emptyMap();
            String url = params.get("url") == null ? "" : String.valueOf(params.get("url"));
            boolean autoplay = !Boolean.FALSE.equals(params.get("autoplay"));

            root = new FrameLayout(context);
            root.setBackgroundColor(0xFF000000);

            video = new VideoView(context);
            root.addView(video, new FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));

            MediaController controller = new MediaController(context);
            controller.setAnchorView(video);
            video.setMediaController(controller);

            video.setOnPreparedListener(mp -> emit("prepared", mp.getDuration()));
            video.setOnCompletionListener(mp -> emit("completion", null));
            video.setOnErrorListener((mp, what, extra) -> {
                Map<String, Object> e = new HashMap<>();
                e.put("what", what);
                e.put("extra", extra);
                emit("error", e);
                return false;
            });

            if (!url.isEmpty()) {
                video.setVideoURI(Uri.parse(url));
                if (autoplay) {
                    video.start();
                }
            }
        }

        @Override
        public View getView() {
            return root;
        }

        @Override
        public void dispose() {
            try {
                video.stopPlayback();
            } catch (Exception ignored) {
            }
        }
    }
}
