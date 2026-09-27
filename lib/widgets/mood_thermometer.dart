import 'package:flutter/material.dart';

import '../theme.dart';

/// 日志情绪温度计。
/// 取值 0 ~ 10，0 为“冰封”，10 为“兴奋”。
/// 编辑器用 [MoodThermometerSlider] 交互调节；列表用 [MoodThermometerBar] 展示。

/// 温度→情绪标签
String moodLabel(int v) {
  v = v.clamp(0, 10);
  if (v == 0) return '冰封';
  if (v <= 2) return '低落';
  if (v <= 5) return '平静';
  if (v <= 7) return '愉悦';
  if (v <= 9) return '开心';
  return '兴奋';
}

/// 温度→颜色：从寒蓝(冷)渐变到暖橙(热)
Color moodColor(int v) {
  v = v.clamp(0, 10);
  final hue = 215 - (215 - 10) * v / 10; // 215(蓝) → 10(橙红)
  return HSLColor.fromAHSL(1, hue, 0.62, 0.52).toColor();
}

/// 温度计渐变（两端色板）
List<Color> moodGradient() => [
      const Color(0xFF6A9BD9), // 蓝(冰)
      const Color(0xFF7FB8C9), // 青
      const Color(0xFFA8C97F), // 绿
      const Color(0xFFE0B35A), // 黄
      const Color(0xFFE37A4F), // 橙
      const Color(0xFFE04B3A), // 红(沸腾)
    ];

/// 交互式温度计滑块（编辑用）
class MoodThermometerSlider extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const MoodThermometerSlider(
      {Key? key, required this.value, required this.onChanged})
      : super(key: key);
  @override
  State<MoodThermometerSlider> createState() => _MoodThermometerSliderState();
}

class _MoodThermometerSliderState extends State<MoodThermometerSlider> {
  late double _v;

  @override
  void initState() {
    super.initState();
    _v = widget.value.toDouble();
  }

  @override
  void didUpdateWidget(covariant MoodThermometerSlider old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) _v = widget.value.toDouble();
  }

  void _update(double dx, double width) {
    final v = (dx / width).clamp(0.0, 1.0) * 10;
    final rounded = v.round().clamp(0, 10);
    setState(() => _v = v);
    if (rounded != widget.value) widget.onChanged(rounded);
  }

  @override
  Widget build(BuildContext context) {
    final v = _v.round();
    final c = moodColor(v);
    final label = moodLabel(v);
    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('$v',
            style: TextStyle(
                fontSize: 42, height: 1.0, fontWeight: FontWeight.w300,
                color: c, fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('°', style: TextStyle(fontSize: 20, color: c)),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: c.withOpacity(0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: c)),
        ),
      ]),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (ctx, box) {
        final w = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _update(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) => _update(d.localPosition.dx, w),
          child: SizedBox(
            height: 40,
            width: w,
            child: Stack(alignment: Alignment.centerLeft, children: [
              // 渐变轨道
              Container(
                height: 12,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(colors: moodGradient()),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 4, offset: const Offset(0, 1))
                  ],
                ),
              ),
              // 游标手柄
              AnimatedPositioned(
                duration: const Duration(milliseconds: 90),
                curve: Curves.easeOut,
                left: (v / 10 * w).clamp(0.0, w),
                top: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(left: 0),
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                          color: c.withOpacity(0.45),
                          blurRadius: 10, offset: const Offset(0, 2))
                    ],
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.local_fire_department,
                      size: 16, color: Colors.white),
                ),
              ),
              // 刻度点
              for (var i = 0; i <= 10; i++)
                Positioned(
                  left: i / 10 * w,
                  top: 19,
                  child: Transform.translate(
                    offset: const Offset(-1, 0),
                    child: Container(
                      width: 2, height: 9,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ),
            ]),
          ),
        );
      }),
      const SizedBox(height: 8),
      const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('冰封 0', style: TextStyle(fontSize: 11, color: Color(0xFF6A9BD9))),
        Text('10 沸腾', style: TextStyle(fontSize: 11, color: Color(0xFFE04B3A))),
      ]),
    ]);
  }
}

/// 静态温度计条（列表/详情展示用）
class MoodThermometerBar extends StatelessWidget {
  final int value;
  final double width;
  const MoodThermometerBar({Key? key, required this.value, this.width = 110})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0, 10);
    final c = moodColor(v);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: width,
            height: 8,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: moodGradient()),
            ),
          ),
        ),
        Positioned(
          left: (width * v / 10).clamp(0.0, width),
          top: 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: 6,
            width: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c,
              border: Border.all(color: Colors.white, width: 1.6),
              boxShadow: [
                BoxShadow(
                    color: c.withOpacity(0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 1))
              ],
            ),
          ),
        ),
      ]),
      const SizedBox(height: 5),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.local_fire_department, size: 13, color: c),
        const SizedBox(width: 3),
        Text('$v · ${moodLabel(v)}',
            style: TextStyle(
                fontSize: 11,
                color: AppTheme.inkSoft,
                fontWeight: FontWeight.w600)),
      ]),
    ]);
  }
}