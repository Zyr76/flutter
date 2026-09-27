import 'package:flutter/material.dart';

import '../../db.dart';
import '../../security.dart';
import '../../services/biometric.dart';
import '../../session.dart';
import '../../theme.dart';

class FingerprintSetupPage extends StatefulWidget {
  const FingerprintSetupPage({Key? key}) : super(key: key);
  @override
  State<FingerprintSetupPage> createState() => _FingerprintSetupPageState();
}

class _FingerprintSetupPageState extends State<FingerprintSetupPage> {
  bool? _supported;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    // 指纹解锁只依赖“指纹”是否可用
    final s = await BioAuth.supported();
    if (mounted) setState(() => _supported = s);
  }

  Future<void> _toggle(bool enable) async {
    if (enable) {
      setState(() => _busy = true);
      final err = await BioAuth.verify('验证指纹以开启指纹解锁', setup: true);
      setState(() => _busy = false);
      if (err != null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(err)));
        }
        return;
      }
      final u = Session.instance.user!;
      // 生成解锁密钥，供后续校验（此处仅做本地标记）
      final key = Security.genKey();
      await Db.instance.updateUser(u.id!, {
        'biometric': 1,
        'gesture_key': Security.obfuscate(key, u.salt),
      });
      await Session.instance.refresh();
      if (mounted) {
        setState(() {}); // 刷新开关显示，确保“开启”后立即反映
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('指纹解锁已开启')));
      }
    } else {
      final u = Session.instance.user!;
      await Db.instance.updateUser(u.id!, {'biometric': 0, 'gesture_key': ''});
      await Session.instance.refresh();
      if (mounted) {
        setState(() {}); // 刷新开关显示，确保“关闭”生效
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已关闭指纹解锁')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = Session.instance.user!;
    final on = u.biometricEnabled == 1;
    final supported = _supported ?? true;
    return Scaffold(
      appBar: AppBar(title: const Text('指纹解锁')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.hairline.withOpacity( 0.6)),
            ),
            child: Row(children: [
              Icon(Icons.fingerprint, size: 30, color: AppTheme.clay),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('使用指纹解锁拾光', style: TextStyle(fontSize: 15)),
              ),
              Switch(
                value: on,
                activeColor: AppTheme.clay,
                onChanged: _busy ? null : _toggle,
              ),
            ]),
          ),
          if (!supported) ...[
            const SizedBox(height: 12),
            Text('当前设备不支持指纹识别。',
                style: TextStyle(color: AppTheme.error, fontSize: 13)),
          ],
          const SizedBox(height: 18),
          Text('开启后，进入应用时将使用指纹快速解锁；即使设置了手势，指纹也能直接通过。',
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.6)),
        ],
      ),
    );
  }
}