import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';

/// 启动页
///
/// 读取 secure_storage 中的 refresh_token：
/// - 成功换到 access_token → 进入会议列表
/// - 无 token / 刷新失败 → 进入登录页
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// 执行冷启动登录态恢复并跳转
  Future<void> _bootstrap() async {
    final loggedIn = await ref.read(authControllerProvider.notifier).bootstrap();
    if (!mounted) return;
    context.go(loggedIn ? '/meetings' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4F46E5), Color(0xFF1E1B4B)],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.video_camera_front_rounded,
                  size: 72, color: Colors.white),
              SizedBox(height: 16),
              Text(
                '会议协助平台',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 28),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
