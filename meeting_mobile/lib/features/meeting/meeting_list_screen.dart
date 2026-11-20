import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/meeting.dart';
import 'meeting_card.dart';
import 'meeting_list_controller.dart';

/// 会议列表页（底部导航“会议”Tab）
class MeetingListScreen extends ConsumerStatefulWidget {
  const MeetingListScreen({super.key});

  @override
  ConsumerState<MeetingListScreen> createState() => _MeetingListScreenState();
}

class _MeetingListScreenState extends ConsumerState<MeetingListScreen> {
  /// 筛选项：label + status 参数
  static const List<(String, String)> _filters = [
    ('即将开始', 'upcoming'),
    ('进行中', 'in_progress'),
    ('已结束', 'completed'),
    ('全部', ''),
  ];

  final ScrollController _scrollController = ScrollController();
  String _status = 'upcoming';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动到距底部 240px 时加载下一页
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      ref.read(meetingListProvider(_status).notifier).loadMore();
    }
  }

  /// 进入会议室
  void _openRoom(Meeting meeting) {
    context.push('/room/${meeting.id}', extra: meeting.title);
  }

  @override
  Widget build(BuildContext context) {
    final asyncMeetings = ref.watch(meetingListProvider(_status));

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的会议'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                ref.read(meetingListProvider(_status).notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final (label, value) = _filters[index];
                final selected = value == _status;
                return Center(
                  child: ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) {
                      if (_status == value) return;
                      setState(() => _status = value);
                    },
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(meetingListProvider(_status).notifier).refresh(),
              child: asyncMeetings.when(
                data: (meetings) => _buildList(meetings),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _buildError(error),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 列表主体
  Widget _buildList(List<Meeting> meetings) {
    if (meetings.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Icon(Icons.event_available_rounded,
              size: 56, color: Color(0xFFCBD5E1)),
          SizedBox(height: 12),
          Center(
            child: Text(
              '暂无会议',
              style: TextStyle(fontSize: 15, color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: meetings.length + 1,
      itemBuilder: (context, index) {
        if (index == meetings.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                '没有更多了',
                style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
              ),
            ),
          );
        }
        final meeting = meetings[index];
        return MeetingCard(
          meeting: meeting,
          onTap: () => context.push('/meetings/${meeting.id}'),
          onJoin: () => _openRoom(meeting),
        );
      },
    );
  }

  /// 错误态（可重试）
  Widget _buildError(Object error) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.cloud_off_rounded,
            size: 52, color: Color(0xFFCBD5E1)),
        const SizedBox(height: 12),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton(
            onPressed: () =>
                ref.read(meetingListProvider(_status).notifier).refresh(),
            child: const Text('重新加载'),
          ),
        ),
      ],
    );
  }
}
