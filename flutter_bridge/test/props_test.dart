// Props 转换器与缓存的单元测试。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_bridge/src/props.dart';

void main() {
  test('toInsets 容错字符串元素（不再 as num 崩溃）', () {
    expect(Props.toInsets(['10', '20']), const EdgeInsets.symmetric(vertical: 10, horizontal: 20));
    expect(Props.toInsets(8), const EdgeInsets.all(8));
    expect(Props.toInsets([1, 2, 3, 4]), const EdgeInsets.fromLTRB(1, 2, 3, 4));
    expect(Props.toInsets(['8dp']), const EdgeInsets.all(8));
  });

  test('dim 支持 dp/sp/px 后缀与 fill/wrap', () {
    expect(Props.dim('16dp'), 16);
    expect(Props.dim('12sp'), 12);
    expect(Props.dim('8px'), 8);
    expect(Props.dim('fill'), double.infinity);
    expect(Props.dim('wrap'), isNull);
  });

  test('toShape：未知名退回 rounded，未传返回 null', () {
    expect(Props.toShape(null), isNull);
    expect(Props.toShape('circle'), isA<CircleBorder>());
    expect(Props.toShape('whatever', 6), isA<RoundedRectangleBorder>());
  });

  test('别名不再跨控件污染：value/fillColor 不再被改写', () {
    final p = Props.of({'value': 'v', 'fillColor': '#ff0000'});
    expect(p['text'], isNull);
    expect(p['value'], 'v');
    expect(p['color'], isNull);
  });

  test('Props.of 命中缓存（同一 Map 返回同一实例）', () {
    final raw = {'type': 'Text', 'text': 'hi'};
    final a = Props.of(raw);
    final b = Props.of(raw);
    expect(identical(a, b), isTrue);
  });

  test('toDate 支持 ISO 字符串与毫秒时间戳', () {
    expect(Props.toDate('2026-01-02'), DateTime(2026, 1, 2));
    expect(Props.toDate(0)!.millisecondsSinceEpoch, 0);
    expect(Props.toDate(null), isNull);
  });

  test('渐变支持 angle 与 radial/sweep', () {
    final linear = Props.toAnyGradient({'colors': ['#f00', '#00f'], 'angle': 90});
    expect(linear, isA<LinearGradient>());
    final radial = Props.toAnyGradient({'type': 'radial', 'colors': ['#f00', '#00f']});
    expect(radial, isA<RadialGradient>());
    final sweep = Props.toAnyGradient({'type': 'sweep', 'colors': ['#f00', '#00f']});
    expect(sweep, isA<SweepGradient>());
  });
}
