import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../data/chat_repository.dart';
import '../../../features/auth/auth_controller.dart';
import '../../../models/chat_message.dart';

/// 会议聊天面板（覆盖在会议室之上）
class ChatPanel extends ConsumerStatefulWidget {
  const ChatPanel({
    super.key,
    required this.meetingId,
    required this.onClose,
  });

  final String meetingId;
  final VoidCallback onClose;

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  ChatSession? _session;
  StreamSubscription<ChatMessage>? _messageSub;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _session?.close();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 加载历史消息并建立 WebSocket 连接
  Future<void> _init() async {
    final repository = ref.read(chatRepositoryProvider);
    try {
      final history = await repository.history(widget.meetingId);
      if (!mounted) return;
      setState(() {
        _messages.addAll(history);
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }

    final session = repository.connect(widget.meetingId);
    _session = session;
    _messageSub = session.messages.listen((message) {
      if (!mounted) return;
      setState(() => _messages.add(message));
      _scrollToBottom();
    });
  }

  /// 滚动到底部
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// 发送消息（服务端会广播回显给所有客户端，包含发送者）
  void _send() {
    final text = _inputController.text;
    if (text.trim().isEmpty) return;
    _session?.send(text);
    _inputController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = ref.watch(authControllerProvider).user?.id ?? '';

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                const SizedBox(width: 8),
                const Text(
                  '会议聊天',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildMessageList(myUserId),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: '说点什么…',
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send_rounded, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 消息列表
  Widget _buildMessageList(String myUserId) {
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          _error ?? '还没有消息，打个招呼吧',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        if (message.isSystem) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  message.content,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ),
            ),
          );
        }

        final isMine = message.userId == myUserId;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                '${message.userName}  ${formatMessageTime(message.createdAt)}',
                style:
                    const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 3),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                constraints: const BoxConstraints(maxWidth: 240),
                decoration: BoxDecoration(
                  color: isMine
                      ? const Color(0xFF4F46E5)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  message.content,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: isMine ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
