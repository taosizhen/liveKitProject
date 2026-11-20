import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/token_pair.dart';
import '../models/user.dart';
import 'api_client.dart';
import 'token_storage.dart';

/// 登录结果（token + 用户信息）
class AuthResult {
  const AuthResult({required this.user, required this.tokens});

  final AppUser user;
  final TokenPair tokens;
}

/// 鉴权仓库
///
/// 复用后端接口：
/// - POST /auth/login
/// - POST /auth/refresh（由 ApiClient 统一处理）
/// - GET  /auth/me
class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStorage _tokens;

  /// 账号密码登录，成功后落地 refresh_token 与用户缓存
  Future<AuthResult> login(String email, String password) async {
    final data = await _api.postJson(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    if (data is! Map<String, dynamic>) {
      throw ApiException('登录响应格式异常');
    }
    final tokens = TokenPair.fromJson(
      (data['tokens'] as Map<String, dynamic>?) ?? const {},
    );
    final user = AppUser.fromJson(
      (data['user'] as Map<String, dynamic>?) ?? const {},
    );
    if (tokens.accessToken.isEmpty || tokens.refreshToken.isEmpty) {
      throw ApiException('登录失败：未获取到有效令牌');
    }
    _tokens.accessToken = tokens.accessToken;
    await _tokens.saveRefreshToken(tokens.refreshToken);
    await _tokens.saveUser(user);
    return AuthResult(user: user, tokens: tokens);
  }

  /// 拉取当前登录用户（用于冷启动恢复登录态）
  Future<AppUser> me() async {
    final data = await _api.getJson('/auth/me');
    if (data is! Map<String, dynamic>) {
      throw ApiException('用户信息格式异常');
    }
    final user = AppUser.fromJson(data);
    await _tokens.saveUser(user);
    return user;
  }

  /// 退出登录（后端暂无吊销接口，先清本地；Phase 2 接 logout + Redis 黑名单）
  Future<void> logout() => _tokens.clear();
}

/// 鉴权仓库 Provider
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
  );
});
