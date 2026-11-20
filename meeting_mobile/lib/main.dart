import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'data/token_storage.dart';

/// 信任自签证书的全局 HttpOverrides
///
/// LiveKit 信令（wss://）由 livekit_client 通过 dart:io 的 WebSocket.connect
/// 建立，内部使用默认 HttpClient，无法像 Dio 那样单独注入 badCertificateCallback。
/// 因此这里用全局覆盖，使 mkcert 自签证书在 debug 构建下可用。
class _TrustAllHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

/// 应用入口
///
/// 启动前完成三件事：
/// 1. 读取 assets/config.json（服务器地址外置）
/// 2. 初始化 TokenStorage（secure_storage + shared_preferences）
/// 3. debug 构建下放开自签证书校验（API + LiveKit 信令）
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = await AppConfig.load();

  // 由 assets/config.json 的 allow_bad_certificate 控制：
  // 本地联调为 true（服务器使用 mkcert 自签证书），对外生产打包时应改为 false
  if (config.allowBadCertificate) {
    HttpOverrides.global = _TrustAllHttpOverrides();
  }

  final tokenStorage = await TokenStorage.create();

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        tokenStorageProvider.overrideWithValue(tokenStorage),
      ],
      child: const MeetingApp(),
    ),
  );
}
