import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/share.dart';
import '../theme.dart';

/// 判断某个扩展名是否属于“可阅读”的文本 / 代码 / 标记格式
const _readableExt = {
  'txt', 'text', 'log', 'md', 'markdown', 'json', 'xml', 'html', 'htm',
  'yaml', 'yml', 'ini', 'cfg', 'conf', 'toml', 'csv', 'tsv', 'srt', 'vtt',
  'sql', 'css', 'scss', 'py', 'dart', 'js', 'jsx', 'ts', 'tsx', 'java',
  'c', 'h', 'cpp', 'hpp', 'cs', 'go', 'rs', 'rb', 'php', 'sh', 'bash',
  'bat', 'ps1', 'lua', 'kt', 'kts', 'swift', 'r', 'm', 'pl', 'perl',
  'properties', 'env', 'gitignore',
};

bool isReadableExt(String path) {
  final e = path.split('.').last.toLowerCase();
  return _readableExt.contains(e);
}

/// 打开可阅读文件（文本 / 代码 / 标记格式）。
/// 若无法识别为可阅读格式，返回 false 交给调用方走导出逻辑。
bool openIfReadable(BuildContext context, String path) {
  final isReadable = isReadableExt(path);
  if (isReadable) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => FileViewerPage(path: path)));
  }
  return isReadable;
}

/// 应用内阅读器：以纯文本形式展示可读文件内容
class FileViewerPage extends StatefulWidget {
  final String path;
  final String? title;
  const FileViewerPage({Key? key, required this.path, this.title})
      : super(key: key);

  @override
  State<FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends State<FileViewerPage> {
  String? _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _text = await _readText();
    } catch (e) {
      if (mounted) setState(() => _error = '读取失败：$e');
      return;
    }
    if (mounted) setState(() {});
  }

  Future<String> _readText() async {
    final bytes = await File(widget.path).readAsBytes();
    // 优先 UTF-8，非法字节用替换字符宽松解码；解码结果非空则直接采用
    final decoded = utf8.decode(bytes, allowMalformed: true);
    if (decoded.trim().isNotEmpty) return decoded;
    return SystemEncoding().decode(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.title ?? widget.path.split('/').last;
    return Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '导出 / 分享',
            onPressed: () => ShareX.one(widget.path, name: name),
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, color: AppTheme.error, size: 48),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.inkSoft)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => ShareX.one(widget.path),
              icon: const Icon(Icons.ios_share),
              label: const Text('导出该文件'),
            ),
          ]),
        ),
      );
    }
    if (_text == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      width: double.infinity,
      color: AppTheme.bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
        child: SelectableText(
          _text!,
          style: TextStyle(
            color: AppTheme.ink,
            fontSize: 14,
            height: 1.6,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}