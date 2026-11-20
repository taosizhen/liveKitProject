import 'package:flutter/material.dart';

import '../../models/user.dart';

/// 用户头像（无头像时用名字首字兜底）
///
/// Demo 数据的 `avatar_url` 为空，必须保证任何场景都能渲染。
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.size = 40,
    this.backgroundColor,
  });

  final AppUser? user;
  final double size;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = user?.avatarUrl;
    final initial = user?.initial ?? '?';
    final bg = backgroundColor ?? const Color(0xFF6366F1);

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: bg,
        backgroundImage: NetworkImage(avatarUrl),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: bg,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
