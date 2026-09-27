import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'db.dart';
import 'screens/auth/login_page.dart';
import 'screens/home_shell.dart';
import 'screens/lock/biometric_unlock.dart';
import 'services/biometric.dart';
import 'services/lan_settings.dart';
import 'services/lan_server.dart';
import 'session.dart';
import 'storage.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Storage.root();
  await Session.instance.init();
  // 指纹（系统生物识别）开启但设备已不支持/未录入时自动降级，避免卡在指纹页。
  final u = Session.instance.user;
  if (u != null && u.biometricEnabled == 1) {
    final sup = await BioAuth.supported();
    final enrolled = sup ? await BioAuth.hasEnrolled() : false;
    if (!sup || !enrolled) {
      await Db.instance.updateUser(u.id!, {
        'biometric': 0,
        'gesture_key': '',
      });
      await Session.instance.init();
    }
  }
  await ThemeController.instance.load();
  await LanSettings.instance.load();
  // 自启动：设置里开启“自启动”且非私密时，进入 App 即自动拉起局域网服务。
  if (!LanSettings.instance.private && LanSettings.instance.autoStart) {
    await LanServer.instance.start();
  }
  // 全局锁竖屏：除播放器内部主动切换横屏外，其余页面始终纵向，
  // 避免解锁页/列表等在横屏态被截断只显示一半。
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ShoesApp());
}

/// 跟随系统亮度变化：以 WidgetsBindingObserver 监听系统深色模式切换，
/// 在”跟随系统“模式下即时刷新 `ThemeController.dark`，实现真正的系统跟随。
class _ThemeHost extends StatefulWidget {
  final Widget child;
  const _ThemeHost({required this.child});
  @override
  State<_ThemeHost> createState() => _ThemeHostState();
}

class _ThemeHostState extends State<_ThemeHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 初始时同步一次当前系统亮度
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _apply();
    });
  }

  @override
  void didChangePlatformBrightness() {
    _apply();
  }

  void _apply() {
    final b = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    ThemeController.instance.applySystem(b);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class ShoesApp extends StatelessWidget {
  const ShoesApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _ThemeHost(
      child: ListenableBuilder(
        listenable: ThemeController.instance,
        builder: (_, __) {
          final tc = ThemeController.instance;
          return MaterialApp(
            title: '拾光',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(dark: false, accent: tc.accent),
            darkTheme: AppTheme.build(dark: true, accent: tc.accent),
            themeMode: tc.themeMode,
            // 关键：页面大量控件直接读 AppTheme 静态色(而非 Theme.of)。
            // 若 home 子树是 const，主题变化时不会重绘，颜色会滞后到下次交互才刷新。
            // 这里用主题快照做 Key，主题(深/浅/主色)每次变化都会重建整棵 home 子树，
            // 让底部导航及各自定义控件即时换肤。
            home: KeyedSubtree(
              key: ValueKey('${tc.dark}:${tc.accent.value}'),
              child: const _Boot(),
            ),
          );
        },
      ),
    );
  }
}

class _Boot extends StatelessWidget {
  const _Boot();

  @override
  Widget build(BuildContext context) {
    // 根据会话状态决定起始页
    Widget next;
    final u = Session.instance.user;
    if (u == null) {
      next = const LoginPage();
    } else if (u.biometricEnabled == 1 ||
        (u.gesture != null && u.gesture!.isNotEmpty)) {
      // 统一解锁页：指纹 + 手势二选一，配了哪种就支持哪种
      next = BiometricUnlockPage();
    } else {
      next = const HomeShell();
    }
    return next;
  }
}