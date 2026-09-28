// Dart 逻辑层与渲染器的基本单元测试（不依赖平台通道）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_bridge/src/bridge.dart';
import 'package:flutter_bridge/src/renderer.dart';

void main() {
  test('dartCall 逻辑方法可返回结果', () {
    final b = FlutterBridge.instance;
    b.handlers.clear();
    b.handlers['add'] = (args) => {'result': (args!['a'] as num) + (args['b'] as num)};
    expect(b.invoke('add', {'a': 1, 'b': 2}), {'result': 3});
    expect((b.invoke('nope', null) as Map)['error'], contains('no such'));
  });

  testWidgets('渲染器把 JSON 描述转成 widget', (tester) async {
    final w = Renderer.build(
      '{"type":"Column","gap":4,"children":[{"type":"Text","text":"hi"},{"type":"Button","text":"go"}]}',
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    expect(find.text('hi'), findsOneWidget);
    expect(find.text('go'), findsOneWidget);
  });
}
