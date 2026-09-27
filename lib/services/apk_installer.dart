import 'dart:io';

import 'package:flutter/services.dart';

/// 通过系统安装器安装本地 APK（走原生 MethodChannel，Android 专用）。
class ApkInstaller {
  ApkInstaller._();
  static const MethodChannel _channel = MethodChannel('privatespace/apk_icon');

  /// 唤起系统安装器安装指定路径的 APK。
  /// 返回 true 表示已成功打开安装界面（后续由系统引导完成安装）。
  static Future<bool> install(String path) async {
    if (!File(path).existsSync()) return false;
    if (Platform.isAndroid) {
      try {
        return await _channel.invokeMethod<bool>('installApk', {'path': path}) ??
            false;
      } catch (_) {
        return false;
      }
    }
    return false;
  }
}