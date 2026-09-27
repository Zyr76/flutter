import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../db.dart';
import '../../models.dart';
import '../../session.dart';
import '../../theme.dart';
import '../../widgets/diary_icons.dart';
import '../../widgets/linkify_text.dart';
import '../../widgets/mood_thermometer.dart';
import 'diary_editor.dart';
import 'diary_mood_report.dart';

class DiaryListPage extends StatefulWidget {
  const DiaryListPage({Key? key}) : super(key: key);
  @override
  State<DiaryListPage> createState() => _DiaryListPageState();
}

class _DiaryListPageState extends State<DiaryListPage> {
  List<Diary>? _items;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = Session.instance.user!.id!;
    final data = await Db.instance.diariesByUser(uid);
    if (mounted) setState(() => _items = data);
  }

  Future<void> _open([Diary? d]) async {
    final changed = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => DiaryEditorPage(existing: d)));
    if (changed == true) _load();
  }

  /// 滑动删除确认：确认后真正删除；取消则返回 false，让条目弹回原位。
  Future<bool> _confirmDelete(Diary d) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('删除这篇日志？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('删除', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (r != true) return false;
    await Db.instance.deleteDiary(d.id);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
        onRefresh: _load,
        child: _items == null
            ? const Center(child: CircularProgressIndicator())
            : _items!.isEmpty
                ? ListView(children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _moodReportEntry(),
                    ),
                    _empty(),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _items!.length + 1,
                    itemBuilder: (_, i) => i == 0
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _moodReportEntry(),
                          )
                        : _card(_items![i - 1]),
                  ),
      ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.edit),
        label: const Text('写日志'),
      ),
    );
  }

  /// 情绪月报入口卡片
  Widget _moodReportEntry() {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const MoodReportPage())),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.clay.withOpacity(0.12),
              AppTheme.sand.withOpacity(0.35),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.hairline.withOpacity(0.5)),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppTheme.clay.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_graph, color: AppTheme.clayDeep, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('情绪月报',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Text('日志数 · 总字数 · 连写 · 情绪分布与走势',
                  style: TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
            ]),
          ),
          Icon(Icons.chevron_right, color: AppTheme.inkSoft, size: 20),
        ]),
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.only(top: 160),
        child: Column(children: [
          Container(width: 96, height: 96, decoration: BoxDecoration(
              shape: BoxShape.circle, color: AppTheme.sand),
              child: Icon(Icons.menu_book, size: 52, color: AppTheme.clayDeep)),
          const SizedBox(height: 18),
          const Text('暂无日志', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('把每天的小事，酿成自己的日记', style: TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
        ]),
      );

  Widget _card(Diary d) {
    final dt = DateTime.fromMillisecondsSinceEpoch(d.createdAt);
    return Dismissible(
      key: ValueKey('d${d.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      // 先弹确认框再真正滑动删除：取消返回 false 条目弹回，不再出现“取消后条目消失”
      confirmDismiss: (_) => _confirmDelete(d),
      onDismissed: (_) => setState(() =>
          _items!.removeWhere((x) => x.id == d.id)),
      child: GestureDetector(
        onTap: () => _open(d),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppTheme.bgDeep.withOpacity( 0.6), borderRadius: BorderRadius.circular(8)),
                child: Text(DateFormat('MM月dd日').format(dt), style: TextStyle(fontSize: 12, color: AppTheme.clayDeep, fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              if (d.weather.isNotEmpty)
                Icon(weatherIcons[d.weather] ?? Icons.wb_sunny_outlined,
                    size: 18, color: AppTheme.clayDeep),
            ]),
            const SizedBox(height: 10),
            Text(d.title.isEmpty ? '随手记' : d.title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 8),
            // 情绪温度计
            MoodThermometerBar(value: d.moodValue),
            const SizedBox(height: 8),
            if (d.location.isNotEmpty) ...[
              Row(children: [
                Icon(Icons.place, size: 14, color: AppTheme.clay),
                const SizedBox(width: 4),
                Text(d.location,
                    style: TextStyle(fontSize: 12, color: AppTheme.clayDeep)),
              ]),
              const SizedBox(height: 6),
            ],
            LinkifyText(d.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppTheme.inkSoft, height: 1.5, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}