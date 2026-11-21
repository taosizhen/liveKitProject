import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../config/app_config.dart';
import '../../../core/widgets/user_avatar.dart';
import '../room_controller.dart';
import '../signal_controller.dart';

/// 同框圆桌视图：全员席位沿圆桌圆周均布（圆形头像/视频，不抠图）
///
/// 席位规则与 Web 端一致：angle=-90°+i×360°/N，圆心+半径 R=短边×38%。
/// 发言人描边、主持人皇冠徽标、举手标记、麦克风状态角标。
class RoundTableView extends ConsumerWidget {
  const RoundTableView({
    super.key,
    required this.meetingId,
    this.mini = false,
    this.onTap,
  });

  final String meetingId;

  /// mini=小地图（点击展开）；否则铺满父容器
  final bool mini;

  /// mini 态点击回调
  final VoidCallback? onTap;

  /// 按人数计算席位直径：人越多越小
  double _seatSize(int count) {
    if (mini) return count <= 8 ? 24 : 20;
    if (count <= 6) return 72;
    if (count <= 12) return 52;
    return 40;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roomControllerProvider(meetingId));
    final signal = ref.watch(signalControllerProvider(meetingId));
    final apiBaseUrl = ref.watch(appConfigProvider).apiBaseUrl;

    // identity → 摄像头轨道（缩略图 + 主画面若为摄像头；
    // 缩略图列表不含主画面轨道，需按 mainIdentity 补上）
    final tracks = <String, VideoTrack>{};
    for (final v in state.thumbnails) {
      if (!v.isScreenShare) tracks[v.identity] = v.track;
    }
    final mainTrack = state.mainTrack;
    final mainIdentity = state.mainIdentity;
    if (mainTrack != null && !state.mainIsScreenShare && mainIdentity != null) {
      tracks[mainIdentity] = mainTrack;
    }

    final members = state.members;
    final n = members.length;
    if (n == 0) return const SizedBox.shrink();
    final seat = _seatSize(n);
    final handCount = signal.hands.length;

    final content = LayoutBuilder(
      builder: (context, constraints) {
        // 内部正方形区域：保证圆周定位横纵一致
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final cx = constraints.maxWidth / 2;
        final cy = constraints.maxHeight / 2;
        final radius = side * 0.38;

        return Stack(
          children: [
            // 中央圆桌（渐变圆形，无位图资源）
            Positioned(
              left: cx - side * 0.27,
              top: cy - side * 0.27,
              width: side * 0.54,
              height: side * 0.54,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFF5B4636), Color(0xFF3A2E23)],
                  ),
                  border: Border.all(color: const Color(0xFF8B6F4E), width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 12),
                  ],
                ),
              ),
            ),
            // 圆周席位
            for (var i = 0; i < n; i++)
              _buildSeat(
                members[i],
                i,
                n,
                cx,
                cy,
                radius,
                seat,
                tracks,
                state,
                signal.hands.containsKey(members[i].identity),
                apiBaseUrl,
              ),
            // 全屏圆桌：举手人数醒目提示（小地图态不显示）
            if (!mini && handCount > 0)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xE6F59E0B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.back_hand_rounded,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        '举手 $handCount 人',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );

    final boxed = mini
        ? Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            clipBehavior: Clip.antiAlias,
            child: content,
          )
        : Container(color: const Color(0xFF0F172A), child: content);

    if (mini && onTap != null) {
      return GestureDetector(onTap: onTap, child: boxed);
    }
    return boxed;
  }

  /// 单个席位（圆周均布）
  Widget _buildSeat(
    RoomMember member,
    int index,
    int count,
    double cx,
    double cy,
    double radius,
    double seat,
    Map<String, VideoTrack> tracks,
    RoomState state,
    bool handRaised,
    String apiBaseUrl,
  ) {
    final rad = (-90 + index * 360 / count) * math.pi / 180;
    final x = cx + radius * math.cos(rad) - seat / 2;
    final y = cy + radius * math.sin(rad) - seat / 2;
    final track = tracks[member.identity];
    final speaking = state.activeSpeakerId == member.identity;
    final avatarUrl = UserAvatar.resolveUrl(member.avatarUrl, apiBaseUrl);

    return Positioned(
      left: x,
      top: y,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: seat,
                height: seat,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: speaking
                        ? const Color(0xFF34D399)
                        : Colors.white24,
                    width: 2,
                  ),
                  boxShadow: speaking
                      ? const [
                          BoxShadow(color: Color(0x9934D399), blurRadius: 8)
                        ]
                      : null,
                ),
                child: ClipOval(
                  child: track != null
                      ? VideoTrackRenderer(
                          track,
                          fit: VideoViewFit.cover,
                          mirrorMode: member.isLocal
                              ? VideoViewMirrorMode.mirror
                              : VideoViewMirrorMode.off,
                        )
                      : avatarUrl != null
                          ? Image.network(
                              avatarUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _initialAvatar(member, seat),
                            )
                          : _initialAvatar(member, seat),
                ),
              ),
              // 主持人徽标
              if (member.isHost)
                const Positioned(
                  left: -3,
                  top: -3,
                  child: Icon(Icons.workspace_premium_rounded,
                      size: 14, color: Color(0xFFFBBF24)),
                ),
              // 举手徽标
              if (handRaised)
                const Positioned(
                  right: -3,
                  top: -3,
                  child: Icon(Icons.back_hand_rounded,
                      size: 13, color: Color(0xFFFBBF24)),
                ),
              // 麦克风状态角标
              if (!mini)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Icon(
                    member.micEnabled
                        ? Icons.mic_rounded
                        : Icons.mic_off_rounded,
                    size: 12,
                    color: member.micEnabled
                        ? const Color(0xFF34D399)
                        : const Color(0xFFF87171),
                  ),
                ),
            ],
          ),
          // 姓名（mini 态省略）
          if (!mini)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                member.isLocal ? '${member.name}（我）' : member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  /// 首字母兜底头像
  Widget _initialAvatar(RoomMember member, double seat) {
    return Container(
      color: const Color(0xFF334155),
      alignment: Alignment.center,
      child: Text(
        member.name.isEmpty ? '?' : member.name.substring(0, 1),
        style: TextStyle(color: Colors.white, fontSize: seat * 0.4),
      ),
    );
  }
}

/// 圆桌全屏时的成员列表小地图（紧凑形态，点击切回舞台）
class MiniMemberList extends StatelessWidget {
  const MiniMemberList({
    super.key,
    required this.members,
    required this.onTap,
  });

  final List<RoomMember> members;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        constraints: const BoxConstraints(maxHeight: 180),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xF20F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: members.length,
          itemBuilder: (context, index) {
            final m = members[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    m.micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                    size: 12,
                    color: m.micEnabled
                        ? const Color(0xFF34D399)
                        : const Color(0xFFF87171),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      m.isLocal ? '${m.name}（我）' : m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                  if (m.isHost)
                    const Icon(Icons.workspace_premium_rounded,
                        size: 12, color: Color(0xFFFBBF24)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
