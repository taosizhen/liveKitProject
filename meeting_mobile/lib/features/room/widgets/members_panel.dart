import 'package:flutter/material.dart';

import '../room_controller.dart';

/// 成员列表面板
class MembersPanel extends StatelessWidget {
  const MembersPanel({
    super.key,
    required this.members,
    required this.onClose,
  });

  final List<RoomMember> members;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: const Color(0xF20F172A),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 6, 10),
            child: Row(
              children: [
                const Text(
                  '参会成员',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
                const SizedBox(width: 6),
                Text(
                  '${members.length}',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF94A3B8)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: Colors.white70),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: members.length,
              itemBuilder: (context, index) {
                final member = members[index];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: member.isLocal
                            ? const Color(0xFF6366F1)
                            : const Color(0xFF334155),
                        child: Text(
                          member.name.isEmpty
                              ? '?'
                              : member.name.substring(0, 1),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          member.isLocal ? '${member.name}（我）' : member.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.white),
                        ),
                      ),
                      Icon(
                        member.micEnabled
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded,
                        size: 15,
                        color: member.micEnabled
                            ? const Color(0xFF34D399)
                            : const Color(0xFFF87171),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        member.cameraEnabled
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        size: 15,
                        color: member.cameraEnabled
                            ? const Color(0xFF34D399)
                            : const Color(0xFF64748B),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
