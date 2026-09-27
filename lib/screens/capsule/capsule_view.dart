import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models.dart';
import '../../services/share.dart';
import '../../theme.dart';
import '../../widgets/media.dart';

/// 时间胶囊查看（带开启仪式感）
class CapsuleViewPage extends StatefulWidget {
  final Capsule capsule;
  const CapsuleViewPage({Key? key, required this.capsule}) : super(key: key);
  @override
  State<CapsuleViewPage> createState() => _CapsuleViewPageState();
}

class _CapsuleViewPageState extends State<CapsuleViewPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _c.forward().then((_) => setState(() => _opened = true));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cap = widget.capsule;
    final openAt = DateTime.fromMillisecondsSinceEpoch(cap.openAt);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF3A3128), Color(0xFF241E18)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Spacer(flex: 2),
              ScaleTransition(
                scale: CurvedAnimation(parent: _c, curve: Curves.elasticOut),
                child: Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [Color(0xFFBE8A5A), Color(0xFF9A6A45)]),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity( 0.3), blurRadius: 20)],
                  ),
                  child: const Icon(Icons.mail_outline, color: Colors.white, size: 54),
                ),
              ),
              const SizedBox(height: 26),
              Text(cap.title.isEmpty ? '未命名胶囊' : cap.title,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: 1)),
              const SizedBox(height: 8),
              Text('开启于 ${DateFormat('yyyy年MM月dd日').format(openAt)}',
                  style: const TextStyle(color: Color(0xFFB9AB98), fontSize: 13)),
              const Spacer(flex: 3),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                child: _opened ? _revealed(cap) : _sealed(),
              ),
              const Spacer(flex: 2),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sealed() => Column(children: [
        const Text('时光已送达，正在开启…', style: TextStyle(color: Color(0xFFB9AB98), fontSize: 14)),
        const SizedBox(height: 16),
        const CircularProgressIndicator(color: Color(0xFFBE8A5A)),
      ]);

  Widget _revealed(Capsule cap) {
    Widget? preview;
    if (cap.filePath != null && cap.filePath!.isNotEmpty) {
      final t = cap.mediaType;
      if (t == 'image') {
        preview = Column(children: [
          GestureDetector(onTap: () => openImage(context, cap.filePath!),
              child: ClipRRect(borderRadius: BorderRadius.circular(14),
                  child: Image.file(File(cap.filePath!), width: double.infinity, fit: BoxFit.cover))),
          const SizedBox(height: 8),
        ]);
      } else if (t == 'video' || t == 'livephoto') {
        preview = Column(children: [
          GestureDetector(onTap: () => openVideo(context, cap.filePath!),
              child: Stack(alignment: Alignment.center, children: [
                ClipRRect(borderRadius: BorderRadius.circular(14),
                    child: Image.file(File(cap.filePath!), width: double.infinity, height: 160, fit: BoxFit.cover)),
                const CircleAvatar(backgroundColor: Colors.black45, radius: 24,
                    child: Icon(Icons.play_arrow, color: Colors.white)),
              ])),
          const SizedBox(height: 8),
        ]);
      } else {
        preview = Row(children: [
          const Icon(Icons.insert_drive_file, color: Color(0xFFBE8A5A)),
          const SizedBox(width: 8),
          Expanded(child: Text(cap.filePath!.split('/').last,
              style: const TextStyle(color: Color(0xFFB9AB98)), maxLines: 1, overflow: TextOverflow.ellipsis)),
          IconButton(icon: const Icon(Icons.ios_share, color: Color(0xFFB9AB98)),
              onPressed: () => ShareX.one(cap.filePath!)),
        ]);
      }
    }

    return Container(
      key: const ValueKey('opened'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity( 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity( 0.08)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (preview != null) preview,
        if (cap.content.isNotEmpty)
          Text(cap.content,
              style: const TextStyle(color: Color(0xFFEDE4D4), fontSize: 16, height: 1.7, letterSpacing: 0.3)),
        if (cap.content.isEmpty && preview == null)
          const Text('（没有内容）', style: TextStyle(color: Color(0xFFB9AB98))),
        const SizedBox(height: 14),
        Center(child: Text('—— 来自 ${_yearsAgo(cap.createdAt)} 年前的你 ——',
            style: const TextStyle(color: Color(0xFF8F8170), fontSize: 12))),
      ]),
    );
  }

  int _yearsAgo(int ms) {
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    return d.inDays ~/ 365;
  }
}