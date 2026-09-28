// Dart 逻辑层：这些方法可以被 Lua 通过 dartCall("名字", {...}) 调用并拿到返回。
//
// 注册进 registerDefaultHandlers 的 handlers 表，方法签名统一为
// `dynamic Function(Map<String, dynamic>? args)`，
// 返回值必须是可 JSON 序列化的对象（Map / List / num / String / bool / null）。

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
