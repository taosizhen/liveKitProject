import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/auth_repository.dart';
import '../../data/token_storage.dart';
import '../../models/user.dart';
import '../../router/app_router.dart';

/// 登录态
class AuthState {
  const AuthState({this.user, this.busy = false, this.error});

  final AppUser? user;
  final bool busy;
  final String? error;

  bool get isLoggedIn => user != null;

  AuthState copyWith({
    AppUser? user,
    bool? busy,
    String? error,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 鉴权控制器
///
/// 负责：冷启动恢复登录态、账号密码登录、退出登录、登录失效跳转
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // 注入登录失效回调：refresh 失败时统一清态并跳登录页
    ref.read(apiClientProvider).onAuthLost = _handleAuthLost;
    return const AuthState();
  }

  /// 冷启动：读 refresh_token → 换 access_token → 拉 /auth/me
  ///
  /// 返回 true 表示登录态有效，可直接进会议列表
  Future<bool> bootstrap() async {
    final tokens = ref.read(tokenStorageProvider);
    final refreshToken = await tokens.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      state = const AuthState();
      return false;
    }

    state = const AuthState(busy: true);
    try {
      await ref.read(apiClientProvider).refresh();
      final user = await ref.read(authRepositoryProvider).me();
      state = AuthState(user: user);
      return true;
    } catch (_) {
      await tokens.clear();
      state = const AuthState();
      return false;
    }
  }

  /// 账号密码登录
  Future<bool> login(String email, String password) async {
    if (email.trim().isEmpty || password.isEmpty) {
      state = state.copyWith(error: '请输入邮箱和密码', clearError: false);
      return false;
    }
    state = const AuthState(busy: true);
    try {
      final result =
          await ref.read(authRepositoryProvider).login(email.trim(), password);
      state = AuthState(user: result.user);
      return true;
    } on ApiException catch (e) {
      state = AuthState(error: e.message);
      return false;
    } catch (e) {
      state = AuthState(error: '登录失败，请稍后重试');
      return false;
    }
  }

  /// 退出登录
  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AuthState();
  }

  /// 清空错误提示
  void clearError() {
    if (state.error != null) {
      state = state.copyWith(clearError: true);
    }
  }

  /// 上传并更新当前用户头像，返回是否成功
  Future<bool> uploadAvatar(String filePath) async {
    final user = state.user;
    if (user == null) return false;
    try {
      final updated =
          await ref.read(authRepositoryProvider).uploadAvatar(user, filePath);
      state = state.copyWith(user: updated);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(error: '头像上传失败，请稍后重试');
      return false;
    }
  }

  /// 修改当前用户昵称，返回是否成功
  Future<bool> updateName(String name) async {
    final user = state.user;
    if (user == null) return false;
    try {
      final updated =
          await ref.read(authRepositoryProvider).updateName(user, name);
      state = state.copyWith(user: updated);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(error: '昵称修改失败，请稍后重试');
      return false;
    }
  }

  /// 登录态失效：清空并跳转登录页
  void _handleAuthLost() {
    state = const AuthState(error: '登录已过期，请重新登录');
    ref.read(routerProvider).go('/login');
  }
}

/// 鉴权控制器 Provider
final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
