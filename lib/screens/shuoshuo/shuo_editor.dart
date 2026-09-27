import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../db.dart';
import '../../models.dart';
import '../../services/audio.dart';
import '../../services/filekind.dart';
import '../../services/picker.dart';
import '../../session.dart';
import '../../storage.dart';
import '../../theme.dart';
import '../../widgets/apk_cover.dart';
import '../../widgets/file_viewer.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/media.dart';

/// 说说预设分类（作为内置选项，不可删除）
const kPresetCategories = ['日常', '生活', '旅行'];

/// 说说编辑器（新建 + 编辑）：简约优雅，带轻触动效与分类选择
class ShuoEditorPage extends StatefulWidget {
  final Shuoshuo? existing;
  final List<Media> existingMedia;
  const ShuoEditorPage({Key? key, this.existing, this.existingMedia = const []})
      : super(key: key);

  @override
  State<ShuoEditorPage> createState() => _ShuoEditorPageState();
}

class _Draft {
  final String type; // image/video/livephoto/file/audio
  final String path;
  final String name;
  final String? thumb;
  _Draft(this.type, this.path, this.name, [this.thumb]);
}

class _ShuoEditorPageState extends State<ShuoEditorPage> {
  final _content = TextEditingController();
  final List<_Draft> _drafts = [];
  String _location = '';
  String _category = '';
  bool _busy = false;
  List<ShuoCategory> _customCategories = [];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _content.text = widget.existing!.content;
      _location = widget.existing!.location;
      _category = widget.existing!.category;
      _drafts.addAll(widget.existingMedia.map((m) =>
          _Draft(m.type, m.filePath, m.name, m.thumb)));
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final uid = Session.instance.user!.id!;
    final list = await Db.instance.shuoCategories(uid);
    if (mounted) {
      setState(() => _customCategories = list);
    }
  }

  /// 全部可选分类 = 预设 + 用户自定义（去重）
  List<String> get _allCategories {
    final names = <String>[
      ...kPresetCategories,
      ..._customCategories.map((c) => c.name),
    ];
    return names.toSet().toList();
  }

  Future<void> _addImages() async {
    final imgs = await Picker.images();
    if (imgs.isEmpty) return;
    setState(() {
      for (final p in imgs) {
        final name = p.split('/').last;
        _drafts.add(_Draft('image', p, name, null));
      }
    });
  }

  Future<void> _addVideo() async {
    final v = await Picker.video();
    if (v == null) return;
    final name = v.split('/').last;
    setState(() => _drafts.add(_Draft('video', v, name, null)));
  }

  Future<void> _addFile() async {
    final f = await Picker.file();
    if (f == null) return;
    setState(() => _drafts.add(_Draft('file', f.path, f.name, null)));
  }

  Future<void> _pickLocation() async {
    final r = await pickLocation(context, initial: _location);
    if (r != null) setState(() => _location = r);
  }

  /// 发送语音：录音后作为音频附件加入说说
  Future<void> _addVoice() async {
    final p = await showVoiceRecorder(context);
    if (p == null || p.isEmpty || !File(p).existsSync()) return;
    if (!mounted) return;
    setState(() {
      final name = p.split('/').last;
      _drafts.add(_Draft('audio', p, name));
    });
  }

  void _remove(int i) => setState(() => _drafts.removeAt(i));

  /// 新增自定义分类
  Future<void> _addCustomCategory() async {
    final uid = Session.instance.user!.id!;
    final name = await _promptCategory();
    if (name == null || name.isEmpty) return;
    final existing = _allCategories.map((e) => e.toLowerCase()).toSet();
    if (existing.contains(name.toLowerCase())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('「$name」已存在')));
      }
      return;
    }
    final id = await Db.instance.insertShuoCategory(uid, name);
    if (mounted) {
      setState(() {
        _customCategories.add(ShuoCategory(id: id, userId: uid, name: name));
        _category = name;
      });
    }
  }

  /// 弹窗输入新增分类名
  Future<String?> _promptCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _CategoryDialog(controller: ctrl),
    );
    ctrl.dispose();
    return name;
  }

  void _openCategoryManager() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      isScrollControlled: true,
      builder: (_) => _CategoryManagerSheet(
        presets: kPresetCategories,
        categories: _customCategories,
        onDelete: (ShuoCategory c) async {
          await Db.instance.deleteShuoCategory(c.id);
          if (mounted) {
            setState(() => _customCategories.removeWhere((x) => x.id == c.id));
            if (_category == c.name) _category = '';
          }
        },
        onAdd: () async {
          final name = await _promptCategory();
          if (name == null || name.isEmpty) return;
          final uid = Session.instance.user!.id!;
          final existing =
              _allCategories.map((e) => e.toLowerCase()).toSet();
          if (existing.contains(name.toLowerCase())) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('「$name」已存在')));
            }
            return;
          }
          final id = await Db.instance.insertShuoCategory(uid, name);
          if (mounted) {
            setState(() =>
                _customCategories.add(ShuoCategory(id: id, userId: uid, name: name)));
          }
        },
      ),
    );
  }

  Future<void> _save() async {
    final content = _content.text.trim();
    if (content.isEmpty && _drafts.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('写点什么或附上内容吧')));
      return;
    }
    setState(() => _busy = true);
    final uid = Session.instance.user!.id!;
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      if (widget.existing != null) {
        // 编辑模式：更新文本/位置/分类
        await Db.instance.updateShuoshuo(
            widget.existing!.id, content, _location,
            category: _category);
        final oldMedia = widget.existingMedia;
        final oldByPath = {for (final m in oldMedia) m.filePath: m};
        final draftPaths = _drafts.map((d) => d.path).toSet();
        // 只删除已从草稿移除的旧媒体文件/镜像，保留仍在草稿里的文件
        for (final m in oldMedia) {
          if (draftPaths.contains(m.filePath)) continue;
          // 逐条容错：旧文件可能已不存在，删除失败不应阻断保存
          try {
            await Db.instance.deleteSpaceMirrorsByPath(uid, m.filePath);
            await Storage.delete(m.filePath);
          } catch (_) {}
        }
        await Db.instance.deleteShuoshuoMedia(widget.existing!.id);
        for (final d in _drafts) {
          final keep = oldByPath[d.path];
          if (keep != null) {
            // 复用原媒体记录（文件已在此前存放在应用目录且未变），避免重复导入。
            // 不再读取/校验原文件，避免旧文件已不存在时触发 PathNotFoundException。
            await Db.instance.linkShuoMedia(widget.existing!.id, keep.id);
          } else {
            await _persistDraft(uid, widget.existing!.id, d, now);
          }
        }
      } else {
        final shuoId = await Db.instance.insertShuoshuo({
          'user_id': uid,
          'content': content,
          'location': _location,
          'category': _category,
          'created_at': now,
          'updated_at': now,
        });
        for (final d in _drafts) {
          await _persistDraft(uid, shuoId, d, now);
        }
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      // 保存主体已写入，媒体同步出现异常时回退 busy，提示用户，不留永久加载态
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已保存，但部分内容同步失败：$e')));
    }
  }

  Future<void> _persistDraft(int uid, int shuoId, _Draft d, int t) async {
    final ext = d.path.split('.').lastOrNull ?? 'bin';
    final fname = Storage.newName(ext.toLowerCase());
    final abs = await Storage.ensureInApp(d.path, 'shuoshuo', fname);
    final mime = _mimeOf(d.path);
    final size = File(abs).lengthSync();

    // 实况图：若有用户选的封面图，则导入并作为封面；否则不落盘，
    // 封面由 VideoCover 实时截帧显示
    var thumb = d.thumb;
    if (d.type == 'livephoto' && thumb != null && thumb.isNotEmpty) {
      final extT = thumb.split('.').lastOrNull ?? 'jpg';
      final tName = Storage.newName(extT.toLowerCase());
      thumb = await Storage.ensureInApp(thumb, 'shuoshuo', tName);
    } else if (d.type == 'video' || d.type == 'livephoto') {
      thumb = null;
    }

    final mediaId = await Db.instance.insertMedia({
      'user_id': uid,
      'type': d.type,
      'file_path': abs,
      'thumb': thumb,
      'mime': mime,
      'name': d.name,
      'size': size,
      'created_at': t,
    });
    await Db.instance.linkShuoMedia(shuoId, mediaId);

    // 同步到空间：普通文件/音频→空间文件根目录；图片/视频/实况图→“说说的照片”相册
    if (d.type == 'file' || d.type == 'audio') {
      await Db.instance.mirrorShuoMediaToSpaceFile(uid, abs,
          mime: mime, name: d.name, size: size, createdAt: t);
    } else {
      await Db.instance.mirrorShuoMediaToAlbum(uid, abs,
          thumb: thumb, mime: mime, name: d.name, size: size, createdAt: t);
    }
  }

  String _mimeOf(String p) {
    final e = p.split('.').last.toLowerCase();
    if (e == 'mp4' || e == 'mov' || e == 'webm') return 'video/$e';
    if (e == 'm4a' || e == 'm4b') return 'audio/mp4';
    if (e == 'mp3') return 'audio/mpeg';
    if (e == 'wav') return 'audio/x-wav';
    if (e == 'aac') return 'audio/aac';
    if (e == 'flac') return 'audio/flac';
    if (e == 'ogg' || e == 'oga' || e == 'opus') return 'audio/ogg';
    if (e == 'amr') return 'audio/amr';
    if (e == 'jpg' || e == 'jpeg') return 'image/jpeg';
    if (e == 'png') return 'image/png';
    if (e == 'gif') return 'image/gif';
    if (e == 'webp') return 'image/webp';
    return 'application/octet-stream';
  }

  void _pop() {
    HapticFeedback.selectionClick();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final canPublish = !_busy && (_content.text.trim().isNotEmpty || _drafts.isNotEmpty);
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(children: [
          _topBar(canPublish),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 正文输入
                  TextField(
                    controller: _content,
                    maxLines: null,
                    minLines: 5,
                    keyboardType: TextInputType.multiline,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 17, height: 1.6, letterSpacing: 0.2),
                    decoration: const InputDecoration(
                        hintText: '此刻，想记录些什么…',
                        border: InputBorder.none,
                        filled: false),
                  ),
                  // 媒体：3 列精确网格 + 末尾添加块
                  if (_drafts.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _mediaGrid(),
                  ],
                  const SizedBox(height: 18),
                  _categorySection(),
                  const SizedBox(height: 14),
                  _locationSection(),
                ],
              ),
            ),
          ),
          _toolbar(context),
        ]),
      ),
    );
  }

  // ---------- 顶部栏 ----------
  Widget _topBar(bool canPublish) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
      child: Row(children: [
        IconButton(
          onPressed: _busy ? null : _pop,
          icon: const Icon(Icons.close),
          tooltip: '关闭',
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Text(
              widget.existing != null ? '编辑说说' : '写说说',
              key: ValueKey(widget.existing != null),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.5),
            ),
          ),
        ),
        _PublishButton(
          busy: _busy,
          enabled: canPublish,
          label: widget.existing != null ? '保存' : '发布',
          onPressed: _save,
        ),
      ]),
    );
  }

  // ---------- 分类 ----------
  Widget _categorySection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('随笔分类', style: TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
        const Spacer(),
        GestureDetector(
          onTap: _openCategoryManager,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('管理分类',
                style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.clay,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 2),
            Icon(Icons.tune, size: 14, color: AppTheme.clay),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in _allCategories) _categoryChip(c),
        _CategoryAddChip(onTap: _addCustomCategory),
      ]),
      AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: _category.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.clay.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(_category,
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.clayDeep,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
      ),
    ]);
  }

  Widget _categoryChip(String c) {
    final sel = c == _category;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _category = sel ? '' : c);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? AppTheme.clay : AppTheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: sel ? AppTheme.clay : AppTheme.hairline,
              width: sel ? 0 : 1),
          boxShadow: sel
              ? [
                  BoxShadow(
                      color: AppTheme.clay.withOpacity(0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ]
              : null,
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: TextStyle(
            fontSize: 13,
            fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
            color: sel ? Colors.white : AppTheme.inkSoft,
          ),
          child: Text(c),
        ),
      ),
    );
  }

  // ---------- 位置 ----------
  Widget _locationSection() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      alignment: Alignment.topLeft,
      child: _location.isEmpty
          ? SizedBox.shrink()
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.sand.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.place, size: 16, color: AppTheme.clayDeep),
                const SizedBox(width: 6),
                Text(_location,
                    style: TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => setState(() => _location = ''),
                  child: Icon(Icons.close, size: 14, color: AppTheme.inkSoft),
                ),
              ]),
            ),
    );
  }

  // ---------- 媒体网格 ----------
  Widget _mediaGrid() {
    final w = MediaQuery.of(context).size.width - 40; // 减去页面左右 20 padding
    const gap = 10.0;
    final cell = ((w - gap * 2) / 3).floorToDouble();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: _drafts.length + 1, // 末尾固定一个"添加"块
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: gap,
        crossAxisSpacing: gap,
      ),
      itemBuilder: (_, i) {
        if (i == _drafts.length) return _addTile(cell);
        final d = _drafts[i];
        return _mediaCard(i, d, cell);
      },
    );
  }

  /// 每个媒体的卡片：统一圆角、内嵌删除叉、入场动画
  Widget _mediaCard(int i, _Draft d, double cell) {
    Widget face;
    if (d.type == 'image') {
      face = GestureDetector(
        onTap: () => openImage(context, d.path),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(File(d.path),
              width: double.infinity, height: double.infinity, fit: BoxFit.cover),
        ),
      );
    } else if (d.type == 'video' || d.type == 'livephoto') {
      face = GestureDetector(
        onTap: () => openVideo(context, d.path, title: d.name, cover: d.thumb),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
              width: double.infinity, height: double.infinity,
              color: const Color(0xFF101014),
              child: Stack(fit: StackFit.expand, children: [
                VideoCover(video: d.path, thumb: d.thumb),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.32),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.55)),
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ])),
        ),
      );
    } else if (d.type == 'audio') {
      final kind = fileKindOf(d.name, _mimeOf(d.path));
      face = GestureDetector(
        onTap: () => openAudio(context, d.path, title: d.name),
        child: _fileFace(
          bg: kind.color.withOpacity(0.1),
          icon: Icon(Icons.music_note_rounded, color: kind.color, size: 30),
          label: '音频',
          color: kind.color,
          cell: cell,
        ),
      );
    } else {
      if (isApkName(d.path)) {
        face = GestureDetector(
          onTap: () => openIfReadable(context, d.path),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ApkCover(path: d.path, size: cell, radius: 16),
          ),
        );
      } else {
        final kind = fileKindOf(d.name, _mimeOf(d.path));
        face = GestureDetector(
          onTap: () {
            if (openIfReadable(context, d.path)) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content:
                    Text('暂不支持预览 ${kind.label}，点右上角发布后可从列表查看')));
          },
          child: _fileFace(
            bg: kind.color.withOpacity(0.1),
            icon: Icon(kind.icon, color: kind.color, size: 30),
            label: d.name,
            color: kind.color,
            cell: cell,
          ),
        );
      }
    }

    return TweenAnimationBuilder<double>(
      key: ValueKey('tile_${d.path}_$i'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeOutBack,
      child: Stack(children: [
        Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.hairline.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: face,
        ),
        _removeBtn(i),
      ]),
      builder: (_, v, child) => Transform.scale(
        scale: v,
        child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
      ),
    );
  }

  /// 普通文件 / 音频的通用视觉面
  Widget _fileFace({
    required Color bg,
    required Icon icon,
    required String label,
    required Color color,
    required double cell,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: bg,
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: icon,
        ),
        const Spacer(),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: AppTheme.inkSoft)),
      ]),
    );
  }

  /// 内嵌删除叉：白描边圆 + 半透明黑底，自带外边距不切角
  Widget _removeBtn(int i) => Positioned(
        top: 8,
        right: 8,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            _remove(i);
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.85), width: 1.4),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1)),
              ],
            ),
            child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
          ),
        ),
      );

  /// 末尾"添加"块
  Widget _addTile(double cell) {
    return GestureDetector(
      onTap: _showAddSheet,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppTheme.clay.withOpacity(0.35),
              width: 1.4,
              style: BorderStyle.solid),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_circle_outline_rounded, color: AppTheme.clay, size: 30),
          const SizedBox(height: 6),
          Text('添加',
              style: TextStyle(fontSize: 11, color: AppTheme.clay, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  /// 底部弹出的添加菜单
  void _showAddSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('添加内容',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 18),
            Row(children: [
              _sheetItem(ctx, Icons.photo_library_outlined, '图片',
                  AppTheme.clay, () => _addImages()),
              _sheetItem(ctx, Icons.videocam_outlined, '视频',
                  AppTheme.clayDeep, () => _addVideo()),
              _sheetItem(ctx, Icons.attach_file, '文件',
                  AppTheme.sage, () => _addFile()),
              _sheetItem(ctx, Icons.mic, '语音',
                  AppTheme.sand, () => _addVoice()),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _sheetItem(BuildContext ctx, IconData ic, String label,
      Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.pop(ctx);
          onTap();
        },
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(ic, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: AppTheme.inkSoft, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    Widget btn(IconData ic, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(ic, color: AppTheme.clay, size: 22),
                const SizedBox(height: 3),
                Text(label, style: TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
              ]),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
      ),
      child: SafeArea(top: false, child: Row(children: [
        btn(Icons.mic, '语音', _addVoice),
        btn(Icons.photo_library_outlined, '图片', _addImages),
        btn(Icons.videocam_outlined, '视频', _addVideo),
        btn(Icons.attach_file, '文件', _addFile),
        btn(Icons.place_outlined, '位置', _pickLocation),
      ])),
    );
  }
}

/// 发布按钮：带按压缩放与发布态动效
class _PublishButton extends StatefulWidget {
  final bool busy;
  final bool enabled;
  final String label;
  final VoidCallback onPressed;
  const _PublishButton({
    required this.busy,
    required this.enabled,
    required this.label,
    required this.onPressed,
  });
  @override
  State<_PublishButton> createState() => _PublishButtonState();
}

class _PublishButtonState extends State<_PublishButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: (_pressed && widget.enabled) ? 0.92 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: GestureDetector(
        onTapDown: (_) =>
            widget.enabled ? setState(() => _pressed = true) : null,
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          if (widget.enabled && !widget.busy) {
            HapticFeedback.lightImpact();
            widget.onPressed();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              AppTheme.clay,
              AppTheme.clayDeep,
            ]),
            borderRadius: BorderRadius.circular(999),
            boxShadow: widget.enabled
                ? [
                    BoxShadow(
                        color: AppTheme.clay.withOpacity(0.32),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]
                : null,
          ),
          child: widget.busy
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(widget.label,
                  style: TextStyle(
                      color: widget.enabled ? Colors.white : Colors.white60,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// 新增分类的芯片（带 + 图标）
class _CategoryAddChip extends StatefulWidget {
  final VoidCallback onTap;
  const _CategoryAddChip({required this.onTap});
  @override
  State<_CategoryAddChip> createState() => _CategoryAddChipState();
}

class _CategoryAddChipState extends State<_CategoryAddChip> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 140),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: AppTheme.clay.withOpacity(0.45), width: 1.2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add, size: 16, color: AppTheme.clay),
            const SizedBox(width: 3),
            Text('新建',
                style: TextStyle(fontSize: 13, color: AppTheme.clay)),
          ]),
        ),
      ),
    );
  }
}

/// 新建分类弹窗
class _CategoryDialog extends StatefulWidget {
  final TextEditingController controller;
  const _CategoryDialog({required this.controller});
  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('新建分类'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 12,
        decoration: const InputDecoration(hintText: '例如：美食'),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: Text('确定', style: TextStyle(color: AppTheme.clay))),
      ],
    );
  }
}

/// 分类管理模式（bottom sheet）：预设 + 自定义的增删
class _CategoryManagerSheet extends StatelessWidget {
  final List<String> presets;
  final List<ShuoCategory> categories;
  final Future<void> Function(ShuoCategory) onDelete;
  final VoidCallback onAdd;
  const _CategoryManagerSheet({
    required this.presets,
    required this.categories,
    required this.onDelete,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('管理随笔分类',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('预设分类不可删除，自定义可增删',
                style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in presets)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppTheme.sand.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(p,
                      style: TextStyle(fontSize: 13, color: AppTheme.clayDeep)),
                ),
            ]),
            const SizedBox(height: 14),
            if (categories.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('还没有自定义分类',
                    style: TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
              )
            else
              for (final c in categories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Icon(Icons.label_outline, size: 16, color: AppTheme.clay),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(c.name,
                            style: const TextStyle(fontSize: 14))),
                    InkWell(
                      onTap: () => onDelete(c),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.delete_outline,
                            size: 18, color: AppTheme.error),
                      ),
                    ),
                  ]),
                ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('新建分类'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.clay,
                  side: BorderSide(color: AppTheme.clay.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}