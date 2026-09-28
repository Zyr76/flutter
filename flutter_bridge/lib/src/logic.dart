// Dart 逻辑层：被 Lua 通过 dartCall / 调用Dart 调用并拿到返回。
//
// 注册进 registerDefaultHandlers 的 handlers 表；签名统一为
//   dynamic Function(Map<String, dynamic>? args)
// 返回值需可 JSON 序列化（Map / List / num / String / bool / null）。
// 也可以返回 Future —— 经 dartCall 时会自动 await；但 onClick 这类 UI 回调不能等异步结果。

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'renderer.dart';

void registerDefaultHandlers(
  Map<String, dynamic Function(Map<String, dynamic>? args)> handlers,
) {
  // ---------- 示例 / 调试 ----------
  handlers['ping'] = (args) => {'pong': true, 'ts': DateTime.now().millisecondsSinceEpoch};
  handlers['echo'] = (args) => {'echo': args};

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

  // ---------- UI 相关 ----------
  handlers['openDrawer'] = (args) {
    Renderer.scaffoldKey.currentState?.openDrawer();
    return {'ok': true};
  };
  handlers['closeDrawer'] = (args) {
    Renderer.scaffoldKey.currentState?.closeDrawer();
    return {'ok': true};
  };

  // ---------- 工具 ----------
  handlers['now'] = (args) => {
        'ms': DateTime.now().millisecondsSinceEpoch,
        'iso': DateTime.now().toIso8601String(),
      };

  handlers['uuid'] = (args) => {'uuid': _uuid()};

  handlers['randomInt'] = (args) {
    final min = (args?['min'] as num?)?.toInt() ?? 0;
    final max = (args?['max'] as num?)?.toInt() ?? 100;
    return {'value': min + _rand.nextInt(max <= min ? 1 : max - min)};
  };

  handlers['sleep'] = (args) async {
    final ms = (args?['ms'] as num?)?.toInt() ?? 0;
    await Future<void>.delayed(Duration(milliseconds: ms));
    return {'ok': true};
  };

  handlers['jsonEncode'] = (args) => {'json': jsonEncode(args?['data'])};
  handlers['jsonDecode'] = (args) {
    try {
      return {'data': jsonDecode((args?['json'] ?? 'null').toString())};
    } catch (e) {
      return {'error': e.toString()};
    }
  };

  handlers['base64Encode'] = (args) => {
        'text': base64Encode(utf8.encode((args?['text'] ?? '').toString())),
      };
  handlers['base64Decode'] = (args) {
    try {
      return {'text': utf8.decode(base64Decode((args?['text'] ?? '').toString()))};
    } catch (e) {
      return {'error': e.toString()};
    }
  };

  // ---------- HTTP（dart:io，异步；经 dartCall 会自动 await） ----------
  handlers['httpGet'] = (args) => _http('GET', args);
  handlers['httpPost'] = (args) => _http('POST', args);

  // ---------- 业务示例（可替换为真实后端） ----------
  handlers['login'] = (args) {
    final user = (args?['user'] ?? '').toString();
    final pass = (args?['pass'] ?? '').toString();
    if (user.isEmpty || pass.isEmpty) {
      return {'ok': false, 'error': '用户名或密码为空'};
    }
    return {'ok': true, 'token': 'demo-token-${_uuid().substring(0, 8)}', 'user': user};
  };

  handlers['fetchOrders'] = (args) {
    final page = (args?['page'] as num?)?.toInt() ?? 1;
    final size = (args?['size'] as num?)?.toInt() ?? 10;
    final list = List.generate(size, (i) {
      final id = (page - 1) * size + i + 1;
      return {
        'id': id,
        'title': '订单 #$id',
        'amount': (id * 12.5).toStringAsFixed(2),
        'status': id % 3 == 0 ? '已完成' : (id % 3 == 1 ? '待付款' : '已发货'),
      };
    });
    return {'page': page, 'size': size, 'list': list};
  };

  handlers['saveProfile'] = (args) {
    // 生产环境接数据库/接口；这里回显以验证链路
    return {'ok': true, 'saved': args ?? {}};
  };
}

Future<Map<String, dynamic>> _http(String method, Map<String, dynamic>? args) async {
  final url = (args?['url'] ?? '').toString();
  if (url.isEmpty) return {'error': 'url 为空'};
  final headers = (args?['headers'] as Map?)?.cast<String, dynamic>();
  final body = args?['body']?.toString();
  final timeout = (args?['timeout'] as num?)?.toInt() ?? 15000;

  final client = HttpClient()..connectionTimeout = Duration(milliseconds: timeout);
  try {
    final req = await client.openUrl(method, Uri.parse(url)).timeout(Duration(milliseconds: timeout));
    headers?.forEach((k, v) => req.headers.set(k, v.toString()));
    if (body != null) req.write(body);
    final resp = await req.close().timeout(Duration(milliseconds: timeout));
    final text = await resp.transform(utf8.decoder).join();
    return {'status': resp.statusCode, 'body': text};
  } catch (e) {
    return {'error': e.toString()};
  } finally {
    client.close(force: true);
  }
}

final Random _rand = Random();

String _uuid() {
  const chars = '0123456789abcdef';
  String seg(int n) => List.generate(n, (_) => chars[_rand.nextInt(16)]).join();
  return '${seg(8)}-${seg(4)}-4${seg(3)}-${chars[8 + _rand.nextInt(4)]}${seg(3)}-${seg(12)}';
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
