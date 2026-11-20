import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/meeting_repository.dart';
import '../../models/meeting.dart';

/// 会议列表控制器（按筛选条件分族）
///
/// status 取值：
/// - `''` 全部
/// - `upcoming` 即将开始（scheduled 且 15 分钟内，前端过滤）
/// - `in_progress` 进行中
/// - `completed` 已结束
class MeetingListController
    extends FamilyAsyncNotifier<List<Meeting>, String> {
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;

  /// 是否还有下一页
  bool get hasMore => _hasMore;

  @override
  Future<List<Meeting>> build(String status) async {
    _page = 1;
    _hasMore = true;
    final result = await _fetchPage(1, status);
    _hasMore = result.hasMore;
    return result.items;
  }

  /// 按页拉取数据；即将开始需要前端二次过滤
  Future<MeetingPage> _fetchPage(int page, String status) async {
    final repo = ref.read(meetingRepositoryProvider);
    if (status == 'upcoming') {
      // 后端无“即将开始”参数：拉 scheduled 全量后按 15 分钟窗口过滤
      final result =
          await repo.list(status: 'scheduled', page: 1, pageSize: 100);
      final filtered = result.items
          .where((m) => m.isScheduled && m.startsWithin15Minutes)
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      return MeetingPage(
        items: filtered,
        total: filtered.length,
        page: 1,
        pageSize: filtered.length,
        pages: 1,
      );
    }
    return repo.list(
      status: status.isEmpty ? null : status,
      page: page,
      pageSize: 20,
    );
  }

  /// 下拉刷新
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      _page = 1;
      final result = await _fetchPage(1, arg);
      _hasMore = result.hasMore;
      return result.items;
    });
  }

  /// 上拉加载下一页
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final current = state.valueOrNull;
    if (current == null) return;

    _loadingMore = true;
    try {
      final nextPage = _page + 1;
      final result = await _fetchPage(nextPage, arg);
      _page = nextPage;
      _hasMore = result.hasMore;
      if (result.items.isNotEmpty) {
        state = AsyncData([...current, ...result.items]);
      }
    } catch (_) {
      // 加载更多失败不打断已有列表，用户可再次上拉
    } finally {
      _loadingMore = false;
    }
  }
}

/// 会议列表 Provider
final meetingListProvider =
    AsyncNotifierProvider.family<MeetingListController, List<Meeting>, String>(
  MeetingListController.new,
);

/// 会议详情 Provider
final meetingDetailProvider =
    FutureProvider.family<Meeting, String>((ref, meetingId) {
  return ref.watch(meetingRepositoryProvider).detail(meetingId);
});
