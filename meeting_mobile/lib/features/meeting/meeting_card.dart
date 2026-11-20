import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../models/meeting.dart';

/// 会议卡片
class MeetingCard extends StatelessWidget {
  const MeetingCard({
    super.key,
    required this.meeting,
    required this.onTap,
    required this.onJoin,
  });

  final Meeting meeting;
  final VoidCallback onTap;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusBackground(meeting.status),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      meeting.statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor(meeting.status),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    meeting.typeLabel,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF94A3B8)),
                  ),
                  const Spacer(),
                  const Icon(Icons.schedule_rounded,
                      size: 14, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 4),
                  Text(
                    formatMeetingTime(meeting.startTime),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                meeting.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.people_alt_outlined,
                      size: 15, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 4),
                  Text(
                    '${meeting.participants.length} 人',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  if (meeting.organizer != null) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.person_outline_rounded,
                        size: 15, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      meeting.organizer!.displayName,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                  const Spacer(),
                  if (meeting.canJoin)
                    SizedBox(
                      height: 32,
                      child: FilledButton.icon(
                        onPressed: onJoin,
                        icon: const Icon(Icons.login_rounded, size: 16),
                        label: const Text('入会',
                            style: TextStyle(fontSize: 13)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    )
                  else
                    const Icon(Icons.chevron_right_rounded,
                        color: Color(0xFFCBD5E1)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
