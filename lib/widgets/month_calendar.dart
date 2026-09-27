import 'package:flutter/material.dart';

import '../theme.dart';

/// 把任意时间转换成"天"的整数键（用于判断某一天是否有内容）
int dayKeyOf(DateTime d) =>
    DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

/// 通用月历：可翻月、选中某天。markDays 里包含的"天"会显示圆点（表示当天有内容）。
  /// onSelect 在点击某一天时回调（传入当天 0 点的 DateTime）。
  class MonthCalendar extends StatefulWidget {
    final Set<int> markDays;
    final DateTime selected;
    final ValueChanged<DateTime> onSelect;

    /// 是否显示上/下一年快速切换（长按年月标题也能快速换年）
    const MonthCalendar({
      Key? key,
      required this.markDays,
      required this.selected,
      required this.onSelect,
    }) : super(key: key);

    @override
    State<MonthCalendar> createState() => _MonthCalendarState();
  }

  class _MonthCalendarState extends State<MonthCalendar> {
    late int _year;
    late int _month;

    @override
    void initState() {
      super.initState();
      final s = widget.selected;
      _year = s.year;
      _month = s.month;
    }

    void _shift(int delta) {
      final dt = DateTime(_year, _month + delta, 1);
      setState(() {
        _year = dt.year;
        _month = dt.month;
      });
    }

    void _shiftYear(int delta) {
      setState(() => _year += delta);
    }

    /// 跳转到某一个月（用户点年月标题选择）
    Future<void> _pickMonth() async {
      final nowPick = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime(_year, _month, 1),
        firstDate: DateTime(nowPick.year - 40),
        lastDate: DateTime(nowPick.year + 2),
      );
      if (picked != null && mounted) {
        setState(() {
          _year = picked.year;
          _month = picked.month;
        });
      }
    }

    @override
    Widget build(BuildContext context) {
      final first = DateTime(_year, _month, 1);
      final daysInMonth = DateTime(_year, _month + 1, 0).day;
      final leading = first.weekday - 1; // 周一为 0

      // 今天（用于区分选中 / 今天）
      final now = DateTime.now();
      final selKey = dayKeyOf(widget.selected);
      final todayKey = dayKeyOf(now);
      // 是否有内容的日子数量（标题展示统计）
      final markCount = widget.markDays.length;

      const week = ['一', '二', '三', '四', '五', '六', '日'];

      final cells = <Widget>[];
      for (var i = 0; i < leading; i++) {
        cells.add(const SizedBox.shrink());
      }
      for (var d = 1; d <= daysInMonth; d++) {
        final day = DateTime(_year, _month, d);
        final key = dayKeyOf(day);
        final marked = widget.markDays.contains(key);
        final isSel = key == selKey;
        final isToday = key == todayKey;
        cells.add(_dayCell(day, marked, isSel, isToday));
      }

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.hairline.withOpacity(0.6)),
        ),
        child: Column(children: [
          // 月份标题 + 翻月/快速跳转
          Row(children: [
            IconButton(
              onPressed: () => _shift(-1),
              icon: const Icon(Icons.chevron_left),
              color: AppTheme.clay,
            ),
            Expanded(
              child: InkWell(
                onTap: _pickMonth,
                borderRadius: BorderRadius.circular(8),
                child: Column(children: [
                  Text(
                    '$_year 年 $_month 月',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.ink),
                  ),
                  if (markCount > 0)
                    Text(
                      '共 $markCount 天有记录',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 10, color: AppTheme.inkSoft),
                    ),
                ]),
              ),
            ),
            IconButton(
              onPressed: () => _shift(1),
              icon: const Icon(Icons.chevron_right),
              color: AppTheme.clay,
            ),
            const SizedBox(width: 26), // 为右侧"回到今天"腾位，保持对称
          ]),
          // 快捷行：上一年 / 今天 / 下一年
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              TextButton.icon(
                onPressed: () => _shiftYear(-1),
                icon: const Icon(Icons.skip_previous, size: 16),
                label: const Text('上一年', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                    foregroundColor: AppTheme.clay, padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 30)),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  final n = DateTime.now();
                  setState(() {
                    _year = n.year;
                    _month = n.month;
                  });
                  widget.onSelect(n);
                },
                child: Text('回到今天',
                    style:
                        TextStyle(fontSize: 12, color: AppTheme.clayDeep)),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _shiftYear(1),
                icon: const Icon(Icons.skip_next, size: 16),
                label: const Text('下一年', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                    foregroundColor: AppTheme.clay, padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 30)),
              ),
            ]),
          ),
          const SizedBox(height: 2),
          // 星期表头
          Row(children: [
            for (final w in week)
              Expanded(
                child: Center(
                  child: Text(w,
                      style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          // 日期格子（自动换行成 6 行）
          Wrap(
            children: [for (final c in cells) c],
          ),
        ]),
      );
    }

    Widget _dayCell(DateTime day, bool marked, bool isSel, bool isToday) {
      return InkWell(
        onTap: () => widget.onSelect(day),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: (MediaQuery.of(context).size.width - 36) / 7,
          height: 46,
          alignment: Alignment.center,
          decoration: isSel
              ? BoxDecoration(
                  color: AppTheme.clay,
                  shape: BoxShape.circle,
                )
              : null,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    isSel || isToday ? FontWeight.w600 : FontWeight.w400,
                color: isSel
                    ? Colors.white
                    : isToday
                        ? AppTheme.clay
                        : AppTheme.ink,
              ),
            ),
            const SizedBox(height: 3),
            // 有内容圆点
            Container(
              width: 4.5,
              height: 4.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: marked
                    ? AppTheme.clay
                    : isSel
                        ? Colors.white.withOpacity( 0.7)
                        : Colors.transparent,
              ),
            ),
          ]),
        ),
      );
    }
  }