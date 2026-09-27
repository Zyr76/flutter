import 'package:flutter/material.dart';

import '../../theme.dart';
import '../album/album_list.dart';
import '../files/files_home.dart';

/// 空间中心：相册 + 文件
class SpaceHub extends StatelessWidget {
  const SpaceHub({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _entry(context, Icons.photo_library_outlined, '空间相册',
              '整理说说里的照片，自定义相册', AppTheme.sage,
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AlbumListPage()))),
          const SizedBox(height: 14),
          _entry(context, Icons.folder_outlined, '空间文件',
              '我的所有文件，自由分类与导出', AppTheme.clay,
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FilesHomePage()))),
        ],
      ),
      ),
    );
  }

  Widget _entry(BuildContext context, IconData icon, String title, String sub, Color color, VoidCallback onTap) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.hairline.withOpacity( 0.6)),
          ),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: color.withOpacity( 0.14), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 3),
              Text(sub, style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
            ])),
            Icon(Icons.chevron_right, color: AppTheme.inkSoft),
          ]),
        ),
      ),
    );
  }
}