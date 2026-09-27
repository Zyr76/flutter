import 'package:flutter/material.dart';

import '../../db.dart';
import '../../security.dart';
import '../../session.dart';
import '../../theme.dart';
import '../../widgets/gesture_pad.dart';

class GestureSetupPage extends StatefulWidget {
  const GestureSetupPage({Key? key}) : super(key: key);
  @override
  State<GestureSetupPage> createState() => _GestureSetupPageState();
}

enum _Step { none, first, confirm }

class _GestureSetupPageState extends State<GestureSetupPage> {
  _Step _step = _Step.none;
  List<int>? _first;
  String _hint = '';
  int _view = 0;

  @override
  void initState() {
    super.initState();
    _view = Session.instance.user?.gesture == null ? 0 : 1;
  }

  void _start() {
    setState(() {
      _view = 1;
      _step = _Step.first;
      _first = null;
      _hint = '请绘制你的专属手势（至少连接 4 个点）';
    });
  }

  void _retry() {
    setState(() {
      _step = _Step.first;
      _first = null;
      _hint = '请重新绘手势';
    });
  }

  void _onComplete(List<int> seq) {
    if (_step == _Step.first) {
      setState(() {
        _first = seq;
        _step = _Step.confirm;
        _hint = '再次绘制以确认';
      });
    } else if (_step == _Step.confirm) {
      if (GestureCode.encode(seq) == GestureCode.encode(_first!)) {
        _save(seq);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('两次绘制不一致，请重新开始')));
        _retry();
      }
    }
  }

  Future<void> _save(List<int> seq) async {
    final u = Session.instance.user!;
    final code = GestureCode.encode(seq);
    await Db.instance.updateUser(u.id!, {'gesture': code});
    await Session.instance.refresh();
    if (mounted) {
      setState(() { _view = 1; _step = _Step.none; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('手势解锁已开启')));
    }
  }

  Future<void> _close() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('关闭手势解锁？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('关闭')),
        ],
      ),
    );
    if (r == true) {
      final u = Session.instance.user!;
      await Db.instance.updateUser(u.id!, {'gesture': null});
      await Session.instance.refresh();
      if (mounted) {
        setState(() { _view = 0; _step = _Step.none; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已关闭手势解锁')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('手势解锁')),
      body: _view == 0
          ? _enabled_view()
          : _setup_view(),
    );
  }

  /// 未开启
  Widget _enabled_view() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(children: [
        const Spacer(),
        Icon(Icons.gesture, size: 64, color: AppTheme.clay),
        const SizedBox(height: 16),
        Text('用一笔一划，守护你的私密空间', style: TextStyle(fontSize: 15, color: AppTheme.inkSoft)),
        const Spacer(),
        ElevatedButton(
          onPressed: _start,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('设置手势'),
        ),
        const Spacer(flex: 2),
      ]),
    );
  }

  /// 绘制中 / 已开启
  Widget _setup_view() {
    final configured = _step == _Step.none;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 12),
        AnimatedSwitcher(duration: const Duration(milliseconds: 200),
          child: Text(configured ? '当前已开启手势解锁' : _hint, key: ValueKey(configured),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: configured ? AppTheme.inkSoft : AppTheme.ink)),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.hairline),
          ),
          child: SizedBox(
            width: 280, height: 280,
            child: GesturePad(onComplete: _onComplete),
          ),
        ),
        const SizedBox(height: 20),
        if (!configured)
          TextButton(onPressed: _retry, child: const Text('重画')),
        if (configured) ...[
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton(
              onPressed: _start,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.clayDeep,
                side: BorderSide(color: AppTheme.hairline),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('更换手势'),
            ),
            const SizedBox(width: 12),
            TextButton(onPressed: _close, child: Text('关闭', style: TextStyle(color: AppTheme.error))),
          ]),
        ],
      ]),
    );
  }
}