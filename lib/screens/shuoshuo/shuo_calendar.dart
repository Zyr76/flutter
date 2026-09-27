import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../db.dart';
import '../../models.dart';
import '../../session.dart';
import '../../theme.dart';
import '../../widgets/linkify_text.dart';
import '../../widgets/media_grid.dart';
import '../../widgets/month_calendar.dart';
import '../../widgets/profile_visual.dart';

/// 说说日历（仿 QQ）：月历上高亮有说说的日子，点击某天可看当天的说说
class ShuoCalendarPage extends StatefulWidget {
  const ShuoCalendarPage({Key? key}) : super(key: key);
  @override
  State<ShuoCalendarPage> createState() => _ShuoCalendarPageState();
}

class _ShuoCalendarPageState extends State<ShuoCalendarPage> {
  List<Map>? _items;
  DateTime _selected = DateTime.now();
  static final _fmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = Session.instance.user!.id!;
    final data = await Db.instance.shuoshuosByUser(uid);
    if (mounted) setState(() => _items = data);
  }

  Set<int> get _markDays {
    final set = <int>{};
    for (final it in _items ?? <Map>[]) {
      final s = it['shuoshuo'] as Shuoshuo;
      set.add(dayKeyOf(DateTime.fromMillisecondsSinceEpoch(s.createdAt)));
    }
    return set;
  }

  List<Map> get _dayItems {
    final key = dayKeyOf(_selected);
    return (_items ?? <Map>[]).where((it) {
      final s = it['shuoshuo'] as Shuoshuo;
      return dayKeyOf(DateTime.fromMillisecondsSinceEpoch(s.createdAt)) == key;
    }).toList();
  }

  String _title() => DateFormat('yyyy年M月d日 EEEE').format(_selected);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('说说日历')),
      body: _items == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
                children: [
                  MonthCalendar(
                    markDays: _markDays,
                    selected: _selected,
                    onSelect: (d) => setState(() => _selected = d),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                    child: Text(_title(),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  if (_dayItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text('这一天还没有记录',
                            style:
                                TextStyle(color: AppTheme.inkSoft, fontSize: 13)),
                      ),
                    )
                  else
                    for (final it in _dayItems) _card(it),
                ],
              ),
            ),
    );
  }

  Widget _card(Map item) {
    final s = item['shuoshuo'] as Shuoshuo;
    final media = item['media'] as List<Media>;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.hairline.withOpacity(0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const MeAvatar(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Session.instance.user?.nickname ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                      _fmt.format(DateTime.fromMillisecondsSinceEpoch(
                          s.createdAt)),
                      style:
                          TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
                ]),
          ),
        ]),
        if (s.content.isNotEmpty) ...[
          const SizedBox(height: 10),
          LinkifyText(s.content,
              maxLines: 100,
              style: const TextStyle(letterSpacing: 0.2, height: 1.5)),
        ],
        if (s.location.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.place, size: 14, color: AppTheme.clay),
            const SizedBox(width: 4),
            Text(s.location,
                style: TextStyle(fontSize: 12, color: AppTheme.clayDeep)),
          ]),
        ],
        if (media.isNotEmpty) ...[
          const SizedBox(height: 10),
          MediaGrid(medias: media),
        ],
      ]),
    );
  }
}