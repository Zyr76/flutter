import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'logic.dart';
import 'props.dart';
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
  /// 渲染尚未到达时先存下的补丁：按 id 去重（同 id 只留最后一次），带时间戳用于过期丢弃。
  final Map<String, (dynamic, DateTime)> _pendingPatches = {};

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

  /// id 的在树引用计数：_IdNode 挂载 +1、卸载 -1，归零才移除 nodeSpecs。
  /// 不清理会让 nodeSpecs 只增不减，且 _applyPatch 的 containsKey 退化成“曾经存在过”。
  final Map<String, int> _nodeRefs = {};

  /// 取得（必要时创建）某 id 节点的 spec notifier（引用计数 +1）。
  ValueNotifier<dynamic> nodeNotifier(String id, dynamic initial) {
    _nodeRefs[id] = (_nodeRefs[id] ?? 0) + 1;
    return nodeSpecs.putIfAbsent(id, () => ValueNotifier<dynamic>(initial));
  }

  /// 节点卸载时调用（引用计数 -1，归零移除）。
  void releaseNode(String id) {
    final n = (_nodeRefs[id] ?? 0) - 1;
    if (n <= 0) {
      _nodeRefs.remove(id);
      nodeSpecs.remove(id);
    } else {
      _nodeRefs[id] = n;
    }
  }

  /// dartCall 的逻辑方法表：名字 -> 函数(参数 map) -> 可 JSON 序列化的返回值。
  final Map<String, dynamic Function(Map<String, dynamic>? args)> handlers = {};

  /// UI 调试总开关（Lua 侧 `flutterUI_debug(true)` 打开）。
  /// 开启后：未知控件告警、构建错误显示红框、Flutter 异常回传 Lua。
  bool uiDebug = false;

  void setUiDebug(bool on) {
    uiDebug = on;
    debugPrint('[Flutter] UI 调试已${on ? "开启" : "关闭"}');
  }

  /// 已上报过的问题（同类只报一次，避免每帧刷屏）。
  final Set<String> _reportedIssues = {};

  /// 上报一条 UI 侧问题（未知控件等）：仅 uiDebug 打开时生效，同类只报一次。
  void reportUiIssue(String message) {
    if (!uiDebug || !_reportedIssues.add(message)) return;
    debugPrint('[Flutter] $message');
    emit('flutterUiIssue', {'message': message});
  }

  /// 原生主动推来的事件监听：事件名 -> 回调列表（同名事件可多个监听，不再互相覆盖）。
  final Map<String, List<void Function(dynamic data)>> eventListeners = {};

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    // 错误边界：单个节点构建失败只坏那一块，不再让整棵树变空白。
    // uiDebug 关闭时渲染成空占位（不给终端用户看红框），但异常照样回传 Lua。
    ErrorWidget.builder = (d) =>
        uiDebug ? _uiErrorBox(d) : const SizedBox.shrink();
    FlutterError.onError = (d) {
      FlutterError.presentError(d);
      emit('flutterError', {'message': d.exceptionAsString()});
    };
    registerDefaultHandlers(handlers);
    channel.setMethodCallHandler(_onMethodCall);
    // 告诉原生：Dart 侧通道已就绪。引擎启动初期通道缓冲有限（见 ChannelBuffers），
    // 过早连发多条消息会把先发的挤掉（典型：render 被后面的 patch 顶掉，界面变占位）。
    channel.invokeMethod<void>('ready').catchError((Object _) {});
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

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'render':
        // B-11：原生误传非 String 时给出明确事件，而不是抛 TypeError
        final rawSpec = call.arguments;
        if (rawSpec is! String && rawSpec != null) {
          emit('renderError', {'message': 'render 参数不是 String: ${rawSpec.runtimeType}'});
          return null;
        }
        spec.value = rawSpec as String?;
        // 排队补丁：丢掉超过 30 秒的（渲染一直不来不能无限攒），其余按 id 补打（已去重）。
        if (_pendingPatches.isNotEmpty) {
          final now = DateTime.now();
          final pending = <String, dynamic>{};
          _pendingPatches.forEach((id, entry) {
            if (now.difference(entry.$2).inSeconds <= 30) pending[id] = entry.$1;
          });
          _pendingPatches.clear();
          pending.forEach(_applyPatch);
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
          _pendingPatches[id] = (patch, DateTime.now());
          emit('patchDiag', 'spec 未到，补丁已排队 id=$id');
        } else {
          _applyPatch(id, patch);
        }
        return null;
      case 'dialog':
        {
          final ctx = navigatorKey.currentContext;
          if (ctx == null) return null;
          try {
            await showDialog<dynamic>(
              context: ctx,
              barrierDismissible: true,
              builder: (_) => Renderer.build(_dialogSpec(decodeSpec(call.arguments))),
            );
            emit('dialogClosed');
          } catch (e) {
            emit('dialogError', {'message': e.toString()});
          }
          return null;
        }
      case 'bottomSheet':
        {
          final ctx = navigatorKey.currentContext;
          if (ctx == null) return null;
          try {
            await showModalBottomSheet<dynamic>(
              context: ctx,
              builder: (_) => Renderer.build(_dialogSpec(decodeSpec(call.arguments), type: 'Column')),
            );
            emit('bottomSheetClosed');
          } catch (e) {
            emit('bottomSheetError', {'message': e.toString()});
          }
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

  /// 与 Props.toColor 保持单一实现（支持 int / 0x 前缀 / 3·6·8 位 hex / 命名色）。
  static Color? _parseColor(dynamic v) => Props.toColor(v);

  Map<String, dynamic>? decodeArgs(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is String && raw.isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) return d.cast<String, dynamic>();
      } catch (e) {
        if (kDebugMode) debugPrint('[Bridge] decodeArgs 解析失败: $e');
      }
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
    // 通道不通（引擎销毁/原生未就绪）时不能变成未处理的 Future 异常，
    // 否则错误处理路径里会二次抛错。
    channel
        .invokeMethod<void>('nativeEvent', jsonEncode({'name': name, 'data': data}))
        .catchError((Object e) {
      if (kDebugMode) debugPrint('[Bridge] emit($name) 失败: $e');
    });
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
      final list = eventListeners[name];
      list?.remove(listener);
      if (list != null && list.isEmpty) eventListeners.remove(name);
    }
  }
}

/// 构建失败时的红框占位（只在 uiDebug 打开时使用）。
Widget _uiErrorBox(FlutterErrorDetails d) {
  final msg = d.exceptionAsString();
  final short = msg.length > 200 ? '${msg.substring(0, 200)}…' : msg;
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFFDE7E9),
        border: Border.all(color: const Color(0xFFE53935)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('渲染错误：$short',
          style: const TextStyle(color: Color(0xFFB71C1C), fontSize: 11)),
    ),
  );
}
