import 'dart:io';

import 'package:flutter/material.dart';

import '../../db.dart';
import '../../security.dart';
import '../../services/picker.dart';
import '../../session.dart';
import '../../storage.dart';
import '../../theme.dart';
import '../home_shell.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({Key? key}) : super(key: key);
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  String? _avatarPath;
  bool _busy = false;
  String? _err;

  Future<void> _pickAvatar() async {
    final p = await Picker.image();
    if (p != null && mounted) setState(() => _avatarPath = p);
  }

  Future<void> _register() async {
    final username = _user.text.trim();
    final pass = _pass.text;
    final confirm = _confirm.text;
    if (username.length < 2) return _fail('账号至少 2 个字符');
    if (pass.length < 4) return _fail('密码至少 4 位');
    if (pass != confirm) return _fail('两次输入的密码不一致');
    setState(() { _busy = true; _err = null; });

    final exist = await Db.instance.getUserByName(username);
    if (exist != null) {
      setState(() { _busy = false; _err = '该账号已被注册'; });
      return;
    }

    final salt = Security.genSalt();
    final hash = Security.hashPassword(salt, username, pass);
    String? avatarRel;
    if (_avatarPath != null) {
      final ext = _avatarPath!.split('.').lastOrNull ?? 'png';
      final name = Storage.newName(ext.toLowerCase());
      avatarRel = await Storage.import(_avatarPath!, 'avatars', name: name);
    }
    final uid = await Db.instance.insertUser({
      'username': username,
      'salt': salt,
      'password_hash': hash,
      'nickname': username,
      'avatar_file': avatarRel,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    if (!mounted) return;
    // 注册成功：写入会话并自动登录进入首页
    final created = await Db.instance.getUserById(uid);
    if (created != null) await Session.instance.login(created);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (_) => false,
    );
  }

  void _fail(String msg) => setState(() { _err = msg; _busy = false; });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              ),
            ),
            const SizedBox(height: 6),
            const Text('创建账号', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: 1)),
            const SizedBox(height: 8),
            Text('注册后即可开始记录你的私密空间', style: TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
            const SizedBox(height: 32),
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(children: [
                  Container(
                    width: 92, height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.sand,
                      border: Border.all(color: AppTheme.hairline),
                      image: _avatarPath == null ? null :
                          DecorationImage(image: FileImage(File(_avatarPath!)), fit: BoxFit.cover),
                    ),
                    child: _avatarPath == null
                        ? Icon(Icons.person_add_alt_1, color: AppTheme.clayDeep, size: 34)
                        : null,
                  ),
                  Positioned(right: 0, bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.clay,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.photo_camera, size: 14, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Center(child: Text('点击设置头像', style: TextStyle(fontSize: 12, color: AppTheme.inkSoft))),
            const SizedBox(height: 30),
            TextField(controller: _user, decoration: const InputDecoration(hintText: '账号')),
            const SizedBox(height: 14),
            TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(hintText: '密码（至少 4 位）')),
            const SizedBox(height: 14),
            TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(hintText: '确认密码')),
            if (_err != null) ...[
              const SizedBox(height: 14),
              Text(_err!, textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.error, fontSize: 13)),
            ],
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _busy ? null : _register,
              child: _busy
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('注 册'),
            ),
          ],
        ),
      ),
    );
  }
}