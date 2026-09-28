// Dart 逻辑层：这些方法可以被 Lua 通过 dartCall("名字", {...}) 调用并拿到返回。
//
// 注册进 registerDefaultHandlers 的 handlers 表，方法签名统一为
// `dynamic Function(Map<String, dynamic>? args)`，
// 返回值必须是可 JSON 序列化的对象（Map / List / num / String / bool / null）。

import 'renderer.dart';

void registerDefaultHandlers(
  Map<String, dynamic Function(Map<String, dynamic>? args)> handlers,
) {
  handlers['ping'] = (args) => {'pong': true, 'ts': DateTime.now().millisecondsSinceEpoch};

  handlers['getUserInfo'] = (args) => {
        'id': args?['id'] ?? 0,
        'name': '张三',
        'age': 28,
        'vip': true,
        'tags': ['flutter', 'dart', 'androlua'],
      };

  handlers['add'] = (args) {
    final a = (args?['a'] as num?)?.toDouble() ?? 0;
    final b = (args?['b'] as num?)?.toDouble() ?? 0;
    return {'result': a + b};
  };

  handlers['toUpper'] = (args) => {
        'text': (args?['text'] as String? ?? '').toUpperCase(),
      };

  handlers['fib'] = (args) {
    final n = (args?['n'] as num?)?.toInt() ?? 0;
    return {'n': n, 'value': _fib(n)};
  };

  // 打开/关闭当前 Scaffold 的抽屉（供 Lua 的 onClick={call="openDrawer"} 使用）
  handlers['openDrawer'] = (args) {
    Renderer.scaffoldKey.currentState?.openDrawer();
    return {'ok': true};
  };
  handlers['closeDrawer'] = (args) {
    Renderer.scaffoldKey.currentState?.closeDrawer();
    return {'ok': true};
  };

  // 回显：便于前端调试时确认参数
  handlers['echo'] = (args) => {'echo': args};
}

int _fib(int n) {
  if (n < 2) return n;
  var a = 0, b = 1;
  for (var i = 2; i <= n; i++) {
    final c = a + b;
    a = b;
    b = c;
  }
  return b;
}
