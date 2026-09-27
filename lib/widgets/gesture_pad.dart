import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../security.dart';

/// 九宫格手势绘制控件
class GesturePad extends StatefulWidget {
  final void Function(List<int> seq)? onComplete;
  final Color? activeColor;
  GesturePad({super.key, this.onComplete, this.activeColor});

  @override
  State<GesturePad> createState() => _GesturePadState();
}

class _GesturePadState extends State<GesturePad> {
  List<int> _points = []; // 已选点，含自动补入的中点
  List<Offset> _dots = List.filled(9, Offset.zero);
  Offset? _current;
  double _size = 0;

  double get _cell => _size / 3;
  double get _r => _cell * 0.12;

  void _layout(Size size) {
    _size = size.shortestSide;
    for (var i = 0; i < 9; i++) {
      final r = i ~/ 3, c = i % 3;
      _dots[i] = Offset(_cell * (c + 0.5), _cell * (r + 0.5));
    }
  }

  int? _hit(Offset p) {
    for (var i = 0; i < 9; i++) {
      if ((p - _dots[i]).distance < _cell * 0.45) return i;
    }
    return null;
  }

  void _move(Offset p) {
    final hit = _hit(p);
    setState(() {
      _current = p;
      if (hit != null) {
        if (!_points.contains(hit)) {
          if (_points.isNotEmpty) {
            final mid = GestureCode.between(_points.last, hit);
            if (mid != null && !_points.contains(mid)) {
              _points.add(mid);
            }
          }
          _points.add(hit);
        }
      }
    });
  }

  void _end() {
    if (_points.length >= 4) {
      widget.onComplete?.call(List.of(_points));
    }
    setState(() {
      _points.clear();
      _current = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      _layout(Size(c.maxWidth, c.maxHeight));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (d) => _move(d.localPosition),
        onPanUpdate: (d) => _move(d.localPosition),
        onPanEnd: (_) => _end(),
        onPanCancel: _end,
        child: CustomPaint(
          painter: _PadPainter(_dots, _points, _current, _r,
              widget.activeColor ?? AppTheme.of(context).clay),
          size: Size(c.maxWidth, c.maxHeight),
        ),
      );
    });
  }
}

class _PadPainter extends CustomPainter {
  final List<Offset> dots;
  final List<int> points;
  final Offset? current;
  final double r;
  final Color c;

  _PadPainter(this.dots, this.points, this.current, this.r, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = Colors.white;
    final base = Paint()
      ..color = const Color(0xFFD9CFBE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final activeFill = Paint()..color = c.withOpacity( 0.16);
    final active = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final center = Paint()..color = c;

    // 连线
    if (points.length > 1) {
      final path = Path();
      path.moveTo(dots[points.first].dx, dots[points.first].dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(dots[points[i]].dx, dots[points[i]].dy);
      }
      if (current != null) path.lineTo(current!.dx, current!.dy);
      canvas.drawPath(path, active);
    }

    for (var i = 0; i < 9; i++) {
      final d = dots[i];
      final selected = points.contains(i);
      // 外圈
      canvas.drawCircle(d, r * 1.9, base);
      canvas.drawCircle(d, r * 1.9, fill);
      if (selected) {
        canvas.drawCircle(d, r * 2.2, activeFill);
        canvas.drawCircle(d, r * 2.2, active);
        canvas.drawCircle(d, r * 0.85, center);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PadPainter old) =>
      old.points != points || old.current != current;
}