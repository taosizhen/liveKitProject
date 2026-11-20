import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../models/signal.dart';
import 'room_controller.dart';

/// 举手/点名信令状态
class SignalState {
  const SignalState({
    this.hands = const {},
    this.designateNotice,
    this.designateAckNotice,
  });

  /// 举手中的人员表：identity → 举手记录
  final Map<String, RaisedHand> hands;

  /// 被点名提示（一次性 toast，null 表示无）
  final String? designateNotice;

  /// 点名回执提示（主持人端，null 表示无）
  final String? designateAckNotice;

  /// 按举手时间升序（主持人点名顺序）
  List<RaisedHand> get raisedHands {
    final list = hands.values.toList()
      ..sort((a, b) => a.ts.compareTo(b.ts));
    return list;
  }

  SignalState copyWith({
    Map<String, RaisedHand>? hands,
    String? designateNotice,
    bool clearDesignateNotice = false,
    String? designateAckNotice,
    bool clearDesignateAckNotice = false,
  }) {
    return SignalState(
      hands: hands ?? this.hands,
      designateNotice:
          clearDesignateNotice ? null : (designateNotice ?? this.designateNotice),
      designateAckNotice: clearDesignateAckNotice
          ? null
          : (designateAckNotice ?? this.designateAckNotice),
    );
  }
}

/// 举手/点名信令控制器
///
/// 协议完全复用 Web 端（topic=`signal`），实现跨端互通。
/// 状态纯内存 + 事件溯源：新加入者广播 hand_sync_req，举手中者重发 hand_raise 收敛。
class SignalController extends FamilyNotifier<SignalState, String> {
  /// 当前 LiveKit 房间（由 RoomController 在连接成功后注入）
  Room? _room;

  /// 当前是否为动态主持人（由 RoomController 同步）
  bool _isHost = false;

  /// 数据通道与成员事件监听句柄
  CancelListenFunc? _dataListener;
  CancelListenFunc? _participantLeftListener;

  /// toast 自动清除计时器
  Timer? _noticeTimer;

  @override
  SignalState build(String meetingId) => const SignalState();

  /// 绑定房间并监听远端信令（连接成功后调用）
  void attach(Room room) {
    if (identical(_room, room)) return;
    detach();
    _room = room;
    _dataListener = room.events.on<DataReceivedEvent>(_onDataReceived);
    _participantLeftListener =
        room.events.on<ParticipantDisconnectedEvent>((e) {
      _removeHand(e.participant.identity);
    });
    // 进房 ~500ms 后广播同步请求，让举手中者重发 hand_raise 收敛状态
    Timer(const Duration(milliseconds: 500), () {
      final identity = _room?.localParticipant?.identity;
      if (identity != null) {
        _publish(SignalMessage(kind: 'hand_sync_req', identity: identity));
      }
    });
  }

  /// 解绑房间并清空状态（离开会议室时调用）
  void detach() {
    _dataListener?.call();
    _dataListener = null;
    _participantLeftListener?.call();
    _participantLeftListener = null;
    _noticeTimer?.cancel();
    _noticeTimer = null;
    _room = null;
    state = const SignalState();
  }

  /// 由 RoomController 同步动态主持人标记（决定点名权限与回执提示）
  void setHost(bool isHost) {
    _isHost = isHost;
  }

  /// 举手（本地登记 + 广播）
  void raiseHand() {
    final identity = _room?.localParticipant?.identity;
    if (identity == null) return;
    final name = _room?.localParticipant?.name;
    final hand = RaisedHand(
      identity: identity,
      name: (name == null || name.isEmpty) ? identity : name,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    state = state.copyWith(hands: {...state.hands, identity: hand});
    _publish(SignalMessage(
      kind: 'hand_raise',
      identity: hand.identity,
      name: hand.name,
      ts: hand.ts,
    ));
  }

  /// 放下手（本地移除 + 广播）
  void lowerHand() {
    final identity = _room?.localParticipant?.identity;
    if (identity == null) return;
    _removeHand(identity);
    _publish(SignalMessage(kind: 'hand_lower', identity: identity));
  }

  /// 主持人点名：邀请指定成员发言
  void designate(String target) {
    if (!_isHost) return;
    final by = _room?.localParticipant?.identity ?? '';
    _publish(SignalMessage(kind: 'designate', target: target, by: by));
  }

  /// 清除一次性提示（toast 展示后调用）
  void clearNotices() {
    if (state.designateNotice != null || state.designateAckNotice != null) {
      state = state.copyWith(
          clearDesignateNotice: true, clearDesignateAckNotice: true);
    }
  }

  /// 移除一条举手记录
  void _removeHand(String identity) {
    if (!state.hands.containsKey(identity)) return;
    final next = Map<String, RaisedHand>.from(state.hands)..remove(identity);
    state = state.copyWith(hands: next);
  }

  /// 发送 Data Channel 消息（失败静默，避免打断会议）
  Future<void> _publish(SignalMessage message) async {
    final room = _room;
    if (room == null) return;
    try {
      await room.localParticipant?.publishData(
        message.encode(),
        reliable: true,
        topic: SignalProtocol.topic,
      );
    } catch (_) {
      // 数据通道暂不可用（重连中）时忽略
    }
  }

  /// 设置一次性提示并安排自动清除
  void _showNotice({String? designate, String? ack}) {
    _noticeTimer?.cancel();
    state = state.copyWith(
      designateNotice: designate,
      designateAckNotice: ack,
    );
    _noticeTimer = Timer(const Duration(seconds: 4), clearNotices);
  }

  /// 接收远端信令消息
  void _onDataReceived(DataReceivedEvent event) {
    if (event.topic != SignalProtocol.topic) return;
    final message = SignalMessage.tryDecode(utf8.decode(event.data));
    if (message == null) return;

    final localIdentity = _room?.localParticipant?.identity;
    switch (message.kind) {
      case 'hand_raise':
        final identity = message.identity;
        if (identity == null || identity.isEmpty) return;
        state = state.copyWith(hands: {
          ...state.hands,
          identity: RaisedHand(
            identity: identity,
            name: message.name?.isNotEmpty == true
                ? message.name!
                : identity,
            ts: message.ts ?? DateTime.now().millisecondsSinceEpoch,
          ),
        });
        break;
      case 'hand_lower':
        final identity = message.identity;
        if (identity != null) _removeHand(identity);
        break;
      case 'hand_sync_req':
        // 新加入者请求同步：若自己正举手，重发 hand_raise 让其收敛
        final mine = state.hands[localIdentity];
        if (mine != null) {
          _publish(SignalMessage(
            kind: 'hand_raise',
            identity: mine.identity,
            name: mine.name,
            ts: mine.ts,
          ));
        }
        break;
      case 'designate':
        // 被点名：自动开麦 → 清除自身举手并广播 → 回执
        if (message.target != localIdentity || localIdentity == null) return;
        final by = message.by ?? '';
        unawaited(() async {
          try {
            await ref
                .read(roomControllerProvider(arg).notifier)
                .enableMicFromDesignate();
          } finally {
            _removeHand(localIdentity);
            _publish(SignalMessage(
                kind: 'hand_lower', identity: localIdentity, by: by));
            _publish(SignalMessage(
                kind: 'designate_ack', identity: localIdentity, ok: true));
          }
        }());
        _showNotice(designate: '主持人邀请你发言，已为你开启麦克风');
        break;
      case 'designate_ack':
        // 主持人端收到回执提示
        if (!_isHost) return;
        final identity = message.identity ?? '';
        final name = state.hands[identity]?.name ?? identity;
        _showNotice(ack: '「$name」已接受发言');
        break;
      default:
        break;
    }
  }
}

/// 举手/点名信令控制器 Provider（每个会议一个实例）
final signalControllerProvider =
    NotifierProvider.family<SignalController, SignalState, String>(
  SignalController.new,
);
