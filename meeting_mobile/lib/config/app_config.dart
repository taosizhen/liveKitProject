import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用运行配置
///
/// 所有服务器地址都外置在 `assets/config.json`，打包生产包时只需替换该文件，
/// 不需要改动任何 Dart 代码。LiveKit 信令地址不在此处配置 —— 它由后端
/// `/meetings/:id/livekit-token` 接口的 `livekit_url` 字段下发。
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.apiPrefix,
    required this.allowBadCertificate,
  });

  /// 后端根地址，例如 https://192.168.100.103:8090
  final String apiBaseUrl;

  /// 接口前缀，默认 /api/v1
  final String apiPrefix;

  /// 是否允许自签证书（仅在 debug 构建中生效，release 忽略）
  final bool allowBadCertificate;

  /// 完整 HTTP API 基地址
  String get apiBase => '$apiBaseUrl$apiPrefix';

  /// WebSocket 基地址（https → wss，http → ws）
  String get wsBase => apiBaseUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');

  /// 从 assets/config.json 读取配置
  static Future<AppConfig> load() async {
    final raw = await rootBundle.loadString('assets/config.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return AppConfig(
      apiBaseUrl: (json['api_base_url'] as String?) ?? 'https://127.0.0.1:8090',
      apiPrefix: (json['api_prefix'] as String?) ?? '/api/v1',
      allowBadCertificate: (json['allow_bad_certificate'] as bool?) ?? false,
    );
  }
}

/// 全局配置 Provider，在 main() 中用真实配置 override
final appConfigProvider = Provider<AppConfig>((ref) {
  throw UnimplementedError('appConfigProvider 必须在 ProviderScope 中 override');
});
