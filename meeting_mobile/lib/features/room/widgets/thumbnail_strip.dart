import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../room_controller.dart';

/// 缩略图条（标注模式下整体隐藏）
///
/// 点击缩略图可钉住/取消钉住到主画面；支持主持人徽标与发言人高亮。
class ThumbnailStrip extends StatelessWidget {
  const ThumbnailStrip({
    super.key,
    required this.videos,
    this.hostIdentity,
    this.activeSpeakerId,
    this.pinnedIdentity,
    this.onTapVideo,
  });

  final List<ParticipantVideo> videos;

  /// 动态主持人 identity（显示皇冠徽标）
  final String? hostIdentity;

  /// 当前发言人 identity（绿色描边高亮）
  final String? activeSpeakerId;

  /// 已钉住的成员 identity（品牌色描边）
  final String? pinnedIdentity;

  /// 点击缩略图（钉住/取消钉住）
  final ValueChanged<String>? onTapVideo;

  @override
  Widget build(BuildContext context) {
    if (videos.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      height: 96,
      color: const Color(0xFF0B1220),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: videos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final video = videos[index];
          final isHost = video.identity == hostIdentity;
          final speaking = video.identity == activeSpeakerId;
          final pinned = video.identity == pinnedIdentity;

          // 描边优先级：钉住 > 发言人
          final borderColor = pinned
              ? const Color(0xFF818CF8)
              : speaking
                  ? const Color(0xFF34D399)
                  : Colors.transparent;

          return GestureDetector(
            onTap: onTapVideo == null ? null : () => onTapVideo!(video.identity),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 128,
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: const Color(0xFF111827)),
                    VideoTrackRenderer(
                      video.track,
                      fit: VideoViewFit.cover,
                      mirrorMode: video.isLocal
                          ? VideoViewMirrorMode.mirror
                          : VideoViewMirrorMode.off,
                    ),
                    Positioned(
                      left: 4,
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          video.isLocal ? '我' : video.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white),
                        ),
                      ),
                    ),
                    // 主持人徽标
                    if (isHost)
                      const Positioned(
                        left: 4,
                        top: 4,
                        child: Icon(Icons.workspace_premium_rounded,
                            size: 14, color: Color(0xFFFBBF24)),
                      ),
                    // 钉住 / 发言中角标
                    if (pinned)
                      const Positioned(
                        right: 4,
                        top: 4,
                        child: Icon(Icons.push_pin_rounded,
                            size: 13, color: Color(0xFF818CF8)),
                      )
                    else if (speaking)
                      const Positioned(
                        right: 4,
                        top: 4,
                        child: Icon(Icons.volume_up_rounded,
                            size: 13, color: Color(0xFF34D399)),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
