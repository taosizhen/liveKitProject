import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';

/// Token 与用户信息存储
///
/// - `refresh_token` → flutter_secure_storage（Android Keystore / iOS Keychain）
/// - `access_token` → 仅内存（进程重启后通过 refresh_token 重新换取）
/// - 缓存的用户资料 → shared_preferences（启动页可先渲染昵称/头像占位）
class TokenStorage {
  TokenStorage(this._secure, this._prefs);

  static const String _kRefreshToken = 'refresh_token';
  static const String _kUser = 'cached_user';

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  String? _accessToken;

  /// 当前 access_token（内存）
  String? get accessToken => _accessToken;

  /// 更新内存中的 access_token
  set accessToken(String? value) => _accessToken = value;

  /// 创建实例并初始化 shared_preferences
  static Future<TokenStorage> create() async {
    const secure = FlutterSecureStorage();
    final prefs = await SharedPreferences.getInstance();
    return TokenStorage(secure, prefs);
  }

  /// 读取 refresh_token
  Future<String?> readRefreshToken() => _secure.read(key: _kRefreshToken);

  /// 保存 refresh_token
  Future<void> saveRefreshToken(String value) =>
      _secure.write(key: _kRefreshToken, value: value);

  /// 缓存登录用户资料
  Future<void> saveUser(AppUser user) =>
      _prefs.setString(_kUser, jsonEncode(user.toJson()));

  /// 读取缓存的用户资料（仅用于启动页占位展示）
  AppUser? readCachedUser() {
    final raw = _prefs.getString(_kUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 清空所有登录态（退出登录 / refresh 失败时调用）
  Future<void> clear() async {
    _accessToken = null;
    await _secure.delete(key: _kRefreshToken);
    await _prefs.remove(_kUser);
  }
}

/// TokenStorage Provider
final tokenStorageProvider = Provider<TokenStorage>((ref) {
  throw UnimplementedError('tokenStorageProvider 必须在 main() 中 override');
});
