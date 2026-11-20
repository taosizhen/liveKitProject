import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import '../config/app_config.dart';
import '../models/chat_message.dart';
import 'api_client.dart';
import 'token_storage.dart';

/// 会议聊天仓库
///
/// 复用后端接口：
/// - GET /meetings/:id/chat/history（HTTP，原始数组响应）
/// - WS  /ws/meetings/:id/chat?token=xxx（消息体 `{type:'chat', content}`）
class ChatRepository {
  ChatRepository({
    required ApiClient api,
    required AppConfig config,
    required TokenStorage tokens,
  })  : _api = api,
        _config = config,
        _tokens = tokens;

  final ApiClient _api;
  final AppConfig _config;
  final TokenStorage _tokens;

  /// 拉取历史消息
  Future<List<ChatMessage>> history(String meetingId, {int limit = 100}) async {
    final data =
        await _api.getRaw('/meetings/$meetingId/chat/history', query: {
      'limit': limit,
    });
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromHistoryJson)
        .toList();
  }

  /// 建立实时聊天连接
  ///
  /// WebSocket 握手无法自定义请求头（Flutter 端可以，但后端也支持 query token），
  /// 因此统一把 access_token 放 query，与 Web 端行为保持一致。
  ChatSession connect(String meetingId) {
    final token = _tokens.accessToken ?? '';
    final uri = Uri.parse(
      '${_config.wsBase}${_config.apiPrefix}/ws/meetings/$meetingId/chat'
      '?token=$token',
    );

    // debug 构建允许自签证书（mkcert），与 Dio 的放行策略保持一致
    HttpClient? client;
    if (kDebugMode && _config.allowBadCertificate) {
      client = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
    }

    final channel = IOWebSocketChannel.connect(uri, customClient: client);
    return ChatSession(channel);
  }
}

/// 单个聊天连接会话
class ChatSession {
  ChatSession(this._channel) {
    _subscription = _channel.stream.listen(
      _onData,
      onError: (Object error) {
        _errors.add(error.toString());
      },
      onDone: () {
        if (!_messages.isClosed) {
          _messages.close();
        }
      },
    );
  }

  final WebSocketChannel _channel;
  final StreamController<ChatMessage> _messages =
      StreamController<ChatMessage>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();
  StreamSubscription<dynamic>? _subscription;

  /// 收到的聊天/系统消息
  Stream<ChatMessage> get messages => _messages.stream;

  /// 连接错误
  Stream<String> get errors => _errors.stream;

  /// 解析推送数据
  void _onData(dynamic raw) {
    if (raw is! String) return;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return;
      final type = json['type'];
      if (type != 'chat' && type != 'system') return;
      _messages.add(ChatMessage.fromWsJson(json));
    } catch (_) {
      // 忽略非 JSON 消息（例如心跳）
    }
  }

  /// 发送聊天消息
  void send(String content) {
    final text = content.trim();
    if (text.isEmpty) return;
    _channel.sink.add(jsonEncode({'type': 'chat', 'content': text}));
  }

  /// 关闭连接并释放资源
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel.sink.close();
    if (!_messages.isClosed) await _messages.close();
    if (!_errors.isClosed) await _errors.close();
  }
}

/// 聊天仓库 Provider
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(
    api: ref.watch(apiClientProvider),
    config: ref.watch(appConfigProvider),
    tokens: ref.watch(tokenStorageProvider),
  );
});
