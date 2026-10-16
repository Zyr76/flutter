import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'logic.dart';
import 'renderer.dart';

/// ValueNotifier 的同值也通知版：`spec` 用它，保证「整页重渲染」一定触发重建。
class RenderSpecNotifier extends ValueNotifier<String?> {
  RenderSpecNotifier(super.value);

  @override
  set value(String? newValue) {
    final same = value == newValue;
    super.value = newValue;
    if (same) notifyListeners();
  }
}

/// Dart 与 Android 原生壳之间的桥。
///
/// 通道名 `androlua/flutter`，两侧约定：
///  * 原生 -> Dart: `render`(json) / `call`([name, argsJson]) / `dispatch`(json)
///  * Dart -> 原生: `nativeEvent`(json)
class FlutterBridge {
  FlutterBridge._();

  static final FlutterBridge instance = FlutterBridge._();

  static const MethodChannel channel = MethodChannel('androlua/flutter');

  /// 渲染尚未到达时先存下的补丁（render 一到就补）。
  final List<MapEntry<String, dynamic>> _pendingPatches = [];

  /// 给 Flutter 里嵌的原生视频播放器（VideoView）用的通道。
  static const MethodChannel videoChannel = MethodChannel('androlua/video');

  /// 当前渲染的 widget 树描述（JSON 字符串），由原生 `render` 写入。
  ///
  /// 用「同值也通知」的 notifier：整页重渲染时如果新 JSON 与上一次完全相同
  /// （Lua 侧重新渲染了一次、但字段值没变），普通 ValueNotifier 会因字符串相等
  /// 而**不通知**，界面就“看起来没反应”。
  final RenderSpecNotifier spec = RenderSpecNotifier(null);

  /// 弹窗类命令（dialog/bottomSheet/snackBar/datePicker/timePicker）用的导航 key。
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// 每个带 id 节点的当前 spec，供命令式更新（patch）或全量 render 时定点重建。
  final Map<String, ValueNotifier<dynamic>> nodeSpecs = {};

  /// 取得（必要时创建）某 id 节点的 spec notifier。
  ValueNotifier<dynamic> nodeNotifier(String id, dynamic initial) =>
      nodeSpecs.putIfAbsent(id, () => ValueNotifier<dynamic>(initial));

  /// dartCall 的逻辑方法表：名字 -> 函数(参数 map) -> 可 JSON 序列化的返回值。
  final Map<String, dynamic Function(Map<String, dynamic>? args)> handlers = {};

  /// 原生主动推来的事件监听：事件名 -> 回调列表（同名事件可多个监听，不再互相覆盖）。
  final Map<String, List<void Function(dynamic data)>> eventListeners = {};

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    registerDefaultHandlers(handlers);
    _registerVideoHandlers();
    channel.setMethodCallHandler(_onMethodCall);
    videoChannel.setMethodCallHandler(_onVideoCall);
    // 告诉原生：Dart 侧通道已就绪。引擎启动初期通道缓冲有限（见 ChannelBuffers），
    // 过早连发多条消息会把先发的挤掉（典型：render 被后面的 patch 顶掉，界面变占位）。
    channel.invokeMethod<void>('ready').catchError((Object _) {});
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

  /// 命令式弹窗的 spec 容错：
  ///  * 没写 type（如 `flutterShowDialog{ title=..., { Text,... } }`）→ 当 AlertDialog，
  ///    数字键的子节点合并到 content；
  ///  * 只给了一个内容节点（如 `flutterShowBottomSheet{ { Padding, ... } }`）→ 直接用那个节点。
  static dynamic _dialogSpec(dynamic spec, {String type = 'AlertDialog'}) {
    if (spec is! Map) return spec;
    final m = spec.cast<String, dynamic>();
    if ((m['type'] ?? m['t']) != null) return m;
    if (m.length == 1 && (m['1'] ?? m[1]) is Map) return m['1'] ?? m[1];
    final kids = <dynamic>[];
    final rest = <String, dynamic>{};
    m.forEach((k, v) {
      if (int.tryParse(k) != null) {
        kids.add(v);
      } else {
        rest[k] = v;
      }
    });
    if (type != 'AlertDialog') {
      return <String, dynamic>{'type': type, ...rest, if (kids.isNotEmpty) 'children': kids};
    }
    final out = <String, dynamic>{'type': type, ...rest};
    if (kids.isNotEmpty) {
      out['content'] = kids.length == 1 ? kids.first : <String, dynamic>{'type': 'Column', 'children': kids};
    }
    return out;
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

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'render':
        spec.value = call.arguments as String?;
        // 之前渲染没到就排队的补丁，现在一并补上。
        if (_pendingPatches.isNotEmpty) {
          final pending = List<MapEntry<String, dynamic>>.from(_pendingPatches);
          _pendingPatches.clear();
          for (final e in pending) {
            _applyPatch(e.key, e.value);
          }
        }
        return null;
      case 'patch':
        // 命令式更新：优先只更新指定 id 节点，由 _IdNode 定点重建，不动全树。
        // 原生传来的 spec 是 JSON 字符串，这里必须解码成结构，否则会被当纯文本渲染。
        final m = (call.arguments as Map).cast<String, dynamic>();
        final id = m['id']?.toString();
        if (id == null) return null;
        final patch = decodeSpec(m['spec']);
        if (spec.value == null || spec.value!.isEmpty) {
          // 渲染还没到（引擎刚启动时 render/patch 可能乱序或被通道缓冲丢弃）：
          // 先存着，render 一到再补，而不是丢掉（丢掉就是“改了没反应”）。
          _pendingPatches.add(MapEntry(id, patch));
          emit('patchDiag', 'spec 未到，补丁已排队 id=$id');
        } else {
          _applyPatch(id, patch);
        }
        return null;
      case 'dialog':
        {
          final ctx = navigatorKey.currentContext;
          if (ctx == null) return null;
          await showDialog<dynamic>(
            context: ctx,
            barrierDismissible: true,
            builder: (_) => Renderer.build(_dialogSpec(decodeSpec(call.arguments))),
          );
          emit('dialogClosed');
          return null;
        }
      case 'bottomSheet':
        {
          final ctx = navigatorKey.currentContext;
          if (ctx == null) return null;
          await showModalBottomSheet<dynamic>(
            context: ctx,
            builder: (_) => Renderer.build(_dialogSpec(decodeSpec(call.arguments), type: 'Column')),
          );
          emit('bottomSheetClosed');
          return null;
        }
      case 'snackBar':
        {
          final ctx = navigatorKey.currentContext;
          if (ctx == null) return null;
          final a = decodeArgs(call.arguments);
          final text = (a?['text'] ?? a?['message'] ?? '').toString();
          final messenger = ScaffoldMessenger.maybeOf(ctx);
          messenger?.showSnackBar(
            SnackBar(
              content: Text(text),
              duration: Duration(milliseconds: (a?['duration'] as num?)?.toInt() ?? 3000),
              backgroundColor: a?['backgroundColor'] != null
                  ? _parseColor(a?['backgroundColor'])
                  : null,
              behavior: a?['behavior']?.toString().toLowerCase() == 'floating'
                  ? SnackBarBehavior.floating
                  : SnackBarBehavior.fixed,
              action: a?['actionLabel'] != null
                  ? SnackBarAction(label: (a?['actionLabel'] ?? '').toString(), onPressed: () => emit('snackBarAction'))
                  : null,
            ),
          );
          return null;
        }
      case 'closeDialog':
        navigatorKey.currentState?.maybePop();
        return null;
      case 'datePicker':
        {
          final ctx = navigatorKey.currentContext;
          if (ctx == null) return null;
          final a = decodeArgs(call.arguments);
          final now = DateTime.now();
          DateTime parse(dynamic v, DateTime def) {
            if (v == null) return def;
            if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
            return DateTime.tryParse(v.toString()) ?? def;
          }

          final first = parse(a?['firstDate'], DateTime(now.year - 1, now.month, now.day));
          final last = parse(a?['lastDate'], DateTime(now.year + 1, now.month, now.day));
          var initial = parse(a?['initialDate'], now);
          if (initial.isBefore(first)) initial = first;
          if (initial.isAfter(last)) initial = last;
          final picked = await showDatePicker(
            context: ctx,
            initialDate: initial,
            firstDate: first,
            lastDate: last,
          );
          emit('datePicked', {'ok': picked != null, 'value': picked?.toIso8601String(), 'year': picked?.year, 'month': picked?.month, 'day': picked?.day});
          return null;
        }
      case 'timePicker':
        {
          final ctx = navigatorKey.currentContext;
          if (ctx == null) return null;
          final a = decodeArgs(call.arguments);
          final picked = await showTimePicker(
            context: ctx,
            initialTime: a?['hour'] != null
                ? TimeOfDay(
                    hour: ((a?['hour'] as num?) ?? 0).toInt(),
                    minute: ((a?['minute'] as num?) ?? 0).toInt(),
                  )
                : TimeOfDay.now(),
          );
          emit('timePicked', {'ok': picked != null, 'hour': picked?.hour, 'minute': picked?.minute});
          return null;
        }
      case 'call':
        // 防御：空 List / 首元素不是 String 都会让旧代码直接崩
        final rawArgs = call.arguments;
        if (rawArgs is! List || rawArgs.isEmpty || rawArgs[0] is! String) {
          return {'error': 'bad call arguments: $rawArgs'};
        }
        final args = rawArgs.cast<dynamic>();
        final name = args[0] as String;
        final raw = args.length > 1 ? args[1] : null;
        return invoke(name, decodeArgs(raw));
      case 'dispatch':
        final data = jsonDecode(call.arguments as String);
        if (data is Map) {
          final name = data['name']?.toString();
          final list = name == null ? null : eventListeners[name];
          if (list != null) {
            // 复制一份再遍历：回调里可能增删监听
            for (final listener in List.of(list)) {
              listener(data['data']);
            }
          }
        }
        return null;
      default:
        throw MissingPluginException('未知方法 ${call.method}');
    }
  }

  /// 把原生传来的 spec（JSON 字符串）解码成 Dart 结构；已是结构则原样返回。
  /// 打一个定点补丁：节点已构建就定点重建；尚未构建就等首帧构建完再补
  /// （走的是和按钮回调里改属性完全相同的定点通道，不动全树）。
  void _applyPatch(String id, dynamic patch) {
    if (nodeSpecs.containsKey(id)) {
      nodeSpecs[id]!.value = patch;
      emit('patchDiag', '定点重建(已构建) id=$id');
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = nodeSpecs[id];
      if (notifier != null) {
        notifier.value = patch;
        emit('patchDiag', '帧后定点重建 id=$id');
      } else {
        emit('patchDiag', '帧后仍无该节点 id=$id（忽略）');
      }
    });
  }

  dynamic decodeSpec(dynamic raw) {
    if (raw is String) {
      try {
        return jsonDecode(raw);
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }

  static Color? _parseColor(dynamic v) {
    if (v is int) return Color(v);
    if (v is! String) return null;
    var hex = v.toLowerCase().replaceFirst('#', '').replaceFirst('0x', '');
    if (hex.length == 6) hex = 'ff$hex';
    final i = int.tryParse(hex, radix: 16);
    return i == null ? null : Color(i);
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
    dynamic res;
    try {
      res = handler(args);
    } catch (e) {
      return {'error': e.toString()};
    }
    // Future 交给 MethodChannel 层 await（原生 dartCall 会自动拿到结果）
    if (res is Future) return res;
    // 返回值必须能过 JSON 序列化，否则 MethodChannel 抛的异常很难排查，这里提前拦下
    try {
      jsonEncode(res);
      return res;
    } catch (e) {
      return {'error': 'return value not serializable: $e'};
    }
  }

  /// Flutter -> 原生 事件。
  void emit(String name, [dynamic data]) {
    channel.invokeMethod<void>('nativeEvent', jsonEncode({'name': name, 'data': data}));
  }

  /// 原生 -> Flutter 事件（内部使用，由 widget 回调触发）。可注册多个同名监听。
  void on(String name, void Function(dynamic data) listener) {
    (eventListeners[name] ??= <void Function(dynamic)>[]).add(listener);
  }

  /// 取消监听：不传 listener 则移除该事件的全部监听。
  void off(String name, [void Function(dynamic data)? listener]) {
    if (listener == null) {
      eventListeners.remove(name);
    } else {
      eventListeners[name]?.remove(listener);
    }
  }
}
