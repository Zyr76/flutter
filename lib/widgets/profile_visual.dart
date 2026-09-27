import 'dart:io';

import 'package:flutter/material.dart';

import '../session.dart';
import '../theme.dart';

/// 圆形头像：有图用图，无图用首字
class ProfileAvatar extends StatelessWidget {
  final String? path;
  final String fallback;
  final double size;
  const ProfileAvatar({
    Key? key,
    this.path,
    required this.fallback,
    this.size = 48,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasImg = path != null && path!.isNotEmpty;
    final f = fallback.isEmpty ? '拾' : fallback.characters.first;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hasImg ? null : AppTheme.sand,
        gradient: hasImg ? null : const LinearGradient(
          colors: [Color(0xFFC9A87F), Color(0xFFBE7E5A)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0,2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasImg
          ? Image.file(File(path!), fit: BoxFit.cover, width: size, height: size)
          : Center(
              child: Text(f, style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w600,
              )),
            ),
    );
  }
}

/// 当前登录用户头像：监听会话变化，换头像后所有使用处自动刷新
class MeAvatar extends StatefulWidget {
  final double size;
  const MeAvatar({Key? key, this.size = 48}) : super(key: key);

  @override
  State<MeAvatar> createState() => _MeAvatarState();
}

class _MeAvatarState extends State<MeAvatar> {
  @override
  void initState() {
    super.initState();
    Session.instance.onChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final u = Session.instance.user;
    return ProfileAvatar(
      path: u?.avatarFile,
      fallback: (u?.nickname.isNotEmpty ?? false) ? u!.nickname : (u?.username ?? '拾'),
      size: widget.size,
    );
  }
}