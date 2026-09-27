import 'package:flutter/material.dart';

import '../../db.dart';
import '../../security.dart';
import '../../session.dart';
import '../../theme.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({Key? key}) : super(key: key);
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  String? _err;
  bool _busy = false;

  Future<void> _save() async {
    final u = Session.instance.user!;
    final old = _old.text;
    final nw = _new.text;
    final cf = _confirm.text;
    if (old.isEmpty || nw.isEmpty) return _fail('请填写原始密码和新密码');
    final oldHash = Security.hashPassword(u.salt, u.username, old);
    if (oldHash != u.passwordHash) return _fail('原始密码不正确');
    if (nw.length < 4) return _fail('新密码至少 4 位');
    if (nw != cf) return _fail('两次输入的新密码不一致');

    setState(() { _busy = true; _err = null; });
    final salt = Security.genSalt();
    final hash = Security.hashPassword(salt, u.username, nw);
    await Db.instance.updateUser(u.id!, {'salt': salt, 'password_hash': hash});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密码已更新')));
    Navigator.pop(context);
  }

  void _fail(String m) => setState(() { _err = m; _busy = false; });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('修改密码')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(controller: _old, obscureText: true,
              decoration: const InputDecoration(hintText: '当前密码')),
          const SizedBox(height: 14),
          TextField(controller: _new, obscureText: true,
              decoration: const InputDecoration(hintText: '新密码（至少 4 位）')),
          const SizedBox(height: 14),
          TextField(controller: _confirm, obscureText: true,
              decoration: const InputDecoration(hintText: '确认新密码')),
          if (_err != null) ...[
            const SizedBox(height: 14),
            Text(_err!, style: TextStyle(color: AppTheme.error, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('保存新密码'),
          ),
        ],
      ),
    );
  }
}