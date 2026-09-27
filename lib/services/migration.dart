import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../db.dart';
import '../storage.dart';

/// 空间数据迁移：把整个空间（账号数据库 + 全部媒体/文件）压缩导出，
/// 或从备份包恢复数据（用于换机 / 备份还原）。
///
/// 备份包结构：
///  - private_space.db        数据库（通过 VACUUM INTO 安全快照）
///  - data/…                  应用私有目录下的全部文件（媒体、头像、背景等）
///
/// 导出 / 导入中"遍历文件 + 压缩 / 解压 + 写盘"等重活在子隔离区（Isolate）里完成，
/// 并通过端口把进度回传主隔离区，从而保证大量文件时界面不卡顿。
class MigrationService {
  MigrationService._();
  static final MigrationService instance = MigrationService._();

  static const _dbFileName = 'private_space.db';

  /// 导出整个空间为一个 zip 备份，返回最终保存路径。
  /// [onProgress] 会在主隔离区被回调 0~1，用于更新进度条。
  Future<String> export({void Function(double)? onProgress}) async {
    final root = await Storage.root();
    // 1. 数据库一致性快照（sqflite 需在主隔离区执行，速度通常较快）
    final db = await Db.instance.db;
    final tmpDb = p.join(root.path, '.migration_tmp.db');
    final tmpDbFile = File(tmpDb);
    if (tmpDbFile.existsSync()) await tmpDbFile.delete();
    await db.rawQuery('VACUUM INTO "$tmpDb"');

    // 2. 打包（子隔离区执行，避免卡住主界面）
    final zipBytes =
        await _packInIsolate(root.path, tmpDb, _dbFileName, onProgress);
    await tmpDbFile.delete();
    onProgress?.call(1.0);

    // 3. 写盘（下载目录）
    return _saveToDownloads(zipBytes, _backupName());
  }

  /// 在子隔离区里完成"遍历文件 + 打 zip 压缩包"。
  /// 主隔离区通过端口接收进度（double）与最终结果（Uint8List）。
  Future<Uint8List> _packInIsolate(
    String rootPath,
    String tmpDb,
    String dbName,
    void Function(double)? onProgress,
  ) async {
    final port = ReceivePort();
    final done = Completer<Uint8List>();
    port.listen((msg) {
      if (msg is double) {
        onProgress?.call(msg);
      } else if (msg is Uint8List) {
        if (!done.isCompleted) {
          port.close();
          done.complete(msg);
        }
      } else if (msg is String) {
        if (!done.isCompleted) {
          port.close();
          done.completeError(Exception(msg));
        }
      }
    }, onError: (Object e, StackTrace st) {
      if (!done.isCompleted) done.completeError(e);
    });
    await Isolate.spawn(_packEntry, {
      'root': rootPath,
      'tmpDb': tmpDb,
      'dbName': dbName,
      'port': port.sendPort,
    });
    return done.future;
  }

  static void _packEntry(Map args) async {
    final SendPort _port = args['port'] as SendPort;
    void send(dynamic m) => _port.send(m);
    final root = args['root'] as String;
    final tmpDb = args['tmpDb'] as String;
    final dbName = args['dbName'] as String;
    try {
      final archive = Archive();
      // 数据库条目（放最前，进度起点）
      final tmp = File(tmpDb);
      archive.addFile(
          ArchiveFile(dbName, tmp.lengthSync(), tmp.readAsBytesSync()));
      send(0.05);

      // 第一遍：收集要打包的文件（保留相对路径）并统计总字节，用于进度
      final files = <File>[];
      final rels = <String>[];
      var totalBytes = 0;
      void walk(Directory dir, String relDir) {
        for (final e in dir.listSync(followLinks: false)) {
          // 注意不能用 e.uri.pathSegments.last：目录 URI 末尾带 /，会得到空段，
          // 导致嵌套目录名全部坍缩成 ///，最终按错误路径导入（媒体损坏）。
          final name = p.basename(e.path);
          if (e is Directory) {
            walk(e, relDir.isEmpty ? name : '$relDir/$name');
          } else if (e is File && !name.startsWith('.migration_')) {
            files.add(e);
            rels.add(relDir.isEmpty ? name : '$relDir/$name');
            totalBytes += e.lengthSync();
          }
        }
      }

      walk(Directory(root), 'data');

      // 第二遍：逐文件写入压缩包，按字节比例回传进度。
      // 关键提速：图片/视频等本身已是压缩数据，直接 STORE（不重新 deflate），
      // 仅对文本类（db/txt/json…）做压缩，大幅降低 CPU 开销。
      const start = 0.05, end = 0.98;
      var addedBytes = 0;
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        final rel = rels[i];
        final len = f.lengthSync();
        if (_shouldStore(rel)) {
          archive.addFile(ArchiveFile.noCompress(rel, len, f.readAsBytesSync()));
        } else {
          archive.addFile(ArchiveFile(rel, len, f.readAsBytesSync()));
        }
        addedBytes += len;
        if (i % 8 == 0 || i == files.length - 1) {
          final prog = totalBytes == 0
              ? end
              : start + (end - start) * (addedBytes / totalBytes);
          send(prog.clamp(start, end));
        }
      }
      if (files.isEmpty) send(end);

      final zipBytes = ZipEncoder().encode(archive);
      send(Uint8List.fromList(zipBytes!));
    } catch (e) {
      send('导出失败：$e');
    }
  }

  /// 该文件是否“直接存储（不压缩）”。
  /// 图片/视频/音乐等压缩格式二次压缩收益极低却非常耗时，直接 STORE 可大幅提速。
  /// 文本类（db/txt/json 等）保留 deflate 压缩以减小体积。
  static bool _shouldStore(String name) {
    final e = name.split('.').last.toLowerCase();
    return !RegExp(r'^(db|txt|md|json|xml|html|css|js|log|csv|ini|cfg|srt|url)$')
        .hasMatch(e);
  }

  String _backupName() {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
    return '私密空间备份_$stamp.zip';
  }

  /// 优先写入「手机下载目录」，失败则退回应用自己的下载目录。
  Future<String> _saveToDownloads(Uint8List bytes, String filename) async {
    // 直接写公共下载目录（旧系统 / 已授权场景）
    for (final base in ['/storage/emulated/0/Download', '/sdcard/Download']) {
      try {
        final d = Directory(base);
        if (await d.exists()) {
          final f = File('$base/$filename');
          await f.writeAsBytes(bytes, flush: true);
          return f.path;
        }
      } catch (_) {}
    }
    // 应用专属下载目录（新系统沙盒，无需权限）
    try {
      final d = await getDownloadsDirectory();
      if (d != null) {
        await d.create(recursive: true);
        final f = File(p.join(d.path, filename));
        await f.writeAsBytes(bytes, flush: true);
        return f.path;
      }
    } catch (_) {}
    // 最后退回应用私有目录并开放分享由用户保存
    final root = await Storage.root();
    final dir = Directory(p.join(root.path, 'exports'));
    await dir.create(recursive: true);
    final f = File(p.join(dir.path, filename));
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  /// 从备份 zip 恢复整个空间。
  /// 成功返回可登录的账号列表；失败抛异常。
  /// [onProgress] 在主隔离区回调 0~1，用于展示导入进度。
  Future<List<String>> import(
      String zipPath, {void Function(double)? onProgress}) async {
    // 1. 在主隔离区关闭当前数据库（sqflite 需在主线程）
    await Db.instance.close();

    final root = await Storage.root();
    final dbPath = p.join(await getDatabasesPath(), _dbFileName);
    // 2. 解压 + 写盘在子隔离区完成，避免大备份卡顿
    await _extractInIsolate(zipPath, dbPath, root.path, _dbFileName, onProgress);

    // 3. 重建连接并返回可登录账号
    await Db.instance.db;
    return Db.instance.userNames();
  }

  Future<void> _extractInIsolate(
      String zipPath,
      String dbPath,
      String rootPath,
      String dbName,
      void Function(double)? onProgress) async {
    final port = ReceivePort();
    final done = Completer<void>();
    port.listen((msg) {
      if (msg is double) {
        onProgress?.call(msg);
        return;
      }
      if (!done.isCompleted) {
        port.close();
        if (msg is String) {
          done.completeError(Exception(msg));
        } else {
          done.complete();
        }
      }
    }, onError: (Object e, StackTrace st) {
      if (!done.isCompleted) done.completeError(e);
    });
    await Isolate.spawn(_extractEntry, {
      'zip': zipPath,
      'dbPath': dbPath,
      'root': rootPath,
      'dbName': dbName,
      'port': port.sendPort,
    });
    await done.future;
  }

  static void _extractEntry(Map args) async {
    final SendPort _port = args['port'] as SendPort;
    void send(dynamic m) => _port.send(m);
    final zip = args['zip'] as String;
    final dbPath = args['dbPath'] as String;
    final rootPath = args['root'] as String;
    final dbName = args['dbName'] as String;
    try {
      final Archive archive;
      try {
        final bytes = await File(zip).readAsBytes();
        archive = ZipDecoder().decodeBytes(bytes);
      } catch (_) {
        send('无法解析备份包，请确认选择了正确的 .zip 文件');
        return;
      }
      final dbEntry =
          archive.files.firstWhereOrNull((f) => f.name == dbName);
      if (dbEntry == null) {
        send('备份包不是有效的账号备份（缺少数据库）');
        return;
      }
      // 写数据库文件
      final dbFile = File(dbPath);
      await dbFile.parent.create(recursive: true);
      await dbFile.writeAsBytes(dbEntry.content, flush: true);
      send(0.15);

      // 清理旧的私有目录内容，再恢复文件
      final rootDir = Directory(rootPath);
      if (rootDir.existsSync()) {
        for (final e in rootDir.listSync(followLinks: false)) {
          try {
            if (e is Directory) {
              await e.delete(recursive: true);
            } else if (e is File) {
              await e.delete();
            }
          } catch (_) {}
        }
      }

      // 只处理 data/ 下的条目，并过滤掉不安全文件名
      final dataFiles = archive.files
          .where((f) => f.isFile && f.name.startsWith('data/'))
          .toList();
      if (dataFiles.isEmpty) {
        send(true);
        return;
      }
      const s0 = 0.15, s1 = 1.0;
      for (var i = 0; i < dataFiles.length; i++) {
        final f = dataFiles[i];
        // 防越权：去掉首尾空、前导 “/”，并剔除 “..” “.” 段，防止用
        // “data//xxx” 之类文件名把目标写到根目录（只读）导致导入报错。
        final safe = f.name
            .substring('data/'.length)
            .split('/')
            .where((s) => s.isNotEmpty && s != '..' && s != '.')
            .join('/');
        if (safe.isEmpty) continue;
        final target = File(p.join(rootPath, safe));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(f.content, flush: true);
        if (i % 8 == 0 || i == dataFiles.length - 1) {
          final prog = s0 + (s1 - s0) * ((i + 1) / dataFiles.length);
          send(prog.clamp(s0, s1));
        }
      }
      send(true);
    } catch (e) {
      send('导入失败：$e');
    }
  }
}

/// 简单的 firstWhereOrNull，避免依赖 collection 包。
extension FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}