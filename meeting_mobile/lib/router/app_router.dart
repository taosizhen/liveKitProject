import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/home/home_shell.dart';
import '../features/meeting/meeting_detail_screen.dart';
import '../features/meeting/meeting_list_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/room/room_screen.dart';
import '../features/splash/splash_screen.dart';

/// 全局路由
///
/// - 启动页：/splash（决定进列表还是登录）
/// - 主外壳：/meetings、/profile（底部导航）
/// - 详情/会议室：全屏压栈
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/meetings',
                builder: (context, state) => const MeetingListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/meetings/:id',
        builder: (context, state) => MeetingDetailScreen(
          meetingId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/room/:id',
        builder: (context, state) => RoomScreen(
          meetingId: state.pathParameters['id']!,
          title: state.extra is String ? state.extra as String : null,
        ),
      ),
    ],
  );
});
