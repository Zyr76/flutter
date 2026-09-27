import 'package:share_plus/share_plus.dart';

import '../models.dart';
import 'package:intl/intl.dart';

/// 导出 / 分享
class ShareX {
  ShareX._();
  static final _fmt = DateFormat('yyyy-MM-dd HH:mm');

  /// 导出说说：文本快照 + 媒体文件
  static Future<void> exportShuoshuo(Shuoshuo s, List<Media> media) async {
    final buf = StringBuffer();
    buf.write(_fmt.format(DateTime.fromMillisecondsSinceEpoch(s.createdAt)));
    if (s.location.isNotEmpty) buf.write(' · ${s.location}');
    buf.writeln();
    buf.writeln();
    if (s.content.isNotEmpty) buf.writeln(s.content);

    final files = media
        .map((m) => XFile(m.filePath, name: m.name.isEmpty ? m.filePath.split('/').last : m.name))
        .toList();

    if (files.isEmpty) {
      await Share.share(buf.toString());
    } else {
      await Share.shareXFiles(files, text: buf.toString());
    }
  }

  /// 导出任意单个文件
  static Future<void> one(String path, {String? name}) async {
    final n = name ?? path.split('/').last;
    await Share.shareXFiles([XFile(path, name: n)]);
  }
}