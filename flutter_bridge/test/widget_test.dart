// Dart 逻辑层与渲染器的基本单元测试（不依赖平台通道）。
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

  testWidgets('有状态交互控件：点开关/复选框会即时切换', (tester) async {
    final w = Renderer.build(
      '{"type":"Column","children":['
      '{"type":"Switch","value":false},'
      '{"type":"Checkbox","value":false}]}',
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    expect(tester.widget<Switch>(find.byType(Switch)).value, false);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, true);
  });

  testWidgets('Material 控件：Scaffold/AppBar/BottomNavigationBar', (tester) async {
    final w = Renderer.build(jsonEncode({
      'type': 'Scaffold',
      'appBar': {
        'type': 'AppBar',
        'title': {'type': 'Text', 'text': '标题'},
      },
      'body': {'type': 'Text', 'text': '内容'},
      'bottomNavigationBar': {
        'type': 'BottomNavigationBar',
        'items': [
          {'icon': 'home', 'label': '首页'},
          {'icon': 'person', 'label': '我的'},
        ],
      },
    }));
    await tester.pumpWidget(MaterialApp(home: w));
    expect(find.text('标题'), findsOneWidget);
    expect(find.text('内容'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
  });

  testWidgets('AndroLua 风格嵌套插槽：appBar/body 用首元素控件名', (tester) async {
    // 模拟 Java 只规范化了顶层、嵌套槽仍是 { "1": "Widget", ... } 的情况
    final w = Renderer.build(jsonEncode({
      '1': 'Scaffold',
      'appBar': {
        '1': 'AppBar',
        'title': {'1': 'Text', 'text': '标题'},
        'actions': [
          {'1': 'IconButton', 'icon': 'search'},
        ],
      },
      'body': {
        '1': 'SingleChildScrollView',
        'child': {
          '1': 'Column',
          'gap': 8,
          '2': {'1': 'Text', 'text': '第一行'},
          '3': {'1': 'Text', 'text': '第二行'},
        },
      },
      'bottomNavigationBar': {
        '1': 'BottomNavigationBar',
        'items': [
          {'1': 'BottomNavigationBarItem', 'icon': 'home', 'label': '首页'},
          {'1': 'BottomNavigationBarItem', 'icon': 'person', 'label': '我的'},
        ],
      },
    }));
    await tester.pumpWidget(MaterialApp(home: w));
    expect(find.text('标题'), findsOneWidget);
    expect(find.text('第一行'), findsOneWidget);
    expect(find.text('第二行'), findsOneWidget);
  });

  testWidgets('ListView.builder 模板懒加载：只构建可见项', (tester) async {
    final w = Renderer.build(jsonEncode({
      '1': 'ListView',
      'itemCount': 200,
      'itemTemplate': {'1': 'Text', 'text': r'第 $index 项'},
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    expect(find.text('第 0 项'), findsOneWidget);
    expect(find.text('第 1 项'), findsOneWidget);
    expect(find.text('第 100 项'), findsNothing); // 未构建
  });

  testWidgets('二维码控件 QrCode', (tester) async {
    final w = Renderer.build(jsonEncode({
      '1': 'QrCode',
      'data': 'https://aicode.murk.top',
      'size': 120,
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: w))));
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('图表控件 Chart', (tester) async {
    final w = Renderer.build(jsonEncode({
      '1': 'Chart',
      'chartType': 'line',
      'height': 200,
      'series': [
        {'name': 'A', 'color': '#3F51B5', 'points': [{'x': 0, 'y': 1}, {'x': 1, 'y': 3}]},
      ],
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('别名 onPressed 正确解析（按钮不能是禁用态）', (tester) async {
    // 嵌套节点：Java 不会规范化，Dart 侧 Props 必须把 onPressed 归到 onTap
    final w = Renderer.build(jsonEncode({
      '1': 'Scaffold',
      'body': {
        '1': 'Center',
        'child': {
          '1': 'ElevatedButton',
          'onPressed': {'call': 'hello'},
          'child': {'1': 'Text', 'text': '点我'},
        },
      },
    }));
    await tester.pumpWidget(MaterialApp(home: w));
    final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(btn.onPressed, isNotNull); // 非禁用态（不是灰色、可点）
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
  });
}
