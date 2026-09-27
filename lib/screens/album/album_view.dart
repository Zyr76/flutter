import 'dart:io';

import 'package:flutter/material.dart';

import '../../db.dart';
import '../../models.dart';
import '../../services/picker.dart';
import '../../session.dart';
import '../../storage.dart';
import '../../theme.dart';
import '../../widgets/media.dart';
import '../../widgets/month_calendar.dart';
import '../shuoshuo/shuo_locate.dart';

class AlbumViewPage extends StatefulWidget {
  final Album album;
  const AlbumViewPage({Key? key, required this.album}) : super(key: key);
  @override
  State<AlbumViewPage> createState() => _AlbumViewPageState();
}

class _AlbumViewPageState extends State<AlbumViewPage> {
  List<AlbumMedia>? _items;
  bool _cal = false; // 日历视图开关
  DateTime _calDay = DateTime.now();
  bool _sel = false; // 多选模式
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await Db.instance.albumMedia(widget.album.id);
    if (mounted) setState(() => _items = data);
  }

  Future<void> _add() async {
    // 选择照片或视频
    final who = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          ListTile(
            leading: Icon(Icons.add_photo_alternate, color: AppTheme.clay),
            title: const Text('添加照片'),
            onTap: () => Navigator.pop(context, 'image'),
          ),
          ListTile(
            leading: Icon(Icons.video_library, color: AppTheme.clay),
            title: const Text('添加视频'),
            onTap: () => Navigator.pop(context, 'video'),
          ),
          const SizedBox(height: 6),
        ]),
      ),
    );
    if (who == null) return;
    await (who == 'video' ? _addVideo() : _addImages());
  }

  Future<void> _addImages() async {
    final imgs = await Picker.images();
    if (imgs.isEmpty) return;
    for (final p in imgs) {
      final ext = p.split('.').lastOrNull ?? 'jpg';
      final name = Storage.newName(ext.toLowerCase());
      final abs = await Storage.ensureInApp(p, 'album', name);
      await _insert(abs, 'image/$ext', name, null);
    }
    _afterAdd();
  }

  Future<void> _addVideo() async {
    final v = await Picker.video();
    if (v == null) return;
    final ext = v.split('.').lastOrNull ?? 'mp4';
    final name = Storage.newName(ext.toLowerCase());
    final abs = await Storage.ensureInApp(v, 'album', name);
    // 视频封面：不落盘，网格项由 VideoCover 实时截帧显示
    await _insert(abs, 'video/$ext', name, null);
    _afterAdd();
  }

  Future<void> _insert(String abs, String mime, String name, String? thumb) async {
    await Db.instance.insertAlbumMedia({
      'album_id': widget.album.id,
      'user_id': Session.instance.user!.id!,
      'file_path': abs,
      'thumb': thumb,
      'mime': mime,
      'name': name,
      'size': File(abs).lengthSync(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _afterAdd() async {
    _load();
    final items2 = await Db.instance.albumMedia(widget.album.id);
    if (items2.isNotEmpty) {
      await Db.instance.updateAlbumCover(widget.album.id, items2.first.filePath);
    }
  }

  List<AlbumMedia> get _calItems => _items!
      .where((m) =>
          dayKeyOf(DateTime.fromMillisecondsSinceEpoch(m.createdAt)) ==
          dayKeyOf(_calDay))
      .toList();

  // ---- 添加 / 预览 / 删除 ----

  void _openAt(int index) {
    final items = _items!
        .map((m) => MediaPagerItem(
              path: m.filePath,
              isVideo: m.mime.startsWith('video'),
              cover: m.thumb,
              title: m.name,
            ))
        .toList();
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MediaPagerView(items: items, start: index),
    )).then((changed) { if (changed == true) _load(); });
  }

  void _toggleSel(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _exitSel() => setState(() {
        _sel = false;
        _selected.clear();
      });

  Future<void> _removeMedia(AlbumMedia m) async {
    await Db.instance.deleteAlbumMedia(m.id);
    // 说说同步进来的镜像只删除相册记录，保留源媒体，避免影响说说
    final fromShuo = await Db.instance.isShuoMedia(m.filePath);
    if (!fromShuo) await Storage.delete(m.filePath);
  }

  /// 相册媒体长按操作：若该媒体属于某条说说，则提供「定位到说说」，否则不显示。
  Future<void> _itemActions(AlbumMedia m) async {
    final fromShuo = await Db.instance.isShuoMedia(m.filePath);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          if (fromShuo)
            ListTile(
              leading: Icon(Icons.forum_outlined, color: AppTheme.clay),
              title: const Text('定位到说说'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          ShuoLocatePage(filePath: m.filePath)),
                );
              },
            ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: AppTheme.error),
            title: Text('删除', style: TextStyle(color: AppTheme.error)),
            onTap: () {
              Navigator.pop(ctx);
              _deleteAt(m);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _deleteAt(AlbumMedia m) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('删除这张照片？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('删除', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (r == true) {
      await _removeMedia(m);
      _load();
    }
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('删除选中的 ${_selected.length} 项？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('删除', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (r != true) return;
    for (final m in _items!) {
      if (_selected.contains(m.id)) {
        await _removeMedia(m);
      }
    }
    _exitSel();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album.name),
        leading: _sel
            ? IconButton(
                onPressed: _exitSel,
                icon: const Icon(Icons.close),
              )
            : null,
        actions: [
          if (!_sel)
            IconButton(
              onPressed: () => setState(() {
                _cal = !_cal;
                _calDay = DateTime.now();
              }),
              icon: Icon(_cal ? Icons.grid_view_outlined : Icons.calendar_month_outlined),
              tooltip: _cal ? '网格视图' : '日历视图',
            ),
          if (_sel)
            IconButton(
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除所选',
            )
          else
            IconButton(
              onPressed: () => setState(() => _sel = true),
              icon: const Icon(Icons.checklist),
              tooltip: '多选',
            ),
          if (!_sel) IconButton(onPressed: _add, icon: const Icon(Icons.add_photo_alternate_outlined)),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_photo_alternate, size: 64, color: AppTheme.sand),
                const SizedBox(height: 14),
                Text('相册还是空的', style: TextStyle(color: AppTheme.inkSoft)),
                const SizedBox(height: 8),
                TextButton(onPressed: _add, child: const Text('添加照片')),
              ]),
            )
          : Stack(children: [
              Column(children: [
                if (_cal) MonthCalendar(
                  markDays: _items!.map((m) =>
                      dayKeyOf(DateTime.fromMillisecondsSinceEpoch(m.createdAt))).toSet(),
                  selected: _calDay,
                  onSelect: (d) => setState(() => _calDay = d),
                ),
                Expanded(
                  child: _cal
                      ? _dayGridView(_calItems)
                      : _allGridView(items),
                ),
              ]),
              if (_sel) _selBar(),
            ]),
    );
  }

  Widget _selBar() => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: AppTheme.surface,
            child: Row(children: [
              Icon(Icons.check_circle, color: AppTheme.clay, size: 20),
              const SizedBox(width: 6),
              Text('已选 ${_selected.length} 项',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: _deleteSelected,
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('删除'),
                style: TextButton.styleFrom(
                    foregroundColor: AppTheme.error),
              ),
            ]),
          ),
        ),
      );

  Widget _allGridView(List<AlbumMedia> list) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6),
        itemCount: list.length,
        itemBuilder: (_, i) => _itemTile(list[i], () {
          if (_sel) {
            _toggleSel(list[i].id);
          } else {
            _openAt(i);
          }
        }, () {
          if (!_sel) _itemActions(list[i]);
        }),
      );

  Widget _dayGridView(List<AlbumMedia> list) {
    if (list.isEmpty) {
      return Center(
        child: Text('这一天没有照片',
            style: TextStyle(color: AppTheme.inkSoft, fontSize: 13)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6),
      itemCount: list.length,
      itemBuilder: (_, i) => _itemTile(list[i], () {
        if (_sel) {
          _toggleSel(list[i].id);
        } else {
          _openAt(_items!.indexOf(list[i]));
        }
      }, () {
        if (!_sel) _itemActions(list[i]);
      }),
    );
  }

  Widget _itemTile(AlbumMedia m, VoidCallback onTap, VoidCallback onLong) {
    final checked = _selected.contains(m.id);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLong,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(fit: StackFit.expand, children: [
          if (m.mime.startsWith('video'))
            VideoCover(video: m.filePath, thumb: m.thumb)
          else
            Image.file(File(m.filePath), fit: BoxFit.cover),
          if (m.mime.startsWith('video'))
            const Center(
              child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 32),
            ),
          if (_sel)
            Positioned(
              top: 4, right: 4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: checked ? AppTheme.clay : Colors.black.withOpacity( 0.4),
                  border: checked
                      ? null
                      : Border.all(color: Colors.white70, width: 1.5),
                ),
                child: Icon(
                  checked ? Icons.check : null,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          if (_sel && checked)
            Positioned.fill(
              child: ColoredBox(color: Colors.black.withOpacity( 0.35)),
            ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Text(
                _fmtDate(m.createdAt),
                textAlign: TextAlign.center,
                maxLines: 1,
                style: const TextStyle(color: Colors.white70, fontSize: 9),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // 相册网格顶部的日期：今天只显示时间，其他显示月日（跨年补年份）
  String _fmtDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '今天 $hm';
    }
    if (d.year == now.year) return '${d.month}月${d.day}日';
    return '${d.year}年${d.month}月${d.day}日';
  }
}