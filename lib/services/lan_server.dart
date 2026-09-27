import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../db.dart';
import '../models.dart';
import '../session.dart';
import '../storage.dart';
import 'lan_settings.dart';
import 'thumbnail.dart';

/// 局域网空间：一个纯 Dart 的 HTTP 服务器。
/// 启动后在局域网内提供精简精美的网页（前端 HTML 内嵌于本文件），
/// 展示当前用户的说说 / 日志 / 相册 / 文件。
///
/// 可见性由 [LanSettings] 控制：
///  - 私密开关打开时，整个空间对外全不可见（/api/* 一律拒绝，网页只显示锁定提示，
///    文件服务也一并关闭）；
///  - 开放时可分别关闭某一内容类型，使其不出现在网页与 API 中。
class LanServer extends ChangeNotifier {
  LanServer._();
  static final LanServer instance = LanServer._();

  HttpServer? _server;
  int _port = 0;
  bool _starting = false;
  String? _lastError;

  bool get running => _server != null;
  int get port => _port;
  int get desiredPort => LanSettings.instance.port;
  bool get starting => _starting;
  String? get lastError => _lastError;

  /// 可访问的局域网地址（尽力枚举本机 IPv4）。
  /// 优先返回“路由器下的局域网私有 IP”（192.168.x / 172.16~31.x / 10.x），
  /// 避免拿到运营商/虚拟网卡上报的公网 IP——那种地址在局域网内是访问不到的。
  Future<String?> lanAddress() async {
    try {
      final list = await NetworkInterface.list(
          includeLinkLocal: false, type: InternetAddressType.IPv4)
          .timeout(const Duration(seconds: 3));
      final private = <String>[];
      String? fallback;
      for (final i in list) {
        for (final a in i.addresses) {
          final ip = a.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;
          final rank = _privateLanRank(ip);
          if (rank >= 0) {
            private.add(ip);
          } else {
            fallback ??= ip;
          }
        }
      }
      if (private.isNotEmpty) {
        // 优先返回最常见的内网段：192.168.x > 172.16~31.x > 10.x
        private.sort((a, b) => _privateLanRank(a).compareTo(_privateLanRank(b)));
        return 'http://${private.first}:$_port';
      }
      if (fallback != null) return 'http://$fallback:$_port';
    } catch (_) {}
    return 'http://localhost:$_port';
  }

  /// 返回 RFC1918 私网的优先级（越小越优先）；非私网返回 -1。
  int _privateLanRank(String ip) {
    if (ip.startsWith('192.168.')) return 0;
    if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').firstMatch(ip) != null) return 1;
    if (ip.startsWith('10.')) return 2;
    return -1;
  }

  Future<void> start() async {
    if (_server != null || _starting) return;
    _starting = true;
    _lastError = null;
    notifyListeners();
    try {
      final s = await HttpServer.bind(
          InternetAddress.anyIPv4, desiredPort);
      _server = s;
      _port = s.port;
      s.listen(_handle);
      await _applyAwake(true);
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  /// 运行期间并结合“保持运行”开关，管理屏幕唤醒锁。
  /// 开启后即使熄屏，App 进程也不会进入深度休眠，局域网服务能持续在线
  /// （注意：真正的系统级前台服务/自恢复需原生实现，本开关为尽力保持在线）。
  Future<void> _applyAwake([bool? running]) async {
    final on = running ?? (_server != null);
    final keep = LanSettings.instance.keepAwake;
    try {
      if (on && keep) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // 平台不支持唤醒锁时静默忽略
    }
  }

  /// 供页面在“保持运行”开关变化时调用，使即时生效而无需重启。
  Future<void> applyKeepAwake() => _applyAwake();

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _port = 0;
    _lastError = null;
    if (s != null) {
      await s.close(force: true);
    }
    await _applyAwake(false);
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  // ------------------- 路由 -------------------

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    // 开发文档：始终可访问，方便极客真机调试自建网页（不泄露数据）
    if (req.method == 'GET' && (path == '/api/docs' || path == '/docs')) {
      await _sendDocs(req);
      return;
    }
    // 未登录（已退出）时数据/api 一律不对外，仅保留静态页面锁定提示
    if (Session.instance.user == null &&
        (path.startsWith('/api/') || path == '/file')) {
      await _json(req, 403, _locked());
      return;
    }
    try {
      if (req.method == 'GET' && (path == '/' || path == '/index.html')) {
        await _sendHtml(req);
      } else if (req.method == 'GET' && path == '/api/config') {
        await _json(req, 200, _configJson());
      } else if (req.method == 'GET' && path == '/api/shuoshuo') {
        await _json(req, 200, await _shuoshuoJson());
      } else if (req.method == 'GET' && path == '/api/diary') {
        await _json(req, 200, await _diaryJson());
      } else if (req.method == 'GET' && path == '/api/albums') {
        await _json(req, 200, await _albumJson());
      } else if (req.method == 'GET' && path == '/api/files') {
        await _json(req, 200, await _fileJson());
      } else if (req.method == 'GET' && path == '/file') {
        await _serveFile(req);
      } else {
        await _json(req, 404, {'error': 'Not Found'});
      }
    } catch (e) {
      debugPrint('LAN error: $e');
      try {
        await _json(req, 500, {'error': 'internal'});
      } catch (_) {}
    }
  }

  bool get _open => !LanSettings.instance.private;

  Map<String, dynamic> _configJson() {
    final u = Session.instance.user;
    final ls = LanSettings.instance;
    return {
      'name': u?.nickname ?? '',
      'private': ls.private,
      's': ls.showShuoshuo,
      'd': ls.showDiary,
      'a': ls.showAlbum,
      'f': ls.showFile,
      'port': _port,
      'brand': ls.brand,
      'accent': ls.accentHex.isEmpty ? null : ls.accentHex,
      'customCss': ls.customCss,
      'customHtml': ls.customHtml,
      'th': ls.webTheme,
      'footer': ls.footerHtml,
      'customJs': ls.customJs,
      'fullPageHtml': ls.fullPageHtml,
    };
  }

  Map<String, dynamic> _locked() => {
        'private': true,
        'locked': true,
        'message': '该空间已设为私密，内容不可见',
      };

  Future<Object> _shuoshuoJson() async {
    if (!_open || !LanSettings.instance.showShuoshuo) return _locked();
    final uid = Session.instance.user!.id!;
    final rows = await Db.instance.shuoshuosByUser(uid);
    final out = <Map<String, dynamic>>[];
    for (final it in rows) {
      final s = it['shuoshuo'] as Shuoshuo;
      final media = it['media'] as List<Media>;
      final ml = <Map<String, dynamic>>[];
      for (final m in media) {
        final cover = await mediaCover(m.filePath, m.mime, m.thumb);
        ml.add({
          'id': m.id,
          'type': _mediaType(m.mime, m.filePath),
          'name': m.name,
          'path': Uri.encodeComponent(m.filePath),
          'thumb': cover == null ? null : Uri.encodeComponent(cover),
          'mime': m.mime,
        });
      }
      out.add({
        'id': s.id,
        'content': s.content,
        'location': s.location,
        'created_at': s.createdAt,
        'media': ml,
      });
    }
    return out;
  }

  Future<Object> _diaryJson() async {
    if (!_open || !LanSettings.instance.showDiary) return _locked();
    final uid = Session.instance.user!.id!;
    final items = await Db.instance.diariesByUser(uid);
    return items
        .map((d) => {
              'id': d.id,
              'title': d.title,
              'content': d.content,
              'mood': d.mood,
              'weather': d.weather,
              'location': d.location,
              'created_at': d.createdAt,
            })
        .toList();
  }

  Future<Object> _albumJson() async {
    if (!_open || !LanSettings.instance.showAlbum) return _locked();
    final uid = Session.instance.user!.id!;
    final albums = await Db.instance.albumsByUser(uid);
    final out = <Map<String, dynamic>>[];
    for (final a in albums) {
      final media = await Db.instance.albumMedia(a.id);
      final ml = <Map<String, dynamic>>[];
      for (final m in media) {
        final cover = await mediaCover(m.filePath, m.mime, m.thumb);
        ml.add({
          'id': m.id,
          'type': _mediaType(m.mime, m.filePath),
          'name': m.name,
          'path': Uri.encodeComponent(m.filePath),
          'thumb': cover == null ? null : Uri.encodeComponent(cover),
        });
      }
      out.add({
        'id': a.id,
        'name': a.name,
        'created_at': a.createdAt,
        'cover': (a.coverPath == null || a.coverPath!.isEmpty)
            ? null
            : Uri.encodeComponent(a.coverPath!),
        'media': ml,
      });
    }
    return out;
  }

  Future<Object> _fileJson() async {
    if (!_open || !LanSettings.instance.showFile) return _locked();
    final uid = Session.instance.user!.id!;
    final files = await Db.instance.allSpaceFiles(uid);
    final out = <Map<String, dynamic>>[];
    for (final f in files) {
      if (!File(f.filePath).existsSync()) continue;
      final type = _mediaType(f.mime, f.filePath);
      String? thumb;
      if (type == 'video') thumb = await _videoThumb(f.filePath);
      if (type == 'file' && f.name.toLowerCase().endsWith('.apk')) {
        thumb = await _apkCover(f.filePath);
      }
      out.add({
        'id': f.id,
        'name': f.name,
        'size': f.size,
        'created_at': f.createdAt,
        'type': type,
        'thumb': (thumb == null || thumb.isEmpty)
            ? null
            : Uri.encodeComponent(thumb),
        'path': Uri.encodeComponent(f.filePath),
        'mime': f.mime,
      });
    }
    return out;
  }

  /// 返回媒体在网页展示用的封面。
  /// 视频实时生成封面帧；图片优先用已有的缩略图。
  Future<String?> mediaCover(String path, String mime, String? thumb) async {
    if (_mediaType(mime, path) == 'video') {
      return _videoThumb(path);
    }
    return (thumb == null || thumb.isEmpty) ? null : thumb;
  }

  /// 生成为视频生成封面图并缓存（进程内 + 磁盘稳定文件名），避免每次请求都重新解码。
  Future<String?> _videoThumb(String path) async {
    final cached = _videoCovers[path];
    if (cached != null) return cached;
    // 磁盘缓存：用路径文件名 + 短哈希作为稳定名
    final root = (await Storage.root()).path;
    final base = path.split('/').last;
    final dot = base.lastIndexOf('.');
    final stem = dot > 0 ? base.substring(0, dot) : base;
    final key = 'lan_${stem}_${path.hashCode.abs() & 0xffff}'
        .replaceAll(RegExp(r'[^\w_-]'), '_');
    final dir = '$root/thumbs';
    await Directory(dir).create(recursive: true);
    final disk = '$dir/$key.jpg';
    if (File(disk).existsSync()) {
      _videoCovers[path] = disk;
      return disk;
    }
    final t = await Thumbs.forVideo(path);
    if (t == null || !File(t).existsSync()) {
      _videoCovers[path] = path; // 失败则回退用原视频
      return path;
    }
    try {
      await File(t).copy(disk);
      await File(t).delete();
    } catch (_) {}
    _videoCovers[path] = disk;
    return disk;
  }

  final Map<String, String> _videoCovers = {};

  /// 解析 APK 应用图标封面（磁盘缓存），用于局域网空间文件列表展示安装包封面。
  Future<String?> _apkCover(String path) async {
    final cached = _apkCovers[path];
    if (cached != null) return cached;
    final root = (await Storage.root()).path;
    final dir = '$root/thumbs';
    await Directory(dir).create(recursive: true);
    final name = path.split('/').last;
    final key = 'apk_' + (name + '_l_' + path.hashCode.abs().toRadixString(16)) +
        '.png';
    final disk = '$dir/$key';
    if (File(disk).existsSync() && File(disk).lengthSync() > 0) {
      _apkCovers[path] = disk;
      return disk;
    }
    final t = await Thumbs.forApk(path);
    if (t == null) {
      _apkCovers[path] = '';
      return null;
    }
    try {
      if (File(t).path != disk) {
        await File(t).copy(disk);
      }
    } catch (_) {}
    _apkCovers[path] = disk;
    return disk;
  }

  final Map<String, String> _apkCovers = {};

  String _mediaType(String mime, String path) {
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('audio/') ||
        RegExp(r'\.(mp3|wav|flac|m4a|aac|ogg|wma)$', caseSensitive: false)
            .firstMatch(path) !=
            null) {
      return 'audio';
    }
    final m = RegExp(r'\.(mp4|mov|webm|m4v)$', caseSensitive: false)
        .firstMatch(path);
    return m != null ? 'video' : 'file';
  }

  /// 是否属于音频（取 media == 'audio'）
  bool _isAudio(String? type) => type == 'audio';

  // ------------------- 响应 -------------------

  Future<void> _json(HttpRequest req, int status, Object body) async {
    final bytes = utf8.encode(jsonEncode(body));
    req.response
      ..statusCode = status
      ..headers.contentType =
          ContentType('application', 'json', charset: 'utf-8')
      ..headers.contentLength = bytes.length
      ..add(bytes);
    await req.response.close();
  }

  Future<void> _serveFile(HttpRequest req) async {
    // 私密时文件一律不对外；开放时允许 App 内文件下载（供图片/视频/文件预览）
    if (!_open) {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }
    final raw = req.uri.queryParameters['p'];
    if (raw == null || raw.isEmpty) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }
    // queryParameters 已做一次百分号解码；这里直接使用，避免对路径二次解码造成错乱。
    final decoded = raw;
    final f = File(decoded);
    if (!f.existsSync()) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    // 安全校验：仅允许应用私有目录内的文件
    // 注意：必须对比“解析符号链接后的真实路径”。
    // 在 Android 上 getApplicationDocumentsDirectory() 返回 /data/user/0/…，
    // 而 resolveSymbolicLinks 会把它解析成 /data/data/…，若只拿未解析的 root
    // 做前缀判断，会导致所有文件被判为越权而 403（图片显示不出、文件下不了）。
    final root = (await Storage.root()).path;
    if (!await _isWithinAppDir(root, decoded)) {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }

    final mime = _mimeOf(decoded);
    final len = f.lengthSync();
    final range = req.headers.value(HttpHeaders.rangeHeader);

    // 解析 Range，得到 [start, end] 闭区间；无 Range 时整段
    int start = 0, end = len - 1;
    bool partial = false;
    if (range != null) {
      final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
      if (m == null) {
        req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        req.response.headers.set(
            HttpHeaders.contentRangeHeader, 'bytes */$len');
        await req.response.close();
        return;
      }
      final s = m.group(1)!;
      final e = m.group(2)!;
      if (s.isNotEmpty) start = int.tryParse(s) ?? 0;
      if (e.isNotEmpty) end = int.parse(e);
      // 尾部相对范围：bytes=-N 表示最后 N 字节
      if (s.isEmpty && e.isNotEmpty) {
        end = len - 1;
        start = (len - (int.parse(e))).clamp(0, len).toInt();
      }
      if (start < 0 || end > len - 1 || start > end) {
        req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        req.response.headers.set(
            HttpHeaders.contentRangeHeader, 'bytes */$len');
        await req.response.close();
        return;
      }
      partial = true;
    }

    // 流式返回（大视频/大文件也稳定，不一次性读入内存）
    req.response.statusCode =
        partial ? HttpStatus.partialContent : HttpStatus.ok;
    req.response.headers
      ..contentType = ContentType.parse(mime)
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentLengthHeader, (end - start + 1).toString());
    if (partial) {
      req.response.headers.set(
          HttpHeaders.contentRangeHeader, 'bytes $start-$end/$len');
    }
    final raf = f.openSync();
    try {
      raf.setPositionSync(start);
      final remaining = end - start + 1;
      const chunk = 64 * 1024;
      var sent = 0;
      while (sent < remaining) {
        final want = remaining - sent < chunk ? remaining - sent : chunk;
        final buf = await raf.read(want);
        if (buf.isEmpty) break;
        req.response.add(buf);
        sent += buf.length;
      }
    } finally {
      raf.closeSync();
    }
    await req.response.close();
  }

  /// 判断候选文件是否位于应用私有目录内。
  /// 先按“解析符号链接后的真实路径”比较，以兼容 Android /data/user/0 ⇄ /data/data
  /// 这类软链/绑定挂载差异；解析失败再退回普通前缀/规范化比较。
  Future<bool> _isWithinAppDir(String root, String candidate) async {
    try {
      final rRoot = await File(root).resolveSymbolicLinks();
      final rFile = await File(candidate).resolveSymbolicLinks();
      return rFile == rRoot || rFile.startsWith('$rRoot/');
    } catch (_) {
      final norm = Directory(root).absolute.path;
      final f = File(candidate).absolute.path;
      return f == norm || f.startsWith('$norm/');
    }
  }

  String _mimeOf(String p) {
    final e = p.split('.').last.toLowerCase();
    switch (e) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'm4v':
        return 'video/mp4';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain; charset=utf-8';
      case 'mp3':
        return 'audio/mpeg';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _sendHtml(HttpRequest req) async {
    final bytes = utf8.encode(_html());
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType =
          ContentType('text', 'html', charset: 'utf-8')
      ..headers.contentLength = bytes.length
      ..add(bytes);
    await req.response.close();
  }

  // ------------------- 开发文档 -------------------

  Future<void> _sendDocs(HttpRequest req) async {
    final bytes = utf8.encode(_docsMarkdown());
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType =
          ContentType('text', 'markdown', charset: 'utf-8')
      ..headers.contentLength = bytes.length
      ..add(bytes);
    await req.response.close();
  }

  /// 局域网开放平台开发文档（标准 Markdown 文本，便于复制/查阅）。
  /// 面向想在局域网内自己写网页 / 脚本 / 客户端读取本机空间的极客。
  String _docsMarkdown() => r'''
# 局域网空间 · 开发文档

通过局域网 HTTP 接口，你可以用自己写的网页 / 脚本 / 客户端读取本机「私密空间」的数据。

访问地址 = 局域网 IP + 端口，示例：`192.168.1.100:8787`（可在 App 内自定义端口后重启服务）。

## 接口总览
| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/` | 内置预览主页（HTML） |
| GET | `/api/config` | 配置 / 可见性 / 主题等元信息 |
| GET | `/api/shuoshuo` | 说说列表 |
| GET | `/api/diary` | 日志列表 |
| GET | `/api/albums` | 相册 + 媒体列表 |
| GET | `/api/files` | 空间文件列表 |
| GET | `/file?p=路径` | 下载 / 预览文件（图片/视频/音频等） |
| GET | `/api/docs` `/docs` | 本开发文档（Markdown） |

> 私密模式下任何数据接口都会返回锁定 JSON，只暴露基础元信息。

## 公共行为
- 所有接口返回 `application/json; charset=utf-8`。
- 文件下载接口支持 HTTP `Range` 范围请求，可用作视频拖动播放。
- 数据中的图片/视频/音频/封面 `path` 均已 `encodeURIComponent` 编码，播放时拼接为 `/file?p=编码后的路径`。

## 1. GET /api/config
返回配置与可见性：
```json
{
  "name": "昵称",
  "private": false,
  "s": true, "d": true,
  "a": true, "f": true,
  "port": 8787,
  "brand": "自定义品牌名(可为 null)",
  "accent": null,
  "customCss": "自定义 CSS(可为空)",
  "customHtml": "自定义页头 HTML(可为空)",
  "customJs": "自定义 JS(可为空)",
  "footer": "自定义页脚 HTML(可为空)",
  "th": { "bga": "#EFE6D6", "bgb": "#F7F4EE", "bgim": "", "radius": 16, "font": "sans", "hs": 0, "ts": 0 }
}
```

## 2. GET /api/shuoshuo
说说列表（数组）：
```json
[{
  "id": 12,
  "content": "今天阳光很好",
  "location": "杭州",
  "created_at": 1735440000000,
  "media": [{
    "id": 55,
    "type": "image",
    "name": "pic.jpg",
    "path": "%2Fdata...",
    "thumb": null,
    "mime": "image/jpeg"
  }]
}]
```

## 3. GET /api/diary
日志列表（数组）：
```json
[{
  "id": 3,
  "title": "标题",
  "content": "正文",
  "mood": "开心",
  "weather": "晴",
  "location": "上海",
  "created_at": 1735440000000
}]
```

## 4. GET /api/albums
相册列表（数组，含各自媒体）：
```json
[{
  "id": 1,
  "name": "旅行",
  "created_at": 1735440000000,
  "cover": "已编码封面路径|null",
  "media": [{ "id": 9, "type": "image", "name": "a.jpg", "path": "%2Fdata...", "thumb": null }]
}]
```

## 5. GET /api/files
空间文件（数组，仅返回仍存在的文件）：
```json
[{
  "id": 2,
  "name": "notes.txt",
  "size": 1234,
  "created_at": 1735440000000,
  "type": "file",
  "thumb": null,
  "path": "%2Fdata...",
  "mime": "text/plain"
}]
```

## 6. GET /file?p=路径
文件下载 / 播放。参数 `p` 为数据接口返回的已编码路径（直接透传即可）。自动推断 MIME 类型，支持 `Range` 断点续传。仅允许访问应用私有目录内的文件，越权返回 403。

## 手写一个网页（示例）
保存下面内容为 `index.html`，用浏览器打开即可读取说说：
```html
<script>
fetch(apiUrl('/api/shuoshuo'))
  .then(r => r.json())
  .then(list => {
    document.body.innerHTML = list.map(s =>
      "<div>" + s.content + "</div>"
    ).join("");
  });
</script>
```

## 公共函数
自定义网页里可直接使用以下全局函数，无需硬编码地址与端口：
- `spaceBase()` → 返回 `http://192.168.x.x:端口`（当前访问地址）。
- `apiUrl('/api/shuoshuo')` → 返回完整接口地址，等价于 `spaceBase() + 路径`。

## 网页定制
App 内即可编辑局域网网页：
- 「设置 → 局域网空间 → 自定义网页（源码）」可编辑 整页 HTML / CSS / JS / 页头 / 页脚 / 品牌名 / 主题色，保存后局域网访问立即生效。
- 整页 HTML（fullPageHtml）非空时，将完全替换内置主页，可自由控制整个网页结构与脚本；同时会自动注入上述公共函数。
  ''';

  // ------------------- 前端 HTML -------------------

  /// 注入到所有网页的公共 JS：提供 `spaceBase()` / `apiUrl()`，
  /// 让自定义网页不必硬编码自己的地址和端口，直接用相对/拼接方式调用接口。
  String _baseScript() => '''
<script>/* 局域网空间 · 自定义网页公共函数 */
window.spaceBase = function(){ return location.protocol + '//' + location.host; };
window.apiUrl = function(path){ return location.origin + (path||''); };
</script>
''';

  /// 把公共脚本安全地注入到当前网页的 <head>（无 <head> 则插入 <body> 前）。
  String _injectScript(String html, String script) {
    final hi = html.toLowerCase().indexOf('</head>');
    if (hi >= 0) return html.replaceRange(hi, hi, script + '\n');
    final bi = html.toLowerCase().indexOf('</body>');
    if (bi >= 0) return html.replaceRange(bi, bi, script + '\n');
    return script + '\n' + html;
  }

  String _html() {
    final fp = LanSettings.instance.fullPageHtml;
    // 整页源码编辑模式：完全用用户源码替换整个网页，并注入公共函数
    if (fp.trim().isNotEmpty) {
      final doc = fp.replaceFirst(RegExp(r'^\s*<!DOCTYPE[^>]*>\s*', caseSensitive: false), '');
      return '<!DOCTYPE html>\n${_injectScript(doc, _baseScript())}';
    }
    return _injectScript(_indexHtml, _baseScript());
  }

  String get _indexHtml => r'''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<title>拾光 · 空间</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
:root{--bg:#f7f4ee;--card:#fff;--ink:#332e28;--ink2:#7a7268;--line:#ece4d6;
--acc:#be7e5a;--acc2:#a66a48;--shadow:0 6px 22px rgba(60,50,40,.08);
--bgA:#EFE6D6;--bgB:#F7F4EE;--bgImg:none;--rk:16px;--fstack:-apple-system,"PingFang SC","Microsoft YaHei",sans-serif}
body{color:var(--ink);font-family:var(--fstack);min-height:100vh;-webkit-tap-highlight-color:transparent;
background-color:var(--bgB);
background-image:var(--bgImg),linear-gradient(180deg,var(--bgA),var(--bgB) 320px);
background-repeat:no-repeat,no-repeat;background-size:cover,auto;background-position:center,top;
background-attachment:fixed,scroll}
.wrap{max-width:680px;margin:0 auto;padding:18px 16px 60px}
header{display:flex;align-items:center;gap:12px;padding:12px 2px 20px}
.dot{width:12px;height:12px;border-radius:50%;background:var(--acc);box-shadow:0 0 0 4px rgba(190,126,90,.18)}
header h1{font-size:20px;font-weight:700}
header .sub{font-size:12px;color:var(--ink2);margin-top:2px}
.tabs{display:flex;gap:8px;margin:2px 0 18px;overflow-x:auto;padding-bottom:2px}
.tab{flex:none;padding:9px 18px;border-radius:20px;border:1px solid var(--line);
color:var(--ink2);font-size:14px;cursor:pointer;transition:.2s;user-select:none}
.tab.on{background:var(--acc);color:#fff;border-color:var(--acc)}
.card{background:var(--card);border:1px solid var(--line);border-radius:var(--rk);
padding:16px;margin-bottom:14px;box-shadow:var(--shadow)}
.t{font-size:12px;color:var(--ink2);margin-bottom:8px;display:flex;align-items:center;gap:6px}
.body{font-size:14px;line-height:1.75;white-space:pre-wrap;word-break:break-word}
.loc{display:inline-flex;align-items:center;gap:4px;margin-top:8px;font-size:12px;color:var(--acc2)}
.imgs{display:grid;grid-template-columns:repeat(3,1fr);gap:6px;margin-top:12px}
.imgs img{width:100%;aspect-ratio:1;object-fit:cover;border-radius:8px;cursor:zoom-in}
.album-name{font-weight:600;font-size:15px;margin-bottom:2px}
.empty{text-align:center;color:var(--ink2);padding:52px 0;font-size:14px}
.lock{display:flex;flex-direction:column;align-items:center;gap:14px;padding:72px 20px;text-align:center}
.lock .icon{width:64px;height:64px;border-radius:50%;background:rgba(190,126,90,.14);
display:flex;align-items:center;justify-content:center;font-size:28px}
.lock .ti{font-size:17px;font-weight:600}
.lock .de{font-size:13px;color:var(--ink2)}
.file{padding:12px 2px;border-bottom:1px solid var(--line);display:flex;align-items:center;gap:12px}
.file:last-child{border-bottom:none}
.file .ic{width:38px;height:38px;border-radius:10px;background:rgba(190,126,90,.12);
display:flex;align-items:center;justify-content:center;font-size:18px}
.file .nm{flex:1;font-size:14px}
.file .sz{font-size:12px;color:var(--ink2)}
.file a{color:var(--acc2);font-size:13px;text-decoration:none;padding:6px 12px;border:1px solid var(--line);border-radius:10px}
.imgs .cell{position:relative;aspect-ratio:1;border-radius:8px;overflow:hidden;cursor:pointer;background:#000}
.imgs video{width:100%;height:100%;object-fit:cover}
.imgs .pb{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;pointer-events:none}
.imgs .pb::before{content:'▶';font-size:14px;color:#fff;width:30px;height:30px;line-height:32px;text-align:center;border-radius:50%;background:rgba(0,0,0,.48);padding-left:3px}
.file .thumb{width:46px;height:38px;padding:0;overflow:hidden;background:#000;cursor:pointer;border-radius:8px}
.file .thumb img{width:100%;height:100%;object-fit:cover;display:block}
.alert{border-left:3px solid var(--acc);padding:12px 14px;background:rgba(190,126,90,.08);border-radius:10px;color:var(--ink2);font-size:13px}
/* ==== 深度定制：页头 / Tab / 页脚样式变体 ==== */
/* 页头：横幅 */
body[data-hs="1"] header.hdr{flex-direction:column;text-align:center;background:linear-gradient(135deg,var(--acc),var(--acc2));border-radius:calc(var(--rk)*1.5);padding:28px 18px;margin-bottom:16px;box-shadow:var(--shadow)}
body[data-hs="1"] header.hdr .dot{display:none}
body[data-hs="1"] header.hdr h1{color:#fff;font-size:22px}
body[data-hs="1"] header.hdr .sub{color:rgba(255,255,255,.85)}
/* 页头：极简 */
body[data-hs="2"] header.hdr{padding-bottom:12px}
body[data-hs="2"] header.hdr .dot{display:none}
body[data-hs="2"] header.hdr h1{font-size:18px}
/* Tab：下划线 */
body[data-ts="1"] .tabs{gap:18px;border-bottom:1px solid var(--line);margin-bottom:18px}
body[data-ts="1"] .tab{background:none;border:none;border-radius:0;padding:10px 2px;color:var(--ink2);border-bottom:2px solid transparent}
body[data-ts="1"] .tab.on{background:none;color:var(--acc);border-bottom-color:var(--acc)}
/* Tab：分块等宽 */
body[data-ts="2"] .tabs{gap:0;border:1px solid var(--line);border-radius:10px;overflow:hidden;margin-bottom:18px}
body[data-ts="2"] .tab{flex:1;text-align:center;border-radius:0;border:none;border-right:1px solid var(--line)}
body[data-ts="2"] .tab:last-child{border-right:none}
body[data-ts="2"] .tab.on{background:var(--acc);border-right:none}
/* 页脚 */
#footer{margin-top:26px;padding-top:16px;border-top:1px solid var(--line);color:var(--ink2);font-size:12px;text-align:center;line-height:1.8}
/* 说说正文 / 日志里的链接：变色 + 下划线，可点击 */
a.link{color:var(--acc2);text-decoration:underline;cursor:pointer;word-break:break-all}
/* 网页跟随手机白夜间模式：通过 JS 读系统色并切到深色变量 */
html[data-theme="dark"]{--bg:#221f1b;--card:#2b2722;--ink:#ede6da;--ink2:#a49b90;--line:#3a342e;--shiftA:#2a2622;--shiftB:#221f1b;
--shadow:0 6px 22px rgba(0,0,0,.35)}
/* 音频行 */
.aus{border:1px solid var(--line);border-radius:10px;overflow:hidden;margin-top:12px;background:var(--card)}
.aus audio{width:100%;display:block}
.imgs .acell{position:relative;aspect-ratio:1;border-radius:8px;overflow:hidden;cursor:pointer;background:var(--card)}
.apk-side{width:44px;height:44px;border-radius:8px;overflow:hidden;background:#3fa14b}
.apk-side img{display:block;width:100%;height:100%;object-fit:cover}
</style>
</head>
<body data-hs="0" data-ts="0">
<div class="wrap">
<header class="hdr">
  <div class="dot"></div>
  <div><h1 id="title">拾光 · 空间</h1><div class="sub" id="sub">主人的私密记录</div></div>
</header>
<div id="customhead"></div>
<div id="view"></div>
<div id="footer"></div>
</div>
<script>
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const pad=n=>String(n).padStart(2,'0');
const dt=t=>{const d=new Date(t);return d.getFullYear()+'-'+pad(d.getMonth()+1)+'-'+pad(d.getDate())+' '+pad(d.getHours())+':'+pad(d.getMinutes())};
const pretty=n=>{n=Number(n)||0;if(n<1024)return n+' B';if(n<1048576)return(n/1024).toFixed(1)+' KB';if(n<1073741824)return(n/1048576).toFixed(1)+' MB';if(n<1099511627776)return(n/1073741824).toFixed(1)+' GB';return(n/1099511627776).toFixed(1)+' TB'};
async function load(u){const r=await fetch(u);return r.json()}
function imgsGrid(media){
  const arr=(media||[]);
  if(!arr.length)return'';
  return '<div class="imgs">'+arr.map(m=>{
    const v=m.type==='video';
    const a=m.type==='audio';
    const src=(m.thumb||m.path);
    if(v)return '<div class="cell" data-video="'+m.path+'"><video muted preload="metadata" poster="/file?p='+src+'" src="/file?p='+m.path+'"></video><div class="pb">▶</div></div>';
    if(a)return '<div class="acell"><audio controls preload="metadata" src="/file?p='+m.path+'"></audio></div>';
    return '<img loading="lazy" src="/file?p='+src+'" alt="'+esc(m.name||'')+'">';
  }).join('')+'</div>';
}
var big=null;
function openView(src,isVideo){
  if(big)document.body.removeChild(big);
  big=document.createElement('div');
  big.style.cssText='position:fixed;inset:0;background:rgba(0,0,0,.9);display:flex;align-items:center;justify-content:center;z-index:99';
  if(isVideo){const v=document.createElement('video');v.src=src;v.controls=true;v.autoplay=true;v.style.cssText='max-width:96vw;max-height:92vh;border-radius:8px;background:#000';big.appendChild(v);}
  else{const im=document.createElement('img');im.src=src;im.style.cssText='max-width:94vw;max-height:94vh;border-radius:8px';big.appendChild(im);}
  big.onclick=()=>{document.body.removeChild(big);big=null};
  document.body.appendChild(big);
}
function bindImg(){
  document.querySelectorAll('.imgs img').forEach(img=>img.onclick=()=>openView(img.src,false));
  document.querySelectorAll('.imgs .cell').forEach(c=>c.onclick=()=>openView('/file?p='+c.dataset.video,true));
  document.querySelectorAll('.file .thumb').forEach(t=>t.onclick=()=>openView('/file?p='+t.dataset.video,true));
}
function lockHtml(){return '<div class="lock"><div class="icon">🔒</div><div class="ti">空间已设为私密</div><div class="de">主人将整个空间关闭，这里空空如也。</div></div>'}
function hiddenHtml(){return '<div class="empty">主人已将该内容设为不可见</div>'}
// 把正文里的 URL 变成带样式(变色+下划线)的可点击链接
function linkify(text){
  const s=esc(text||'');
  return s.replace(/(https?:\/\/[^\s<>"'()]+|[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*\.(com|cn|net|org|io|co|me|gov|edu)(\/[^\s<>"'()]*)?)/g,
    u=>'<a class="link" href="'+(u.match(/^https?:\/\//)?u:'http://'+u)+'" target="_blank" rel="noopener noreferrer">'+u+'</a>');
}
var K=null;
async function switchTab(k){
  K=k;
  const v=$('content');v.innerHTML='<div class="empty">加载中…</div>';
  const cfg=window._cfg||{};
  if(cfg.private){v.innerHTML=lockHtml();return}
  if(cfg[k]===false){v.innerHTML=hiddenHtml();return}
  try{
    if(k==='s'){const d=await load('/api/shuoshuo');if(K===k)renderShuoshuo(v,d)}
    else if(k==='d'){const d=await load('/api/diary');if(K===k)renderDiary(v,d)}
    else if(k==='a'){const d=await load('/api/albums');if(K===k)renderAlbums(v,d)}
    else if(k==='f'){const d=await load('/api/files');if(K===k)renderFiles(v,d)}
  }catch(e){if(K===k)v.innerHTML='<div class="empty">加载失败</div>'}
}
function renderShuoshuo(v,list){
  if(!list||list.length===0){v.innerHTML='<div class="empty">还没有说说</div>';return}
  v.innerHTML=list.map(s=>'<div class="card"><div class="t">'+esc(window._cfg.name||'主人')+' · '+dt(s.created_at)+'</div>'+(s.content?'<div class="body">'+linkify(s.content)+'</div>':'')+(s.location?'<div class="loc">📍 '+esc(s.location)+'</div>':'')+imgsGrid(s.media)+'</div>').join('');
  bindImg();
}
function renderDiary(v,list){
  if(!list||list.length===0){v.innerHTML='<div class="empty">还没有日志</div>';return}
  v.innerHTML=list.map(d=>'<div class="card"><div class="t">'+dt(d.created_at)+'</div>'+(d.title?'<div class="body" style="font-weight:600;margin-bottom:6px">'+esc(d.title)+'</div>':'')+(d.content?'<div class="body">'+linkify(d.content)+'</div>':'')+((d.mood||d.weather||d.location)?'<div class="loc">'+(d.mood?'😀 '+esc(d.mood):'')+(d.weather?' · ⛅ '+esc(d.weather):'')+(d.location?' · 📍 '+esc(d.location):'')+'</div>':'')+'</div>').join('');
}
function renderAlbums(v,list){
  if(!list||list.length===0){v.innerHTML='<div class="empty">还没有相册</div>';return}
  v.innerHTML=list.map(a=>'<div class="card"><div class="album-name">🗂 '+esc(a.name)+'</div>'+imgsGrid(a.media)+'</div>').join('');
  bindImg();
}
function renderFiles(v,list){
  if(!list||list.length===0){v.innerHTML='<div class="empty">还没有文件</div>';return}
  v.innerHTML='<div class="alert">📁 共 '+list.length+' 个文件，视频支持在线播放，音频在线试听，点击右侧即可下载。</div><div class="card" style="margin-top:12px">'+list.map(f=>{
    var media;
    if(f.type==='video'){
      var cover='/file?p='+(f.thumb||f.path);
      media='<div class="thumb" data-video="'+f.path+'" data-url="'+cover+'"><img src="'+cover+'" alt=""></div>';
    }else if(f.type==='audio'){
      media='<div class="ic" title="'+esc(f.name)+'">'+fileEmoji(f.name)+'</div>';
    }else if(f.thumb){
      // APK 等带封面图的文件：显示应用图标封面
      var cov='/file?p='+f.thumb;
      media='<div class="apk-side"><img src="'+cov+'" alt=""></div>';
    }else{
      media='<div class="ic" title="'+esc(f.name)+'">'+fileEmoji(f.name)+'</div>';
    }
    var extra='';
    if(f.type==='audio'){
      extra='<div class="aus"><audio controls preload="metadata" src="/file?p='+f.path+'"></audio></div>';
    }
    return '<div class="file">'+media+'<div class="nm">'+esc(f.name)+'<div class="sz">'+pretty(f.size)+' · '+dt(f.created_at)+'</div></div>'+((f.type==='audio')?'':('<a href="/file?p='+f.path+'" download>下载</a>'))+'</div>'+extra;
  }).join('')+'</div>';
  bindImg();
}
function fileEmoji(name){
  const e=(String(name||'')).toLowerCase().split('.').pop();
  const map={'apk':'🤖','pdf':'📕','zip':'🗜️','rar':'🗜️','7z':'🗜️','tar':'🗜️','gz':'🗜️','apk':'🤖',
    'mp3':'🎵','wav':'🎵','flac':'🎵','m4a':'🎵','aac':'🎵','mp4':'🎬','mov':'🎬','mkv':'🎬','webm':'🎬',
    'jpg':'🖼️','jpeg':'🖼️','png':'🖼️','gif':'🖼️','webp':'🖼️','heic':'🖼️',
    'doc':'📘','docx':'📘','xls':'📗','xlsx':'📗','ppt':'📙','pptx':'📙','key':'📙',
    'txt':'📄','md':'📄','pdf':'📕','html':'🌐','htm':'🌐','json':'🧾','xml':'🧾','csv':'📊','srt':'📝',
    'mp4':'🎬'};
  return map[e]||'📄';
}
function $(id){return document.getElementById(id)}
async function init(){
  let cfg={};
  try{cfg=await load('/api/config')}catch(e){}
  window._cfg=cfg;
  // 网页跟随手机白夜间模式：监听系统配色并切换 <html> 上 data-theme
  const darkMq=window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)');
  function applyDark(){
    const dark=darkMq&&darkMq.matches;
    document.documentElement.setAttribute('data-theme',dark?'dark':'light');
    const st=document.documentElement.style;
    if(dark){st.setProperty('--bgA','#221f1b');st.setProperty('--bgB','#1a1715');}
  }
  applyDark();
  if(darkMq&&darkMq.addEventListener)darkMq.addEventListener('change',applyDark);
  // 品牌名：优先用户配置，其次昵称，最后默认
  const brand=(cfg.brand||('拾光 · '+(cfg.name||'空间')));
  document.title=brand;
  $('title').textContent=brand;
  // 自定义主题色 → 覆盖 CSS 变量
  if(cfg.accent){const a=document.documentElement.style;a.setProperty('--acc',cfg.accent);a.setProperty('--acc2',cfg.accent);}
  // 整页主题（背景渐变/背景图/圆角/字体/页头/Tab 样式/页脚）
  const th=cfg.th||{};
  const ro=document.documentElement.style;
  ro.setProperty('--bgA',th.bga||'#EFE6D6');
  ro.setProperty('--bgB',th.bgb||'#F7F4EE');
  ro.setProperty('--bgImg',th.bgim&&String(th.bgim).trim()?'url("'+String(th.bgim).trim()+'")':'none');
  ro.setProperty('--rk',(parseInt(th.radius)||16)+'px');
  const fsmap={sans:'-apple-system,"PingFang SC","Microsoft YaHei",sans-serif',song:'"Songti SC","SimSun",serif',hei:'"PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif',mono:'"SF Mono","Consolas","Courier New",monospace'};
  if(fsmap[th.font])ro.setProperty('--fstack',fsmap[th.font]);
  // 深色模式下重新应用暗色背景（覆盖上面的浅色主题配置）
  applyDark();
  document.body.dataset.hs=String(th.hs??0);
  document.body.dataset.ts=String(th.ts??0);
  if(cfg.footer&&String(cfg.footer).trim()){const f=$('footer');if(f)f.innerHTML=cfg.footer;}
  // 注入自定义 CSS
  if(cfg.customCss){try{document.head.appendChild(Object.assign(document.createElement('style'),{textContent:cfg.customCss}));}catch(e){}}
  // 自定义页头 HTML
  if(cfg.customHtml){const h=$('customhead');if(h)h.innerHTML=cfg.customHtml;}
  // 自定义 JS（整页脚本，最后执行以能访问已生成的 DOM）
  if(cfg.customJs){try{new Function(cfg.customJs)()}catch(e){}}
  if(cfg.private){$('view').innerHTML=lockHtml();return}
  const tabs=[['s','说说'],['d','日志'],['a','相册'],['f','文件']];
  $('view').innerHTML='<div class="tabs">'+tabs.map(([k,n])=>'<div class="tab" data-k="'+k+'">'+n+'</div>').join('')+'</div><div id="content"></div>';
  document.querySelectorAll('.tab').forEach(t=>t.addEventListener('click',()=>{
    document.querySelectorAll('.tab').forEach(x=>x.classList.remove('on'));
    t.classList.add('on');
    switchTab(t.dataset.k);
  }));
  const first=document.querySelector('.tab');first.classList.add('on');switchTab('s');
}
init();
</script>
</body>
</html>''';
}