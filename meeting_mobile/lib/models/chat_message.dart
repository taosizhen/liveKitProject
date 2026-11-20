/// 会议内聊天消息
///
/// 两个来源：
/// 1. HTTP 历史：`GET /meetings/:id/chat/history` → `ChatMessage` 模型（含 user、created_at）
/// 2. WebSocket 实时：`{type, user_id, user_name, content, info, timestamp}`（毫秒时间戳）
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.userId,
    required this.userName,
    required this.content,
    required this.createdAt,
    this.isSystem = false,
  });

  final String id;
  final String userId;
  final String userName;
  final String content;
  final DateTime createdAt;

  /// 系统消息（加入 / 离开房间）
  final bool isSystem;

  /// 解析历史消息
  factory ChatMessage.fromHistoryJson(Map<String, dynamic> json) {
    final user = json['user'];
    return ChatMessage(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      userName: user is Map<String, dynamic> ? (user['name'] as String? ?? '') : '',
      content: (json['content'] as String?) ?? '',
      createdAt: json['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  /// 解析 WebSocket 推送消息
  factory ChatMessage.fromWsJson(Map<String, dynamic> json) {
    final type = (json['type'] as String?) ?? 'chat';
    final isSystem = type == 'system';
    final info = (json['info'] as String?) ?? '';
    final userName = (json['user_name'] as String?) ?? '';
    final timestamp = json['timestamp'];
    return ChatMessage(
      id: 'ws-${timestamp ?? DateTime.now().millisecondsSinceEpoch}-$userName',
      userId: (json['user_id'] as String?) ?? '',
      userName: userName,
      content: isSystem
          ? (info == 'joined' ? '$userName 加入了会议' : '$userName 离开了会议')
          : ((json['content'] as String?) ?? ''),
      createdAt: timestamp is int
          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
          : DateTime.now(),
      isSystem: isSystem,
    );
  }
}
