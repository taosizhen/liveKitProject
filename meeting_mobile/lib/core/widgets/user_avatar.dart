import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import '../../models/user.dart';

/// 用户头像（无头像时用名字首字兜底）
///
/// 后端返回的 `avatar_url` 可能是 `/storage/...` 相对路径，
/// 这里统一拼接服务器根地址后再交给 NetworkImage。
class UserAvatar extends ConsumerWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.size = 40,
    this.backgroundColor,
  });

  final AppUser? user;
  final double size;
  final Color? backgroundColor;

  /// 把后端头像地址解析为可访问的完整 URL（相对路径拼服务器根地址）
  static String? resolveUrl(String? avatarUrl, String apiBaseUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty) return null;
    if (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://')) {
      return avatarUrl;
    }
    return '$apiBaseUrl$avatarUrl';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiBaseUrl = ref.watch(appConfigProvider).apiBaseUrl;
    final resolved = resolveUrl(user?.avatarUrl, apiBaseUrl);
    final initial = user?.initial ?? '?';
    final bg = backgroundColor ?? const Color(0xFF6366F1);

    if (resolved != null) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: bg,
        backgroundImage: NetworkImage(resolved),
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
