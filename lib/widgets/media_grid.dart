import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/share.dart';
import '../theme.dart';
import 'file_viewer.dart';
import 'media.dart';
import 'apk_cover.dart';

/// 说说/相册的媒体网格：图片、视频、文件的展示与点击预览
class MediaGrid extends StatelessWidget {
  final List<Media> medias;
  final double spacing;
  const MediaGrid({Key? key, required this.medias, this.spacing = 4})
      : super(key: key);

  // 打开说说里的单个视频/实况图
  void _openSingle(BuildContext context, Media m) => openVideo(context,
      m.filePath,
      live: m.type == 'livephoto',
      title: m.name,
      cover: m.type == 'livephoto' ? m.thumb : null);

  // 可滑动预览的图片/视频项
  List<Media> get _visual => medias
      .where((m) => m.type == 'image' || m.type == 'video' || m.type == 'livephoto')
      .toList();

  // 点击图片/视频：多条时打开滑动预览，可左右看到该说说所有图/视频；单条走原有单页
  void _openVisual(BuildContext context, Media m) {
    final vis = _visual;
    if (vis.length > 1) {
      final idx = vis.indexWhere((e) => e.filePath == m.filePath);
      openMediaPager(
        context,
        vis
            .map((e) => MediaPagerItem(
                  path: e.filePath,
                  isVideo: e.type == 'video' || e.type == 'livephoto',
                  live: e.type == 'livephoto',
                  cover: e.type == 'livephoto' ? e.thumb : null,
                  title: e.name,
                ))
            .toList(),
        start: idx < 0 ? 0 : idx,
      );
      return;
    }
    if (m.type == 'video' || m.type == 'livephoto') _openSingle(context, m);
    else openImage(context, m.filePath);
  }

  // 打开说说里的文件：可阅读的在 App 内阅读，否则弹出分享/导出
  void _openShuoFile(BuildContext context, Media m) {
    if (m.mime.startsWith('image')) return openImage(context, m.filePath);
    if (m.mime.startsWith('video')) return openVideo(context, m.filePath);
    if (m.mime.startsWith('audio')) {
      return openAudio(context, m.filePath, title: m.name);
    }
    final readable = openIfReadable(context, m.filePath);
    if (readable) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          ListTile(
            leading: Icon(Icons.insert_drive_file, color: AppTheme.clay),
            title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('无法在应用内预览此格式',
                style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.ios_share, color: AppTheme.clay),
            title: const Text('导出 / 分享到手机'),
            onTap: () {
              Navigator.pop(sheetCtx);
              ShareX.one(m.filePath, name: m.name);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (medias.isEmpty) return const SizedBox.shrink();
    final types = medias.map((m) => m.type).toSet();
    final isAllFiles =
        types.every((t) => t == 'file' || t == 'audio') &&
            medias.length <= 3;

    Widget tile(Media m) {
      if (m.type == 'image') {
        return GestureDetector(
          onTap: () => _openVisual(context, m),
          onLongPress: () => ShareX.one(m.filePath, name: m.name),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(File(m.filePath), fit: BoxFit.cover,
                width: double.infinity, height: double.infinity),
          ),
        );
      }
      if (m.type == 'video' || m.type == 'livephoto') {
        return GestureDetector(
          onTap: () => _openVisual(context, m),
          onLongPress: () => ShareX.one(m.filePath, name: m.name),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(fit: StackFit.expand, children: [
              VideoCover(video: m.filePath, thumb: m.thumb),
              const Center(
                child: Icon(Icons.play_circle_fill,
                    color: Colors.white70, size: 42),
              ),
              if (m.type == 'livephoto')
                const Positioned(
                  left: 6, bottom: 6,
                  child: Icon(Icons.motion_photos_on,
                      color: Colors.white70, size: 16),
                ),
            ]),
          ),
        );
      }
      // 文件
      return GestureDetector(
        onTap: () {
          if (m.mime.startsWith('image')) {
            openImage(context, m.filePath);
          } else if (m.mime.startsWith('video')) {
            openVideo(context, m.filePath);
          } else {
            _openShuoFile(context, m);
          }
        },
        onLongPress: () => ShareX.one(m.filePath, name: m.name),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.bgDeep.withOpacity( 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            isApkName(m.name)
                ? ApkCover(path: m.filePath, size: 30, radius: 5)
                : Icon(Icons.insert_drive_file, color: AppTheme.clay),
            const SizedBox(width: 8),
            Expanded(
              child: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
            ),
          ]),
        ),
      );
    }

    // 单条媒体（图片/视频）自适应
    if (medias.length == 1 &&
        (medias.first.type == 'image' ||
            medias.first.type == 'video' ||
            medias.first.type == 'livephoto')) {
      return (medias.first.type == 'image')
          ? AspectRatio(
              aspectRatio: 1.4,
              child: tile(medias.first),
            )
          : GestureDetector(
              onTap: () => _openSingle(context, medias.first),
              onLongPress: () => ShareX.one(medias.first.filePath, name: medias.first.name),
              child: AdaptiveVideoCover(
                  video: medias.first.filePath, thumb: medias.first.thumb),
            );
    }

    if (isAllFiles) {
      return Column(children: medias.map(tile).toList());
    }

    return GridView.count(
      crossAxisCount: medias.length == 1 ? 1 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
      children: medias.map(tile).toList(),
    );
  }
}