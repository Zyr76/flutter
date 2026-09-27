import 'package:flutter/material.dart';

/// 根据文件名/路径，返回该文件类型的图标与配色（图片/视频交给各自的封面组件，
/// 这里只处理“普通文件”的通用视觉）。
({IconData icon, Color color, String label}) fileKindOf(String name, String mime) {
  final e = name.contains('.')
      ? name.split('.').last.toLowerCase()
      : '';
  if (mime.startsWith('audio/')) {
    return (icon: Icons.music_note, color: const Color(0xFF4C8C6A), label: '音频');
  }
  switch (e) {
    case 'apk':
      return (icon: Icons.android, color: const Color(0xFF3FA14B), label: 'APK');
    case 'pdf':
      return (icon: Icons.picture_as_pdf, color: const Color(0xFFD24B42), label: 'PDF');
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
      return (icon: Icons.folder_zip, color: const Color(0xFFE0A325), label: '压缩包');
    case 'doc':
    case 'docx':
      return (icon: Icons.description, color: const Color(0xFF3B6FB5), label: '文档');
    case 'xls':
    case 'xlsx':
    case 'csv':
      return (icon: Icons.table_chart, color: const Color(0xFF3E9B4F), label: '表格');
    case 'ppt':
    case 'pptx':
    case 'key':
      return (icon: Icons.slideshow, color: const Color(0xFFE07A2F), label: '演示');
    case 'txt':
    case 'md':
    case 'log':
      return (icon: Icons.article, color: const Color(0xFF8A8178), label: '文本');
    case 'html':
    case 'htm':
      return (icon: Icons.language, color: const Color(0xFFD2644C), label: '网页');
    case 'json':
    case 'xml':
      return (icon: Icons.data_object, color: const Color(0xFF6A7FA8), label: '数据');
    case 'mp3':
    case 'wav':
    case 'flac':
    case 'm4a':
    case 'aac':
      return (icon: Icons.music_note, color: const Color(0xFF4C8C6A), label: '音频');
    default:
      return (icon: Icons.insert_drive_file, color: const Color(0xFF9A8065), label: '文件');
  }
}