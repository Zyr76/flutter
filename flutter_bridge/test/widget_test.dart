// Dart 逻辑层与渲染器的基本单元测试（不依赖平台通道）。
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  test('invoke 拦截不可序列化返回值（避免 MethodChannel 抛难查异常）', () {
    final b = FlutterBridge.instance;
    b.handlers.clear();
    b.handlers['bad'] = (args) => const Color(0xFF000000);
    expect((b.invoke('bad', null) as Map)['error'], contains('not serializable'));
    b.handlers['ok'] = (args) => {'a': 1};
    expect(b.invoke('ok', null), {'a': 1});
  });

  test('eventListeners 支持多监听 + off 取消', () {
    final b = FlutterBridge.instance;
    b.eventListeners.clear();
    void l1(dynamic d) {}
    void l2(dynamic d) {}
    b.on('e', l1);
    b.on('e', l2);
    expect(b.eventListeners['e']!.length, 2);
    b.off('e', l1);
    expect(b.eventListeners['e']!.length, 1);
    b.off('e');
    expect(b.eventListeners.containsKey('e'), isFalse);
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

  testWidgets('图表控件 LineChart', (tester) async {
    final w = Renderer.build(jsonEncode({
      '1': 'LineChart',
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

  testWidgets('点击回调：事件名 = 回调名（AndroLua 风格 onPressed={call="hello"}）', (tester) async {
    final events = <Map<String, dynamic>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      FlutterBridge.channel,
      (MethodCall call) async {
        if (call.method == 'nativeEvent') {
          events.add((jsonDecode(call.arguments as String) as Map).cast<String, dynamic>());
        }
        return null;
      },
    );
    final w = Renderer.build(jsonEncode({
      '1': 'ElevatedButton',
      'onPressed': {'call': 'hello'},
      'child': {'1': 'Text', 'text': '点我'},
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    final hello = events.firstWhere((e) => e['name'] == 'hello');
    expect((hello['data'] as Map)['action'], 'hello');
  });

  testWidgets('id 句柄：带 id 的可点控件按 id 发 click 事件（供 h.onClick 风格）', (tester) async {
    final events = <Map<String, dynamic>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      FlutterBridge.channel,
      (MethodCall call) async {
        if (call.method == 'nativeEvent') {
          events.add((jsonDecode(call.arguments as String) as Map).cast<String, dynamic>());
        }
        return null;
      },
    );
    final w = Renderer.build(jsonEncode({
      '1': 'Column',
      '2': {'1': 'ElevatedButton', 'id': 'h', 'child': {'1': 'Text', 'text': '4664'}},
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    final e = events.firstWhere((x) => x['name'] == 'h');
    expect((e['data'] as Map)['type'], 'click');
  });

  testWidgets('稳定 key：相同结构全量重建不丢失交互状态', (tester) async {
    Widget build() => MaterialApp(
          home: Scaffold(
            body: Renderer.build(jsonEncode({
              '1': 'Column',
              '2': {'1': 'Switch', 'value': false},
            })),
          ),
        );
    await tester.pumpWidget(build());
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
    // 同结构重新渲染（模拟每次 render 全量重建），用户切换的状态应保留
    await tester.pumpWidget(build());
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
  });

  testWidgets('受控组件：Lua 回写不同 value 时同步更新', (tester) async {
    Widget build(bool v) => MaterialApp(
          home: Scaffold(
            body: Renderer.build(jsonEncode({
              '1': 'Column',
              '2': {'1': 'Switch', 'value': v},
            })),
          ),
        );
    await tester.pumpWidget(build(false));
    await tester.pumpWidget(build(true));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
  });

  testWidgets('受控组件：Lua 回写 TextField.text', (tester) async {
    Widget build(String s) => MaterialApp(
          home: Scaffold(
            body: Renderer.build(jsonEncode({'1': 'TextField', 'text': s})),
          ),
        );
    await tester.pumpWidget(build('a'));
    await tester.pumpWidget(build('b'));
    await tester.pumpAndSettle();
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('新增控件：Badge/Tooltip/SwitchListTile/CheckboxListTile/ExpansionTile/AnimatedOpacity',
      (tester) async {
    final w = Renderer.build(jsonEncode({
      '1': 'Column',
      '2': {'1': 'Badge', 'label': '3', 'child': {'1': 'Icon', 'icon': 'mail'}},
      '3': {'1': 'Tooltip', 'message': '提示', 'child': {'1': 'Text', 'text': '悬停'}},
      '4': {'1': 'SwitchListTile', 'title': '开关项', 'value': true},
      '5': {'1': 'CheckboxListTile', 'title': '复选项', 'value': false},
      '6': {
        '1': 'ExpansionTile',
        'title': '展开',
        'children': [
          {'1': 'Text', 'text': '内容X'},
        ],
      },
      '7': {'1': 'AnimatedOpacity', 'opacity': 0.5, 'duration': 100, 'child': {'1': 'Text', 'text': '淡'}},
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    expect(find.byType(Badge), findsOneWidget);
    expect(find.byType(Tooltip), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(find.byType(ExpansionTile), findsOneWidget);
    expect(find.byType(AnimatedOpacity), findsOneWidget);
    expect(find.text('开关项'), findsOneWidget);
  });

  testWidgets('DataTable 渲染', (tester) async {
    final w = Renderer.build(jsonEncode({
      '1': 'DataTable',
      'columns': ['名称', '数量'],
      'rows': [
        ['A', '1'],
        ['B', '2'],
      ],
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('名称'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('Radio 套 RadioGroup 渲染（避免已弃用参数）', (tester) async {
    final w = Renderer.build(jsonEncode({
      '1': 'Radio',
      'value': 'a',
      'groupValue': 'a',
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    expect(find.byWidgetPredicate((w) => w is Radio), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is RadioGroup<dynamic>), findsOneWidget);
  });

  testWidgets('id 节点定点更新：改 notifier 只重建该节点', (tester) async {
    final w = Renderer.build(jsonEncode({
      '1': 'Column',
      '2': {'1': 'Text', 'id': 'h', 'text': '旧'},
      '3': {'1': 'Text', 'text': '固定'},
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    expect(find.text('旧'), findsOneWidget);
    // 模拟 h.Text="新" 下发的 patch
    FlutterBridge.instance.nodeSpecs['h']!.value = {'1': 'Text', 'id': 'h', 'text': '新'};
    await tester.pump();
    expect(find.text('新'), findsOneWidget);
    expect(find.text('旧'), findsNothing);
    expect(find.text('固定'), findsOneWidget);
  });

  testWidgets('属性名大小写不敏感：h.Text 等价 text', (tester) async {
    final w = Renderer.build(jsonEncode({'1': 'Text', 'Text': '大写键'}));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    expect(find.text('大写键'), findsOneWidget);
  });

  testWidgets('图片 src 自适应：network / data(base64) / file', (tester) async {
    Future<Image> buildImage(String src) async {
      final w = Renderer.build(jsonEncode({'1': 'Image', 'src': src}));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
      return tester.widget<Image>(find.byType(Image));
    }

    final net = await buildImage('https://example.com/a.png');
    expect(net.image, isA<NetworkImage>());

    const png1x1 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
    final mem = await buildImage('data:image/png;base64,$png1x1');
    expect(mem.image, isA<MemoryImage>());

    final file = await buildImage('/data/local/tmp/a.png');
    expect(file.image, isA<FileImage>());
  });

  testWidgets('扩充控件批量渲染不报错', (tester) async {
    final w = Renderer.build(jsonEncode({
      '1': 'SingleChildScrollView',
      'child': {
        '1': 'Column',
        'gap': 8,
        'children': [
          {'1': 'Material', 'elevation': 2, 'child': {'1': 'Text', 'text': 'M'}},
          {'1': 'SegmentedButton', 'segments': [
            {'value': 'a', 'label': 'A'},
            {'value': 'b', 'label': 'B'},
          ], 'selected': ['a']},
          {'1': 'ToggleButtons', 'isSelected': [true, false], 'children': [
            {'1': 'Text', 'text': 'T1'},
            {'1': 'Text', 'text': 'T2'},
          ]},
          {'1': 'PopupMenuButton', 'items': [{'value': 'x', 'text': 'X'}]},
          {'1': 'ActionChip', 'text': 'chip'},
          {'1': 'RangeSlider', 'min': 0, 'max': 10, 'start': 2, 'end': 8},
          {'1': 'NavigationBar', 'items': [
            {'icon': 'home', 'label': 'H'},
            {'icon': 'person', 'label': 'P'},
          ]},
          {'1': 'AnimatedScale', 'scale': 1.0, 'child': {'1': 'Text', 'text': 'scale'}},
          {'1': 'AnimatedCrossFade', 'children': [
            {'1': 'Text', 'text': 'one'},
            {'1': 'Text', 'text': 'two'},
          ]},
          {'1': 'RichText', 'spans': [
            {'text': 'ra', 'fontWeight': 'bold'},
            {'text': 'rb'},
          ]},
          {'1': 'DecoratedBox', 'color': '#eeeeee', 'child': {'1': 'Text', 'text': 'D'}},
          {'1': 'ConstrainedBox', 'minWidth': 10, 'child': {'1': 'Text', 'text': 'C'}},
        ],
      },
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    expect(find.text('M'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(find.byType(RangeSlider), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(AnimatedCrossFade), findsOneWidget);
    expect(find.text('rarb'), findsOneWidget);
  });

  testWidgets('patch 传 JSON 字符串能正确渲染（回归：之前会当纯文本显示）', (tester) async {
    final w = Renderer.build(jsonEncode({
      '1': 'Column',
      '2': {'1': 'Text', 'id': 'tv', 'text': '旧'},
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    expect(find.text('旧'), findsOneWidget);
    // 模拟原生 patch：spec 是节点 JSON 字符串
    FlutterBridge.instance.nodeSpecs['tv']!.value =
        jsonEncode({'1': 'Text', 'id': 'tv', 'text': '你好'});
    await tester.pump();
    expect(find.text('你好'), findsOneWidget);
    expect(find.textContaining('"1"'), findsNothing);
  });

  testWidgets('弹窗/复杂/动画控件批量渲染', (tester) async {
    final w = Renderer.build(jsonEncode({
      '1': 'SingleChildScrollView',
      'child': {
        '1': 'Column',
        'gap': 8,
        'children': [
          {
            '1': 'AlertDialog',
            'title': {'1': 'Text', 'text': '标题D'},
            'content': {'1': 'Text', 'text': '内容D'},
            'actions': [
              {'1': 'TextButton', 'text': 'OK'},
            ],
          },
          {'1': 'SimpleDialog', 'title': {'1': 'Text', 'text': 'SD'}, 'children': [
            {'1': 'Text', 'text': 'sd1'},
          ]},
          {'1': 'Dialog', 'child': {'1': 'Text', 'text': 'D'}},
          {'1': 'BottomSheet', 'children': [{'1': 'Text', 'text': 'BS'}]},
          {'1': 'SizedBox', 'height': 200, 'child': {
            '1': 'PageView',
            'children': [
              {'1': 'Center', 'child': {'1': 'Text', 'text': 'P1'}},
              {'1': 'Center', 'child': {'1': 'Text', 'text': 'P2'}},
            ],
          }},
          {'1': 'SizedBox', 'height': 300, 'child': {
            '1': 'NavigationRail',
            'items': [
              {'icon': 'home', 'label': 'H'},
              {'icon': 'person', 'label': 'P'},
            ],
          }},
          {'1': 'DropdownMenu', 'items': [
            {'value': 'a', 'label': 'A'},
            {'value': 'b', 'label': 'B'},
          ]},
          {'1': 'Table', 'border': true, 'rows': [
            ['a', 'b'],
            ['c', 'd'],
          ]},
          {'1': 'ExpansionPanelList', 'panels': [
            {'header': '头', 'body': {'1': 'Text', 'text': '体'}},
          ]},
          {'1': 'SizedBox', 'height': 200, 'child': {
            '1': 'Stack',
            'children': [
              {'1': 'AnimatedPositioned', 'left': 10, 'top': 10, 'child': {'1': 'Text', 'text': 'AP'}},
              {'1': 'AnimatedSize', 'child': {'1': 'Text', 'text': 'AS'}},
            ],
          }},
          {'1': 'SizedBox', 'height': 200, 'child': {
            '1': 'CustomScrollView',
            'slivers': [
              {'1': 'SliverToBoxAdapter', 'child': {'1': 'Text', 'text': 'S1'}},
              {'1': 'SliverList', 'children': [
                {'1': 'Text', 'text': 'S2'},
              ]},
            ],
          }},
        ],
      },
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    expect(find.text('内容D'), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(AnimatedPositioned), findsOneWidget);
    expect(find.byType(CustomScrollView, skipOffstage: false), findsOneWidget);
  });

  testWidgets('ListChart 支持 groups 分组柱（不传 groups 仍兼容 series）', (tester) async {
    final w = Renderer.build(jsonEncode({
      '1': 'BarChart',
      'height': 200,
      'groups': [
        {'values': [1, 2]},
        {'values': [3, 4]},
      ],
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    expect(find.byType(BarChart), findsOneWidget);
  });

  testWidgets('未知控件名优雅降级，不报错', (tester) async {
    // 控件名去别名后，非 Flutter 名（如 Button）会走降级分支
    final w = Renderer.build(jsonEncode({
      '1': 'Column',
      '2': {'1': 'Button', 'text': 'x'},
    }));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));
    expect(tester.takeException(), isNull);
  });
}
