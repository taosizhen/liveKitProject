import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../room_controller.dart';

/// 缩略图条（标注模式下整体隐藏）
class ThumbnailStrip extends StatelessWidget {
  const ThumbnailStrip({super.key, required this.videos});

  final List<ParticipantVideo> videos;

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
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 128,
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
