import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_config.dart';
import '../../core/widgets/user_avatar.dart';
import '../auth/auth_controller.dart';

/// 我的页面
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    final config = ref.watch(appConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                UserAvatar(user: user, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? '未登录',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.email ?? '',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          user?.roleLabel ?? '',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF4F46E5)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _settingTile(
            icon: Icons.dns_outlined,
            title: '服务器地址',
            subtitle: config.apiBase,
          ),
          _settingTile(
            icon: Icons.info_outline_rounded,
            title: '版本',
            subtitle: '0.1.0（Phase 1 MVP）',
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('退出登录'),
                    content: const Text('退出后需要重新输入账号密码，确认退出？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('退出'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                await ref.read(authControllerProvider.notifier).logout();
                if (!context.mounted) return;
                context.go('/login');
              },
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('退出登录'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFFECACA)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 设置项
  Widget _settingTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF64748B)),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Flexible(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );
  }
}
