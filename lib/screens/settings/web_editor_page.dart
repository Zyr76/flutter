import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/lan_server.dart';
import '../../services/lan_settings.dart';
import '../../theme.dart';
import '../lan_preview_page.dart';

/// 局域网空间网页源码编辑器。
/// 编辑「整页 HTML」（fullPageHtml），非空时会完全替换内置主页；
/// 保存后局域网访问立即生效，也可在 App 内预览效果。
class WebEditorPage extends StatefulWidget {
  const WebEditorPage({Key? key}) : super(key: key);

  @override
  State<WebEditorPage> createState() => _WebEditorPageState();
}

class _WebEditorPageState extends State<WebEditorPage> {
  late final TextEditingController _ctrl;
  bool _loading = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final v = LanSettings.instance.fullPageHtml;
    if (mounted) {
      setState(() {
        // 尚无自定义源码时，预填一份可用的默认完整 HTML，便于直接修改。
        _ctrl.text = v.trim().isEmpty ? _defaultHtml() : v;
        _loading = false;
      });
    }
  }

  /// 默认整页 HTML 模板：完整可运行，含说明和最小样式。
  String _defaultHtml() {
    return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>我的空间</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:-apple-system,"PingFang SC","Microsoft YaHei",sans-serif;
       background:#f7f4ee;color:#332e28;min-height:100vh}
  .wrap{max-width:680px;margin:0 auto;padding:24px 16px 60px}
  header h1{color:#be7e5a;font-size:22px;margin-bottom:4px}
  header p{color:#7a7268;font-size:13px;margin-bottom:20px}
  .card{background:#fff;border:1px solid #ece4d6;border-radius:16px;
        padding:16px;margin-bottom:14px}
  .card h2{font-size:15px;margin-bottom:8px}
  .card p{font-size:14px;line-height:1.75;color:#5a534a}
</style>
</head>
<body>
  <div class="wrap">
    <header>
      <h1>我的空间</h1>
      <p>这是一个用「自定义网页（源码）」编辑出来的网页。</p>
    </header>
    <div class="card">
      <h2>说说</h2>
      <p id="ss">…</p>
    </div>
  </div>
  <script>
    // 公共函数 spaceBase() / apiUrl() 已自动注入，无需硬编码地址和端口。
    fetch(apiUrl('/api/shuoshuo'))
      .then(r => r.json())
      .then(list => {
        var el = document.getElementById('ss');
        if (!el) return;
        el.textContent = (list.length ? list.map(s => s.content).join(' | ')
                                       : '暂无说说');
        el.textContent += '（访问地址：' + spaceBase() + '）';
      })
      .catch(e => console.log(e));
  </script>
</body>
</html>
''';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _hasCustom => _ctrl.text.trim().isNotEmpty;

  Future<void> _save() async {
    final v = _ctrl.text;
    await LanSettings.instance.setFullPageHtml(v);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_hasCustom ? '已保存，局域网访问立即生效' : '已清空，恢复为内置默认网页'),
      duration: const Duration(seconds: 2),
    ));
    setState(() => _dirty = false);
  }

  Future<void> _resetDefault() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('恢复默认网页？'),
        content: const Text('将清空整页 HTML 源码，局域网网页恢复为软件内置的默认样式。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _ctrl.text = '');
    await _save();
  }

  Future<void> _preview() async {
    // 预览前先保存，保证看到的是最新源码
    await LanSettings.instance.setFullPageHtml(_ctrl.text);
    final srv = LanServer.instance;
    if (!srv.running) await srv.start();
    final target = await srv.lanAddress();
    if (!mounted || target == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LanPreviewPage(url: target, isLan: true),
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _ctrl.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('源码已复制')));
  }

  /// 将源码替换为一份带注释的最小可用骨架，方便从头写起。
  Future<void> _insertSnippet() async {
    final newText =
        _ctrl.text.trim().isEmpty ? _snippet() : '$_ctrl.text\n\n${_snippet()}';
    setState(() => _ctrl.text = newText);
  }

  String _snippet() {
    return '''
<!-- 在这里编写你的整页 HTML/CSS/JS，保存后局域网访问即为你的网页。
     可通过 fetch('/api/xxx') 读取空间数据（见「开发文档」）。 -->
<style>
  body{font-family:sans-serif;background:#f7f4ee;color:#332e28;margin:0}
  .wrap{max-width:680px;margin:40px auto;padding:0 16px}
  h1{color:#be7e5a}
</style>
<div class="wrap">
  <h1>My Space</h1>
  <p>这是我的自定义网页。</p>
</div>
<script>
  // fetch('/api/shuoshuo').then(r=>r.json()).then(console.log);
</script>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自定义网页（源码）'),
        actions: [
          IconButton(
              tooltip: '预览',
              onPressed: _hasCustom ? _preview : null,
              icon: const Icon(Icons.remove_red_eye_outlined)),
          IconButton(
              tooltip: '复制',
              onPressed: _copy,
              icon: const Icon(Icons.copy_outlined)),
          IconButton(
              tooltip: '保存',
              onPressed: _dirty ? _save : null,
              icon: const Icon(Icons.check)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Container(
                width: double.infinity,
                color: AppTheme.surface,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(children: [
                  Icon(_hasCustom ? Icons.code : Icons.code_off,
                      size: 15, color: AppTheme.inkSoft),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _hasCustom
                          ? '整页 HTML 已启用（非空时替换默认网页）'
                          : '未启用自定义网页，使用内置默认网页',
                      style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                    ),
                  ),
                  TextButton(
                    onPressed: _insertSnippet,
                    child: const Text('插入模板'),
                  ),
                  TextButton(
                    onPressed: _hasCustom ? _resetDefault : null,
                    child: Text(_hasCustom ? '恢复默认' : '已默认',
                        style: TextStyle(
                            color: _hasCustom
                                ? AppTheme.error
                                : AppTheme.inkSoft)),
                  ),
                ]),
              ),
              // 代码编辑区：等宽字体，可横向滚动，行数不限
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: AppTheme.bgDeep,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: TextField(
                      controller: _ctrl,
                      maxLines: null,
                      expands: false,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.5,
                        color: AppTheme.ink,
                      ),
                      cursorColor: AppTheme.clay,
                      onChanged: (_) {
                        if (!_dirty) setState(() => _dirty = true);
                      },
                      decoration: InputDecoration(
                        hintText:
                            '在此填写整页 HTML（<html>-<body> 均需包含）。\n\n示例见「插入模板」。',
                        hintStyle: TextStyle(
                            color: AppTheme.inkSoft.withOpacity(0.6),
                            fontFamily: 'monospace',
                            fontSize: 13),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
              ),
            ]),
    );
  }
}