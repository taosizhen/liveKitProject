import 'package:flutter/material.dart';

import '../../../models/signal.dart';
import '../room_controller.dart';

/// 成员列表面板（含举手列表与主持人点名入口）
class MembersPanel extends StatelessWidget {
  const MembersPanel({
    super.key,
    required this.members,
    required this.raisedHands,
    required this.isHost,
    required this.localIdentity,
    required this.onDesignate,
    required this.onClose,
  });

  final List<RoomMember> members;

  /// 举手列表（已按时间升序）
  final List<RaisedHand> raisedHands;

  /// 自己是否为动态主持人（决定"邀请发言"按钮显隐）
  final bool isHost;

  /// 本地成员 identity（标记"（我）"、不给自己点名）
  final String localIdentity;

  /// 主持人点名回调
  final ValueChanged<String> onDesignate;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final handIdentities = raisedHands.map((h) => h.identity).toSet();
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
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // 举手列表（按时间升序），主持人可点名邀请发言
                if (raisedHands.isNotEmpty) ...[
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0x33F59E0B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0x66F59E0B)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.back_hand_rounded,
                                size: 13, color: Color(0xFFFBBF24)),
                            SizedBox(width: 4),
                            Text('举手',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFBBF24))),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ...raisedHands.map((h) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      h.identity == localIdentity
                                          ? '${h.name}（我）'
                                          : h.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.white),
                                    ),
                                  ),
                                  if (isHost && h.identity != localIdentity)
                                    GestureDetector(
                                      onTap: () => onDesignate(h.identity),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF4338CA),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text('邀请发言',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.white)),
                                      ),
                                    ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                ],
                // 成员列表
                ...members.map((member) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
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
                              member.isLocal
                                  ? '${member.name}（我）'
                                  : member.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.white),
                            ),
                          ),
                          // 举手徽标
                          if (handIdentities.contains(member.identity))
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.back_hand_rounded,
                                  size: 15, color: Color(0xFFFBBF24)),
                            ),
                          // 主持人徽标
                          if (member.isHost)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.workspace_premium_rounded,
                                  size: 15, color: Color(0xFFFBBF24)),
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
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
