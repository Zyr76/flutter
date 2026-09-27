import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/thumbnail.dart';

/// 全屏图片预览（支持缩放/拖拽）
class ImageViewer extends StatelessWidget {
  final String path;
  const ImageViewer({Key? key, required this.path}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: PhotoView(
        imageProvider: FileImage(File(path)),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      ),
    );
  }
}

/// 色彩常量：进度条/强调色统一走这条线，所有视频控件共用，保证视觉一致。
abstract final class PlayerTheme {
  static const Color clay = Color(0xFFBE7E5A);
  static const Color clayLight = Color(0xFFE3B28E);
  static const Color bg = Color(0xFF000000);

  // ---- 现代化深色玻璃色板 ----
  static const Color surfaceStrong = Color(0xEB2C2823); // 深色半透明面板
  static const Color panelBorder = Color(0x33FFFFFF); // 面板描边
  static const Color track = Color(0x4DFFFFFF); // 进度条底轨
  static const Color buffered = Color(0x29FFFFFF); // 已缓冲区间
  static const Color ink = Color(0xFFFFFFFF);
  static const Color inkDim = Color(0xE6FFFFFF);
}

/// 企业级视频播放器。
///
/// 目标：提供一个在真实 App 里可长期维护、体验完整的播放器，而非 demo。
/// 特性：
///  - 自动隐藏控制条（3s 无操作自动隐藏，单击切换显隐，暂停时保持常驻）
///  - 手势：单击显隐控制条；双击左右 1/3 快退/快进 15s；长按 2 倍速
///  - 亮度（左 1/3）与音量（右 1/3）纵向拖动调节，带中央提示
///  - 横向拖动快进，进度条支持点击/拖拽即时跳转（画面实时跟随）
///  - 进度条展示「已缓冲」区间，横屏沉浸全屏，保持屏幕常亮
///  - 控制条：±10s 跳转、播放/暂停、静音、倍速菜单、画面比例、循环、全屏
///  - 缓冲加载指示、播放完成回到片头、加载/失败/兜底封面各状态
///
/// 全屏播放页和滑动预览里的视频页都复用同一个组件，保证行为一致。
class SimpleVideoPlayer extends StatefulWidget {
  final String path;
  final String title;
  final bool live; // 是否为实况图
  final String? cover; // 实况图的静态封面（视频解不了时兜底显示）
  final bool autoplay; // 就绪后是否自动播放
  final bool showTopBar; // 是否显示顶部返回栏（滑动预览里由外层提供返回/计数）
  final VoidCallback? onBack;
  const SimpleVideoPlayer({
    Key? key,
    required this.path,
    this.title = '',
    this.live = false,
    this.cover,
    this.autoplay = true,
    this.showTopBar = true,
    this.onBack,
  }) : super(key: key);

  @override
  State<SimpleVideoPlayer> createState() => _SimpleVideoPlayerState();
}

class _SimpleVideoPlayerState extends State<SimpleVideoPlayer> {
  VideoPlayerController? _vc;
  bool _ready = false;
  bool _failed = false;
  Orientation? _lastOrient;

  // ---------- 控制条可见性 ----------
  bool _controlsVisible = true;
  Timer? _hideTimer;

  // ---------- 手势 / 临时提示 ----------
  double _dim = 0.0; // 亮度遮罩 0~0.85
  bool _muted = false;
  bool _fast = false; // 长按 2 倍速是否生效
  int _skip = 0; // 最近一次跳转方向：-15 / +15（0 = 无）
  Timer? _skipTimer;
  bool _brightShow = false;
  Timer? _vertTimer;
  bool _seekShow = false;
  double _seekTotalDx = 0;
  double _seekStartMs = 0;
  int _seekMs = -1;
  int _seekDelta = 0;
  Timer? _seekTimer;

  // ---------- 播放设置 ----------
  double _speed = 1.0;
  bool _aspectFill = false; // true=拉伸铺满, false=等比 contain
  bool _loop = false;

  // ---------- 进度条 scrubbing ----------
  bool _scrubbing = false;
  double _scrubFrac = -1;

  bool get _landscape =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  @override
  void initState() {
    super.initState();
    _vc = VideoPlayerController.file(File(widget.path));
    _init();
  }

  Future<void> _init() async {
    final vc = _vc;
    if (vc == null) return;
    try {
      await vc.initialize();
      if (!mounted) {
        vc.dispose();
        return;
      }
      // 同步音量到控制器
      vc.setVolume(_muted ? 0.0 : 1.0);
      if (widget.live) vc.setLooping(true);
      setState(() => _ready = true);
      if (widget.autoplay) {
        vc.play();
        WakelockPlus.enable();
      }
      _scheduleAutoHide();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant SimpleVideoPlayer old) {
    super.didUpdateWidget(old);
    if (old.autoplay == widget.autoplay) return;
    final vc = _vc;
    if (vc == null || !_ready || _failed) return;
    if (widget.autoplay) {
      if (!vc.value.isPlaying) vc.play();
      WakelockPlus.enable();
    } else {
      vc.pause();
      WakelockPlus.disable();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final o = MediaQuery.of(context).orientation;
    if (o != _lastOrient) {
      _lastOrient = o;
      SystemChrome.setEnabledSystemUIMode(
          o == Orientation.landscape
              ? SystemUiMode.immersiveSticky
              : SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    _skipTimer?.cancel();
    _vertTimer?.cancel();
    _seekTimer?.cancel();
    _hideTimer?.cancel();
    WakelockPlus.disable();
    _vc?.dispose();
    _vc = null;
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------- 控制条显隐 ----------
  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    // 播放中才自动隐藏；暂停/未初始化不隐藏，方便看清控件
    final playing = _vc?.value.isPlaying ?? false;
    if (!playing || _scrubbing || _seekShow) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _vc?.value.isPlaying == true) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleAutoHide(); else _hideTimer?.cancel();
  }

  // ---------- 播放控制 ----------
  void _togglePlay() {
    final vc = _vc;
    if (vc == null || !_ready) return;
    if (vc.value.isPlaying) {
      vc.pause();
      WakelockPlus.disable();
    } else {
      // 播完重新开始
      final d = vc.value.duration;
      if (d.inMilliseconds > 0 &&
          vc.value.position >= (d - const Duration(milliseconds: 300))) {
        vc.seekTo(Duration.zero);
      }
      vc.play();
      WakelockPlus.enable();
    }
    setState(() {});
    _scheduleAutoHide();
  }

  void _seek(double v) {
    final vc = _vc;
    if (vc == null) return;
    final d = vc.value.duration;
    if (d.inMilliseconds > 0) vc.seekTo(d * v);
  }

  // ---------- 倍速 / 循环 / 比例 / 静音 ----------
  void _setSpeed(double s) {
    final vc = _vc;
    if (vc == null || !_ready) return;
    vc.setPlaybackSpeed(s);
    setState(() => _speed = s);
  }

  void _toggleLoop() {
    final vc = _vc;
    if (vc == null || !_ready) return;
    setState(() => _loop = !_loop);
    vc.setLooping(_loop);
  }

  void _toggleAspect() => setState(() => _aspectFill = !_aspectFill);

  void _toggleMute() {
    final vc = _vc;
    if (vc == null || !_ready) return;
    setState(() => _muted = !_muted);
    vc.setVolume(_muted ? 0.0 : 1.0);
  }

  // ---------- 进度条 scrubbing：拖拽进度条时直接 seek，画面实时跟随 ----------
  int _scrubTotalMs() =>
      (_vc?.value.duration.inMilliseconds ?? 0);

  void _scrubStart(double localDx, double trackW) {
    final vc = _vc;
    if (vc == null || !_ready) return;
    final total = _scrubTotalMs();
    if (total <= 0) return;
    _hideTimer?.cancel();
    setState(() {
      _scrubbing = true;
      _controlsVisible = true;
      _scrubFrac = (localDx.clamp(0, trackW)) / (trackW > 0 ? trackW : 1.0);
    });
    _seekVideo(total);
  }

  void _scrubUpdate(double localDx, double trackW) {
    if (!_scrubbing) return;
    final total = _scrubTotalMs();
    if (total <= 0) return;
    setState(() {
      _scrubFrac = (localDx.clamp(0, trackW)) / (trackW > 0 ? trackW : 1.0);
    });
    _seekVideo(total);
  }

  void _scrubEnd() {
    if (!_scrubbing) return;
    setState(() => _scrubbing = false);
    _scheduleAutoHide();
  }

  void _seekVideo(int total) {
    final vc = _vc;
    if (vc == null || !_ready || total <= 0) return;
    final ms = (_scrubFrac.clamp(0.0, 1.0) * total).round().clamp(0, total);
    vc.seekTo(Duration(milliseconds: ms));
  }

  // 跳过 ± 秒（进度条按钮）
  Future<void> _skipSec(int seconds) async {
    final vc = _vc;
    if (vc == null || !_ready) return;
    final d = vc.value.duration;
    if (d.inMilliseconds <= 0) return;
    final cur = vc.value.position.inMilliseconds;
    final target = (cur + seconds * 1000).clamp(0, d.inMilliseconds);
    await vc.seekTo(Duration(milliseconds: target));
    setState(() => _skip = seconds);
    _skipTimer?.cancel();
    _skipTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _skip = 0);
    });
  }

  // ---------- 长按 2 倍速 ----------
  void _onLongStart() {
    final vc = _vc;
    if (vc == null || !_ready) return;
    vc.setPlaybackSpeed(2.0);
    setState(() => _fast = true);
  }

  void _onLongEnd() {
    final vc = _vc;
    if (vc == null || !_ready || !_fast) return;
    vc.setPlaybackSpeed(_speed);
    setState(() => _fast = false);
  }

  // ---------- 亮度拖动手势（整屏，上滑调亮 / 下滑调暗） ----------
  void _onVStart(DragStartDetails de) {
    _brightShow = true;
    setState(() {});
  }

  void _onVUpdate(DragUpdateDetails de) {
    final sz = MediaQuery.of(context).size;
    // 灵敏度系数 2.6：让亮度调节更跟手
    final delta = de.delta.dy / sz.height * 2.6;
    setState(() => _dim = (_dim + delta).clamp(0.0, 0.85));
  }

  void _onVEnd() {
    _vertTimer?.cancel();
    _vertTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _brightShow = false);
    });
  }

  // ---------- 横向拖动快进 ----------
  void _onSeekStart(DragStartDetails de) {
    final vc = _vc;
    if (vc == null || !_ready) return;
    if (vc.value.duration.inMilliseconds <= 0) return;
    _hideTimer?.cancel();
    _seekTotalDx = 0;
    _seekStartMs = vc.value.position.inMilliseconds.toDouble();
    _seekMs = vc.value.position.inMilliseconds;
    _seekDelta = 0;
    setState(() { _seekShow = true; _controlsVisible = true; });
  }

  void _onSeekUpdate(DragUpdateDetails de) {
    if (!_seekShow) return;
    final vc = _vc;
    if (vc == null) return;
    _seekTotalDx += de.delta.dx;
    final w = MediaQuery.of(context).size.width;
    final dMs = vc.value.duration.inMilliseconds;
    final range = 120000.0; // 满屏横滑 ≈ 120 秒
    final target = (_seekStartMs + _seekTotalDx / w * range)
        .round()
        .clamp(0, dMs);
    _seekDelta = ((target - _seekStartMs) / 1000).round();
    _seekMs = target;
    setState(() {});
  }

  void _onSeekEnd() {
    if (!_seekShow) return;
    final vc = _vc;
    final t = _seekMs;
    _seekShow = false;
    if (vc != null && t >= 0 && _ready) {
      vc.seekTo(Duration(milliseconds: t));
    }
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekDelta = 0);
    });
    setState(() {});
    _scheduleAutoHide();
  }

  // ---------- 全屏 ----------
  Future<void> _toggleFullscreen() async {
    _lastOrient = null;
    if (_landscape) {
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours > 0 ? '${d.inHours}:' : '';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h$m:$s';
  }

  // =============================================
  //  视图
  // =============================================

  Widget _failedView() {
    final cover = widget.cover;
    final hasCover =
        cover != null && cover.isNotEmpty && File(cover).existsSync();
    if (hasCover) {
      return Stack(fit: StackFit.expand, children: [
        Image.file(File(cover), fit: BoxFit.contain),
        const Center(
          child: Icon(Icons.motion_photos_on, color: Colors.white70, size: 48),
        ),
      ]);
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, color: Colors.white70, size: 48),
        const SizedBox(height: 10),
        const Text('无法播放该视频',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: widget.onBack ?? () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('返回'),
        ),
      ]),
    );
  }

  Widget _surface() {
    final a = _vc!.value.aspectRatio;
    final ratio = (a > 0 && a.isFinite) ? a.clamp(0.4, 3.0).toDouble() : 1.4;
    // 拉伸铺满 or 等比 contain
    return _aspectFill
        ? SizedBox.expand(child: VideoPlayer(_vc!))
        : Center(
            child: AspectRatio(aspectRatio: ratio, child: VideoPlayer(_vc!)));
  }

  Widget _topBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Row(children: [
        if (widget.onBack != null)
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
          ),
        Expanded(
          child: Text(
            widget.title.isEmpty
                ? widget.live
                    ? '实况图'
                    : '视频'
                : widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(
          width: 40,
          child: IconButton(
            tooltip: _landscape ? '退出全屏' : '全屏',
            onPressed: _toggleFullscreen,
            icon: Icon(
                _landscape ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white,
                size: 20),
          ),
        ),
      ]),
    );
  }

  bool _hasCenterIndicator() =>
      _seekShow || _brightShow || _skip != 0 || _fast;

  Widget _centerIndicators() {
    final items = <Widget>[];
    if (_seekShow) {
      items.add(_pill(Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          _seekDelta > 0
              ? '+${_seekDelta}s'
              : (_seekDelta < 0 ? '$_seekDelta s' : '0s'),
          style: const TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(_fmt(Duration(milliseconds: _seekMs)),
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ])));
    }
    if (_brightShow) {
      items.add(_pill(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_dim >= 0.5 ? Icons.brightness_5 : Icons.brightness_4,
            color: Colors.white, size: 22),
        const SizedBox(width: 8),
        Text('${((1 - _dim / 0.7) * 100).round()}%',
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
      ])));
    }
    if (_skip != 0 || _fast) {
      items.add(_pill(Text(
        _fast ? '2x' : (_skip > 0 ? '+15s' : '-15s'),
        style: const TextStyle(
            color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
      )));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) children.add(const SizedBox(height: 8));
      children.add(items[i]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _pill(Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: PlayerTheme.surfaceStrong,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: PlayerTheme.panelBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0x47000000),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  // 进度条（含已缓冲区间 + 拖拽即时跳转）
  Widget _progressBar(VideoPlayerValue v, double total, double frac) {
    // 已缓冲进度
    double buffered = 0.0;
    if (v.buffered.isNotEmpty) {
      buffered = (v.buffered.last.end.inMilliseconds / total).clamp(0.0, 1.0);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (de) => _seek(de.localPosition.dx / (w > 0 ? w : 1)),
          onHorizontalDragStart: (de) => _scrubStart(de.localPosition.dx, w),
          onHorizontalDragUpdate: (de) => _scrubUpdate(de.localPosition.dx, w),
          onHorizontalDragEnd: (_) => _scrubEnd(),
          onHorizontalDragCancel: _scrubEnd,
          child: SizedBox(
            height: 28,
            child: Center(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // 底轨
                  Container(height: 3.4, color: PlayerTheme.track),
                  // 已缓冲区间
                  FractionallySizedBox(
                    widthFactor: buffered.clamp(0.0, 1.0),
                    child: Container(height: 3.4, color: PlayerTheme.buffered),
                  ),
                  // 已播放轨（圆角渐变 + 底部辉光）
                  FractionallySizedBox(
                    widthFactor: frac.clamp(0.0, 1.0),
                    child: Container(
                      height: 3.4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: const LinearGradient(
                          colors: [PlayerTheme.clay, PlayerTheme.clayLight],
                          stops: [0.0, 1.0],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: PlayerTheme.clay.withOpacity(0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 播放头（描边发光；拖拽时放大）
                  Positioned(
                    left: (frac.clamp(0.0, 1.0)) * w - (_scrubbing ? 8 : 6),
                    child: Container(
                      width: _scrubbing ? 16 : 12,
                      height: _scrubbing ? 16 : 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: PlayerTheme.clay, width: 2.2),
                        boxShadow: [
                          BoxShadow(
                            color: PlayerTheme.clay.withOpacity(0.65),
                            blurRadius: _scrubbing ? 10 : 5,
                            spreadRadius: _scrubbing ? 1.5 : 0,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _btn(Widget child, VoidCallback onTap, {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        highlightColor: const Color(0x24FFFFFF),
        splashColor: const Color(0x47BE7E5A),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: child,
        ),
      ),
    );
  }

  Widget _bottomBar(VideoPlayerValue v) {
    final d = v.duration;
    final total = d.inMilliseconds > 0 ? d.inMilliseconds : 0;
    final pos = v.position.inMilliseconds.clamp(0, math.max(total, 1));
    final frac = _scrubbing
        ? (_scrubFrac.clamp(0.0, 1.0))
        : (total > 0 ? pos / total : 0.0);
    final shownMs = _scrubbing
        ? (_scrubFrac.clamp(0.0, 1.0) * total).round()
        : pos.toInt();
    final isLive = total <= 0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: [0.0, 0.75],
          colors: [Colors.black, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(0, 48, 4, 2),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!isLive) ...[
          _progressBar(v, total.toDouble(), frac),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              Text(_fmt(Duration(milliseconds: shownMs)),
                  style: const TextStyle(
                      color: PlayerTheme.inkDim,
                      fontSize: 11,
                      fontFeatures: [ui.FontFeature.tabularFigures()])),
              const Spacer(),
              Text(_fmt(d),
                  style: const TextStyle(
                      color: PlayerTheme.inkDim,
                      fontSize: 11,
                      fontFeatures: [ui.FontFeature.tabularFigures()])),
            ]),
          ),
        ],
        Row(children: [
          const SizedBox(width: 4),
          if (!isLive)
            _btn(const Icon(Icons.replay_10, color: Colors.white, size: 24),
                () => _skipSec(-10), tooltip: '快退 10 秒'),
          _btn(
              Icon(v.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white, size: 30),
              _togglePlay,
              tooltip: v.isPlaying ? '暂停' : '播放'),
          if (!isLive)
            _btn(const Icon(Icons.forward_10, color: Colors.white, size: 24),
                () => _skipSec(10), tooltip: '快进 10 秒'),
          const Spacer(),
          _btn(
              Icon(_muted ? Icons.volume_off : Icons.volume_up,
                  color: Colors.white, size: 22),
              _toggleMute,
              tooltip: '静音'),
          _btn(
              Icon(Icons.loop,
                  color: _loop ? PlayerTheme.clayLight : Colors.white,
                  size: 22),
              _toggleLoop,
              tooltip: '循环播放'),
          _btn(
              Icon(_aspectFill ? Icons.fullscreen : Icons.fit_screen,
                  color: Colors.white, size: 22),
              _toggleAspect,
              tooltip: _aspectFill ? '等比显示' : '拉伸铺满'),
          Theme(
              data: ThemeData(
                brightness: Brightness.dark,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: PlayerTheme.clay,
                  brightness: Brightness.dark,
                ),
              ),
              child: MenuAnchor(
              alignmentOffset: const Offset(0, -8),
              builder: (context, controller, child) {
                return InkWell(
                  onTap: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(_speedLabel(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                );
              },
              menuChildren: _speedItems(),
            )),
          _btn(
              Icon(_landscape ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: Colors.white, size: 22),
              _toggleFullscreen,
              tooltip: _landscape ? '退出全屏' : '全屏'),
        ]),
      ]),
    );
  }

  String _speedLabel() {
    if (_speed == 1.0) return '1x';
    // 去掉多余 0 用于显示，如 1.5x
    final s = _speed.toString().replaceFirst(RegExp(r'\.0$'), '');
    return '${s}x';
  }

  List<Widget> _speedItems() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0];
    return speeds.map((s) {
      return MenuItemButton(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 40,
            child: Text(
              s == 1.0 ? '1x' : '${s}x',
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),
          if (s == _speed)
            const Icon(Icons.check, color: PlayerTheme.clayLight, size: 16),
        ]),
        onPressed: () => _setSpeed(s),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 最底层纯黑 + 安全区
        const ColoredBox(color: PlayerTheme.bg),
        SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_failed)
                _failedView()
              else if (!_ready)
                const Center(
                    child: CircularProgressIndicator(color: Colors.white54))
              else
                _surface(),
              // 亮度遮罩
              if (_ready && !_failed && _dim > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(color: Colors.black.withOpacity(_dim)),
                  ),
                ),
              // 手势层
              if (_ready && !_failed)
                Positioned.fill(
                  child: LayoutBuilder(builder: (context, c) {
                    return GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _toggleControls,
                      onDoubleTapDown: (details) {
                        final w = c.maxWidth;
                        if (details.localPosition.dx < w / 3) {
                          _skipSec(-15);
                        } else if (details.localPosition.dx > w * 2 / 3) {
                          _skipSec(15);
                        }
                      },
                      onLongPressStart: (_) => _onLongStart(),
                      onLongPressEnd: (_) => _onLongEnd(),
                      onLongPressCancel: _onLongEnd,
                      onVerticalDragStart: _onVStart,
                      onVerticalDragUpdate: _onVUpdate,
                      onVerticalDragEnd: (_) => _onVEnd(),
                      onVerticalDragCancel: _onVEnd,
                      onHorizontalDragStart: _onSeekStart,
                      onHorizontalDragUpdate: _onSeekUpdate,
                      onHorizontalDragEnd: (_) => _onSeekEnd(),
                      onHorizontalDragCancel: _onSeekEnd,
                      child: const SizedBox.expand(),
                    );
                  }),
                ),
              // 中央提示标识
              if (_ready && !_failed && _hasCenterIndicator())
                IgnorePointer(child: Center(child: _centerIndicators())),
              // 缓冲中（仅在播放且被控条可见时右下角不大显示，这里居中淡显）
              if (_ready && !_failed)
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _vc!,
                  builder: (_, v, __) {
                    if (!v.isPlaying || !v.isBuffering) {
                      return const SizedBox.shrink();
                    }
                    return const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white70),
                      ),
                    );
                  },
                ),
              // 控制条
              if (_ready && !_failed && _controlsVisible)
                IgnorePointer(
                  ignoring: false,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _controlsVisible ? 1 : 0,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (widget.showTopBar)
                          Positioned(
                              top: 0, left: 0, right: 0, child: _topBar()),
                        ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: _vc!,
                          builder: (_, v, __) => Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _bottomBar(v),
                          ),
                        ),
                        // 暂停时中央大播放键
                        ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: _vc!,
                          builder: (_, v, __) {
                            if (v.isPlaying || _hasCenterIndicator())
                              return const SizedBox.shrink();
                            return Center(
                              child: GestureDetector(
                                onTap: _togglePlay,
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  decoration: const BoxDecoration(
                                    color: Colors.black45,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.play_arrow,
                                      color: Colors.white, size: 40),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 打开图片预览
void openImage(BuildContext context, String path) {
  Navigator.push(
      context, MaterialPageRoute(builder: (_) => ImageViewer(path: path)));
}

/// 全屏网络图片预览（内置浏览器/网页图片复用软件的图片查看器）。
/// 用法：点击页面中的图片时用软件自带的缩放查看器打开。
class NetworkImageViewer extends StatelessWidget {
  final String url;
  const NetworkImageViewer({Key? key, required this.url}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '复制地址',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('图片地址已复制')));
              }
            },
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      body: PhotoView(
        imageProvider: NetworkImage(url),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        errorBuilder: (context, error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.broken_image_outlined,
                  color: Colors.white70, size: 48),
              const SizedBox(height: 12),
              const Text('图片加载失败',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 用软件自带的图片查看器打开一张网络图片。
void openNetworkImage(BuildContext context, String url, [String? fallbackUrl]) {
  final target = url.trim().isNotEmpty ? url : (fallbackUrl ?? '');
  if (target.isEmpty) return;
  Navigator.push(context,
      MaterialPageRoute(builder: (_) => NetworkImageViewer(url: target)));
}

/// 打开视频播放（全屏）
void openVideo(BuildContext context, String path,
    {bool live = false, String title = '', String? cover}) {
  Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                body: SimpleVideoPlayer(
                  path: path,
                  live: live,
                  title: title,
                  cover: cover,
                  autoplay: true,
                  showTopBar: true,
                  onBack: () => Navigator.pop(context),
                ),
              )));
}

/// 滑动预览中的单个媒体项（图片 / 视频 / 实况图）
class MediaPagerItem {
  final String path;
  final bool isVideo; // 视频或实况图
  final bool live; // 是否为实况图
  final String? cover; // 实况图封面
  final String title;
  const MediaPagerItem({
    required this.path,
    this.isVideo = false,
    this.live = false,
    this.cover,
    this.title = '',
  });
}

/// 打开滑动预览：图片与视频混排，左右滑动切换，视频在对应页可播放
void openMediaPager(BuildContext context, List<MediaPagerItem> items,
    {int start = 0}) {
  if (items.isEmpty) return;
  Navigator.push(context,
      MaterialPageRoute(builder: (_) => MediaPagerView(items: items, start: start)));
}

/// 统一的媒体滑动预览页：PhotoView 看图片，内嵌播放器播视频/实况图
class MediaPagerView extends StatefulWidget {
  final List<MediaPagerItem> items;
  final int start;
  const MediaPagerView({Key? key, required this.items, this.start = 0})
      : super(key: key);

  @override
  State<MediaPagerView> createState() => _MediaPagerViewState();
}

class _MediaPagerViewState extends State<MediaPagerView> {
  late final PageController _pc =
      PageController(initialPage: widget.start);
  late int _idx = widget.start;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pc,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _idx = i),
            itemBuilder: (_, i) {
              final it = widget.items[i];
              if (it.isVideo) {
                // 当前页自动播放，非当前页暂停（切换由 didUpdateWidget 处理）
                return SimpleVideoPlayer(
                  path: it.path,
                  title: it.title,
                  live: it.live,
                  cover: it.cover,
                  autoplay: i == _idx,
                  showTopBar: false,
                );
              }
              return PhotoView(
                imageProvider: FileImage(File(it.path)),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
                backgroundDecoration: const BoxDecoration(color: Colors.black),
              );
            },
          ),
          // 顶部计数条
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_idx + 1} / ${widget.items.length}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
          // 关闭按钮
          Positioned(
            right: 8,
            top: MediaQuery.of(context).padding.top + 4,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 26),
            ),
          ),
        ],
      ),
    );
  }
}

/// 视频/实况图封面：实时截取视频帧显示，不落盘。
/// 优先显示已有的本地缩略图（旧版本遗留）；否则当场解码该视频第一帧，
/// 字节只缓存在内存里，随用随取，失败时兜底显示图标，避免出现黑块。
class VideoCover extends StatefulWidget {
  final String video;
  final String? thumb;
  const VideoCover({Key? key, required this.video, this.thumb}) : super(key: key);

  @override
  State<VideoCover> createState() => _VideoCoverState();
}

class _VideoCoverState extends State<VideoCover> {
  static final Map<String, Uint8List> _memCache = {};
  Uint8List? _bytes;
  String? _thumb;

  @override
  void initState() {
    super.initState();
    final t = widget.thumb;
    if (t != null && t.isNotEmpty) {
      _thumb = t;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    final cached = _memCache[widget.video];
    if (cached != null) {
      _bytes = cached;
      return;
    }
    final b = await Thumbs.videoBytes(widget.video);
    if (!mounted) return;
    if (b != null && b.isNotEmpty) {
      _memCache[widget.video] = b;
      setState(() => _bytes = b);
    } else {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant VideoCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video == widget.video && oldWidget.thumb == widget.thumb) return;
    final t = widget.thumb;
    if (t != null && t.isNotEmpty) {
      _thumb = t;
      _bytes = null;
      return;
    }
    final cached = _memCache[widget.video];
    if (cached != null) {
      _bytes = cached;
      return;
    }
    _thumb = null;
    _bytes = null;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = _thumb;
    if (t != null && t.isNotEmpty && File(t).existsSync()) {
      return Image.file(File(t),
          fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    }
    final b = _bytes;
    if (b != null && b.isNotEmpty) {
      return Image.memory(b,
          fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    }
    return Container(
      color: const Color(0xFF101014),
      alignment: Alignment.center,
      child: const Icon(Icons.videocam_outlined,
          color: Colors.white24, size: 40),
    );
  }
}

/// 自适应视频封面：读取视频真实宽高比，用对应比例展示封面，避免固定高度导致的变形/黑边。
/// 读取失败时回退到固定高度。
///
/// 注意：这里只用缩略图读尺寸，绝不为"测比例"创建同一文件的播放器。
/// 原因跟播放页白屏同源——同文件起多个播放器会抢占解码资源，导致"有声音没画面"。
class AdaptiveVideoCover extends StatefulWidget {
  final String video;
  final String? thumb;
  const AdaptiveVideoCover({Key? key, required this.video, this.thumb})
      : super(key: key);

  @override
  State<AdaptiveVideoCover> createState() => _AdaptiveVideoCoverState();
}

class _AdaptiveVideoCoverState extends State<AdaptiveVideoCover> {
  double _aspect = 0.8;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final t = widget.thumb;
    Uint8List? bytes;
    if (t != null && t.isNotEmpty && File(t).existsSync()) {
      bytes = await File(t).readAsBytes();
    } else {
      bytes = await Thumbs.videoBytes(widget.video);
    }
    if (!mounted || bytes == null || bytes.isEmpty) return;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) return;
      setState(() {
        final fw = frame.image.width;
        final fh = frame.image.height;
        _aspect = (fw > 0 && fh > 0) ? (fw / fh).clamp(0.4, 2.0).toDouble() : 0.8;
      });
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget cover = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(fit: StackFit.expand, children: [
        VideoCover(video: widget.video, thumb: widget.thumb),
        const Center(
          child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 44),
        ),
      ]),
    );
    final maxH = MediaQuery.of(context).size.width * 0.9;
    final ratio = _aspect.clamp(0.4, 2.0);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = (w / ratio).clamp(0.0, maxH);
      return Center(child: SizedBox(width: w, height: h, child: cover));
    });
  }
}

/// 音频播放器：复用 video_player 解码音频文件（mp3 / wav / flac / m4a 等），
/// 提供播放/暂停、进度条、时长的轻量播放器。
class SimpleAudioPlayer extends StatefulWidget {
  final String path;
  final String title;
  const SimpleAudioPlayer({Key? key, required this.path, this.title = ''})
      : super(key: key);

  @override
  State<SimpleAudioPlayer> createState() => _SimpleAudioPlayerState();
}

class _SimpleAudioPlayerState extends State<SimpleAudioPlayer> {
  VideoPlayerController? _vc;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _vc = VideoPlayerController.file(File(widget.path));
    _init();
  }

  Future<void> _init() async {
    final vc = _vc;
    if (vc == null) return;
    try {
      await vc.initialize();
      if (!mounted) {
        vc.dispose();
        return;
      }
      setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _vc?.dispose();
    _vc = null;
    super.dispose();
  }

  void _toggle() {
    final vc = _vc;
    if (vc == null || !_ready) return;
    if (vc.value.isPlaying) {
      vc.pause();
    } else {
      vc.play();
    }
    setState(() {});
  }

  void _seek(double v) {
    final vc = _vc;
    if (vc == null) return;
    final d = vc.value.duration;
    if (d.inMilliseconds > 0) vc.seekTo(d * v);
  }

  String _fmt(Duration d) {
    final h = d.inHours > 0 ? '${d.inHours}:' : '';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h$m:$s';
  }

  Widget _failedView() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.music_off, color: Colors.white70, size: 48),
        const SizedBox(height: 10),
        const Text('无法播放该音频',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF17151B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
      ),
      body: SafeArea(
        child: _failed
            ? _failedView()
            : !_ready
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white70))
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF3A3350), Color(0xFF211D2A)],
                              ),
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: const Icon(Icons.music_note,
                                color: Colors.white70, size: 64),
                          ),
                          const SizedBox(height: 28),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 32),
                            child: ValueListenableBuilder<VideoPlayerValue>(
                              valueListenable: _vc!,
                              builder: (_, v, __) {
                                final d = v.duration;
                                final total = d.inMilliseconds > 0
                                    ? d.inMilliseconds
                                    : 0;
                                final pos = v.position.inMilliseconds
                                    .clamp(0, total > 0 ? total : 1);
                                final frac = total > 0 ? pos / total : 0.0;
                                return Column(children: [
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 4,
                                      activeTrackColor: PlayerTheme.clay,
                                      inactiveTrackColor: Colors.white24,
                                      thumbColor: PlayerTheme.clay,
                                      thumbShape:
                                          const RoundSliderThumbShape(
                                              enabledThumbRadius: 7),
                                    ),
                                    child: Slider(
                                      value: frac.clamp(0.0, 1.0),
                                      onChanged: total > 0 ? _seek : null,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6),
                                    child: Row(children: [
                                      Text(
                                        _fmt(v.position),
                                        style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _fmt(d),
                                        style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 12),
                                      ),
                                    ]),
                                  ),
                                ]);
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                          ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: _vc!,
                            builder: (_, v, __) => IconButton(
                              onPressed: _toggle,
                              iconSize: 76,
                              color: PlayerTheme.clay,
                              icon: Icon(v.isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_fill),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: _vc!,
                            builder: (_, v, __) => Text(
                              v.isPlaying ? '播放中' : '已暂停',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}

/// 打开音频播放页
void openAudio(BuildContext context, String path, {String title = ''}) {
  Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => SimpleAudioPlayer(path: path, title: title)));
}