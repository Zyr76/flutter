import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

String _textExt(RegExp keepText) {
  return keepText.stringMatch('_') ?? '';
}

// 复刻 pack 逻辑：文本压缩，媒体 STORE
List<int> _pack(Directory root, String tmpDb, String dbName) {
  final archive = Archive();
  final tmp = File(tmpDb);
  archive.addFile(ArchiveFile(dbName, tmp.lengthSync(), tmp.readAsBytesSync()));

  final files = <File>[];
  final rels = <String>[];
  void walk(Directory dir, String relDir) {
    for (final e in dir.listSync(followLinks: false)) {
      final name = p.basename(e.path);
      if (e is Directory) {
        walk(e, relDir.isEmpty ? name : '$relDir/$name');
      } else if (e is File && !name.startsWith('.migration_')) {
        files.add(e);
        rels.add(relDir.isEmpty ? name : '$relDir/$name');
      }
    }
  }

  walk(root, 'data');

  for (var i = 0; i < files.length; i++) {
    final f = files[i];
    final rel = rels[i];
    final len = f.lengthSync();
    final e = rel.split('.').last.toLowerCase();
    final isText = RegExp(r'^(db|txt|md|json|xml|html|css|js|log|csv|ini|cfg|srt|url)$')
        .hasMatch(e);
    if (isText) {
      archive.addFile(ArchiveFile(rel, len, f.readAsBytesSync()));
    } else {
      archive.addFile(ArchiveFile.noCompress(rel, len, f.readAsBytesSync()));
    }
  }
  final zipBytes = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipBytes!);
}

// 复刻 import 逻辑
void _extract(List<int> zip, String rootPath, String dbName) {
  final archive = ZipDecoder().decodeBytes(zip);
  final dbEntry = archive.files.firstWhere((f) => f.name == dbName);
  File('${rootPath}/_restored_db').writeAsBytesSync(dbEntry.content, flush: true);
  final dataFiles = archive.files
      .where((f) => f.isFile && f.name.startsWith('data/'))
      .toList();
  for (final f in dataFiles) {
    stdout.writeln('  entry: ${f.name}  compress=${f.isCompressed}');
    final safe = f.name
        .substring('data/'.length)
        .split('/')
        .where((s) => s.isNotEmpty && s != '..' && s != '.')
        .join('/');
    if (safe.isEmpty) continue;
    final target = File(p.join(rootPath, safe));
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(f.content, flush: true);
  }
}

void main() {
  final root = Directory.systemTemp.createTempSync('rt_');
  final rootPath = root.path;
  try {
    // 造数据：jpg（随机字节）、mp4、文本、嵌套文件名
    final mediaDir = '${rootPath}/users/0/media';
    Directory(mediaDir).createSync(recursive: true);
    final jpg = Uint8List.fromList(
        List<int>.generate(300000, (i) => i % 97)); // JPEG-ish raw bytes
    File('$mediaDir/pic.jpg').writeAsBytesSync(jpg);
    final mp4 = Uint8List.fromList(
        List<int>.generate(2 * 1024 * 1024, (i) => (i * 13) % 251));
    File('$mediaDir/vid.mp4').writeAsBytesSync(mp4);
    File('${rootPath}/users/0/notes/text.txt').parent.createSync(recursive: true);
    File('${rootPath}/users/0/notes/text.txt').writeAsStringSync('hello 中文');
    // db
    final dummyDb = '${rootPath}/.migration_tmp.db';
    File(dummyDb).writeAsStringSync('FAKEDB\r\nline2');

    // round trip
    final zip = _pack(root, dummyDb, 'private_space.db');
    final restored = Directory.systemTemp.createTempSync('rt2_');
    final restPath = restored.path;
    try {
      _extract(zip, restPath, 'private_space.db');

      final jpgBytes = File('$restPath/users/0/media/pic.jpg').existsSync()
          ? File('$restPath/users/0/media/pic.jpg').readAsBytesSync()
          : Uint8List(0);
      stdout.writeln('restored pic exists=${File('$restPath/users/0/media/pic.jpg').existsSync()} len=${jpgBytes.length}');
      final okJpg = jpgBytes.length == jpg.length &&
          _hexEquals(jpgBytes, jpg);
      final okMp4 = File('$restPath/users/0/media/vid.mp4').existsSync() &&
          _hexEquals(File('$restPath/users/0/media/vid.mp4').readAsBytesSync(), mp4);
      final okTxt = File('$restPath/users/0/notes/text.txt').existsSync() &&
          File('$restPath/users/0/notes/text.txt').readAsStringSync() == 'hello 中文';

      stdout.writeln('pic.jpg 完整: $okJpg  实际=${File('$restPath/users/0/media/pic.jpg').lengthSync()}B 期望=${jpg.length}B');
      stdout.writeln('vid.mp4 完整: $okMp4  实际=${File('$restPath/users/0/media/vid.mp4').lengthSync()}B');
      stdout.writeln('text.txt 完整: $okTxt');
    } finally {
      restored.deleteSync(recursive: true);
    }
  } finally {
    root.deleteSync(recursive: true);
  }
}

bool _hexEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}