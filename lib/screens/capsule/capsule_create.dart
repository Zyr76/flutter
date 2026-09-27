import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../db.dart';
import '../../models.dart';
import '../../services/picker.dart';
import '../../session.dart';
import '../../storage.dart';
import '../../theme.dart';

class CapsuleCreatePage extends StatefulWidget {
  const CapsuleCreatePage({Key? key}) : super(key: key);
  @override
  State<CapsuleCreatePage> createState() => _CapsuleCreatePageState();
}

class _CapsuleCreatePageState extends State<CapsuleCreatePage> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  Duration _keep = const Duration(days: 365);
  DateTime? _custom;

  String? _filePath;
  String _mediaType = 'none'; // image / video / file

  static const _presets = [
    (Duration(days: 365), '1 年'),
    (Duration(days: 365 * 3), '3 年'),
    (Duration(days: 365 * 5), '5 年'),
    (Duration(days: 365 * 10), '10 年'),
  ];

  Future<void> _pickMedia() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo), title: const Text('图片'), onTap: () => Navigator.pop(context, 'image')),
          ListTile(leading: const Icon(Icons.videocam), title: const Text('视频'), onTap: () => Navigator.pop(context, 'video')),
          ListTile(leading: const Icon(Icons.attach_file), title: const Text('文件'), onTap: () => Navigator.pop(context, 'file')),
        ]),
      ),
    );
    if (choice == null) return;
    String? path;
    if (choice == 'image') path = await Picker.image();
    if (choice == 'video') path = await Picker.video();
    if (choice == 'file') {
      final f = await Picker.file();
      path = f?.path;
    }
    if (path != null) setState(() { _filePath = path; _mediaType = choice; });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty && _content.text.trim().isEmpty && _filePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('胶囊里写点什么吧')));
      return;
    }
    final uid = Session.instance.user!.id!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final openAt = _custom ?? DateTime.now().add(_keep);

    String? storedPath;
    if (_filePath != null) {
      final ext = _filePath!.split('.').lastOrNull ?? 'bin';
      final name = Storage.newName(ext.toLowerCase());
      storedPath = await Storage.ensureInApp(_filePath!, 'capsule', name);
    }
    await Db.instance.insertCapsule({
      'user_id': uid,
      'title': title,
      'content': _content.text.trim(),
      'file_path': storedPath,
      'media_type': _mediaType,
      'unlock_at': now,
      'open_at': openAt.millisecondsSinceEpoch,
      'created_at': now,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已封存，等待开启那天')));
      Navigator.pop(context, true);
    }
  }

  Future<void> _pickCustomDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 30)),
    );
    if (p != null) setState(() => _custom = p);
  }

  @override
  Widget build(BuildContext context) {
    final open = _custom ?? DateTime.now().add(_keep);
    return Scaffold(
      appBar: AppBar(
        title: const Text('封存时间胶囊'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _save,
              child: const Text('封存', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: _title,
              decoration: const InputDecoration(hintText: '胶囊的名字（写给谁）')),
          const SizedBox(height: 14),
          TextField(controller: _content, maxLines: 6,
              decoration: const InputDecoration(hintText: '想对未来的自己说什么…', alignLabelWithHint: true)),
          const SizedBox(height: 20),
          Text('附上一份记忆', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (_mediaType == 'none')
            OutlinedButton.icon(
              onPressed: _pickMedia,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加图片 / 视频 / 文件'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.clayDeep,
                side: BorderSide(color: AppTheme.hairline),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          else
            InkWell(
              onTap: _pickMedia,
              child: Stack(children: [
                Container(
                  width: 110, height: 110, clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: AppTheme.bgDeep,
                    image: _mediaType == 'image'
                        ? DecorationImage(image: FileImage(File(_filePath!)), fit: BoxFit.cover)
                        : null,
                  ),
                  child: _mediaType == 'image'
                      ? null
                      : Center(child: Icon(
                          _mediaType == 'video' ? Icons.videocam : Icons.insert_drive_file,
                          color: AppTheme.clay, size: 34)),
                ),
                Positioned(right: 4, top: 4,
                  child: GestureDetector(
                    onTap: () => setState(() { _filePath = null; _mediaType = 'none'; }),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                      child: const Icon(Icons.close, size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 24),
          Text('开启时间', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < _presets.length; i++)
              ChoiceChip(
                label: Text(_presets[i].$2),
                selected: _custom == null && _keep == _presets[i].$1,
                onSelected: (_) => setState(() { _keep = _presets[i].$1; _custom = null; }),
              ),
            ChoiceChip(
              label: const Text('自定义日期'),
              selected: _custom != null,
              onSelected: (_) => _pickCustomDate(),
            ),
          ]),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.sand.withOpacity( 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(Icons.schedule, size: 18, color: AppTheme.clayDeep),
              const SizedBox(width: 8),
              Text('将于 ${DateFormat('yyyy年MM月dd日 HH:mm').format(open)} 开启',
                  style: TextStyle(color: AppTheme.clayDeep, fontWeight: FontWeight.w500)),
            ]),
          ),
          const SizedBox(height: 12),
          Text('提示：时间胶囊一经封存，内容便不可编辑，请谨慎填写。',
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
        ]),
      ),
    );
  }
}