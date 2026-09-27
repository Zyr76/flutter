import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';
import 'models.dart';

/// 当前的登录态与会话（内存 + SharedPreferences 持久化 userId）
class Session {
  Session._();

  static final Session instance = Session._();

  User? user;
  static const _k = 'ps_login_user';

  final StreamController<User?> _ctrl = StreamController.broadcast();
  Stream<User?> get onChange => _ctrl.stream;

  bool get loggedIn => user != null;

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    final id = sp.getInt(_k);
    if (id != null) {
      final u = await Db.instance.getUserById(id);
      if (u != null) user = u;
    }
  }

  Future<void> login(User u) async {
    user = u;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_k, u.id!);
    _ctrl.add(u);
  }

  Future<void> refresh() async {
    if (user == null) return;
    final u = await Db.instance.getUserById(user!.id!);
    if (u != null) user = u;
    _ctrl.add(user);
  }

  Future<void> logout() async {
    user = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_k);
    _ctrl.add(null);
  }
}