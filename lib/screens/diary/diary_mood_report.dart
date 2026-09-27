import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../db.dart';
import '../../models.dart';
import '../../session.dart';
import '../../theme.dart';
import '../../widgets/mood_thermometer.dart';

/// 日志情绪月报：统计某个月的日志数、总字数、连续记录天数、心情分布比例与情绪波形。
class MoodReportPage extends StatefulWidget {
  const MoodReportPage({Key? key}) : super(key: key);
  @override
  State<MoodReportPage> createState() => _MoodReportPageState();
}

class _MoodReportPageState extends State<MoodReportPage> {
  List<String>? _months; // 倒序
  String? _cur;
  List<Diary>? _diaries;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uid = Session.instance.user!.id!;
    final months = await Db.instance.diaryMonths(uid);
    if (!mounted) return;
    setState(() {
      _months = months;
      _cur = months.isNotEmpty ? months.first : null;
    });
    if (_cur != null) await _loadMonth();
  }

  Future<void> _loadMonth() async {
    final uid = Session.instance.user!.id!;
    final ds = await Db.instance.diariesByMonth(uid, _cur!);
    if (mounted) setState(() => _diaries = ds);
  }

  void _switchMonth(String m) {
    if (m == _cur) return;
    setState(() {
      _cur = m;
      _diaries = null;
    });
    _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    final month = _cur ?? '';
    final p = month.split('-');
    final titleText =
        month.isEmpty ? '情绪月报' : '${p[0]}年${p[1]}月 心情';
    return Scaffold(
      appBar: AppBar(
        title: Text(titleText),
        actions: [
          if (_months != null && _months!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.calendar_month_outlined),
              tooltip: '切换月份',
              onPressed: _switchMonthDialog,
            ),
        ],
      ),
      body: _diaries == null
          ? const Center(child: CircularProgressIndicator())
          : _cur == null || _diaries!.isEmpty
              ? _empty()
              : _report(_diaries!),
    );
  }

  Future<void> _switchMonthDialog() async {
    final months = _months!;
    final sel = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          const Text('选择月份',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final m in months)
            ListTile(
              title: Text(_monthTitle(m)),
              trailing:
                  m == _cur ? Icon(Icons.check, color: AppTheme.clay) : null,
              onTap: () => Navigator.pop(sheetCtx, m),
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
    if (sel != null) _switchMonth(sel);
  }

  String _monthTitle(String m) {
    final x = m.split('-');
    return '${x[0]}年${x[1]}月';
  }

  Widget _empty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.insert_chart_outlined,
              size: 56, color: AppTheme.inkSoft.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text('这个月还没有日志', style: TextStyle(color: AppTheme.inkSoft)),
          const SizedBox(height: 6),
          Text('写下第一篇，情绪月报将自动生成',
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
        ]),
      );

  // ---------- 报表主体 ----------
  Widget _report(List<Diary> ds) {
    final stats = _stats(ds);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _overview(stats),
        const SizedBox(height: 16),
        _card(
          title: '心情分布',
          icon: Icons.pie_chart_outline,
          child: _distribution(stats),
        ),
        const SizedBox(height: 16),
        _card(
          title: '情绪波形',
          icon: Icons.show_chart,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _axisLabel('10 兴奋', AppTheme.clay),
              _axisLabel('5 平静', AppTheme.clayDeep),
              _axisLabel('0 冰封', AppTheme.inkSoft),
            ]),
            const SizedBox(height: 6),
            _MoodWave(ds),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${ds.length} 篇日志',
                  style: TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
              Text('横轴按时间 · 纵轴 0-10 情绪值',
                  style: TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
            ]),
          ]),
        ),
      ]),
    );
  }

  // ---------- 通用卡片 ----------
  Widget _card({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.hairline.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
              color: AppTheme.ink.withOpacity(0.05),
              blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: AppTheme.clay),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  // ---------- 统计 ----------
  _MoodStats _stats(List<Diary> ds) {
    var words = 0;
    for (final d in ds) {
      words += d.title.length + d.content.length;
    }
    // 连写天数：从该月最后一天往前，有日志那天则累计
    final dateSet = ds
        .map((d) => DateFormat('yyyy-MM-dd').format(
            DateTime.fromMillisecondsSinceEpoch(d.createdAt)))
        .toSet();
    var streak = 0;
    var cursor =
        ds.isEmpty ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(ds.last.createdAt);
    while (dateSet.contains(DateFormat('yyyy-MM-dd').format(cursor))) {
      streak++;
      dateSet.remove(DateFormat('yyyy-MM-dd').format(cursor));
      cursor = cursor.subtract(const Duration(days: 1));
    }

    final dist = <String, int>{};
    for (final d in ds) {
      final label = moodLabel(d.moodValue);
      dist[label] = (dist[label] ?? 0) + 1;
    }
    return _MoodStats(
      count: ds.length,
      words: words,
      streak: streak,
      dist: dist,
    );
  }

  Widget _overview(_MoodStats s) {
    Widget stat(IconData icon, Color color, String num, String label) =>
        Expanded(
          child: Column(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(num,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, height: 1)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
          ]),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.hairline.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
              color: AppTheme.ink.withOpacity(0.05),
              blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(children: [
        stat(Icons.article_outlined, _blue, '${s.count}', '日志数'),
        stat(Icons.text_fields, _orange, '${s.words}', '总字数'),
        stat(Icons.local_fire_department, _red, '${s.streak}', '连写天'),
      ]),
    );
  }

  // ---------- 心情分布 ----------
  Widget _distribution(_MoodStats s) {
    const order = ['冰封', '低落', '平静', '愉悦', '开心', '兴奋'];
    final entries = order
        .where((k) => s.dist.containsKey(k))
        .map((k) => (label: k, count: s.dist[k]!))
        .toList();
    if (entries.isEmpty) {
      return Text('暂无情绪记录', style: TextStyle(color: AppTheme.inkSoft));
    }
    return Column(children: [
      for (final e in entries) ...[
        _distRow(e.label, e.count, s.count),
        const SizedBox(height: 12),
      ],
    ]);
  }

  Widget _distRow(String label, int count, int total) {
    final ratio = total == 0 ? 0.0 : count / total;
    final color = _labelColor(label);
    return Row(children: [
      SizedBox(
        width: 46,
        child: Text(label,
            style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(children: [
            Container(height: 10, color: AppTheme.bgDeep.withOpacity(0.6)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: ratio,
              child: Container(height: 10, color: color),
            ),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 40,
        child: Text('${(ratio * 100).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ),
    ]);
  }

  /// 情绪标签 -> 代表性数值（用于取色）
  Color _labelColor(String label) {
    const idx = ['冰封', '低落', '平静', '愉悦', '开心', '兴奋'];
    final i = idx.indexOf(label);
    return moodColor(i < 0 ? 5 : i * 2);
  }

  Widget _axisLabel(String text, Color color) => Text(text,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color));
}

// ---------- 波形走势 ----------
class _MoodWave extends StatelessWidget {
  final List<Diary> diaries;
  const _MoodWave(this.diaries);
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 180,
      child: CustomPaint(painter: _WavePainter(diaries)),
    );
  }
}

class _WavePainter extends CustomPainter {
  final List<Diary> diaries;
  _WavePainter(this.diaries);

  @override
  void paint(Canvas canvas, Size size) {
    if (diaries.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final topPad = 14.0;
    final botPad = 14.0;
    final chartH = h - topPad - botPad;

    // 0 / 5 / 10 基线
    for (final v in [0, 5, 10]) {
      final y = topPad + chartH * (1 - v / 10);
      canvas.drawLine(
        Offset(0, y), Offset(w, y),
        Paint()
          ..color = AppTheme.ink.withOpacity(0.06)
          ..strokeWidth = 1,
      );
    }

    final points = <Offset>[];
    for (var i = 0; i < diaries.length; i++) {
      final x = diaries.length == 1 ? w / 2 : w * i / (diaries.length - 1);
      final v = diaries[i].moodValue.clamp(0, 10);
      final y = topPad + chartH * (1 - v / 10);
      points.add(Offset(x, y));
    }

    if (points.length == 1) {
      canvas.drawCircle(points.first, 4,
          Paint()..color = moodColor(diaries.first.moodValue));
      return;
    }

    // 面积渐变
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final area = Path.from(path)
      ..lineTo(w, h - botPad)
      ..lineTo(0, h - botPad)
      ..close();
    final base = moodColor(diaries.first.moodValue);
    final shade = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [base.withOpacity(0.28), base.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(area, shade);

    // 折线
    final line = Paint()
      ..color = AppTheme.clay
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line);

    // 数据点
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 3.5,
          Paint()..color = moodColor(diaries[i].moodValue));
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}

const Color _blue = Color(0xFF6A9BD9);
const Color _orange = Color(0xFFE0A325);
const Color _red = Color(0xFFE04B3A);

class _MoodStats {
  final int count;
  final int words;
  final int streak;
  final Map<String, int> dist;
  _MoodStats({
    required this.count,
    required this.words,
    required this.streak,
    required this.dist,
  });
}