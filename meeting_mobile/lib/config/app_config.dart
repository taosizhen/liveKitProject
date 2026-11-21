import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用运行配置
///
/// 所有服务器地址都外置在 `assets/config.json`，打包生产包时只需替换该文件，
/// 不需要改动任何 Dart 代码。LiveKit 信令地址不在此处配置 —— 它由后端
/// `/meetings/:id/livekit-token` 接口的 `livekit_url` 字段下发。
///
/// 运行时可通过 [saveOverride] 用 SharedPreferences 覆盖 `api_base_url`，
/// 覆盖值在下次启动时优先生效（用于联调时临时切换后端地址，无需重新打包）。
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.apiPrefix,
    required this.allowBadCertificate,
    this.overrideApiBaseUrl,
  });

  /// SharedPreferences 中存储用户覆盖地址的键名
  static const String _overrideKey = 'config.api_base_url_override';

  /// 后端根地址，例如 https://192.168.100.103:8090
  final String apiBaseUrl;

  /// 接口前缀，默认 /api/v1
  final String apiPrefix;

  /// 是否允许自签证书（仅在 debug 构建中生效，release 忽略）
  final bool allowBadCertificate;

  /// 用户运行时覆盖的原始地址（未覆盖时为 null，仅用于展示/恢复默认）
  final String? overrideApiBaseUrl;

  /// 当前是否使用了用户自定义覆盖地址
  bool get hasOverride => overrideApiBaseUrl?.isNotEmpty == true;

  /// 完整 HTTP API 基地址
  String get apiBase => '$apiBaseUrl$apiPrefix';

  /// WebSocket 基地址（https → wss，http → ws）
  String get wsBase => apiBaseUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');

  /// 从 assets/config.json 读取配置，并叠加 SharedPreferences 中的用户覆盖
  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final override = prefs.getString(_overrideKey);

    final raw = await rootBundle.loadString('assets/config.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final defaultBase =
        (json['api_base_url'] as String?) ?? 'https://127.0.0.1:8090';

    return AppConfig(
      apiBaseUrl: override?.isNotEmpty == true ? override! : defaultBase,
      apiPrefix: (json['api_prefix'] as String?) ?? '/api/v1',
      allowBadCertificate:
          (json['allow_bad_certificate'] as bool?) ?? false,
      overrideApiBaseUrl: override,
    );
  }

  /// 持久化用户自定义服务器地址（保存后需重启 App 生效）
  ///
  /// 传入 null 或空串表示清除覆盖，恢复使用 config.json 中的默认地址。
  static Future<void> saveOverride(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await prefs.remove(_overrideKey);
    } else {
      await prefs.setString(_overrideKey, trimmed);
    }
  }
}

/// 全局配置 Provider，在 main() 中用真实配置 override
final appConfigProvider = Provider<AppConfig>((ref) {
  throw UnimplementedError('appConfigProvider 必须在 ProviderScope 中 override');
});
