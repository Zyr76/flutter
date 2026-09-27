import 'package:flutter/material.dart';

import '../../security.dart';
import '../../session.dart';
import '../../services/biometric.dart';
import '../../theme.dart';
import '../../widgets/gesture_pad.dart';
import '../../widgets/profile_visual.dart';
import '../auth/login_page.dart';
import '../home_shell.dart';

/// 解锁页：支持指纹（生物识别）+ 手势双重验证，
/// 拥有对应能力的入口在页内一键切换，不强制单一方式。
class BiometricUnlockPage extends StatefulWidget {
  @override
  State<BiometricUnlockPage> createState() => _BiometricUnlockPageState();
}

class _BiometricUnlockPageState extends State<BiometricUnlockPage> {
  bool _busy = false;
  String _msg = '';
  bool _err = false;

  // 是否展示手势面板（false = 生物识别模式）
  bool _gestureMode = false;

  // 设备生物识别类型掩码：1=指纹 3=两者（解锁只使用指纹）
  int _bioMask = 1;

  String _gestureHint = '绘制手势解锁';
  Color _gestureHintColor = Colors.white70;
  int _gestureFail = 0;

  Session get _s => Session.instance;
  // 指纹解锁独立开关
  bool get _hasFingerEnroll => _s.user?.biometricEnabled == 1;
  bool get _hasGesture {
    final g = _s.user?.gesture;
    return g != null && g.isNotEmpty;
  }
  // 设备层面是否真的录入了指纹
  bool get _devHasFinger => (_bioMask & 1) != 0;

  @override
  void initState() {
    super.initState();
    // 若只配了手势没配指纹，默认进手势面板，不去拉起生物识别
    if (_hasGesture && !_hasFingerEnroll) {
      _gestureMode = true;
    }
    // 读取设备生物识别类型；等首帧后再拉起系统识别，避免个别机型弹窗被丢弃
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final m = await BioAuth.availableTypes();
      if (mounted) {
        setState(() => _bioMask = m);
      }
      // 系统指纹就绪时自动拉起，一进页面即可按指纹解锁
      if (mounted && !_gestureMode) _tryBio();
    });
  }

  // 系统指纹验证
  Future<void> _tryBio() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = '';
      _err = false;
    });
    final err = await BioAuth.verify('验证指纹以解锁拾光');
    if (err == null && mounted) {
      _enter();
      return;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _err = true;
        _msg = err ?? '验证失败或已取消，请重试';
      });
    }
  }

  void _enter() {
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()), (_) => false);
  }

  // 手势验证
  void _verifyGesture(List<int> seq) {
    final saved = _s.user?.gesture ?? '';
    if (saved.isNotEmpty && GestureCode.encode(seq) == saved) {
      _enter();
      return;
    }
    _gestureFail++;
    setState(() {
      _gestureHint = _gestureFail >= 5 ? '错误次数过多，请用密码登录' : '手势错误，请重试';
      _gestureHintColor = AppTheme.error;
    });
    if (_gestureFail >= 5) {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) _logout();
      });
    }
  }

  void _switchToGesture() {
    setState(() {
      _gestureMode = true;
      _busy = false;
      _err = false;
      _msg = '';
    });
  }

  void _logout() {
    Session.instance.logout();
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = Session.instance.user;
    final mh = MediaQuery.of(context).size.height;
    final fingerOk = _hasFingerEnroll && _devHasFinger;
    final gestureOk = _hasGesture;
    final modeCount = (fingerOk ? 1 : 0) + (gestureOk ? 1 : 0);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3A3138), Color(0xFF1C1A22), Color(0xFF0F0E14)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: mh * 0.03),
                    // 品牌
                    Container(
                      width: 88,
                      height: 88,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFE8C9A0), Color(0xFFD98E5F)],
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: Color(0x4438414d),
                              blurRadius: 28, offset: Offset(0, 14)),
                        ],
                      ),
                      child: const Text('拾',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 22),
                    Text('欢迎回来',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      MeAvatar(size: 22),
                      const SizedBox(width: 8),
                      Text(user?.nickname ?? '',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontSize: 14)),
                    ]),
                    const SizedBox(height: 26),
                    // 切换方式（多于一种时才显示）
                    if (modeCount >= 2) _modeSwitch(fingerOk, gestureOk),
                    const SizedBox(height: 18),
                    // 生物识别 / 手势 主区域
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _gestureMode
                          ? _gestureCard()
                          : _fingerCard(),
                    ),
                    const SizedBox(height: 26),
                    // 操作按钮区
                    if (!_gestureMode) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _tryBio,
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('重新指纹验证',
                              style: TextStyle(fontSize: 16)),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD98E5F),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      if (gestureOk)
                        TextButton(
                          onPressed: () => setState(() => _gestureMode = true),
                          child: const Text('改用手势解锁',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ),
                    ] else if (fingerOk)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: () => setState(() => _gestureMode = false),
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('改用指纹验证',
                              style: TextStyle(fontSize: 16)),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD98E5F),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _logout,
                      child: Text('使用账号密码登录',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 13)),
                    ),
                    SizedBox(height: mh * 0.03),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 指纹验证卡片
  Widget _fingerCard() {
    return AnimatedContainer(
      key: const ValueKey('fp'),
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 40),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(_busy ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(_err ? 0.5 : 0.12)),
        boxShadow: _err
            ? [BoxShadow(color: AppTheme.error.withOpacity(0.25), blurRadius: 30)]
            : null,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedScale(
          duration: const Duration(milliseconds: 200),
          scale: _busy ? 0.9 : 1.0,
          child: Stack(alignment: Alignment.center, children: [
            const Icon(Icons.fingerprint,
              size: 96,
              color: Colors.white,
            ),
            if (_busy)
              const Positioned.fill(
                child: Center(child: SizedBox(
                    width: 26, height: 26,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white70))),
              ),
          ]),
        ),
        const SizedBox(height: 18),
        Text(
          _busy
              ? '正在验证，请将手指放在传感器上'
              : (_msg.isEmpty ? '请将手指放在指纹传感器上' : _msg),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _err ? AppTheme.error : Colors.white70,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ]),
    );
  }

  // 手势验证卡片
  Widget _gestureCard() {
    return Container(
      key: const ValueKey('gesture'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
            color: Colors.white.withOpacity(_gestureFail > 0 ? 0.5 : 0.12)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          _gestureHint,
          textAlign: TextAlign.center,
          style: TextStyle(color: _gestureHintColor, fontSize: 14),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 240,
          height: 240,
          child: GesturePad(
            activeColor: const Color(0xFFE8C9A0),
            onComplete: _verifyGesture,
          ),
        ),
        if (_hasFingerEnroll) ...[
          const SizedBox(height: 8),
          Text('或切换到指纹验证',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
        ],
      ]),
    );
  }

  // 顶部方式切换胶囊
  Widget _modeSwitch(bool fingerOk, bool gestureOk) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (fingerOk)
          _switchChip(
            icon: Icons.fingerprint,
            label: '指纹',
            selected: !_gestureMode,
            onTap: () => setState(() => _gestureMode = false),
          ),
        if (gestureOk)
          _switchChip(
            icon: Icons.gesture,
            label: '手势',
            selected: _gestureMode,
            onTap: _switchToGesture,
          ),
      ]),
    );
  }

  Widget _switchChip({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFD98E5F) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 18,
              color: selected ? Colors.white : Colors.white60),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ]),
      ),
    );
  }
}
