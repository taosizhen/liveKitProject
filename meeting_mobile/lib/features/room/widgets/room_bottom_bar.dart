import 'package:flutter/material.dart';

import '../room_controller.dart';

/// 会议室底部工具栏
class RoomBottomBar extends StatelessWidget {
  const RoomBottomBar({
    super.key,
    required this.state,
    required this.annotationMode,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onToggleScreenShare,
    required this.onToggleChat,
    required this.onToggleMembers,
    required this.onToggleAnnotation,
    required this.onHangup,
  });

  final RoomState state;

  /// 是否正处于标注模式（按钮高亮）
  final bool annotationMode;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onToggleChat;
  final VoidCallback onToggleMembers;
  final VoidCallback onToggleAnnotation;
  final VoidCallback onHangup;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _iconButton(
              icon: state.micEnabled
                  ? Icons.mic_rounded
                  : Icons.mic_off_rounded,
              active: state.micEnabled,
              danger: !state.micEnabled,
              label: '麦克风',
              onTap: onToggleMic,
            ),
            _iconButton(
              icon: state.cameraEnabled
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              active: state.cameraEnabled,
              danger: !state.cameraEnabled,
              label: '摄像头',
              onTap: onToggleCamera,
            ),
            _iconButton(
              icon: Icons.screen_share_rounded,
              active: state.screenSharing,
              label: '共享',
              onTap: onToggleScreenShare,
            ),
            _iconButton(
              icon: Icons.chat_bubble_outline_rounded,
              label: '聊天',
              onTap: onToggleChat,
            ),
            _iconButton(
              icon: Icons.people_alt_outlined,
              label: '成员',
              onTap: onToggleMembers,
            ),
            _iconButton(
              icon: Icons.edit_rounded,
              active: annotationMode,
              label: '标注',
              onTap: onToggleAnnotation,
            ),
            _iconButton(
              icon: Icons.call_end_rounded,
              danger: true,
              label: '挂断',
              onTap: onHangup,
            ),
          ],
        ),
      ),
    );
  }

  /// 单个工具按钮
  Widget _iconButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    bool danger = false,
  }) {
    final background = danger
        ? const Color(0xFF7F1D1D)
        : (active ? const Color(0xFF4338CA) : Colors.white10);
    final color = danger
        ? const Color(0xFFFCA5A5)
        : (active ? Colors.white : Colors.white70);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(fontSize: 9, color: color.withOpacity(0.9)),
            ),
          ],
        ),
      ),
    );
  }
}
