// Dart 逻辑层：只保留「必须在 Flutter/Dart 侧做」的能力。
//
// 设计原则：业务逻辑写 Lua（调原生 / 调 Lua 库都行），Dart 侧只提供
// Flutter 上下文与插件相关的入口；能用 Lua 做的（http/json/base64/uuid/时间…）
// 一律不在这里重复实现。
//
// 可用的 dartCall 名称：
//   flutterControl({ id=, action=, ... })  —— 统一控制（媒体/滚动/翻页/文本框/抽屉），
//                                             动作清单见 renderer.dart 的 FlutterControl 注释
//   flutterVideo({ id=, action=, ... })    —— 视频控制（等价 flutterControl 的媒体分支）
//   openDrawer / closeDrawer               —— Scaffold 抽屉开关（需要 Flutter 上下文）
//
// 另外，任何带 id 的控件都能用 Lua 的 `id.dart.属性 = 值` 命令式改属性
// （原生 patchNode → Dart 定点重建），不经过本文件。

import 'renderer.dart';

void registerDefaultHandlers(
  Map<String, dynamic Function(Map<String, dynamic>? args)> handlers,
) {
  // 统一控制入口：{ id, action, ... }
  handlers['flutterControl'] = FlutterControl.call;

  // 视频专用入口（等价 flutterControl 的媒体分支，语义更直观）
  handlers['flutterVideo'] = FlutterVideo.call;

  // 需要 Flutter 上下文的抽屉操作
  handlers['openDrawer'] = (args) {
    Renderer.scaffoldKey.currentState?.openDrawer();
    return {'ok': true};
  };
  handlers['closeDrawer'] = (args) {
    Renderer.scaffoldKey.currentState?.closeDrawer();
    return {'ok': true};
  };
}
