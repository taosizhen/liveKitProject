import 'user.dart';

/// 会议参会者
class MeetingParticipant {
  const MeetingParticipant({
    required this.id,
    required this.userId,
    required this.role,
    required this.status,
    this.user,
  });

  final String id;
  final String userId;

  /// host / speaker / attendee
  final String role;

  /// invited / confirmed / joined / declined
  final String status;
  final AppUser? user;

  /// 角色中文名
  String get roleLabel {
    switch (role) {
      case 'host':
        return '主持人';
      case 'speaker':
        return '主讲';
      case 'attendee':
        return '参会者';
      default:
        return role;
    }
  }

  /// 解析参会者 JSON
  factory MeetingParticipant.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    return MeetingParticipant(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      role: (json['participant_role'] as String?) ?? 'attendee',
      status: (json['status'] as String?) ?? 'invited',
      user: rawUser is Map<String, dynamic> ? AppUser.fromJson(rawUser) : null,
    );
  }
}

/// 会议实体
///
/// 对应后端 `GET /api/v1/meetings` 分页 `items[]` 与 `GET /api/v1/meetings/:id`
class Meeting {
  const Meeting({
    required this.id,
    required this.title,
    required this.description,
    required this.startTime,
    required this.status,
    required this.meetingType,
    required this.roomName,
    this.endTime,
    this.organizer,
    this.participants = const [],
  });

  final String id;
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime? endTime;

  /// scheduled / in_progress / completed / cancelled
  final String status;

  /// tutoring / group_class / webinar
  final String meetingType;
  final String roomName;
  final AppUser? organizer;
  final List<MeetingParticipant> participants;

  bool get isScheduled => status == 'scheduled';
  bool get isInProgress => status == 'in_progress';
  bool get isFinished => status == 'completed' || status == 'cancelled';

  /// 距离开始是否不足 15 分钟（含已开始）
  ///
  /// 后端 `/meetings` 只支持 status 过滤，没有“即将开始”参数，
  /// 因此该条件在前端计算（与 PRD 评审结论一致）。
  bool get startsWithin15Minutes {
    final diff = startTime.difference(DateTime.now());
    return diff.inMinutes <= 15;
  }

  /// 是否可以入会：进行中，或 15 分钟内即将开始
  bool get canJoin => isInProgress || (isScheduled && startsWithin15Minutes);

  /// 状态中文名
  String get statusLabel {
    switch (status) {
      case 'scheduled':
        return '待开始';
      case 'in_progress':
        return '进行中';
      case 'completed':
        return '已结束';
      case 'cancelled':
        return '已取消';
      default:
        return status;
    }
  }

  /// 会议类型中文名
  String get typeLabel {
    switch (meetingType) {
      case 'tutoring':
        return '一对一辅导';
      case 'group_class':
        return '小组课';
      case 'webinar':
        return '公开课';
      default:
        return meetingType;
    }
  }

  /// 解析会议 JSON（时间统一转本地时区）
  factory Meeting.fromJson(Map<String, dynamic> json) {
    final rawOrganizer = json['organizer'];
    final rawParticipants = json['participants'];
    return Meeting(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] as String?) ?? '未命名会议',
      description: (json['description'] as String?) ?? '',
      startTime: DateTime.parse(json['start_time'] as String).toLocal(),
      endTime: json['end_time'] == null
          ? null
          : DateTime.parse(json['end_time'] as String).toLocal(),
      status: (json['status'] as String?) ?? 'scheduled',
      meetingType: (json['meeting_type'] as String?) ?? 'tutoring',
      roomName: (json['room_name'] as String?) ?? '',
      organizer:
          rawOrganizer is Map<String, dynamic> ? AppUser.fromJson(rawOrganizer) : null,
      participants: rawParticipants is List
          ? rawParticipants
              .whereType<Map<String, dynamic>>()
              .map(MeetingParticipant.fromJson)
              .toList()
          : const [],
    );
  }
}
