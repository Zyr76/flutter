import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/apk_installer.dart';
import '../storage.dart';
import '../theme.dart';
import '../widgets/media.dart';

/// App 内置浏览器。
/// 既能加载局域网空间主页（局域网预览），也能打开说说/任意位置提供的网页链接。
///
/// 完善后的能力（参照主流 Flutter 开源浏览器）：
///  地址栏：当前 URL 展示 + 点击可编辑导航；URL 归一化 + 无网址时自动转搜索；
///          https 显示安全锁标识；聚焦时显示"前往"、失焦显示"刷新"。
///  整页能力：后退 / 前进 / 刷新 / 首页、加载进度、主帧错误重试 + 回到首页；
///  页面内查找（前进/后退高亮定位）；
///  网页图片：长按 → 软件自带图片查看器预览 / 外部打开 / 复制地址（注入 JS 拦截）；
///  下载监听：检测到可下载文件自动下载到 App 内，APK 可直接安装；
///  自定义 scheme：bilibili:// 等交给系统/对应 App 外部打开，不在 WebView 内渲染；
///  菜单：刷新、首页、外部浏览器打开、复制链接、分享、历史（本次会话访问记录）；
///  页面外壳与 WebView 底色随系统/软件浅深色主题自动切换。
class LanPreviewPage extends StatefulWidget {
  final String url;
  final bool isLan;
  const LanPreviewPage({Key? key, required this.url, this.isLan = false})
      : super(key: key);

  @override
  State<LanPreviewPage> createState() => _LanPreviewPageState();
}

class _LanPreviewPageState extends State<LanPreviewPage> {
  static const String _searchEngine = 'https://www.bing.com/search?q=';

  late WebViewController _ctrl;
  late String _address;
  bool _loading = true;
  String? _error;
  double _progress = 0.0;
  bool _canGoBack = false;
  bool _canGoForward = false;

  // 地址栏
  late final TextEditingController _urlCtrl;
  late final FocusNode _urlFocus;
  bool _secure = false; // 当前是否为 https（展示安全锁）

  // 页面内查找
  bool _findVisible = false;
  late final TextEditingController _findCtrl;

  // 本次会话的历史记录（去重）
  final List<String> _history = [];
  String? _lastHistory;

  @override
  void initState() {
    super.initState();
    _address = widget.url;
    _urlCtrl = TextEditingController(text: widget.url);
    _findCtrl = TextEditingController();
    _urlFocus = FocusNode()
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _ctrl = _makeController(widget.url);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _findCtrl.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  WebViewController _makeController(String url) {
    // 自定义 scheme（bilibili://、应用跳转等）无法在 WebView 内渲染，
    // 直接走系统外部打开（调用对应的原生 App）。
    if (!_isWebUrl(url)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openExternalScheme(url);
      });
      return WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(AppTheme.bgDeep);
    }
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.bgDeep)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (u) {
          if (mounted) setState(() {
            _loading = true;
            _error = null;
            _progress = 0.0;
            _canGoBack = false;
            _canGoForward = false;
            _syncUrl(u);
          });
        },
        onProgress: (pp) {
          if (mounted) setState(() => _progress = pp / 100.0);
        },
        onPageFinished: (u) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _progress = 1.0;
            _syncUrl(u);
            _refreshNav();
            _recordHistory(u);
          });
          _injectLongPressImageHook();
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) {
            setState(() {
              _loading = false;
              _error = e.description;
            });
          }
        },
        onNavigationRequest: (req) {
          if (req.isMainFrame) {
            if (_isDownloadUrl(req.url)) {
              _handleDownload(req.url);
              return NavigationDecision.prevent;
            }
            if (!_isWebUrl(req.url)) {
              _openExternalScheme(req.url);
              return NavigationDecision.prevent;
            }
          }
          return NavigationDecision.navigate;
        },
      ))
      ..addJavaScriptChannel('psImage', onMessageReceived: (msg) {
        final src = msg.message.trim();
        if (src.isNotEmpty) _onImageLongPress(src);
      })
      ..loadRequest(Uri.parse(url));
  }

  /// 同步地址栏与安全标识到当前页面 URL
  void _syncUrl(String u) {
    _address = u;
    if (!_urlFocus.hasFocus) {
      _urlCtrl.text = u;
    }
    final s = u.toLowerCase();
    _secure = s.startsWith('https://');
  }

  /// 记录本次会话访问历史（连续去重）
  void _recordHistory(String u) {
    if (u.isEmpty) return;
    if (_lastHistory != u) {
      _lastHistory = u;
      _history.remove(u);
      _history.insert(0, u);
      if (_history.length > 200) _history.removeLast();
    }
  }

  /// 刷新后退/前进按钮可用状态
  void _refreshNav() {
    _ctrl.canGoBack().then((b) {
      _ctrl.canGoForward().then((f) {
        if (mounted && (_canGoBack != b || _canGoForward != f)) {
          setState(() {
            _canGoBack = b;
            _canGoForward = f;
          });
        }
      });
    });
  }

  bool _isWebUrl(String u) {
    final s = u.toLowerCase();
    return s.startsWith('http://') || s.startsWith('https://');
  }

  /// 自定义 scheme（bilibili:// 等）跳转前先弹底部确认框，由用户决定是否前往。
/// 跳转后不关闭内置浏览器，用户从外部应用返回仍停留在原页面。
void _openExternalScheme(String u) {
    _urlFocus.unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppTheme.bgDeep,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.open_in_new,
                      color: AppTheme.clay, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_schemeLabel(u),
                          style: TextStyle(
                              color: AppTheme.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(u,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppTheme.inkSoft, fontSize: 12)),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.inkSoft,
                      side: BorderSide(color: AppTheme.hairline),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      launchUrl(Uri.parse(u),
                          mode: LaunchMode.externalApplication);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.clay,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('前往打开'),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _schemeLabel(String u) {
    final s = u.split('://').first.toLowerCase();
    return switch (s) {
      'bilibili' => 'bilibili 哔哩哔哩',
      'weixin' || 'wechat' => '微信',
      'weibo' => '微博',
      'qq' => 'QQ',
      'taobao' => '淘宝',
      'jd' => '京东',
      'douyin' => '抖音',
      'weidian' => '微店',
      _ => '外部应用',
    };
  }

  void _rebuild(String url) {
    _ctrl = _makeController(url);
    setState(() {
      _error = null;
      _loading = true;
    });
  }

  // ---------- 导航 ----------

  /// URL 归一化 + 搜索兜底：无网址形态的输入自动转搜索引擎
  String _normalizeOrSearch(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return _address;
    final lower = t.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return t;
    if (lower.startsWith('//')) return 'https:$t';
    final ci = t.indexOf(':');
    if (ci > 0) {
      final scheme = t.substring(0, ci);
      if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*$').hasMatch(scheme)) return t;
    }
    // 非网址（含空格 / 无点）：当作搜索词
    if (!t.contains('.') || t.contains(' ')) {
      return _searchEngine + Uri.encodeQueryComponent(t);
    }
    return 'http://$t';
  }

  void _navigateFromField(String raw) {
    final target = _normalizeOrSearch(raw);
    _urlCtrl.text = target;
    _address = target;
    FocusScope.of(context).unfocus();
    _ctrl.loadRequest(Uri.parse(target));
  }

  void _reload() {
    _urlFocus.unfocus();
    _ctrl.reload();
  }

  void _goHome() {
    _urlFocus.unfocus();
    _ctrl.loadRequest(Uri.parse(_address));
  }

  void _goBack() {
    _refreshNav();
    _ctrl.goBack();
  }

  void _goForward() {
    _refreshNav();
    _ctrl.goForward();
  }

  Future<void> _openExternal() async {
    final ok = await launchUrl(Uri.parse(_address),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法打开外部浏览器')));
    }
  }

  void _copyUrl() async {
    await Clipboard.setData(ClipboardData(text: _address));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网址已复制')));
    }
  }

  void _shareUrl() {
    Share.share(_address);
  }

  void _showHistory() {
    _urlFocus.unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: _history.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(40),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.history, size: 44, color: AppTheme.inkSoft),
                  const SizedBox(height: 12),
                  Text('暂无访问记录', style: TextStyle(color: AppTheme.inkSoft)),
                  const SizedBox(height: 60),
                ]),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('历史记录',
                        style: TextStyle(
                            color: AppTheme.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _history.length,
                      itemBuilder: (_, i) {
                        final h = _history[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.public, size: 20),
                          title: Text(h,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            Navigator.pop(context);
                            _address = h;
                            _syncUrl(h);
                            _ctrl.loadRequest(Uri.parse(h));
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
      ),
    );
  }

  // ---------- 页面内查找 ----------

  void _findInPage(String q, {bool backwards = false}) {
    if (q.isEmpty) return;
    final escaped = q
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n');
    try {
      _ctrl.runJavaScript("window.find('$escaped', false, $backwards, true);");
    } catch (_) {}
  }

  void _toggleFind() {
    setState(() => _findVisible = !_findVisible);
    // 输入框 autofocus，无需手动请求焦点
    _findCtrl.clear();
  }

  // ---------- 网页图片长按 ----------

  void _injectLongPressImageHook() {
    try {
      _ctrl.runJavaScript("""
        if (!window.__psImgHook) {
          window.__psImgHook = true;
          (function(){
            var timer=null, el=null;
            var fire=function(){
              var url=el && el.src ? el.src : '';
              if(url){ window.psImage.postMessage(url); }
              timer=null; el=null;
            };
            document.addEventListener('touchstart',function(e){
              var t=e.target;
              if(t && t.tagName && (t.tagName.toUpperCase()==='IMG'||t.tagName.toUpperCase()==='PICTURE')){
                el=t.tagName.toUpperCase()==='IMG'?t:(t.querySelector&&t.querySelector('img'));
                if(el){ timer=setTimeout(fire, 620); e.preventDefault&&e.preventDefault(); }
              }
            }, {passive:false});
            document.addEventListener('touchend',function(){
              if(timer){clearTimeout(timer);timer=null;el=null;}
            });
            document.addEventListener('touchmove',function(){
              if(timer){clearTimeout(timer);timer=null;el=null;}
            }, {passive:true});
          })();
        }
      """);
    } catch (_) {}
  }

  void _onImageLongPress(String rawSrc) {
    if (!mounted) return;
    final src = _resolveAbsolute(rawSrc);
    SystemChannels.platform.invokeMethod('HapticFeedback.vibrate');
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('查看图片'),
            subtitle: Text(src.split('/').last,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              Navigator.pop(context);
              openNetworkImage(context, src);
            },
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('在浏览器打开'),
            onTap: () async {
              Navigator.pop(context);
              await launchUrl(Uri.parse(src),
                  mode: LaunchMode.externalApplication);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('复制图片地址'),
            onTap: () async {
              Navigator.pop(context);
              await Clipboard.setData(ClipboardData(text: src));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('图片地址已复制')));
              }
            },
          ),
        ]),
      ),
    );
  }

  String _resolveAbsolute(String raw) {
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final u = Uri.parse(_address);
    if (raw.startsWith('/')) {
      return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}$raw';
    }
    return raw;
  }

  // ---------- 下载监听 ----------

  static const Set<String> _downloadExt = {
    'apk', 'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso',
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'csv', 'srt',
    'exe', 'bin', 'msi', 'dmg', 'deb', 'rpm',
  };

  bool _isDownloadUrl(String u) {
    final lower = u.toLowerCase();
    return _downloadExt.any((e) => RegExp(r'\.' + e + r'([?#]|$)')
        .hasMatch(lower));
  }

  Future<void> _handleDownload(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final filename = _fileNameOf(url);
    messenger.showSnackBar(
        SnackBar(content: Text('正在下载 $filename …'), duration: const Duration(seconds: 2)));
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        messenger.showSnackBar(SnackBar(content: Text('下载失败：HTTP ${res.statusCode}')));
        return;
      }
      final bytes = res.bodyBytes;
      final saved = await Storage.writeBytes(bytes, 'downloads', filename);
      if (!mounted) return;
      final isApk = filename.toLowerCase().endsWith('.apk');
      messenger.showSnackBar(SnackBar(
        content: Text('已下载：$filename'),
        duration: const Duration(seconds: 4),
        action: isApk
            ? SnackBarAction(label: '安装', onPressed: () => _installApk(saved))
            : null,
      ));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('下载失败：$e')));
      }
    }
  }

  Future<void> _installApk(String path) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ApkInstaller.install(path);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(ok ? '已打开安装界面，请按提示完成安装' : '无法打开安装界面，请到空间中手动安装'),
      duration: const Duration(seconds: 2),
    ));
  }

  String _fileNameOf(String url) {
    final u = Uri.parse(url);
    final seg = u.queryParameters['p'];
    if (seg != null && seg.isNotEmpty) return seg.split('/').last;
    final last = u.pathSegments.where((s) => s.isNotEmpty).toList();
    if (last.isNotEmpty) {
      final n = p.basename(last.last);
      if (n.isNotEmpty) return n;
    }
    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

  // ---------- 视图 ----------

  Widget _progressStrip() {
    return SizedBox(
      height: 3,
      child: _loading
          ? LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.transparent,
              color: AppTheme.clay,
            )
          : null,
    );
  }

  Widget _addressBar() {
    final editing = _urlFocus.hasFocus || _urlCtrl.selection.isValid;
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(children: [
        // 安全锁 / 普通网页图标
        Icon(
          _secure ? Icons.lock_outline : Icons.public,
          size: 18,
          color: _secure ? Colors.green : AppTheme.inkSoft,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: TextField(
            controller: _urlCtrl,
            focusNode: _urlFocus,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onSubmitted: _navigateFromField,
            style: TextStyle(color: AppTheme.ink, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: '输入网址或搜索',
              filled: true,
              fillColor: AppTheme.bgDeep,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              suffixIcon: editing
                  ? IconButton(
                      tooltip: '前往',
                      icon: const Icon(Icons.arrow_forward),
                      color: AppTheme.clay,
                      onPressed: () => _navigateFromField(_urlCtrl.text),
                    )
                  : IconButton(
                      tooltip: '刷新',
                      icon: const Icon(Icons.refresh),
                      color: AppTheme.inkSoft,
                      onPressed: _reload,
                    ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          color: AppTheme.surface,
          onSelected: (v) {
            switch (v) {
              case 'reload':
                _reload();
                break;
              case 'home':
                _goHome();
                break;
              case 'external':
                _openExternal();
                break;
              case 'find':
                _toggleFind();
                break;
              case 'copy':
                _copyUrl();
                break;
              case 'share':
                _shareUrl();
                break;
              case 'history':
                _showHistory();
                break;
            }
          },
          itemBuilder: (_) {
            return [
              const PopupMenuItem(value: 'reload', child: Text('刷新')),
              const PopupMenuItem(value: 'home', child: Text('首页')),
              const PopupMenuItem(value: 'find', child: Text('在页面中查找')),
              const PopupMenuItem(value: 'external', child: Text('外部浏览器打开')),
              const PopupMenuItem(value: 'copy', child: Text('复制链接')),
              const PopupMenuItem(value: 'share', child: Text('分享链接')),
              const PopupMenuItem(value: 'history', child: Text('历史记录')),
            ];
          },
        ),
      ]),
    );
  }

  Widget _findBar() {
    return Material(
      color: AppTheme.surface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          const Icon(Icons.search, size: 20, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _findCtrl,
              autofocus: true,
              onChanged: (q) => _findInPage(q),
              onSubmitted: (q) => _findInPage(q),
              style: TextStyle(color: AppTheme.ink, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: '查找页面内容',
                border: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            tooltip: '上一个',
            icon: const Icon(Icons.keyboard_arrow_up, size: 22),
            onPressed: () => _findInPage(_findCtrl.text, backwards: true),
          ),
          IconButton(
            tooltip: '下一个',
            icon: const Icon(Icons.keyboard_arrow_down, size: 22),
            onPressed: () => _findInPage(_findCtrl.text),
          ),
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close, size: 20),
            onPressed: _toggleFind,
          ),
        ]),
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      color: AppTheme.surface,
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: '后退',
              onPressed: _canGoBack ? _goBack : null,
              icon: const Icon(Icons.arrow_back),
            ),
            IconButton(
              tooltip: '前进',
              onPressed: _canGoForward ? _goForward : null,
              icon: const Icon(Icons.arrow_forward),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '首页',
              onPressed: _goHome,
              icon: const Icon(Icons.home_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 44, color: AppTheme.inkSoft),
            const SizedBox(height: 12),
            Text('加载失败\n$_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.inkSoft, height: 1.6)),
            const SizedBox(height: 16),
            Wrap(spacing: 12, children: [
              FilledButton.icon(
                onPressed: () => _ctrl.reload(),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
              OutlinedButton.icon(
                onPressed: () => _ctrl.loadRequest(Uri.parse(_address)),
                icon: const Icon(Icons.home_outlined),
                label: const Text('首页'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppTheme.bg,
          appBar: AppBar(title: const Text('内置浏览器')),
          body: Column(children: [
            _addressBar(),
            if (_findVisible) _findBar(),
            _progressStrip(),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _ctrl),
                  if (_error != null) _errorView(),
                ],
              ),
            ),
            _bottomBar(),
          ]),
        );
      },
    );
  }
}