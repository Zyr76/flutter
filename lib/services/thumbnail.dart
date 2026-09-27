import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../storage.dart';

/// 视频封面 / APK 图标生成
class Thumbs {
  Thumbs._();

  /// 为视频/实况图生成一张封面（jpeg），返回应用私有目录内的绝对路径。
  /// 生成失败返回 null（调用方可回退使用原文件或占位图）。
  static Future<String?> forVideo(String src) async {
    try {
      final dir = await Storage.root();
      final file = await VideoThumbnail.thumbnailFile(
        video: src,
        thumbnailPath: dir.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        quality: 80,
      );
      if (file == null || file.isEmpty) return null;
      // 复制到应用目录下的 thumbs 子目录，避免污染根目录
      return Storage.ensureInApp(file, 'thumbs', Storage.newName('jpg'));
    } catch (_) {
      return null;
    }
  }

  /// 实时截取视频某一帧返回 JPEG 字节（不落盘）。
  /// 用于列表封面：解码后仅缓存在内存里，随用随取，失败返回 null。
  static Future<Uint8List?> videoBytes(String src) =>
      videoBytesAt(src, 0);

  /// 截取视频指定毫秒位置的帧返回 JPEG 字节（不落盘）。
  /// 用于进度条拖拽时的帧预览：实时解码，随用随取，失败返回 null。
  static Future<Uint8List?> videoBytesAt(String src, int timeMs) async {
    try {
      return await VideoThumbnail.thumbnailData(
        video: src,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 480,
        quality: 72,
        timeMs: timeMs,
      );
    } catch (_) {
      return null;
    }
  }

  /// 解析 APK 的应用图标（走原生 MethodChannel，Android 专用）。
  /// 返回应用目录内缓存的图标路径；失败/非 Android 返回 null。
  static Future<String?> forApk(String apkPath) async {
    try {
      // 非 Android 直接放弃
      if (Platform.operatingSystem != 'android') return null;
      // 磁盘缓存：同一 APK 只解析一次
      final root = await Storage.root();
      final base = apkPath.split('/').last;
      final key = 'apk_' + base.hashCode.abs().toRadixString(16) + '.png';
      final dir = Directory('${root.path}/thumbs');
      await dir.create(recursive: true);
      final cached = '${dir.path}/$key';
      if (File(cached).existsSync() && File(cached).lengthSync() > 0) {
        return cached;
      }
      const channel = MethodChannel('privatespace/apk_icon');
      final ok = await channel
          .invokeMethod<bool>('extractIcon', {
            'path': apkPath,
            'out': cached,
          })
          .timeout(const Duration(seconds: 10));
      if (ok == true && File(cached).existsSync() && File(cached).lengthSync() > 0) {
        return cached;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}