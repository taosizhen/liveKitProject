import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/meeting.dart';
import 'api_client.dart';

/// 会议分页结果
class MeetingPage {
  const MeetingPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.pages,
  });

  final List<Meeting> items;
  final int total;
  final int page;
  final int pageSize;
  final int pages;

  /// 是否还有下一页
  bool get hasMore => page < pages;
}

/// LiveKit 入会凭证
///
/// 信令地址来自后端下发的 `livekit_url`，前端不硬编码。
class LivekitCredentials {
  const LivekitCredentials({
    required this.url,
    required this.token,
    required this.roomName,
  });

  final String url;
  final String token;
  final String roomName;
}

/// 会议仓库
class MeetingRepository {
  MeetingRepository(this._api);

  final ApiClient _api;

  /// 会议列表（支持 status 过滤与分页）
  Future<MeetingPage> list({
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _api.getJson('/meetings', query: {
      'page': page,
      'page_size': pageSize,
      if (status != null && status.isNotEmpty) 'status': status,
    });
    if (data is! Map<String, dynamic>) {
      throw ApiException('会议列表格式异常');
    }
    final rawItems = data['items'];
    return MeetingPage(
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(Meeting.fromJson)
              .toList()
          : const [],
      total: (data['total'] as num?)?.toInt() ?? 0,
      page: (data['page'] as num?)?.toInt() ?? page,
      pageSize: (data['page_size'] as num?)?.toInt() ?? pageSize,
      pages: (data['pages'] as num?)?.toInt() ?? 1,
    );
  }

  /// 会议详情
  Future<Meeting> detail(String meetingId) async {
    final data = await _api.getJson('/meetings/$meetingId');
    if (data is! Map<String, dynamic>) {
      throw ApiException('会议详情格式异常');
    }
    return Meeting.fromJson(data);
  }

  /// 确认参加（后端会同时把 participant 状态置为 joined）
  Future<void> join(String meetingId) async {
    await _api.postJson('/meetings/$meetingId/join');
  }

  /// 获取 LiveKit 连接信息
  Future<LivekitCredentials> fetchLivekitToken(String meetingId) async {
    final data = await _api.getJson('/meetings/$meetingId/livekit-token');
    if (data is! Map<String, dynamic>) {
      throw ApiException('入会凭证格式异常');
    }
    final url = (data['livekit_url'] as String?) ?? '';
    final token = (data['token'] as String?) ?? '';
    if (url.isEmpty || token.isEmpty) {
      throw ApiException('服务器未返回有效的 LiveKit 地址或令牌');
    }
    return LivekitCredentials(
      url: url,
      token: token,
      roomName: (data['room_name'] as String?) ?? '',
    );
  }
}

/// 会议仓库 Provider
final meetingRepositoryProvider = Provider<MeetingRepository>((ref) {
  return MeetingRepository(ref.watch(apiClientProvider));
});
