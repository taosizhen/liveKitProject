import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/api_client.dart';
import '../../data/meeting_repository.dart';
import 'annotation_controller.dart';

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
  });

  final String identity;
  final String name;
  final bool isLocal;
  final bool micEnabled;
  final bool cameraEnabled;
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
    this.mainIsLocal = false,
    this.mainIsScreenShare = false,
    this.thumbnails = const [],
    this.members = const [],
  });

  final RoomPhase phase;
  final String? error;
  final bool micEnabled;
  final bool cameraEnabled;
  final bool screenSharing;

  /// 主舞台画面（唯一）——标注只作用于这一路
  final VideoTrack? mainTrack;
  final String? mainName;
  final bool mainIsLocal;
  final bool mainIsScreenShare;

  /// 缩略图（其他参会者摄像头）
  final List<ParticipantVideo> thumbnails;

  /// 成员列表
  final List<RoomMember> members;

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
    bool? mainIsLocal,
    bool? mainIsScreenShare,
    bool clearMain = false,
    List<ParticipantVideo>? thumbnails,
    List<RoomMember>? members,
  }) {
    return RoomState(
      phase: phase ?? this.phase,
      error: clearError ? null : (error ?? this.error),
      micEnabled: micEnabled ?? this.micEnabled,
      cameraEnabled: cameraEnabled ?? this.cameraEnabled,
      screenSharing: screenSharing ?? this.screenSharing,
      mainTrack: clearMain ? null : (mainTrack ?? this.mainTrack),
      mainName: clearMain ? null : (mainName ?? this.mainName),
      mainIsLocal: mainIsLocal ?? this.mainIsLocal,
      mainIsScreenShare: mainIsScreenShare ?? this.mainIsScreenShare,
      thumbnails: thumbnails ?? this.thumbnails,
      members: members ?? this.members,
    );
  }
}

/// 会议室控制器
///
/// 负责 LiveKit 连接、主画面选取、成员/缩略图同步、生命周期与重连。
class RoomController extends FamilyNotifier<RoomState, String> {
  Room? _room;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _micWanted = true;
  bool _leaving = false;

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

      // LiveKit SDK 默认麦克风/摄像头全关，必须显式开启
      await _enableMicrophoneSafely();
      await _disableCameraSafely();

      // 绑定标注 Data Channel 监听（topic=annotation）
      ref.read(annotationControllerProvider(arg).notifier).attach(room);

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
      ..add(events.on<ActiveSpeakersChangedEvent>((_) => _syncTracks()))
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
  /// 屏幕共享 > 远端摄像头 > 本地摄像头（永远只有 1 路）
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

    ParticipantVideo? main;
    // 1) 屏幕共享（远端优先，其次本地）
    main = _firstOrNull(allVideos, (v) => v.isScreenShare && !v.isLocal) ??
        _firstOrNull(allVideos, (v) => v.isScreenShare && v.isLocal) ??
        // 2) 远端摄像头
        _firstOrNull(allVideos, (v) => !v.isScreenShare && !v.isLocal) ??
        // 3) 本地摄像头
        _firstOrNull(allVideos, (v) => !v.isScreenShare && v.isLocal);

    final thumbnails = allVideos
        .where((v) => !v.isScreenShare && !identical(v.track, main?.track))
        .take(8)
        .toList();

    final members = <RoomMember>[];
    for (final participant in room.remoteParticipants.values) {
      members.add(_toMember(participant, false));
    }
    if (room.localParticipant != null) {
      members.add(_toMember(room.localParticipant!, true));
    }

    state = RoomState(
      phase: state.phase,
      error: state.error,
      micEnabled: state.micEnabled,
      cameraEnabled: state.cameraEnabled,
      screenSharing: state.screenSharing,
      mainTrack: main?.track,
      mainName: main?.name,
      mainIsLocal: main?.isLocal ?? false,
      mainIsScreenShare: main?.isScreenShare ?? false,
      thumbnails: thumbnails,
      members: members,
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

  /// 转换为成员项
  RoomMember _toMember(Participant participant, bool isLocal) {
    var micEnabled = false;
    var cameraEnabled = false;
    for (final publication in participant.trackPublications.values) {
      final track = publication.track;
      if (track == null || publication.muted) continue;
      if (track is AudioTrack) micEnabled = true;
      if (track is VideoTrack) cameraEnabled = true;
    }
    return RoomMember(
      identity: participant.identity,
      name: _displayName(participant),
      isLocal: isLocal,
      micEnabled: micEnabled,
      cameraEnabled: cameraEnabled,
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
      await _enableMicrophoneSafely();
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
    _cancelRoomListeners();

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
