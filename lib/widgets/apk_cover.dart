import 'dart:io';

import 'package:flutter/material.dart';

import '../services/thumbnail.dart';

/// APK 应用图标封面：异步解析 APK 的真实 app 图标，并做进程内缓存。
/// 解析失败/进行中回退显示安卓机器人图标占位。
/// 空间文件、说说媒体、分享预览等所有展示 APK 的场景统一使用本组件。
class ApkCover extends StatefulWidget {
  final String path;
  final double size;
  final double radius;
  const ApkCover({Key? key, required this.path, this.size = 42, this.radius = 6})
      : super(key: key);
  @override
  State<ApkCover> createState() => _ApkCoverState();
}

class _ApkCoverState extends State<ApkCover> {
  static final Map<String, String?> _cache = {};
  String? _cover;

  static String? cached(String path) => _cache[path];

  @override
  void initState() {
    super.initState();
    final hit = _cache.containsKey(widget.path);
    if (hit) {
      _cover = _cache[widget.path];
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final c = await Thumbs.forApk(widget.path);
    _cache[widget.path] = c;
    if (mounted && _cover != c) setState(() => _cover = c);
  }

  @override
  Widget build(BuildContext context) {
    final c = _cover;
    if (c != null && c.isNotEmpty && File(c).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: Image.file(File(c),
            width: widget.size, height: widget.size, fit: BoxFit.cover),
      );
    }
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
          color: const Color(0xFF3FA14B).withOpacity(0.12),
          borderRadius: BorderRadius.circular(widget.radius)),
      child: Icon(Icons.android,
          color: const Color(0xFF3FA14B), size: widget.size * 0.52),
    );
  }
}

/// 判断文件名是否为 APK
bool isApkName(String name) => name.toLowerCase().endsWith('.apk');