/// 后端登录返回的 Token 对
///
/// 对应 `POST /auth/login` 的 `data.tokens` 与 `POST /auth/refresh` 的 `data`
class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.tokenType,
  });

  final String accessToken;
  final String refreshToken;

  /// 有效期（秒）
  final int expiresIn;

  /// 固定为 Bearer
  final String tokenType;

  /// 解析 Token JSON
  factory TokenPair.fromJson(Map<String, dynamic> json) => TokenPair(
        accessToken: (json['access_token'] as String?) ?? '',
        refreshToken: (json['refresh_token'] as String?) ?? '',
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
        tokenType: (json['token_type'] as String?) ?? 'Bearer',
      );
}
