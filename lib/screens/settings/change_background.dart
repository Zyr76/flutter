import 'dart:io';

import 'package:flutter/material.dart';

import '../../db.dart';
import '../../services/picker.dart';
import '../../session.dart';
import '../../storage.dart';
import '../../theme.dart';

class ChangeBackgroundPage extends StatefulWidget {
  const ChangeBackgroundPage({Key? key}) : super(key: key);
  @override
  State<ChangeBackgroundPage> createState() => _ChangeBackgroundPageState();
}

class _ChangeBackgroundPageState extends State<ChangeBackgroundPage> {
  bool _bgError = false;

  @override
  Widget build(BuildContext context) {
    final u = Session.instance.user!;
    final bg = u.bgFile;
    return Scaffold(
      appBar: AppBar(title: const Text('更换空间背景')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(children: [
              Container(
                height: 220, width: double.infinity,
                color: AppTheme.bgDeep,
                child: (bg != null && bg.isNotEmpty && !_bgError && File(bg).existsSync())
                    ? Image.file(File(bg), fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) { _bgError = true; return const SizedBox(); })
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF9C8B72), Color(0xFFB9A28A), Color(0xFFD9CBB6)],
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          ),
                        ),
                        child: const Center(child: Text('默认背景', style: TextStyle(color: Colors.white70))),
                      ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('从相册选择背景图'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('恢复默认背景'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.clayDeep,
              side: BorderSide(color: AppTheme.hairline),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 18),
          Text('建议选择深色或柔和的图片，能让首屏更耐看。',
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
        ],
      ),
    );
  }

  Future<void> _pick() async {
    final p = await Picker.image();
    if (p == null) return;
    final u = Session.instance.user!;
    final ext = p.split('.').lastOrNull ?? 'png';
    final name = Storage.newName(ext.toLowerCase());
    final abs = await Storage.ensureInApp(p, 'bg', name);
    // 删除旧背景（保留默认）
    final old = u.bgFile;
    if (old != null && old.isNotEmpty) await Storage.delete(old);
    await Db.instance.updateUser(u.id!, {'bg_file': abs});
    await Session.instance.refresh();
    if (mounted && _bgError) setState(() => _bgError = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('背景已更新')));
      Navigator.pop(context, true);
    }
  }

  Future<void> _reset() async {
    final u = Session.instance.user!;
    await Storage.delete(u.bgFile);
    await Db.instance.updateUser(u.id!, {'bg_file': null});
    await Session.instance.refresh();
    if (mounted) Navigator.pop(context, true);
  }
}