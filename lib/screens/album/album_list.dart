import 'dart:io';

import 'package:flutter/material.dart';

import '../../db.dart';
import '../../models.dart';
import '../../session.dart';
import '../../storage.dart';
import '../../theme.dart';
import '../../widgets/media.dart';
import 'album_view.dart';

class AlbumListPage extends StatefulWidget {
  const AlbumListPage({Key? key}) : super(key: key);
  @override
  State<AlbumListPage> createState() => _AlbumListPageState();
}

class _AlbumListPageState extends State<AlbumListPage> {
  List<Album>? _albums;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = Session.instance.user!.id!;
    final data = await Db.instance.albumsByUser(uid);
    if (mounted) setState(() => _albums = data);
  }

  Future<void> _create() async {
    final name = await _promptName();
    if (name == null || name.trim().isEmpty) return;
    final uid = Session.instance.user!.id!;
    await Db.instance.insertAlbum({
      'user_id': uid, 'name': name.trim(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    _load();
  }

  Future<String?> _promptName() => showDialog<String>(
        context: context,
        builder: (_) => _NameDialog(title: '新建相册', hint: '相册名称'),
      );

  void _open(Album a) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumViewPage(album: a)))
        .then((_) => _load());
  }

  Future<void> _delete(Album a) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('删除相册「${a.name}」？'),
        content: Text('相册中的照片将被一并删除。', style: TextStyle(color: AppTheme.inkSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('删除', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (r == true) {
      final medias = await Db.instance.albumMedia(a.id);
      for (final m in medias) {
        // 说说同步进来的镜像只删除相册记录，保留源媒体
        final fromShuo = await Db.instance.isShuoMedia(m.filePath);
        if (!fromShuo) await Storage.delete(m.filePath);
      }
      await Db.instance.deleteAlbum(a.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('空间相册')),
      body: _albums == null
          ? const Center(child: CircularProgressIndicator())
          : _albums!.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 96, height: 96, decoration: BoxDecoration(
                        shape: BoxShape.circle, color: AppTheme.sand),
                        child: Icon(Icons.photo_album, size: 50, color: AppTheme.clayDeep)),
                    const SizedBox(height: 16),
                    const Text('还没有相册', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ]),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.9),
                  itemCount: _albums!.length,
                  itemBuilder: (_, i) => _albumCard(_albums![i]),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('新建相册'),
      ),
    );
  }

  Future<_AlbumCount> _count(Album a) async {
    final medias = await Db.instance.albumMedia(a.id);
    // 封面：选第一张"真正能显示出来"的媒体 —— 跳过文件已丢失的，
    // 视频/实况图只要文件在或已有缩略图就能由封面组件异步生成，图片必须文件存在。
    AlbumMedia? cover;
    for (final m in medias) {
      final fileOk = File(m.filePath).existsSync();
      final thumbOk = m.thumb != null &&
          m.thumb!.isNotEmpty &&
          File(m.thumb!).existsSync();
      if (_isVideo(m.filePath, m.mime)) {
        if (fileOk || thumbOk) {
          cover = m;
          break;
        }
      } else if (fileOk) {
        cover = m;
        break;
      }
    }
    return _AlbumCount(medias.length, cover);
  }

  /// 判断媒体是否为视频/实况图：优先看 mime；mime 缺失时按扩展名兜底，
  /// 避免把视频当图片解析导致封面显示失败。
  bool _isVideo(String path, String mime) {
    if (mime.startsWith('video')) return true;
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    return const {
      'mp4', 'mov', 'mkv', 'webm', 'avi', '3gp', 'm4v', 'flv',
    }.contains(ext);
  }

  Widget _albumCard(Album a) {
    return FutureBuilder<_AlbumCount>(
      future: _count(a),
      builder: (_, snap) {
        final cov = snap.data?.cover;
        final count = snap.data?.count ?? 0;
        return GestureDetector(
          onTap: () => _open(a),
          onLongPress: () => _delete(a),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: AppTheme.bgDeep,
                  child: cov == null
                      ? Center(
                          child: Icon(Icons.photo_library_outlined,
                              color: AppTheme.clay, size: 40))
                      : _isVideo(cov.filePath, cov.mime)
                          // 视频封面：用缩略图组件生成，避免 Image 无法解析视频文件
                          ? ClipRect(
                              child: SizedBox(
                                width: double.infinity,
                                child: VideoCover(
                                    video: cov.filePath, thumb: cov.thumb),
                              ),
                            )
                          : Image.file(File(cov.filePath),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              // 图片损坏/格式异常时兜底，避免整块灰屏
                              errorBuilder: (_, __, ___) => Center(
                                child: Icon(Icons.broken_image_outlined,
                                    color: AppTheme.clay, size: 40),
                              )),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('$count 张', style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _AlbumCount {
  final int count;
  final AlbumMedia? cover;
  _AlbumCount(this.count, this.cover);
}

class _NameDialog extends StatefulWidget {
  final String title;
  final String hint;
  const _NameDialog({required this.title, required this.hint});
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _c = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint, isDense: true),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(context, _c.text),
            child: const Text('确定', style: TextStyle(fontWeight: FontWeight.w600))),
      ],
    );
  }
}