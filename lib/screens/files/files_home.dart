import 'dart:io';

import 'package:flutter/material.dart';

import '../../db.dart';
import '../../models.dart';
import '../../services/filekind.dart';
import '../../services/picker.dart';
import '../../services/share.dart';
import '../../services/thumbnail.dart';
import '../../session.dart';
import '../../services/apk_installer.dart';
import '../../storage.dart';
import '../../theme.dart';
import '../../widgets/file_viewer.dart';
import '../../widgets/media.dart';
import '../../widgets/month_calendar.dart';

class FilesHomePage extends StatefulWidget {
  const FilesHomePage({Key? key}) : super(key: key);
  @override
  State<FilesHomePage> createState() => _FilesHomePageState();
}

/// 将字节数格式化为人类易读的单位（B / KB / MB / GB / TB）。
String fmtSize(num size) {
  final n = size.toDouble();
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  var v = n;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return i == 0 ? '${v.toStringAsFixed(0)} ${units[i]}'
      : '${v.toStringAsFixed(1)} ${units[i]}';
}

class _FilesHomePageState extends State<FilesHomePage> {
  // 面包屑栈：根(0) + 各层 folderId
  final List<SpaceFolder> _crumbs = [];
  List<SpaceFolder> _folders = [];
  List<SpaceFile> _files = [];
  bool _loading = true;
  String? _curName;
  bool _cal = false; // 日历视图
  DateTime _calDay = DateTime.now();
  bool _sel = false; // 多选模式
  final Set<int> _selIds = {};

  int get _folderId => _crumbs.isEmpty ? 0 : _crumbs.last.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = Session.instance.user!.id!;
    final folders = await Db.instance.foldersBy(uid, _folderId);
    final files = await Db.instance.spaceFilesBy(uid, _folderId);
    if (mounted) {
      setState(() {
        _folders = folders;
        _files = files;
        _loading = false;
      });
    }
  }

  void _enter(SpaceFolder f) {
    setState(() => _crumbs.add(f));
    _load();
  }

  void _backTo(int i) {
    setState(() {
      _crumbs.removeRange(i, _crumbs.length);
    });
    _load();
  }

  Future<void> _createFolder() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('新建文件夹'),
        content: TextField(controller: c, autofocus: true,
            decoration: const InputDecoration(hintText: '文件夹名称', isDense: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('确定')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final uid = Session.instance.user!.id!;
    await Db.instance.insertFolder({
      'user_id': uid, 'parent_id': _folderId, 'name': name.trim(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    _load();
  }

  Future<void> _upload() async {
    final files = await Picker.files();
    if (files.isEmpty || !mounted) return;
    final uid = Session.instance.user!.id!;
    final now = DateTime.now();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImportDialog(
        files: files,
        userId: uid,
        folderId: _folderId,
        now: now,
      ),
    );
    _load();
  }

  Future<void> _deleteFolder(SpaceFolder f) async {
    final r = await _confirm('删除文件夹「${f.name}」？', '文件夹内所有文件将一并删除。');
    if (r == true) {
      // 清理真实文件
      await _purgeFolderFiles(f.id);
      await Db.instance.deleteFolder(f.id);
      if (mounted && _crumbs.contains(f)) _crumbs.remove(f);
      _load();
    }
  }

  Future<void> _purgeFolderFiles(int folderId) async {
    final files = await Db.instance.spaceFilesBy(Session.instance.user!.id!, folderId);
    for (final f in files) await Storage.delete(f.filePath);
    final subs = await Db.instance.foldersBy(Session.instance.user!.id!, folderId);
    for (final s in subs) await _purgeFolderFiles(s.id);
  }

  Future<void> _deleteFile(SpaceFile f) async {
    final r = await _confirm('删除文件「${f.name}」？', '');
    if (r == true) {
      await _removeFile(f);
      _load();
    }
  }

  Future<void> _removeFile(SpaceFile f) async {
    // 说说同步进来的镜像只删除空间文件记录，保留源文件，避免影响说说
    final fromShuo = await Db.instance.isShuoMedia(f.filePath);
    if (!fromShuo) await Storage.delete(f.filePath);
    await Db.instance.deleteSpaceFile(f.id);
  }

  /// 重命名文件：普通文件连同磁盘上的文件一起改名，说说同步进来的镜像只改显示名。
  Future<void> _renameFile(SpaceFile f) async {
    final c = TextEditingController(text: f.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('重命名'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件名称', isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    if (newName == null ||
        newName.isEmpty ||
        newName == f.name ||
        !mounted) return;

    var path = f.filePath;
    // 说说同步进来的镜像只改名显示名，不动源文件，避免影响说说
    final fromShuo = await Db.instance.isShuoMedia(f.filePath);
    if (!fromShuo) {
      final oldFile = File(f.filePath);
      if (oldFile.existsSync()) {
        final dir = oldFile.parent.path;
        final ext = f.filePath.contains('.')
            ? f.filePath.split('.').last
            : '';
        final base = newName.toLowerCase().endsWith(ext.isEmpty ? '\u0000' : '.$ext')
            ? newName
            : '$newName${ext.isEmpty ? '' : '.$ext'}';
        var target = '$dir/$base';
        var n = 1;
        while (File(target).existsSync()) {
          target = '$dir/${_insertSuffix(base, n++)}';
        }
        await oldFile.rename(target);
        path = target;
      }
    }
    await Db.instance.renameSpaceFile(f.id, newName, path);
    _load();
  }

  /// 文件长按操作菜单：重命名 / 删除。
  void _fileActions(SpaceFile f) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('重命名'),
            onTap: () {
              Navigator.pop(ctx);
              _renameFile(f);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: AppTheme.error),
            title: Text('删除', style: TextStyle(color: AppTheme.error)),
            onTap: () {
              Navigator.pop(ctx);
              _deleteFile(f);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  String _insertSuffix(String base, int n) {
    final dot = base.lastIndexOf('.');
    if (dot <= 0) return '$base ($n)';
    return '${base.substring(0, dot)} ($n)${base.substring(dot)}';
  }

  void _toggleSel(int id) {
    setState(() {
      if (!_selIds.add(id)) _selIds.remove(id);
    });
  }

  void _exitSel() => setState(() {
        _sel = false;
        _selIds.clear();
      });

  Future<void> _deleteSelectedFiles() async {
    if (_selIds.isEmpty) return;
    final r = await _confirm('删除选中的 ${_selIds.length} 个文件？', '');
    if (r == true) {
      for (final f in _files) {
        if (_selIds.contains(f.id)) await _removeFile(f);
      }
      _exitSel();
      _load();
    }
  }

  List<SpaceFile> get _calFiles => _files
      .where((f) =>
          dayKeyOf(DateTime.fromMillisecondsSinceEpoch(f.createdAt)) ==
          dayKeyOf(_calDay))
      .toList();

  Future<bool?> _confirm(String title, String content) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(title),
          content: content.isEmpty ? null : Text(content, style: TextStyle(color: AppTheme.inkSoft)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(context, true),
                child: Text('删除', style: TextStyle(color: AppTheme.error))),
          ],
        ),
      );

  void _preview(SpaceFile f) {
    final mime = f.mime;
    if (mime.startsWith('image')) {
      openImage(context, f.filePath);
    } else if (mime.startsWith('video')) {
      openVideo(context, f.filePath);
    } else if (mime.startsWith('audio')) {
      openAudio(context, f.filePath, title: f.name);
    } else if (f.name.toLowerCase().endsWith('.apk')) {
      _apkDialog(f);
    } else if (openIfReadable(context, f.filePath)) {
      // 可阅读格式：txt/md/html/json/pdf 等，直接在 App 内阅读
    } else {
      // 其他类型：显示详情，可导出
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.insert_drive_file, color: AppTheme.clay), const SizedBox(width: 8), Expanded(child: Text(f.name))]),
            const SizedBox(height: 12),
            Text('大小：${fmtSize(f.size)}', style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
            const SizedBox(height: 8),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            TextButton(onPressed: () async { Navigator.pop(context); await ShareX.one(f.filePath, name: f.name); }, child: const Text('导出')),
          ],
        ),
      );
    }
  }

  /// APK 详情弹窗：展示应用图标封面 + 文件信息，可分享/保存到相册等。
  Future<void> _apkDialog(SpaceFile f) async {
    String? cover = await Thumbs.forApk(f.filePath);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _ApkCoverSquare(path: f.filePath, cover: cover),
            const SizedBox(width: 12),
            Expanded(child: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 3, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 12),
          Text('大小：${fmtSize(f.size)}', style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.5),
              children: const [
                TextSpan(text: '「'),
                TextSpan(text: '安装包', style: TextStyle(color: Color(0xFF3FA14B), fontWeight: FontWeight.w600)),
                TextSpan(text: '」点击「立即安装」会在系统安装器中打开安装（首次安装未知来源应用时需在系统设置中允许本应用）。\n'),
                TextSpan(text: '也可以导出 / 分享给其他设备安装。'),
              ],
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              foregroundColor: const Color(0xFF3FA14B),
              backgroundColor: const Color(0xFF3FA14B).withOpacity(0.12),
            ),
            icon: const Icon(Icons.download_done, size: 18),
            label: const Text('立即安装'),
            onPressed: () async {
              Navigator.pop(context);
              await _tryInstallApk(f);
            },
          ),
          TextButton(onPressed: () async { Navigator.pop(context); await ShareX.one(f.filePath, name: f.name); }, child: const Text('导出 / 分享')),
        ],
      ),
    );
  }

  Future<void> _tryInstallApk(SpaceFile f) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ApkInstaller.install(f.filePath);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? '已打开系统安装器，请按界面提示完成安装'
          : '无法打开安装界面，请尝试导出后手动安装'),
      duration: const Duration(seconds: 2),
    ));
  }

  String _mime(String e) {
    if (e == 'jpg' || e == 'jpeg') return 'image/jpeg';
    if (e == 'png') return 'image/png';
    if (e == 'gif') return 'image/gif';
    if (e == 'mp4' || e == 'mov' || e == 'webm') return 'video/$e';
    if (e == 'mp3' || e == 'wav') return 'audio/$e';
    if (e == 'pdf') return 'application/pdf';
    if (e == 'txt') return 'text/plain';
    return 'application/octet-stream';
  }

  // 日期格式化：今天只显示时间，其他显示月日（跨年补年份）
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

  @override
  Widget build(BuildContext context) {
    final isRoot = _crumbs.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('空间文件'),
        leading: _sel
            ? IconButton(onPressed: _exitSel, icon: const Icon(Icons.close))
            : null,
        actions: [
          if (!_sel)
            IconButton(
              onPressed: () => setState(() {
                _cal = !_cal;
                _calDay = DateTime.now();
              }),
              icon: Icon(_cal ? Icons.grid_view_outlined : Icons.calendar_month_outlined),
              tooltip: _cal ? '列表视图' : '日历视图',
            ),
          if (_sel)
            IconButton(
              onPressed: _deleteSelectedFiles,
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除所选',
            )
          else
            IconButton(
              onPressed: () => setState(() => _sel = true),
              icon: const Icon(Icons.checklist),
              tooltip: '多选',
            ),
          if (!_sel) IconButton(onPressed: _createFolder, icon: const Icon(Icons.create_new_folder_outlined), tooltip: '新建文件夹'),
          if (!_sel) IconButton(onPressed: _upload, icon: const Icon(Icons.upload_file_outlined), tooltip: '上传文件'),
        ],
      ),
      body: Stack(children: [
        Column(children: [
          if (!isRoot) _breadcrumb(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_folders.isEmpty && _files.isEmpty)
                    ? const _EmptyFiles()
                    : _cal
                        ? _calBody()
                        : _listBody(),
          ),
        ]),
        if (_sel) _selBar(),
      ]),
    );
  }

  Widget _selBar() => Positioned(
        left: 0, right: 0, bottom: 0,
        child: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            color: AppTheme.surface,
            child: Row(children: [
              Icon(Icons.check_circle, color: AppTheme.clay, size: 20),
              const SizedBox(width: 6),
              Text('已选 ${_selIds.length} 项',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: _deleteSelectedFiles,
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('删除'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.error),
              ),
            ]),
          ),
        ),
      );

  Widget _calBody() {
    final dayFiles = _calFiles;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
      children: [
        MonthCalendar(
          markDays: _files
              .map((f) => dayKeyOf(
                  DateTime.fromMillisecondsSinceEpoch(f.createdAt)))
              .toSet(),
          selected: _calDay,
          onSelect: (d) => setState(() => _calDay = d),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            _calDay.year == DateTime.now().year &&
                    _calDay.month == DateTime.now().month &&
                    _calDay.day == DateTime.now().day
                ? '今天 · ${_calDay.month}月${_calDay.day}日'
                : '${_calDay.month}月${_calDay.day}日',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (dayFiles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text('这一天没有文件',
                  style: TextStyle(color: AppTheme.inkSoft, fontSize: 13)),
            ),
          )
        else
          for (final f in dayFiles) _fileTile(f),
      ],
    );
  }

  Widget _listBody() => ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        children: [
          if (_folders.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Text('文件夹', style: TextStyle(fontSize: 13, color: AppTheme.inkSoft, fontWeight: FontWeight.w600)),
            ),
            ..._folders.map((f) => _folderTile(f)),
            const SizedBox(height: 8),
          ],
          if (_files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Text('文件', style: TextStyle(fontSize: 13, color: AppTheme.inkSoft, fontWeight: FontWeight.w600)),
            ),
          ..._files.map((f) => _fileTile(f)),
        ],
      );

  Widget _breadcrumb() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _crumbChip('全部文件', () => _backTo(0)),
          for (var i = 0; i < _crumbs.length; i++) ...[
            Text(' / ', style: TextStyle(color: AppTheme.inkSoft)),
            _crumbChip(_crumbs[i].name, () => _backTo(i + 1)),
          ],
        ]),
      ),
    );
  }

  Widget _crumbChip(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Text(label, style: TextStyle(fontSize: 13, color: AppTheme.clayDeep)),
      );

  Widget _folderTile(SpaceFolder f) {
    return GestureDetector(
      onTap: () => _enter(f),
      onLongPress: () => _deleteFolder(f),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.hairline.withOpacity( 0.5)),
        ),
        child: Row(children: [
          Icon(Icons.folder, color: AppTheme.clay),
          const SizedBox(width: 12),
          Expanded(child: Text(f.name, style: const TextStyle(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis)),
          Icon(Icons.chevron_right, color: AppTheme.inkSoft, size: 20),
        ]),
      ),
    );
  }

  Widget _fileTile(SpaceFile f) {
    final isImg = f.mime.startsWith('image');
    final isVid = f.mime.startsWith('video');
    final checked = _selIds.contains(f.id);
    final kind = fileKindOf(f.name, f.mime);
    final isApk = f.name.toLowerCase().endsWith('.apk');
    final isReadable = isReadableExt(f.filePath);
    return GestureDetector(
      onTap: () {
        if (_sel) {
          _toggleSel(f.id);
        } else {
          _preview(f);
        }
      },
      onLongPress: () {
        if (_sel) {
          _toggleSel(f.id);
        } else {
          _fileActions(f);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: checked ? AppTheme.sand.withOpacity(0.4) : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          if (isImg)
            ClipRRect(borderRadius: BorderRadius.circular(6),
                child: Image.file(File(f.filePath), width: 42, height: 42, fit: BoxFit.cover))
          else if (isVid)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 42, height: 42,
                child: Stack(fit: StackFit.expand, children: [
                  VideoCover(video: f.filePath),
                  const Center(
                    child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 22),
                  ),
                ]),
              ),
            )
          else if (isApk)
            _ApkCover(path: f.filePath)
          else
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                  color: kind.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: Icon(kind.icon, color: kind.color, size: 22),
            ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.name, style: const TextStyle(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('${fmtSize(f.size)} · ${_fmtDate(f.createdAt)}',
                style: TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
          ])),
          if (isReadable)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                  color: AppTheme.sand.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(6)),
              child: Text('查看', style: TextStyle(fontSize: 10, color: AppTheme.clayDeep)),
            ),
          IconButton(
            icon: Icon(Icons.ios_share, size: 18, color: AppTheme.inkSoft),
            onPressed: () => ShareX.one(f.filePath, name: f.name),
          ),
          if (_sel)
            Icon(checked ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 22,
                color: checked ? AppTheme.clay : AppTheme.inkSoft),
          const SizedBox(width: 4),
        ]),
      ),
    );
  }
}

/// APK 应用图标封面：异步解析 APK 的 app 图标，并做进程内缓存。
/// 解析失败回退显示安卓机器人图标占位。
class _ApkCover extends StatefulWidget {
  final String path;
  const _ApkCover({required this.path});
  @override
  State<_ApkCover> createState() => _ApkCoverState();
}

class _ApkCoverState extends State<_ApkCover> {
  static final Map<String, String?> _cache = {};
  String? _cover;

  @override
  void initState() {
    super.initState();
    final hit = _cache.containsKey(widget.path);
    if (hit) {
      _cover = _cache[widget.path];
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final c = await Thumbs.forApk(widget.path);
    _cache[widget.path] = c;
    if (mounted && _cover != c) setState(() => _cover = c);
  }

  @override
  Widget build(BuildContext context) {
    final c = _cover;
    if (c != null && c.isNotEmpty && File(c).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(File(c), width: 42, height: 42, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
          color: const Color(0xFF3FA14B).withOpacity(0.12),
          borderRadius: BorderRadius.circular(6)),
      child: const Icon(Icons.android, color: Color(0xFF3FA14B), size: 22),
    );
  }
}

/// APK 详情弹窗里的大号图标封面（可直接传入已解析的 cover）
class _ApkCoverSquare extends StatelessWidget {
  final String path;
  final String? cover;
  const _ApkCoverSquare({required this.path, this.cover});

  @override
  Widget build(BuildContext context) {
    final c = cover ?? (_ApkCoverState._cache[path]);
    if (c != null && c.isNotEmpty && File(c).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(File(c), width: 56, height: 56, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
          color: const Color(0xFF3FA14B).withOpacity(0.14),
          borderRadius: BorderRadius.circular(12)),
      child: const Icon(Icons.android, color: Color(0xFF3FA14B), size: 30),
    );
  }
}

class _EmptyFiles extends StatelessWidget {
  const _EmptyFiles();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 96, height: 96, decoration: BoxDecoration(
            shape: BoxShape.circle, color: AppTheme.sand),
            child: Icon(Icons.folder_open, size: 50, color: AppTheme.clayDeep)),
        const SizedBox(height: 16),
        const Text('这里空空如也', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('点击右上角上传文件或新建文件夹', style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
      ]),
    );
  }
}

/// 导入文件时的进度弹窗：逐文件复制到应用私有目录并实时显示进度。
class _ImportDialog extends StatefulWidget {
  final List<Picked> files;
  final int userId;
  final int folderId;
  final DateTime now;
  const _ImportDialog({
    required this.files,
    required this.userId,
    required this.folderId,
    required this.now,
  });

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  int _index = 0; // 当前处理到第几个文件
  double _fileProgress = 0.0; // 当前文件的复制进度 0..1
  String _current = '';

  double get _total => widget.files.length.toDouble();
  double get _value =>
      (_index + _fileProgress) / (_total <= 0 ? 1 : _total);

  Future<void> _run() async {
    for (var i = 0; i < widget.files.length; i++) {
      final f = widget.files[i];
      if (!mounted) return;
      setState(() {
        _index = i;
        _current = f.name.isEmpty ? '文件 ${i + 1}' : f.name;
        _fileProgress = 0.0;
      });
      final ext = f.path.split('.').lastOrNull ?? 'bin';
      final saveAs = Storage.newName(ext.toLowerCase());
      try {
        final abs = await Storage.copyWithProgress(
          f.path,
          'spacefiles',
          saveAs,
          (p) {
            if (mounted) setState(() => _fileProgress = p);
          },
        );
        await Db.instance.insertSpaceFile({
          'user_id': widget.userId,
          'folder_id': widget.folderId,
          'file_path': abs,
          'name': f.name.isEmpty ? saveAs : f.name,
          'size': File(abs).lengthSync(),
          'mime': _importMime(ext),
          'created_at': widget.now.millisecondsSinceEpoch,
        });
      } catch (_) {
        // 单个文件失败不中断整体导入
      }
    }
    if (mounted) setState(() => _fileProgress = 1.0);
    if (mounted) Navigator.of(context).pop();
  }

  String _importMime(String e) {
    if (e == 'jpg' || e == 'jpeg') return 'image/jpeg';
    if (e == 'png') return 'image/png';
    if (e == 'gif') return 'image/gif';
    if (e == 'mp4' || e == 'mov' || e == 'webm') return 'video/$e';
    if (e == 'mp3' || e == 'wav') return 'audio/$e';
    if (e == 'pdf') return 'application/pdf';
    if (e == 'txt') return 'text/plain';
    return 'application/octet-stream';
  }

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.files.length;
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('正在导入文件…'),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$_current',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: _value,
                minHeight: 8,
                backgroundColor: Colors.black12,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppTheme.clay),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '当前第 ${(_index + 1).clamp(1, n)} / $n 个 · '
              '${(_value * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}