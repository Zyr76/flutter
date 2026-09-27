import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../theme.dart';

/// 语音相关能力：录音（发送语音）。
/// 录音用 record 插件写本地音频。

class RecordResult {
  final String path;
  final int durationMs;
  RecordResult(this.path, this.durationMs);
}

/// 打开“发送语音”录音弹层。
/// 返回录好的音频文件绝对路径；取消或录音过短返回 null。
Future<String?> showVoiceRecorder(BuildContext context) async {
  final r = await showModalBottomSheet<RecordResult>(
    context: context,
    isDismissible: false,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => const _VoiceRecorderSheet(),
  );
  if (r == null) return null;
  if (r.durationMs < 1000) return null; // 过短视为无效
  return r.path;
}

// -------------------------------------------------------------- 录音 ----

class _VoiceRecorderSheet extends StatefulWidget {
  const _VoiceRecorderSheet();
  @override
  State<_VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<_VoiceRecorderSheet> {
  AudioRecorder? _recorder;
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _timer;
  Stopwatch? _clock;
  double _level = 0.0; // 0~1 音量
  bool _recording = false;
  String? _outPath;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final recorder = AudioRecorder();
    _recorder = recorder;
    final ok = await recorder.hasPermission();
    if (!mounted) {
      if (ok) recorder.dispose();
      return;
    }
    setState(() {});
    if (!ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未获得麦克风权限，无法录音')));
      return;
    }
    final tmp = await getTemporaryDirectory();
    final name = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _outPath = '${tmp.path}/$name';
    try {
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          numChannels: 1,
          bitRate: 96000,
          autoGain: true,
          noiseSuppress: true,
        ),
        path: _outPath!,
      );
      if (!mounted) return;
      _clock = Stopwatch()..start();
      setState(() => _recording = true);
      _ampSub = recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((a) {
        // current 为 -160~0 dBFS，映射到 0~1
        final v = ((a.current + 160) / 160).clamp(0.0, 1.0);
        if (mounted) setState(() => _level = v);
      });
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() {});
      });
    } catch (_) {
      recorder.dispose();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('录音启动失败')));
      }
    }
  }

  String _fmt(int ms) {
    final s = (ms / 1000).floor();
    final m = (s / 60).floor();
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  Future<void> _finish() async {
    _timer?.cancel();
    _ampSub?.cancel();
    final recorder = _recorder;
    String? path;
    if (recorder != null && _recording) {
      try {
        path = await recorder.stop();
      } catch (_) {
        path = null;
      }
    }
    _clock?.stop();
    final elapsedMs = _clock?.elapsedMilliseconds ?? 0;
    _recorder?.dispose();
    if (!mounted) return;
    Navigator.pop(
        context, RecordResult(path ?? '', elapsedMs));
  }

  Future<void> _cancelRec() async {
    _timer?.cancel();
    _ampSub?.cancel();
    final recorder = _recorder;
    if (recorder != null && _recording) {
      try {
        await recorder.cancel();
      } catch (_) {}
    }
    _recorder?.dispose();
    final p = _outPath;
    if (p != null && p.isNotEmpty) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final ms = _clock?.elapsedMilliseconds ?? 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Expanded(
              child: Text('发送语音',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            GestureDetector(
              onTap: _cancelRec,
              child: Icon(Icons.close, color: AppTheme.inkSoft, size: 22),
            ),
          ]),
          const SizedBox(height: 18),
          Text(_fmt(ms),
              style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [ui.FontFeature.tabularFigures()])),
          const SizedBox(height: 18),
          // 音量波形
          Container(
            width: w - 80,
            height: 36,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < 24; i++)
                  Container(
                    width: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    height: (4 + _level * 28 * (0.4 + 0.6 * ((i % 5) / 5)))
                        .clamp(3.0, 32.0),
                    decoration: BoxDecoration(
                      color: AppTheme.clay.withOpacity(0.4 + _level * 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Material(
            color: AppTheme.error.withOpacity(0.1),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _finish,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Icon(Icons.stop_circle, color: AppTheme.error, size: 44),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('点击红色按钮结束录音',
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
        ]),
      ),
    );
  }
}
