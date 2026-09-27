import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../screens/lan_preview_page.dart';
import '../theme.dart';

/// 把文本中的网页链接自动识别出来，染成主题色 + 下划线，点击可在系统浏览器打开。
/// 用于 App 内的说说 / 日志 / 文件等纯文本展示，与局域网网页的 linkify 行为一致。
class LinkifyText extends StatelessWidget {
  final String text;
  final int maxLines;
  final TextOverflow overflow;
  final TextStyle? style;
  final TextAlign? textAlign;

  const LinkifyText(
    this.text, {
    Key? key,
    this.maxLines = 3,
    this.overflow = TextOverflow.ellipsis,
    this.style,
    this.textAlign,
  }) : super(key: key);

  /// 与网页端一致的 URL 正则：http(s) 开头、常见顶级域裸链接，或自定义 scheme（如 bilibili://）。
  static final RegExp _linkRe = RegExp(
    r'([a-zA-Z][a-zA-Z0-9+.-]*://[^\s<>,;:]+|https?://[^\s<>,;:]+|[a-zA-Z0-9-]+\.(?:com|cn|net|org|io|co|me|gov|edu|vip|top|xyz|info|site|club|fun|online|wang|shop|store|mobi|asia|biz)(?:/[^\s<>,;:]*)?)',
  );

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    final base = (style ?? const TextStyle()).copyWith(
      height: style?.height ?? 1.5,
    );

    final spans = <TextSpan>[];
    var last = 0;
    for (final m in _linkRe.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final raw = m.group(0)!;
      // 自定义 scheme（bilibili:// 等）已含 ://，直接原样打开；
      // 否则裸域名补前缀 http://
      final uri = raw.contains('://') ? raw : 'http://$raw';
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _open(context, uri);
      spans.add(TextSpan(
        text: raw,
        style: base.copyWith(
          color: AppTheme.clay,
          decoration: TextDecoration.underline,
          decorationColor: AppTheme.clay,
        ),
        recognizer: recognizer,
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }

    return Text.rich(
      TextSpan(children: spans, style: base),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }

  /// 点击链接：在 App 内置浏览器中打开（可离线浏览局域网内容）。
  void _open(BuildContext context, String uri) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LanPreviewPage(url: uri)),
    );
  }
}