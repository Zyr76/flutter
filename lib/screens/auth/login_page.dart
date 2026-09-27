import 'package:flutter/material.dart';

import '../../db.dart';
import '../../security.dart';
import '../../services/migration.dart';
import '../../services/picker.dart';
import '../../session.dart';
import '../../storage.dart';
import '../../theme.dart';
import '../home_shell.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  final Widget? next; // 解锁通过后跳转
  const LoginPage({Key? key, this.next}) : super(key: key);
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _err;

  Future<void> _login() async {
    final username = _user.text.trim();
    final password = _pass.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _err = '请填写账号和密码');
      return;
    }
    setState(() { _busy = true; _err = null; });
    final u = await Db.instance.getUserByName(username);
    if (u == null) {
      setState(() { _busy = false; _err = '账号不存在'; });
      return;
    }
    final hash = Security.hashPassword(u.salt, username, password);
    if (hash != u.passwordHash) {
      setState(() { _busy = false; _err = '密码不正确'; });
      return;
    }
    await Session.instance.login(u);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (_) => false,
    );
  }

  void _goRegister() {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RegisterPage()));
  }

  /// 从备份 zip 恢复账号数据，成功后提示可登录的账号。
  Future<void> _importAccount() async {
    final picked = await Picker.file();
    if (picked == null || picked.path.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // 带进度的导入对话框（子隔离区后台执行，界面不卡顿）
    final progress = ValueNotifier<double>(0);
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImportProgressDialog(progress: progress),
    );
    try {
      final names = await MigrationService.instance.import(picked.path,
          onProgress: (v) => progress.value = v);
      navigator.pop();
      if (!mounted) return;
      if (names.isEmpty) {
        messenger.showSnackBar(
            const SnackBar(content: Text('导入完成，但备份中没有账号，请重新注册')));
        return;
      }
      // 导入成功：提示可登录的账号，点击填入账号输入框
      final chosen = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('导入成功'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('备份已恢复，可用以下账号登录：', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            for (final n in names) ...[
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.pop(context, n),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(children: [
                    Icon(Icons.person_outline, size: 18, color: AppTheme.clay),
                    const SizedBox(width: 8),
                    Text('@$n', style: const TextStyle(fontSize: 14)),
                  ]),
                ),
              ),
            ],
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
          ],
        ),
      );
      if (chosen != null && chosen.isNotEmpty && mounted) {
        setState(() {
          _user.text = chosen;
          _pass.clear();
          _err = null;
        });
      }
    } catch (e) {
      navigator.pop();
      if (mounted) {
        messenger.showSnackBar(SnackBar(
            content: Text('导入失败：$e'), duration: const Duration(seconds: 4)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Positioned(
            top: 0,
            child: ClipPath(
              clipper: _WaveClipper(),
              child: Container(
                width: MediaQuery.of(context).size.width,
                height: 300,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.sand, AppTheme.bg],
                  ),
                ),
              ),
            ),
          ),
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            children: [
              const SizedBox(height: 110),
              Center(
                child: Container(
                  width: 86, height: 86,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.surface,
                    border: Border.all(color: AppTheme.hairline),
                  ),
                  child: Text('拾',
                      style: TextStyle(
                          fontSize: 46, color: AppTheme.clayDeep,
                          fontWeight: FontWeight.w300, height: 1)),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Text('拾光', style: TextStyle(
                    fontSize: 30, letterSpacing: 8, color: AppTheme.ink,
                    fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text('私密个人空间 · 只属于你的记录', style: TextStyle(
                    fontSize: 13, color: AppTheme.inkSoft, letterSpacing: 1)),
              ),
              const SizedBox(height: 44),
              TextField(
                controller: _user,
                decoration: const InputDecoration(hintText: '账号'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(hintText: '密码'),
                onSubmitted: (_) => _login(),
              ),
              if (_err != null) ...[
                const SizedBox(height: 14),
                Text(_err!, textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.error, fontSize: 13)),
              ],
              const SizedBox(height: 26),
              ElevatedButton(
                onPressed: _busy ? null : _login,
                child: _busy
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('登 录'),
              ),
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: _goRegister,
                  child: Text('没有账号？去注册', style: TextStyle(
                      color: AppTheme.clayDeep, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton.icon(
                  onPressed: _importAccount,
                  icon: const Icon(Icons.file_upload_outlined, size: 16),
                  label: const Text('导入账号数据（恢复备份）', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.inkSoft),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ]),
      ),
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..lineTo(0, size.height - 60)
      ..quadraticBezierTo(size.width * 0.25, size.height,
          size.width * 0.5, size.height - 40)
      ..quadraticBezierTo(size.width * 0.75, size.height - 90,
          size.width, size.height - 50)
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// 恢复备份（导入账号数据）时的进度弹窗。
class _ImportProgressDialog extends StatelessWidget {
  final ValueNotifier<double> progress;
  const _ImportProgressDialog({Key? key, required this.progress})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('正在恢复备份…', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, v, __) {
              final pct = (v * 100).clamp(0, 100).toStringAsFixed(0);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 7,
                      backgroundColor: AppTheme.hairline,
                      color: AppTheme.clay,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('$pct%', style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text('后台解压中，界面不会卡顿，请稍候…', style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
        ]),
      ),
    );
  }
}