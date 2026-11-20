import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/api_client.dart';
import '../../data/meeting_repository.dart';
import 'annotation_controller.dart';
import 'signal_controller.dart';

/// 入会阶段
enum RoomPhase {
  idle,

  /// 正在向后端申请 LiveKit Token
  fetchingToken,

  /// 正在连接信令服务器
  connecting,
  connected,
  failed,
}

/// 参会者摄像头画面（缩略图）
class ParticipantVideo {
  const ParticipantVideo({
    required this.identity,
    required this.name,
    required this.track,
    required this.isLocal,
    required this.isScreenShare,
  });

  final String identity;
  final String name;
  final VideoTrack track;
  final bool isLocal;
  final bool isScreenShare;
}

/// 成员列表项
class RoomMember {
  const RoomMember({
    required this.identity,
    required this.name,
    required this.isLocal,
    required this.micEnabled,
    required this.cameraEnabled,
    this.isHost = false,
    this.avatarUrl,
  });

  final String identity;
  final String name;
  final bool isLocal;
  final bool micEnabled;
  final bool cameraEnabled;

  /// 是否为动态主持人（由房间成员按确定性规则推导）
  final bool isHost;

  /// 头像地址（token metadata 注入，可能为空）
  final String? avatarUrl;
}

/// 会议室状态
class RoomState {
  const RoomState({
    this.phase = RoomPhase.idle,
    this.error,
    this.micEnabled = false,
    this.cameraEnabled = false,
    this.screenSharing = false,
    this.mainTrack,
    this.mainName,
    this.mainIdentity,
    this.mainIsLocal = false,
    this.mainIsScreenShare = false,
    this.thumbnails = const [],
    this.members = const [],
    this.hostIdentity,
    this.activeSpeakerId,
    this.followSpeaker = true,
    this.pinnedIdentity,
  });

  final RoomPhase phase;
  final String? error;
  final bool micEnabled;
  final bool cameraEnabled;
  final bool screenSharing;

  /// 主舞台画面（唯一）——标注只作用于这一路
  final VideoTrack? mainTrack;
  final String? mainName;

  /// 主画面成员 identity（同框圆桌席位取主画面视频用）
  final String? mainIdentity;
  final bool mainIsLocal;
  final bool mainIsScreenShare;

  /// 缩略图（其他参会者摄像头）
  final List<ParticipantVideo> thumbnails;

  /// 成员列表
  final List<RoomMember> members;

  /// 动态主持人 identity（算法与 Web 端一致）
  final String? hostIdentity;

  /// 当前发言人 identity（ActiveSpeakers 首位，用于高亮兜底）
  final String? activeSpeakerId;

  /// 是否跟随发言人自动切主位（工具栏开关）
  final bool followSpeaker;

  /// 钉住到主画面的成员 identity（点击缩略图）
  final String? pinnedIdentity;

  int get participantCount => members.length;

  /// 主画面标题
  String get mainTitle {
    final name = mainName ?? '';
    if (mainIsScreenShare) {
      return name.isEmpty ? '屏幕共享' : '$name 的屏幕共享';
    }
    return name.isEmpty ? '等待画面' : name;
  }

  RoomState copyWith({
    RoomPhase? phase,
    String? error,
    bool clearError = false,
    bool? micEnabled,
    bool? cameraEnabled,
    bool? screenSharing,
    VideoTrack? mainTrack,
    String? mainName,
    String? mainIdentity,
    bool? mainIsLocal,
    bool? mainIsScreenShare,
    bool clearMain = false,
    List<ParticipantVideo>? thumbnails,
    List<RoomMember>? members,
    String? hostIdentity,
    String? activeSpeakerId,
    bool clearActiveSpeaker = false,
    bool? followSpeaker,
    String? pinnedIdentity,
    bool clearPinned = false,
  }) {
    return RoomState(
      phase: phase ?? this.phase,
      error: clearError ? null : (error ?? this.error),
      micEnabled: micEnabled ?? this.micEnabled,
      cameraEnabled: cameraEnabled ?? this.cameraEnabled,
      screenSharing: screenSharing ?? this.screenSharing,
      mainTrack: clearMain ? null : (mainTrack ?? this.mainTrack),
      mainName: clearMain ? null : (mainName ?? this.mainName),
      mainIdentity: clearMain ? null : (mainIdentity ?? this.mainIdentity),
      mainIsLocal: mainIsLocal ?? this.mainIsLocal,
      mainIsScreenShare: mainIsScreenShare ?? this.mainIsScreenShare,
      thumbnails: thumbnails ?? this.thumbnails,
      members: members ?? this.members,
      hostIdentity: hostIdentity ?? this.hostIdentity,
      activeSpeakerId:
          clearActiveSpeaker ? null : (activeSpeakerId ?? this.activeSpeakerId),
      followSpeaker: followSpeaker ?? this.followSpeaker,
      pinnedIdentity:
          clearPinned ? null : (pinnedIdentity ?? this.pinnedIdentity),
    );
  }
}

/// 会议室控制器
///
/// 负责 LiveKit 连接、主画面选取、成员/缩略图同步、生命周期与重连。
class RoomController extends FamilyNotifier<RoomState, String> {
  Room? _room;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _micWanted = false; // 静音入会：仅主持人/手动开麦后置 true
  bool _leaving = false;

  /// 标注模式标记（由 RoomScreen 同步）：标注中不自动切主位
  bool _annotating = false;

  /// 上次是否为主持人（用于检测"接任主持人"跃迁）
  bool _wasHost = false;

  /// 发言人覆盖（语音活动自动切主位）与防抖控制
  String? _speakerOverride;
  String? _speakerCandidate;
  DateTime _lastSpeakerSwitch = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _speakerConfirmTimer;

  /// 房间事件监听句柄，退会/重连时统一取消
  final List<CancelListenFunc> _roomListeners = [];

  /// 取消全部房间事件监听
  void _cancelRoomListeners() {
    for (final cancel in _roomListeners) {
      cancel();
    }
    _roomListeners.clear();
  }

  /// 暴露给标注控制器使用的房间实例
  Room? get room => _room;

  @override
  RoomState build(String meetingId) {
    return const RoomState();
  }

  /// 入会：取凭证 → 连信令 → 显式开麦/关摄像头 → 绑定标注
  Future<void> connect() async {
    if (_room != null && state.phase == RoomPhase.connected) return;

    // 上一次入会失败后可能残留 Room 实例，重试前先断开并释放，避免
    // 旧连接占用摄像头/麦克风导致新连接取不到设备
    final previous = _room;
    if (previous != null) {
      _room = null;
      _cancelRoomListeners();
      try {
        await previous.disconnect();
      } catch (_) {
        // 旧连接可能已断开，忽略
      }
      try {
        await previous.dispose();
      } catch (_) {
        // 忽略
      }
    }

    _leaving = false;
    state = state.copyWith(phase: RoomPhase.fetchingToken, clearError: true);

    try {
      final credentials =
          await ref.read(meetingRepositoryProvider).fetchLivekitToken(arg);

      final room = Room();
      _room = room;

      state = state.copyWith(phase: RoomPhase.connecting);
      _bindRoomEvents(room);

      await room.connect(credentials.url, credentials.token);

      // 静音入会：全员默认不开麦；若按动态规则自己是主持人则自动开麦
      await _enableMicIfHost();
      await _disableCameraSafely();

      // 绑定标注 Data Channel 监听（topic=annotation）
      ref.read(annotationControllerProvider(arg).notifier).attach(room);
      // 绑定举手/点名信令监听（topic=signal）
      ref.read(signalControllerProvider(arg).notifier).attach(room);

      await WakelockPlus.enable();
      _watchConnectivity();

      state = state.copyWith(phase: RoomPhase.connected, clearError: true);
      _syncTracks();
    } on ApiException catch (e) {
      state = state.copyWith(phase: RoomPhase.failed, error: e.message);
    } catch (e) {
      state = state.copyWith(
        phase: RoomPhase.failed,
        error: '入会失败：$e',
      );
    }
  }

  /// 注册 LiveKit 房间事件
  ///
  /// livekit_client 2.13 采用强类型事件：room.events.on<XxxEvent>(cb)
  void _bindRoomEvents(Room room) {
    _cancelRoomListeners();
    final events = room.events;
    _roomListeners
      ..add(events.on<ParticipantConnectedEvent>((_) => _syncTracks()))
      ..add(events.on<ParticipantDisconnectedEvent>((_) => _syncTracks()))
      ..add(events.on<TrackSubscribedEvent>((_) => _syncTracks()))
      ..add(events.on<TrackUnsubscribedEvent>((_) => _syncTracks()))
      ..add(events.on<LocalTrackPublishedEvent>((_) => _syncTracks()))
      ..add(events.on<LocalTrackUnpublishedEvent>((_) => _syncTracks()))
      ..add(events.on<TrackMutedEvent>((_) => _syncTracks()))
      ..add(events.on<TrackUnmutedEvent>((_) => _syncTracks()))
      ..add(events.on<ActiveSpeakersChangedEvent>(
          (e) => _onActiveSpeakers(e.speakers)))
      ..add(events.on<ParticipantMetadataUpdatedEvent>((_) => _syncTracks()))
      ..add(events.on<RoomDisconnectedEvent>((_) => _onRoomDisconnected()));
  }

  /// 信令断开（非主动退会时提示用户重试）
  void _onRoomDisconnected() {
    if (_leaving) return;
    state = state.copyWith(
      phase: RoomPhase.failed,
      error: '连接已断开，请检查网络后重试入会',
    );
  }

  /// 安全开启麦克风（iOS 首次可能因权限抛错，降级为静音）
  Future<void> _enableMicrophoneSafely() async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    try {
      await participant.setMicrophoneEnabled(true);
      _micWanted = true;
      state = state.copyWith(micEnabled: true);
    } catch (_) {
      state = state.copyWith(micEnabled: false);
    }
  }

  /// 解析 participant.metadata（JSON：{"role":"...","avatar_url":"..."}）
  Map<String, String> _parseMeta(Participant participant) {
    try {
      final raw = participant.metadata;
      if (raw == null || raw.isEmpty) return const {};
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic>) {
        return {
          'role': (m['role'] as String?) ?? 'student',
          'avatar_url': (m['avatar_url'] as String?) ?? '',
        };
      }
    } catch (_) {
      // metadata 非 JSON 时按默认值处理
    }
    return const {};
  }

  /// 角色权重：老师/管理员优先接任主持人（算法与 Web 端一致）
  int _roleWeight(String role) =>
      (role == 'admin' || role == 'teacher') ? 0 : 1;

  /// 计算动态主持人 identity：角色权重 → joinedAt 升序 → identity 字典序，取第一
  String? _computeHostIdentity(Room room) {
    final all = <Participant>[
      ...room.remoteParticipants.values,
      if (room.localParticipant != null) room.localParticipant!,
    ];
    if (all.isEmpty) return null;
    all.sort((a, b) {
      final wa = _roleWeight(_parseMeta(a)['role'] ?? 'student');
      final wb = _roleWeight(_parseMeta(b)['role'] ?? 'student');
      if (wa != wb) return wa.compareTo(wb);
      final ta = a.joinedAt.millisecondsSinceEpoch;
      final tb = b.joinedAt.millisecondsSinceEpoch;
      if (ta != tb) return ta.compareTo(tb);
      return a.identity.compareTo(b.identity);
    });
    return all.first.identity;
  }

  /// 连接后按动态规则决定开麦：仅主持人自动开麦，其余保持静音
  Future<void> _enableMicIfHost() async {
    final room = _room;
    if (room == null) return;
    final hostId = _computeHostIdentity(room);
    _wasHost = hostId != null && hostId == room.localParticipant?.identity;
    if (_wasHost) {
      await _enableMicrophoneSafely();
    } else {
      state = state.copyWith(micEnabled: false);
    }
  }

  /// ActiveSpeakers 变化：高亮发言人 + 满足条件时自动切主位
  ///
  /// 生效条件：跟随开启 && 未标注 && 未钉住 && 无屏幕共享 && 发言人不是自己；
  /// 防抖 2.5s + 新发言人连续 ~800ms 居首位才切换（与 Web 端一致）。
  void _onActiveSpeakers(List<Participant> speakers) {
    state = state.copyWith(
      activeSpeakerId: speakers.isEmpty ? null : speakers.first.identity,
      clearActiveSpeaker: speakers.isEmpty,
    );

    final room = _room;
    if (room == null) return;
    if (!state.followSpeaker || _annotating || state.pinnedIdentity != null) {
      return;
    }
    if (_hasScreenShare(room)) return;

    final localIdentity = room.localParticipant?.identity;
    Participant? candidate;
    for (final s in speakers) {
      if (s.identity != localIdentity) {
        candidate = s;
        break;
      }
    }
    if (candidate == null) return;

    if (candidate.identity == _speakerOverride) {
      _speakerCandidate = null;
      _speakerConfirmTimer?.cancel();
      return;
    }
    // 防抖：距上次切换不足 2.5s 不换人
    if (DateTime.now().difference(_lastSpeakerSwitch).inMilliseconds < 2500) {
      return;
    }
    if (_speakerCandidate == candidate.identity) return;
    _speakerCandidate = candidate.identity;
    _speakerConfirmTimer?.cancel();
    _speakerConfirmTimer = Timer(const Duration(milliseconds: 800), () {
      if (_speakerCandidate == candidate!.identity) {
        _speakerOverride = candidate.identity;
        _lastSpeakerSwitch = DateTime.now();
        _speakerCandidate = null;
        _syncTracks();
      }
    });
  }

  /// 房间内是否存在屏幕共享轨道
  bool _hasScreenShare(Room room) {
    bool hasScreen(Participant p) => p.trackPublications.values
        .any((pub) => pub.track != null && _isScreenShare(pub));
    if (room.remoteParticipants.values.any(hasScreen)) return true;
    final local = room.localParticipant;
    return local != null && hasScreen(local);
  }

  /// 切换"跟随发言人"开关
  void toggleFollowSpeaker() {
    state = state.copyWith(followSpeaker: !state.followSpeaker);
  }

  /// 点击缩略图钉住/取消钉住主画面（钉住优先于发言人覆盖）
  void togglePin(String identity) {
    if (state.pinnedIdentity == identity) {
      state = state.copyWith(clearPinned: true);
    } else {
      _speakerOverride = null;
      state = state.copyWith(pinnedIdentity: identity);
    }
    _syncTracks();
  }

  /// 由 RoomScreen 同步标注模式：标注中不自动切主位
  void setAnnotationMode(bool annotating) {
    _annotating = annotating;
  }

  /// 被主持人点名后自动开麦（由 SignalController 调用）
  ///
  /// 与手动开麦走同一条安全路径：权限被拒时降级为静音，
  /// 并同步 _micWanted 保证前后台切换后自动恢复
  Future<void> enableMicFromDesignate() async {
    await _enableMicrophoneSafely();
  }

  /// 安全关闭摄像头（SDK 默认即关闭，此处显式保证）
  Future<void> _disableCameraSafely() async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    try {
      await participant.setCameraEnabled(false);
      state = state.copyWith(cameraEnabled: false);
    } catch (_) {
      // 忽略
    }
  }

  /// 切换麦克风
  Future<void> toggleMicrophone() async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    final next = !state.micEnabled;
    try {
      await participant.setMicrophoneEnabled(next);
      _micWanted = next;
      state = state.copyWith(micEnabled: next, clearError: true);
    } catch (e) {
      state = state.copyWith(error: '麦克风不可用：请检查系统权限');
    }
  }

  /// 切换摄像头（iOS 首次可能抛 MediaDevicesError，降级并提示）
  Future<void> toggleCamera() async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    final next = !state.cameraEnabled;
    try {
      await participant.setCameraEnabled(next);
      state = state.copyWith(cameraEnabled: next, clearError: true);
      _syncTracks();
    } catch (e) {
      state = state.copyWith(error: '摄像头不可用：请在系统设置中授权后重试');
    }
  }

  /// 切换屏幕共享（iOS 需 Broadcast Upload Extension，Phase 3 支持）
  Future<void> toggleScreenShare() async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    final next = !state.screenSharing;
    try {
      await participant.setScreenShareEnabled(next);
      state = state.copyWith(screenSharing: next, clearError: true);
      _syncTracks();
    } catch (_) {
      state = state.copyWith(error: '当前设备暂不支持屏幕共享');
    }
  }

  /// 同步主画面、缩略图与成员列表
  ///
  /// 主画面优先级与 Web 端完全一致：
  /// 钉住 > 屏幕共享（永不被抢）> 发言人 > 远端摄像头 > 本地摄像头
  void _syncTracks() {
    final room = _room;
    if (room == null) return;

    final allVideos = <ParticipantVideo>[];
    for (final participant in room.remoteParticipants.values) {
      _collectVideos(participant, false, allVideos);
    }
    if (room.localParticipant != null) {
      _collectVideos(room.localParticipant!, true, allVideos);
    }

    // 发言人离开/关摄像头后自动解除覆盖
    if (_speakerOverride != null &&
        !allVideos.any(
            (v) => v.identity == _speakerOverride && !v.isScreenShare)) {
      _speakerOverride = null;
    }

    ParticipantVideo? main;
    // 0) 钉住的成员
    final pinned = state.pinnedIdentity;
    if (pinned != null) {
      main = _firstOrNull(allVideos,
          (v) => v.identity == pinned && !v.isScreenShare);
    }
    // 1) 屏幕共享（远端优先，其次本地）
    main ??=
        _firstOrNull(allVideos, (v) => v.isScreenShare && !v.isLocal) ??
            _firstOrNull(allVideos, (v) => v.isScreenShare && v.isLocal);
    // 2) 发言人覆盖
    if (main == null && _speakerOverride != null) {
      main = _firstOrNull(allVideos,
          (v) => v.identity == _speakerOverride && !v.isScreenShare);
    }
    // 3) 远端摄像头 → 本地摄像头
    main ??= _firstOrNull(allVideos, (v) => !v.isScreenShare && !v.isLocal) ??
        _firstOrNull(allVideos, (v) => !v.isScreenShare && v.isLocal);

    final thumbnails = allVideos
        .where((v) => !v.isScreenShare && !identical(v.track, main?.track))
        .take(8)
        .toList();

    // 动态主持人：跃迁为"自己是主持人"时自动开麦
    final hostIdentity = _computeHostIdentity(room);
    final isHost =
        hostIdentity != null && hostIdentity == room.localParticipant?.identity;
    if (isHost && !_wasHost && state.phase == RoomPhase.connected) {
      _wasHost = true;
      unawaited(_enableMicrophoneSafely());
    } else if (!isHost) {
      _wasHost = false;
    }
    // 同步主持人标记给信令控制器（决定点名权限与回执提示）
    ref.read(signalControllerProvider(arg).notifier).setHost(isHost);

    final members = <RoomMember>[];
    for (final participant in room.remoteParticipants.values) {
      members.add(_toMember(participant, false, hostIdentity));
    }
    if (room.localParticipant != null) {
      members.add(_toMember(room.localParticipant!, true, hostIdentity));
    }

    state = RoomState(
      phase: state.phase,
      error: state.error,
      micEnabled: state.micEnabled,
      cameraEnabled: state.cameraEnabled,
      screenSharing: state.screenSharing,
      mainTrack: main?.track,
      mainName: main?.name,
      mainIdentity: main?.identity,
      mainIsLocal: main?.isLocal ?? false,
      mainIsScreenShare: main?.isScreenShare ?? false,
      thumbnails: thumbnails,
      members: members,
      hostIdentity: hostIdentity,
      activeSpeakerId: state.activeSpeakerId,
      followSpeaker: state.followSpeaker,
      pinnedIdentity: state.pinnedIdentity,
    );
  }

  /// 按条件取第一个视频，没有则返回 null
  ParticipantVideo? _firstOrNull(
    List<ParticipantVideo> videos,
    bool Function(ParticipantVideo) test,
  ) {
    for (final video in videos) {
      if (test(video)) return video;
    }
    return null;
  }

  /// 收集某参会者的已订阅视频轨道
  void _collectVideos(
    Participant participant,
    bool isLocal,
    List<ParticipantVideo> out,
  ) {
    final name = _displayName(participant);
    for (final publication in participant.trackPublications.values) {
      final track = publication.track;
      if (track is! VideoTrack) continue;
      out.add(ParticipantVideo(
        identity: participant.identity,
        name: name,
        track: track,
        isLocal: isLocal,
        isScreenShare: _isScreenShare(publication),
      ));
    }
  }

  /// 判断轨道是否为屏幕共享
  ///
  /// 不同 livekit_client 小版本对 TrackSource 的枚举命名略有差异
  /// （screenShare / screenShareVideo），这里用字符串匹配保证编译兼容。
  bool _isScreenShare(TrackPublication publication) {
    return publication.source.toString().toLowerCase().contains('screen');
  }

  /// 转换为成员项（附带动态主持人标记与头像）
  RoomMember _toMember(Participant participant, bool isLocal, String? hostIdentity) {
    var micEnabled = false;
    var cameraEnabled = false;
    for (final publication in participant.trackPublications.values) {
      final track = publication.track;
      if (track == null || publication.muted) continue;
      if (track is AudioTrack) micEnabled = true;
      if (track is VideoTrack) cameraEnabled = true;
    }
    final meta = _parseMeta(participant);
    return RoomMember(
      identity: participant.identity,
      name: _displayName(participant),
      isLocal: isLocal,
      micEnabled: micEnabled,
      cameraEnabled: cameraEnabled,
      isHost: hostIdentity == participant.identity,
      avatarUrl: (meta['avatar_url'] ?? '').isEmpty ? null : meta['avatar_url'],
    );
  }

  /// 展示名（LiveKit identity 兜底）
  String _displayName(Participant participant) {
    final name = participant.name;
    return name.isNotEmpty ? name : participant.identity;
  }

  /// 监听网络切换：从无网恢复后自动重连
  void _watchConnectivity() {
    _connectivitySub?.cancel();
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) async {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (!online) return;
      final room = _room;
      if (room == null) return;
      if (room.connectionState == ConnectionState.disconnected) {
        await _reconnect();
      }
    });
  }

  /// 重新获取凭证并重连
  Future<void> _reconnect() async {
    try {
      final credentials =
          await ref.read(meetingRepositoryProvider).fetchLivekitToken(arg);
      await _room?.connect(credentials.url, credentials.token);
      ref.read(annotationControllerProvider(arg).notifier).attach(_room!);
      ref.read(signalControllerProvider(arg).notifier).attach(_room!);
      await _enableMicIfHost();
      state = state.copyWith(phase: RoomPhase.connected, clearError: true);
      _syncTracks();
    } catch (_) {
      state = state.copyWith(
        phase: RoomPhase.failed,
        error: '重连失败，请返回列表后重新入会',
      );
    }
  }

  /// App 切到后台：仅静音，不断开连接
  Future<void> onAppPaused() async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    if (!state.micEnabled) return;
    try {
      await participant.setMicrophoneEnabled(false);
      state = state.copyWith(micEnabled: false);
    } catch (_) {
      // 忽略
    }
  }

  /// App 回到前台：必要时重连并恢复麦克风
  Future<void> onAppResumed() async {
    final room = _room;
    if (room == null) return;
    if (room.connectionState == ConnectionState.disconnected) {
      await _reconnect();
      return;
    }
    if (_micWanted && !state.micEnabled) {
      await _enableMicrophoneSafely();
    }
  }

  /// 主动退会并释放资源
  Future<void> leaveRoom() async {
    _leaving = true;
    await WakelockPlus.disable();
    await _connectivitySub?.cancel();
    _connectivitySub = null;

    ref.read(annotationControllerProvider(arg).notifier).detach();
    ref.read(signalControllerProvider(arg).notifier).detach();
    _cancelRoomListeners();

    // 复位主持人/发言人状态
    _speakerConfirmTimer?.cancel();
    _speakerConfirmTimer = null;
    _speakerOverride = null;
    _speakerCandidate = null;
    _wasHost = false;
    _annotating = false;
    _micWanted = false;

    final room = _room;
    _room = null;
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {
        // 忽略
      }
      try {
        await room.dispose();
      } catch (_) {
        // 忽略
      }
    }
    state = const RoomState();
  }

  /// 清除一次性错误提示
  void clearError() {
    if (state.error != null) {
      state = state.copyWith(clearError: true);
    }
  }
}

/// 会议室控制器 Provider
final roomControllerProvider =
    NotifierProvider.family<RoomController, RoomState, String>(
  RoomController.new,
);
