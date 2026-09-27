import 'dart:io';

import 'package:flutter/material.dart';

import '../../db.dart';
import '../../services/migration.dart';
import '../../services/picker.dart';
import '../../services/share.dart';
import '../../session.dart';
import '../../storage.dart';
import '../../theme.dart';
import '../../widgets/profile_visual.dart';
import '../auth/login_page.dart';
import 'change_background.dart';
import 'change_password.dart';
import 'fingerprint_setup.dart';
import 'gesture_setup.dart';
import 'lan_space_page.dart';
import 'theme_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    Session.instance.onChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _changeAvatar() async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const ChangeAvatarPage()));
    if (ok == true) Session.instance.refresh();
  }

  Future<void> _editNickname() async {
    final u = Session.instance.user!;
    final c = TextEditingController(text: u.nickname);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('修改昵称'),
        content: TextField(controller: c, autofocus: true,
            decoration: const InputDecoration(hintText: '昵称', isDense: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('保存')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || name.trim() == u.nickname) return;
    await Db.instance.updateUser(u.id!, {'nickname': name.trim()});
    Session.instance.refresh();
  }

  void _logout() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('退出登录？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Session.instance.logout();
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
            },
            child: Text('退出', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  /// 导出整个空间为备份 zip 到下载目录。
  /// 先弹出二级确认框，再在子隔离区后台导出，导出期间展示带进度条的对话框。
  Future<void> _exportData() async {
    final messenger = ScaffoldMessenger.of(context);
    // 1) 二级确认弹窗
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('备份空间数据？'),
        content: const Text(
            '将把整个空间（账号数据库 + 全部图片/视频/文件）压缩导出到手机下载目录。\n'
            '导出期间请勿关闭应用。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始备份'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    // 2) 带进度条的导出对话框（子隔离区后台执行，界面不卡顿）
    final progress = ValueNotifier<double>(0);
    // 记录顶层 Navigator，之后用它关掉进度弹窗
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExportProgressDialog(progress: progress),
    );

    try {
      final saved = await MigrationService.instance.export(
        onProgress: (v) => progress.value = v,
      );
      if (!mounted) return;
      navigator.pop(); // 关闭进度弹窗
      messenger.showSnackBar(SnackBar(
        content: Text('备份已导出：$saved'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '分享',
          onPressed: () => ShareX.one(saved),
        ),
      ));
    } catch (e) {
      progress.value = 0.0;
      navigator.pop();
      if (mounted) {
        messenger.showSnackBar(SnackBar(
            content: Text('导出失败：$e'), duration: const Duration(seconds: 4)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = Session.instance.user!;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // 账号卡
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [const Color(0xFF51463A), const Color(0xFF2E2A24)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(children: [
              MeAvatar(size: 58),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u.nickname, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text('@${u.username}', style: TextStyle(color: Colors.white.withOpacity( 0.7), fontSize: 12)),
                ]),
              ),
              const Icon(Icons.favorite, color: Color(0xFFD9A76A), size: 22),
            ]),
          ),
          // 分组
          _group('账号设置', [
            _tile(Icons.face_outlined, '更换头像', () => _changeAvatar()),
            _tile(Icons.badge_outlined, '修改昵称', _editNickname),
            _tile(Icons.photo_outlined, '更换空间背景', () async {
              final ok = await Navigator.push<bool>(context,
                  MaterialPageRoute(builder: (_) => const ChangeBackgroundPage()));
              if (ok == true) Session.instance.refresh();
            }),
            _tile(Icons.lock_outline, '修改密码', () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ChangePasswordPage()));
            }),
          ]),
          _group('安全', [
            _tile(Icons.gesture, '手势解锁',
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const GestureSetupPage())),
                trailing: u.gesture == null ? null : _chip('已开启')),
            _tile(Icons.fingerprint, '指纹解锁',
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const FingerprintSetupPage())),
                trailing: u.biometricEnabled == 1 ? _chip('已开启') : null),
          ]),
          _group('外观', [
            _tile(Icons.palette_outlined, '主题与配色',
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ThemeSettingsPage())),
                trailing: _themeChip()),
          ]),
          _group('局域网空间', [
            _tile(Icons.wifi_tethering, '局域网分享',
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LanSpacePage()))),
          ]),
          _group('数据', [
            _tile(Icons.file_download_outlined, '导出空间数据（备份）', _exportData),
          ]),
          _group('其他', [
            _tile(Icons.info_outline, '关于拾光', () => _about()),
          ]),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton(
              onPressed: _logout,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: BorderSide(color: AppTheme.error.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('退出登录'),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _chip(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.sage.withOpacity( 0.16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(s, style: TextStyle(fontSize: 11, color: AppTheme.sage)),
      );

  Widget _themeChip() => Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ThemeController.instance.accent,
          border: Border.all(color: AppTheme.hairline),
        ),
      );

  Widget _group(String title, List<Widget> tiles) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
          child: Text(title, style: TextStyle(fontSize: 12, color: AppTheme.inkSoft, fontWeight: FontWeight.w600)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.hairline.withOpacity( 0.6)),
          ),
          child: Column(children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 54, color: AppTheme.hairline),
              tiles[i],
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _tile(IconData icon, String title, VoidCallback onTap, {Widget? trailing}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, color: AppTheme.clayDeep, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      trailing: Trailing(tr: trailing),
      onTap: onTap,
    );
  }

  void _about() {
    showAboutDialog(
      context: context,
      applicationName: '拾光',
      applicationVersion: '1.0.0',
      children: [
        Text('私密个人空间动态记录。\n说说、日志、时间胶囊、空间相册、空间文件，都只属于你，始终于此。',
            style: TextStyle(color: AppTheme.inkSoft)),
      ],
    );
  }
}

class Trailing extends StatelessWidget {
  final Widget? tr;
  const Trailing({Key? key, this.tr}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (tr != null) tr!,
      const SizedBox(width: 4),
      Icon(Icons.chevron_right, color: AppTheme.inkSoft, size: 20),
    ]);
  }
}

/// 更换头像页
class ChangeAvatarPage extends StatefulWidget {
  const ChangeAvatarPage({Key? key}) : super(key: key);
  @override
  State<ChangeAvatarPage> createState() => _ChangeAvatarPageState();
}

class _ChangeAvatarPageState extends State<ChangeAvatarPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('更换头像')),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 160, height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.sand,
              image: _hasAvatar()
                  ? DecorationImage(image: FileImage(File(Session.instance.user!.avatarFile!)), fit: BoxFit.cover)
                  : null,
            ),
            child: _hasAvatar() ? null : Icon(Icons.person, size: 70, color: AppTheme.clayDeep),
          ),
          const SizedBox(height: 30),
          FilledButton.icon(
            onPressed: _pickGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('从相册选择'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickCamera,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('拍照'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.clayDeep,
              side: BorderSide(color: AppTheme.hairline),
              padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          if (_hasAvatar())
            TextButton(onPressed: _clear, child: Text('恢复默认头像', style: TextStyle(color: AppTheme.inkSoft))),
        ]),
      ),
    );
  }

  bool _hasAvatar() {
    final a = Session.instance.user?.avatarFile;
    return a != null && a.isNotEmpty;
  }

  Future<void> _save(String src) async {
    final u = Session.instance.user!;
    final ext = src.split('.').lastOrNull ?? 'png';
    final name = Storage.newName(ext.toLowerCase());
    final abs = await Storage.ensureInApp(src, 'avatars', name);
    await Db.instance.updateUser(u.id!, {'avatar_file': abs});
    if (mounted) {
      await Session.instance.refresh();
      Navigator.pop(context, true);
    }
  }

  Future<void> _pickGallery() async {
    final p = await Picker.image();
    if (p != null) _save(p);
  }

  Future<void> _pickCamera() async {
    final p = await Picker.cameraImage();
    if (p != null) _save(p);
  }

  Future<void> _clear() async {
    final u = Session.instance.user!;
    await Storage.delete(u.avatarFile);
    await Db.instance.updateUser(u.id!, {'avatar_file': null});
    await Session.instance.refresh();
    if (mounted) Navigator.pop(context, true);
  }
}

/// 导出备份时的进度弹窗。
class _ExportProgressDialog extends StatelessWidget {
  final ValueNotifier<double> progress;
  const _ExportProgressDialog({Key? key, required this.progress})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('正在导出备份…', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
          Text('后台执行中，界面不会卡顿，请稍候…', style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
        ]),
      ),
    );
  }
}