import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../db.dart';
import '../../models.dart';
import '../../session.dart';
import '../../theme.dart';
import 'capsule_create.dart';
import 'capsule_view.dart';

class CapsuleListPage extends StatefulWidget {
  const CapsuleListPage({Key? key}) : super(key: key);
  @override
  State<CapsuleListPage> createState() => _CapsuleListPageState();
}

class _CapsuleListPageState extends State<CapsuleListPage> {
  List<Capsule>? _items;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = Session.instance.user!.id!;
    final data = await Db.instance.capsulesByUser(uid);
    if (mounted) setState(() => _items = data);
  }

  Future<void> _create() async {
    final created = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const CapsuleCreatePage()));
    if (created == true) _load();
  }

  // 时间胶囊不支持编辑，仅可删除
  Future<void> _delete(Capsule c) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('删除这封时间胶囊？'),
        content: Text('胶囊将在开启时间到达后永远封存，删除后无法恢复。', style: TextStyle(color: AppTheme.inkSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('删除', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (r == true) {
      await Db.instance.deleteCapsule(c.id);
      _load();
    }
  }

  void _open(Capsule c) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CapsuleViewPage(capsule: c)));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _items == null
          ? const Center(child: CircularProgressIndicator())
          : _items!.isEmpty
              ? _empty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: _items!.length,
                  itemBuilder: (_, i) => _card(_items![i], now),
                ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.hourglass_bottom),
        label: const Text('封存'),
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 100, height: 100, decoration: BoxDecoration(
              shape: BoxShape.circle, color: AppTheme.sand),
              child: Icon(Icons.timelapse, size: 54, color: AppTheme.clayDeep)),
          const SizedBox(height: 18),
          const Text('还没有时间胶囊', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('把此刻的话，寄给未来的自己', style: TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
        ]),
      );

  Widget _card(Capsule c, int nowMs) {
    final locked = nowMs < c.openAt;
    final open = DateTime.fromMillisecondsSinceEpoch(c.openAt);
    final created = DateTime.fromMillisecondsSinceEpoch(c.createdAt);
    final diff = open.difference(DateTime.now());
    return GestureDetector(
      onTap: locked ? null : () => _open(c),
      onLongPress: () => _delete(c),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: locked
                ? [AppTheme.surface, AppTheme.bgDeep]
                : [AppTheme.clay, AppTheme.clayDeep],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity( ThemeController.instance.dark ? 0.4 : 0.04), blurRadius: 8)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(locked ? Icons.lock_outline : Icons.lock_open, size: 20,
                color: locked ? AppTheme.inkSoft : Colors.white.withOpacity( 0.9)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(c.title.isEmpty ? '未命名胶囊' : c.title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 12),
          if (locked)
            Text('封存于 ${DateFormat('yyyy年MM月dd日').format(created)}，还有 ${_left(diff)} 才能开启',
                style: TextStyle(fontSize: 12, color: AppTheme.inkSoft))
          else
            Text('已于 ${DateFormat('yyyy年MM月dd日').format(open)} 开启 · 点击查看',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.hourglass_bottom, size: 14, color: AppTheme.inkSoft),
            const SizedBox(width: 4),
            Text('开启时间 ${DateFormat('yyyy年MM月dd日').format(open)}',
                style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
          ]),
        ]),
      ),
    );
  }

  String _left(Duration d) {
    if (d.inDays > 365) return '${(d.inDays / 365).floor()} 年 ${(d.inDays % 365 / 30).floor()} 个月';
    if (d.inDays > 30) return '${d.inDays ~/ 30} 个月 ${d.inDays % 30} 天';
    if (d.inDays > 0) return '${d.inDays} 天 ${d.inHours % 24} 小时';
    if (d.inHours > 0) return '${d.inHours} 小时 ${d.inMinutes % 60} 分钟';
    return '${d.inMinutes} 分钟';
  }
}