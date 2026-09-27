import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../db.dart';
import '../../models.dart';
import '../../services/share.dart';
import '../../session.dart';
import '../../storage.dart';
import '../../theme.dart';
import '../../widgets/media_grid.dart';
import '../../widgets/linkify_text.dart';
import '../../widgets/profile_visual.dart';

import 'shuo_calendar.dart';
import 'shuo_editor.dart';

/// 首页：空间背景 + 说说流
class HomeFeedPage extends StatefulWidget {
  const HomeFeedPage({Key? key}) : super(key: key);
  @override
  State<HomeFeedPage> createState() => _HomeFeedPageState();
}

class _HomeFeedPageState extends State<HomeFeedPage> {
  List<Map>? _items;
  bool _bgError = false;
  final ScrollController _sc = ScrollController();
  bool _showTop = false;
  static final _fmt = DateFormat('yyyy-MM-dd HH:mm');

  // 筛选状态
  String? _filterMonth; // '2026-09'
  String? _filterDate; // '2026-09-25'（精确到某天）
  String? _filterCategory;
  List<String> _months = [];
  List<String> _categories = [];

  @override
  void initState() {
    super.initState();
    _sc.addListener(_onScroll);
    _load();
    _loadFilterOptions();
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _sc.hasClients && _sc.offset > 520;
    if (show != _showTop) setState(() => _showTop = show);
  }

  void _jumpTop() {
    if (_sc.hasClients) {
      _sc.animateTo(0, duration: const Duration(milliseconds: 380),
          curve: Curves.easeOut);
    }
  }

  Future<void> _load() async {
    final uid = Session.instance.user!.id!;
    final data = await Db.instance.shuoshuosByUser(uid,
        category: _filterCategory, monthKey: _filterMonth, dateKey: _filterDate);
    if (mounted) setState(() => _items = data);
  }

  Future<void> _loadFilterOptions() async {
    final uid = Session.instance.user!.id!;
    final months = await Db.instance.shuoshuoMonths(uid);
    final inUse = await Db.instance.shuoshuoCategoriesInUse(uid);
    final custom = await Db.instance.shuoCategories(uid);
    // 分类 = 预设 + 在用 + 用户自定义（去重保序）
    final cats = <String>[
      ...kPresetCategories,
      ...inUse,
      ...custom.map((c) => c.name),
    ].toSet().toList();
    if (mounted) {
      setState(() {
        _months = months;
        _categories = cats;
      });
    }
  }

  Future<void> _write() async {
    final changed = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const ShuoEditorPage()));
    if (changed == true) {
      _load();
      _loadFilterOptions();
    }
  }

  Future<void> _edit(Map item) async {
    final s = item['shuoshuo'] as Shuoshuo;
    final media = item['media'] as List<Media>;
    final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => ShuoEditorPage(existing: s, existingMedia: media)));
    if (changed == true) {
      _load();
      _loadFilterOptions();
    }
  }

  Future<void> _delete(Map item) async {
    final s = item['shuoshuo'] as Shuoshuo;
    final media = item['media'] as List<Media>;
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('删除这条说说？'),
        content: Text('删除后无法恢复。', style: TextStyle(color: AppTheme.inkSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text('删除', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (r == true) {
      final uid = Session.instance.user!.id!;
      for (final m in media) {
        await Db.instance.deleteSpaceMirrorsByPath(uid, m.filePath);
        await Storage.delete(m.filePath);
      }
      await Db.instance.deleteShuoshuoSilent(s.id, media.map((e) => e.id).toList());
      _load();
    }
  }

  Widget _background() {
    final u = Session.instance.user;
    final bg = u?.bgFile;
    if (bg != null && bg.isNotEmpty && !_bgError && File(bg).existsSync()) {
      return Image.file(File(bg), fit: BoxFit.cover, width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) {
            _bgError = true;
            return const _BgGradient();
          });
    }
    return const _BgGradient();
  }

  @override
  Widget build(BuildContext context) {
    final u = Session.instance.user!;
    final items = _items ?? [];
    return Stack(children: [
      _background(),
      SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppTheme.clay,
          child: ListView(
            controller: _sc,
            // 内容不足以填满屏幕时也可下拉刷新
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              // 头部
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 92),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    MeAvatar(size: 56),
                    const SizedBox(width: 14),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(u.nickname,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white,
                              shadows: [Shadow(color: Colors.black26, blurRadius: 4)])),
                      const SizedBox(height: 4),
                      Text('${_greeting()} · ${_fmt.format(DateTime.now()).split(' ').first}',
                          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity( 0.85))),
                    ]),
                  ]),
                ]),
              ),
              // 筛选栏
              _filterBar(),
              if (items.isEmpty)
                _HomeEmpty(filterActive: _filterMonth != null || _filterDate != null || _filterCategory != null)
              else
                for (final it in items) _card(it),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
      if (_showTop)
        Positioned(
          right: 16,
          bottom: 92,
          child: Material(
            color: AppTheme.surface.withOpacity(0.95),
            shape: const CircleBorder(),
            elevation: 4,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _jumpTop,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(Icons.arrow_upward, color: AppTheme.clay, size: 22),
              ),
            ),
          ),
        ),
      Positioned(right: 16, bottom: 20,
        child: FloatingActionButton.extended(
          onPressed: _write,
          icon: const Icon(Icons.edit),
          label: const Text('写说说'),
        )),
      Positioned(left: 16, bottom: 20,
        child: FloatingActionButton(
          heroTag: 'feed_calendar',
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ShuoCalendarPage())),
          child: const Icon(Icons.calendar_month_outlined),
        )),
    ]);
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return '夜深了';
    if (h < 12) return '早上好';
    if (h < 14) return '中午好';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  Widget _card(Map item) {
    final s = item['shuoshuo'] as Shuoshuo;
    final media = item['media'] as List<Media>;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.hairline.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
              color: AppTheme.ink.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const MeAvatar(size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(Session.instance.user?.nickname ?? '',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.ink)),
              const SizedBox(height: 2),
              Text(_fmt.format(DateTime.fromMillisecondsSinceEpoch(s.createdAt)),
                  style: TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
            ]),
          ),
          PopupMenuButton<String>(
            color: AppTheme.surface,
            onSelected: (v) {
              if (v == 'edit') _edit(item);
              if (v == 'export') ShareX.exportShuoshuo(s, media);
              if (v == 'delete') _delete(item);
            },
            icon: Icon(Icons.more_horiz, color: AppTheme.inkSoft, size: 20),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑')),
              const PopupMenuItem(value: 'export', child: Text('导出')),
              PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: AppTheme.error))),
            ],
          ),
        ]),
        if (s.category.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.clay.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.sell_outlined,
                  size: 12, color: AppTheme.clayDeep),
              const SizedBox(width: 3),
              Text(s.category,
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.clayDeep,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
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
            Text(s.location, style: TextStyle(fontSize: 12, color: AppTheme.clayDeep)),
          ]),
        ],
        if (media.isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: MediaGrid(medias: media),
          ),
        ],
      ]),
    );
  }

  // ---------- 筛选栏 ----------
  Widget _filterBar() {
    final hasDate = _filterDate != null;
    final hasMonth = _filterMonth != null;
    final hasCate = _filterCategory != null;
    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.hairline.withOpacity(0.6)),
          boxShadow: [
            BoxShadow(
                color: AppTheme.ink.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 分类筛选
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              _filterChip('全部', !hasCate, onTap: _clearCategory,
                  icon: Icons.auto_awesome),
              for (final c in _categories) ...[
                const SizedBox(width: 6),
                _filterChip(c, c == _filterCategory,
                    onTap: () => _toggleCategory(c),
                    icon: Icons.label_outline),
              ],
            ]),
          ),
          const SizedBox(height: 8),
          // 月份 + 具体日期筛选
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              _filterChip('全部时间', !hasMonth && !hasDate,
                  onTap: _clearTime,
                  icon: Icons.date_range),
              for (final m in _months) ...[
                const SizedBox(width: 6),
                _filterChip(_fmtMonth(m), m == _filterMonth,
                    onTap: () {
                      setState(() {
                        _filterMonth = m;
                        _filterDate = null;
                      });
                      _load();
                    },
                    icon: Icons.calendar_month_outlined),
              ],
              const SizedBox(width: 6),
              _filterChip(
                hasDate ? _fmtDate(_filterDate!) : '具体日期',
                hasDate,
                icon: Icons.event,
                onTap: _pickDate,
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  void _clearCategory() {
    setState(() => _filterCategory = null);
    _load();
  }

  void _clearTime() {
    setState(() {
      _filterMonth = null;
      _filterDate = null;
    });
    _load();
  }

  /// 弹出日期选择器，选择后精确到某天进行筛选
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.fromSeed(
              seedColor: AppTheme.clay, surface: AppTheme.surface),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _filterDate = DateFormat('yyyy-MM-dd').format(picked);
      _filterMonth = null;
    });
    _load();
  }

  void _toggleCategory(String c) {
    setState(() => _filterCategory = _filterCategory == c ? null : c);
    _load();
  }

  Widget _filterChip(String text, bool active,
      {required VoidCallback onTap, IconData icon = Icons.circle}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.clay : AppTheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: active ? AppTheme.clay : AppTheme.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: active ? Colors.white : AppTheme.inkSoft),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? Colors.white : AppTheme.inkSoft,
              )),
        ]),
      ),
    );
  }

  String _fmtMonth(String key) {
    try {
      final parts = key.split('-');
      return '${parts[1]}月';
    } catch (_) {
      return key;
    }
  }

  String _fmtDate(String key) {
    try {
      final parts = key.split('-');
      return '${parts[1]}月${parts[2]}日';
    } catch (_) {
      return key;
    }
  }
}

class _BgGradient extends StatelessWidget {
  const _BgGradient();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.clayDeep,
            AppTheme.sand,
            AppTheme.bg,
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
    );
  }
}

class _HomeEmpty extends StatelessWidget {
  final bool filterActive;
  const _HomeEmpty({this.filterActive = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 34),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.hairline.withOpacity(0.6)),
      ),
      child: Column(children: [
        Icon(filterActive ? Icons.filter_alt_off :
            Icons.auto_awesome_outlined, size: 40, color: AppTheme.inkSoft),
        const SizedBox(height: 12),
        Text(filterActive ? '没有符合筛选的说说了' : '这里还是空白',
            style: TextStyle(
                color: AppTheme.ink,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(filterActive ? '换一个月份或分类试试' : '点击右下角「写说说」，记录你的第一段时光',
            style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
      ]),
    );
  }
}