import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/api_client.dart';
import '../../data/meeting_repository.dart';
import '../../models/meeting.dart';
import 'meeting_list_controller.dart';

/// 会议详情页
class MeetingDetailScreen extends ConsumerStatefulWidget {
  const MeetingDetailScreen({super.key, required this.meetingId});

  final String meetingId;

  @override
  ConsumerState<MeetingDetailScreen> createState() =>
      _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends ConsumerState<MeetingDetailScreen> {
  bool _joining = false;

  /// 确认参加并进入会议室
  Future<void> _join(Meeting meeting) async {
    if (_joining) return;
    setState(() => _joining = true);
    try {
      await ref.read(meetingRepositoryProvider).join(meeting.id);
      if (!mounted) return;
      context.push('/room/${meeting.id}', extra: meeting.title);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncMeeting = ref.watch(meetingDetailProvider(widget.meetingId));

    return Scaffold(
      appBar: AppBar(title: const Text('会议详情')),
      body: asyncMeeting.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(meetingDetailProvider(widget.meetingId)),
                  child: const Text('重新加载'),
                ),
              ],
            ),
          ),
        ),
        data: (meeting) => _buildContent(meeting),
      ),
    );
  }

  /// 详情内容
  Widget _buildContent(Meeting meeting) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
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
                        const SizedBox(width: 8),
                        Text(
                          meeting.typeLabel,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      meeting.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _InfoRow(
                      icon: Icons.schedule_rounded,
                      label: '开始时间',
                      value: formatMeetingTime(meeting.startTime),
                    ),
                    if (meeting.endTime != null)
                      _InfoRow(
                        icon: Icons.timelapse_rounded,
                        label: '结束时间',
                        value: formatMeetingTime(meeting.endTime!),
                      ),
                    _InfoRow(
                      icon: Icons.meeting_room_outlined,
                      label: '房间号',
                      value: meeting.roomName,
                    ),
                    if (meeting.organizer != null)
                      _InfoRow(
                        icon: Icons.person_outline_rounded,
                        label: '组织者',
                        value: meeting.organizer!.displayName,
                      ),
                  ],
                ),
              ),
              if (meeting.description.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '会议说明',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        meeting.description,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '参会人员（${meeting.participants.length}）',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    if (meeting.participants.isEmpty)
                      const Text(
                        '暂无参会人员',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF94A3B8)),
                      )
                    else
                      ...meeting.participants.map(
                        (p) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              UserAvatar(user: p.user, size: 36),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.user?.displayName ?? p.userId,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500),
                                    ),
                                    if (p.user != null)
                                      Text(
                                        p.user!.roleLabel,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF94A3B8)),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  p.roleLabel,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              height: 50,
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    meeting.canJoin && !_joining ? () => _join(meeting) : null,
                icon: _joining
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.login_rounded),
                label: Text(
                  meeting.isFinished
                      ? '会议已结束'
                      : (meeting.canJoin ? '一键入会' : '会议开始前 15 分钟可入会'),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 详情信息行
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
            ),
          ),
        ],
      ),
    );
  }
}
