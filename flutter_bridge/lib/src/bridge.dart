import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'logic.dart';

/// Dart 与 Android 原生壳之间的桥。
///
/// 通道名 `androlua/flutter`，两侧约定：
///  * 原生 -> Dart: `render`(json) / `call`([name, argsJson]) / `dispatch`(json)
///  * Dart -> 原生: `nativeEvent`(json)
class FlutterBridge {
  FlutterBridge._();

  static final FlutterBridge instance = FlutterBridge._();

  static const MethodChannel channel = MethodChannel('androlua/flutter');

  /// 给 Flutter 里嵌的原生 AndroidView 用的通道。
  static const MethodChannel nativeViewChannel = MethodChannel('androlua/nativeview');

  /// 给 Flutter 里嵌的原生视频播放器（VideoView）用的通道。
  static const MethodChannel videoChannel = MethodChannel('androlua/video');

  /// 当前渲染的 widget 树描述（JSON 字符串），由原生 `render` 写入。
  final ValueNotifier<String?> spec = ValueNotifier<String?>(null);

  /// dartCall 的逻辑方法表：名字 -> 函数(参数 map) -> 可 JSON 序列化的返回值。
  final Map<String, dynamic Function(Map<String, dynamic>? args)> handlers = {};

  /// 原生主动推来的事件监听：事件名 -> 回调。
  final Map<String, void Function(dynamic data)> eventListeners = {};

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    registerDefaultHandlers(handlers);
    _registerVideoHandlers();
    channel.setMethodCallHandler(_onMethodCall);
    nativeViewChannel.setMethodCallHandler(_onNativeViewCall);
    videoChannel.setMethodCallHandler(_onVideoCall);
  }

  /// 视频播放器控制（供 Lua 通过 dartCall 调用）。
  void _registerVideoHandlers() {
    handlers['videoLoad'] = (a) {
      video('load', a?['url']);
      return {'ok': true};
    };
    handlers['videoPlay'] = (a) {
      video('play');
      return {'ok': true};
    };
    handlers['videoPause'] = (a) {
      video('pause');
      return {'ok': true};
    };
    handlers['videoSeek'] = (a) {
      video('seek', (a?['pos'] as num?)?.toInt() ?? 0);
      return {'ok': true};
    };
    handlers['videoSeekPercent'] = (a) {
      final pct = (a?['percent'] ?? a?['value']) as num?;
      video('seekPercent', pct?.toInt() ?? 0);
      return {'ok': true};
    };
  }

  /// 向原生视频播放器发指令。
  void video(String method, [dynamic args]) {
    videoChannel.invokeMethod<void>(method, args);
  }

  /// 原生视频播放器回传的事件（prepared / completion / error）。
  Future<dynamic> _onVideoCall(MethodCall call) async {
    emit('videoEvent', {'event': call.method, 'data': call.arguments});
    return null;
  }

  /// Flutter 里嵌的 AndroidView（原生控件）回传的消息。
  Future<dynamic> _onNativeViewCall(MethodCall call) async {
    if (call.method == 'click') {
      emit('nativeViewClick', {'text': call.arguments});
    }
    return null;
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'render':
        spec.value = call.arguments as String?;
        return null;
      case 'call':
        final args = (call.arguments as List).cast<dynamic>();
        final name = args[0] as String;
        final raw = args.length > 1 ? args[1] : null;
        return invoke(name, decodeArgs(raw));
      case 'dispatch':
        final data = jsonDecode(call.arguments as String);
        if (data is Map) {
          final name = data['name']?.toString();
          if (name != null && eventListeners.containsKey(name)) {
            eventListeners[name]!(data['data']);
          }
        }
        return null;
      default:
        throw MissingPluginException('未知方法 ${call.method}');
    }
  }

  Map<String, dynamic>? decodeArgs(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is String && raw.isNotEmpty) {
      final d = jsonDecode(raw);
      if (d is Map) return d.cast<String, dynamic>();
    }
    return null;
  }

  /// 执行一个 Dart 逻辑方法并返回其结果（供 dartCall 使用）。
  dynamic invoke(String name, Map<String, dynamic>? args) {
    final handler = handlers[name];
    if (handler == null) {
      return {'error': 'no such dart method: $name'};
    }
    try {
      return handler(args);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Flutter -> 原生 事件。
  void emit(String name, [dynamic data]) {
    channel.invokeMethod<void>('nativeEvent', jsonEncode({'name': name, 'data': data}));
  }

  /// 原生 -> Flutter 事件（内部使用，由 widget 回调触发）。
  void on(String name, void Function(dynamic data) listener) {
    eventListeners[name] = listener;
  }
}
