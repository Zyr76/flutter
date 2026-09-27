import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 应用私有目录内的文件管理。
/// 所有媒体/资料都保存在应用自身的数据目录，导出时通过分享面板送出副本。
class Storage {
  Storage._();

  static Directory? _root;

  /// 应用私有目录根
  static Future<Directory> root() async {
    if (_root != null) return _root!;
    final dir = await getApplicationDocumentsDirectory();
    _root = dir;
    return dir;
  }

  /// 判断路径是否已在应用私有目录内（用于复用，避免重复复制）
  static Future<bool> isInApp(String path) async {
    final r = await root();
    return path.startsWith(r.path);
  }

  /// 若路径不在应用目录则导入，否则原样返回
  static Future<String> ensureInApp(String src, String sub, String name) async {
    if (await isInApp(src)) return src;
    final dir = await userDir(0, sub);
    final abs = '${dir.path}/$name';
    await File(src).copy(abs);
    return abs;
  }

  /// 把文件复制进应用私有目录并实时回报复制进度（0.0~1.0，便于导入进度条）。
  /// 已在应用目录内时直接返回原路径，不产生复制，进度一次性置 1.0。
  static Future<String> copyWithProgress(
    String srcPath,
    String sub,
    String name,
    void Function(double progress) onProgress,
  ) async {
    if (await isInApp(srcPath)) {
      onProgress(1.0);
      return srcPath;
    }
    final dir = await userDir(0, sub);
    final abs = '${dir.path}/$name';
    final src = File(srcPath);
    final total = src.lengthSync();
    final ws = File(abs).openWrite();
    try {
      int copied = 0;
      await for (final chunk in src.openRead()) {
        ws.add(chunk);
        copied += chunk.length;
        if (total > 0) onProgress((copied / total).clamp(0.0, 1.0));
      }
      await ws.flush();
    } finally {
      await ws.close();
    }
    onProgress(1.0);
    return abs;
  }

  /// 按用户划分的目录
  static Future<Directory> userDir(int userId, [String? sub]) async {
    final r = await root();
    final base = Directory('${r.path}/users/$userId${sub == null ? '' : '/$sub'}');
    if (!base.existsSync()) base.createSync(recursive: true);
    return base;
  }

  static String newName(String ext) {
    final t = DateTime.now().microsecondsSinceEpoch;
    final r = Random().nextInt(99999);
    return '$t$r.$ext';
  }

  /// 把某个来源文件复制进应用私有目录，返回绝对路径
  static Future<String> import(String srcPath, String sub, {String? name}) async {
    final src = File(srcPath);
    if (!src.existsSync()) throw Exception('文件不存在');
    final dir = await userDir(0, sub); // 目录可复用为共享子目录
    final safe = name ?? src.uri.pathSegments.last;
    final abs = '${dir.path}/$safe';
    await src.copy(abs);
    return abs;
  }

  /// 把字节写入子目录
  static Future<String> writeBytes(Uint8List bytes, String sub, String name) async {
    final dir = await userDir(0, sub);
    final abs = '${dir.path}/$name';
    final f = File(abs);
    await f.writeAsBytes(bytes);
    return abs;
  }

  /// 当前用户的私有目录（按 user 分）对外可用，导出时用独立共享子目录即可
  static Future<Directory> sharedDir(String sub) => userDir(0, sub);

  static Future<void> delete(String? absPath) async {
    if (absPath == null || absPath.isEmpty) return;
    final f = File(absPath);
    if (f.existsSync()) await f.delete();
  }

  static Future<String> printable(int sizeBytes) async {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}