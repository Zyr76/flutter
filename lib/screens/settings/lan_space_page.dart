import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/lan_server.dart';
import '../../services/lan_settings.dart';
import '../../theme.dart';
import '../lan_preview_page.dart';
import 'web_editor_page.dart';

/// 局域网空间：启动/停止服务器 + 隐私/可见性控制 + 端口/自启动/保持运行。
class LanSpacePage extends StatefulWidget {
  const LanSpacePage({Key? key}) : super(key: key);
  @override
  State<LanSpacePage> createState() => _LanSpacePageState();
}

class _LanSpacePageState extends State<LanSpacePage> {
  String? _url = 'http://192.168.x.x:8787';
  final TextEditingController _portCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _portCtrl.text = LanSettings.instance.port.toString();
    LanSettings.instance.addListener(_onSettings);
    LanServer.instance.addListener(_onServer);
    _loadUrl();
  }

  @override
  void dispose() {
    LanSettings.instance.removeListener(_onSettings);
    LanServer.instance.removeListener(_onServer);
    _portCtrl.dispose();
    super.dispose();
  }

  void _onSettings() {
    if (mounted) {
      _portCtrl.text = LanSettings.instance.port.toString();
      setState(() {});
    }
  }

  void _onServer() {
    if (mounted) {
      _loadUrl();
      setState(() {});
    }
  }

  Future<void> _loadUrl() async {
    final u = await LanServer.instance.lanAddress();
    if (mounted && u != null) setState(() => _url = u);
  }

  Future<void> _applyPort(String raw) async {
    final v = int.tryParse(raw.trim());
    final srv = LanServer.instance;
    if (v == null || v < 1 || v > 65535) {
      setState(() => _portCtrl.text = srv.port.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请输入 1-65535 之间的端口号')));
      }
      return;
    }
    // Android 系统限制：非 root 应用无法绑定 1024 以下的高权限端口，
    // 直接绑定会报 SocketException(Permission denied, errno=13)。
    // 这里提前拦截并提示，避免“改了就报错、重启却显示改好”的困惑。
    if (v < 1024) {
      setState(() => _portCtrl.text = srv.port.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('1024 以下端口需要系统权限，手机上无法使用，请改用 1024-65535'),
            duration: Duration(seconds: 3)));
      }
      return;
    }
    await LanSettings.instance.setPort(v);
    if (!mounted) return;
    if (srv.running) {
      await srv.stop();
      await srv.start();
    } else {
      await _loadUrl();
    }
    if (mounted) {
      final ok = srv.running;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? '端口已切换为 $v，服务已重启'
              : (srv.lastError != null
                  ? '端口 $v 切换失败：${srv.lastError}'
                  : '端口已切换为 $v，点击启动服务器生效')),
          duration: const Duration(seconds: 3)));
    }
  }

  Future<void> _toggle() async {
    final srv = LanServer.instance;
    if (srv.running) {
      await srv.stop();
    } else {
      await srv.start();
    }
  }

  Future<void> _open() async {
    final srv = LanServer.instance;
    final u = _url;
    if (!srv.running) {
      await srv.start();
      await _loadUrl();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('服务器已启动，正在打开预览')));
    }
    final target = await srv.lanAddress() ?? u;
    if (!mounted || target == null) return;
    // 在 App 内嵌预览，方便即时查看编辑效果
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LanPreviewPage(url: target)),
    );
  }

  /// 打开开发文档：面向极客的 HTTP 接口说明，可据此编写自建网页。
  Future<void> _openDocs() async {
    final srv = LanServer.instance;
    if (!srv.running) {
      await srv.start();
      await _loadUrl();
    }
    final target = await srv.lanAddress();
    if (!mounted || target == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LanPreviewPage(url: '$target/docs')),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Text(title,
            style: TextStyle(
                fontSize: 12,
                color: AppTheme.inkSoft,
                fontWeight: FontWeight.w600)),
      );

  Widget _card(List<Widget> children) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.hairline.withOpacity(0.6)),
        ),
        child: Column(children: children),
      );

  Widget _divider() => Divider(height: 1, indent: 54, color: AppTheme.hairline);

  Widget _switchRow({
    required IconData icon,
    required String title,
    required String sub,
    required bool value,
    required Future<void> Function(bool) onChanged,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      secondary: Icon(icon, color: AppTheme.clayDeep, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(sub,
          style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
      value: value,
      activeColor: AppTheme.clay,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final srv = LanServer.instance;
    final ls = LanSettings.instance;
    final running = srv.running;
    return Scaffold(
      appBar: AppBar(title: const Text('局域网空间')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const SizedBox(height: 8),
          // 启动卡片
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [const Color(0xFF51463A), const Color(0xFF2E2A24)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: running ? const Color(0xFF7BD88F) : const Color(0xFF8A8178),
                    boxShadow: running
                        ? [BoxShadow(color: const Color(0xFF7BD88F).withOpacity(0.6), blurRadius: 8)]
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(running ? '服务运行中' : '服务未启动',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_url ?? '',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _open,
                  tooltip: '打开地址',
                  icon: const Icon(Icons.open_in_new, color: Colors.white, size: 22),
                ),
                IconButton(
                  onPressed: () async {
                    if (_url != null) {
                      await Clipboard.setData(ClipboardData(text: _url!));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('地址已复制')));
                      }
                    }
                  },
                  tooltip: '复制地址',
                  icon: const Icon(Icons.copy, color: Colors.white, size: 20),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _portCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: _applyPort,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: '端口号',
                      labelStyle: const TextStyle(color: Colors.white54),
                      hintText: LanSettings.defaultPort.toString(),
                      hintStyle: const TextStyle(color: Colors.white30),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => _applyPort(_portCtrl.text),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black38,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('应用'),
                ),
              ]),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: srv.starting ? null : _toggle,
                  style: FilledButton.styleFrom(
                    backgroundColor: running ? Colors.white : const Color(0xFFBE7E5A),
                    foregroundColor: running ? const Color(0xFF332E28) : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: Icon(running ? Icons.stop : Icons.play_arrow),
                  label: Text(srv.starting ? '启动中…' : (running ? '停止服务器' : '启动服务器'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
          if (srv.lastError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text('启动失败：${srv.lastError}',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text('同一局域网内的设备，在浏览器里打开上面地址，即可浏览你的空间。关闭服务器后他人无法访问。',
                style: TextStyle(fontSize: 12, height: 1.6, color: AppTheme.inkSoft)),
          ),
          // 权限开关
          _section('最高权限'),
          _card([
            _switchRow(
              icon: Icons.lock_outline,
              title: '私密模式',
              sub: '开启后整个空间对外不可见，即使打开预览也看不到任何内容',
              value: ls.private,
              onChanged: (v) => ls.setPrivate(v),
            ),
          ]),
          // 内容可见性
          _section('对外可见内容'),
          _card([
            _switchRow(
              icon: Icons.chat_bubble_outline,
              title: '说说',
              sub: '是否在网页中展示说说的动态与配图',
              value: ls.showShuoshuo,
              onChanged: (v) => ls.setShuoshuo(v),
            ),
            _divider(),
            _switchRow(
              icon: Icons.menu_book_outlined,
              title: '日志',
              sub: '是否在网页中展示日志内容',
              value: ls.showDiary,
              onChanged: (v) => ls.setDiary(v),
            ),
            _divider(),
            _switchRow(
              icon: Icons.photo_library_outlined,
              title: '相册',
              sub: '是否在网页中展示空间相册',
              value: ls.showAlbum,
              onChanged: (v) => ls.setAlbum(v),
            ),
            _divider(),
            _switchRow(
              icon: Icons.folder_outlined,
              title: '文件',
              sub: '是否在网页中展示空间文件并允许下载',
              value: ls.showFile,
              onChanged: (v) => ls.setFile(v),
            ),
          ]),
          // 运行与外观
          _section('运行与外观'),
          _card([
            _switchRow(
              icon: Icons.play_circle_outline,
              title: '开机 / 进入自动启动',
              sub: '打开 App 时自动拉起局域网服务，无需每次手动开启',
              value: ls.autoStart,
              onChanged: (v) => ls.setAutoStart(v),
            ),
            _divider(),
            _switchRow(
              icon: Icons.wb_sunny_outlined,
              title: '保持运行（后台）',
              sub: '熄屏后保持进程与网络在线，局域网内可持续访问',
              value: ls.keepAwake,
              onChanged: (v) async {
                await ls.setKeepAwake(v);
                await LanServer.instance.applyKeepAwake();
              },
            ),
          ]),
          // 开发者
          _section('开发者'),
          _card([
            ListTile(
              leading: Icon(Icons.code, color: AppTheme.clayDeep),
              title: const Text('自定义网页（源码）'),
              subtitle: const Text('编辑整页 HTML/CSS/JS，非空即替换局域网默认网页，保存后立即生效'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WebEditorPage()),
              ),
            ),
            _divider(),
            ListTile(
              leading: Icon(Icons.description_outlined, color: AppTheme.clayDeep),
              title: const Text('开发文档（HTTP API）'),
              subtitle: const Text('接口请求链接与详细说明，可用于编写自己的网页/客户端'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: _openDocs,
            ),
          ]),
        ],
      ),
    );
  }
}