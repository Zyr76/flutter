// Props 转换器与缓存的单元测试。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  test('Props.of 不做实例缓存：同一 Map 的原地修改也要反映出来', () {
    final raw = {'type': 'Text', 'text': 'hi'};
    final a = Props.of(raw);
    raw['text'] = 'changed'; // 原地改（修复前会命中缓存拿到旧值）
    final b = Props.of(raw);
    expect(a['text'], 'hi');
    expect(b['text'], 'changed');
    expect(identical(a, b), isFalse);
  });

  test('toDate 支持 ISO 字符串与毫秒时间戳', () {
    expect(Props.toDate('2026-01-02'), DateTime(2026, 1, 2));
    expect(Props.toDate(0)!.millisecondsSinceEpoch, 0);
    expect(Props.toDate(null), isNull);
  });

  test('toDate：Lua os.time() 的秒级时间戳要按秒解析（P-11）', () {
    const sec = 1750000000; // 2025-06-15 左右，10 位
    final a = Props.toDate(sec)!;
    final b = Props.toDate(sec * 1000)!; // 同刻的毫秒值
    expect(a.year, greaterThan(2024));
    expect(a.millisecondsSinceEpoch, sec * 1000);
    expect(a, b);
  });

  test('toKeyboardType：number 不再返回电话键盘（P-15）', () {
    expect(Props.toKeyboardType('number'), TextInputType.number);
    expect(Props.toKeyboardType('phone'), TextInputType.phone);
    expect(Props.toKeyboardType('decimal')!.decimal, isTrue);
  });

  test('toColor：命名色与 3 位简写都认（B-8 复用后能力一致）', () {
    expect(Props.toColor('red'), const Color(0xFFF44336));
    expect(Props.toColor('#f00'), const Color(0xFFFF0000));
    expect(Props.toColor('#80ff0000'), const Color(0x80FF0000));
    expect(Props.toColor(0xFFFF0000), const Color(0xFFFF0000));
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
