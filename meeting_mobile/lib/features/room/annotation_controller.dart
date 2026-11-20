import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../models/annotation.dart';

/// 标注工具（移动端只提供 4 种，与 Web 端的 pen/rect/circle/laser 子集一致）
enum AnnotationToolKind { pen, rect, circle, laser }

/// 标注状态
class AnnotationState {
  const AnnotationState({
    this.strokes = const [],
    this.laserDots = const [],
    this.whiteboard = false,
    this.tool = AnnotationToolKind.pen,
    this.color = '#ef4444',
    this.width = 3,
  });

  /// 静态笔迹（含正在绘制的草稿）
  final List<AnnotationStroke> strokes;

  /// 激光笔轨迹点
  final List<LaserDot> laserDots;

  /// 是否白板模式
  final bool whiteboard;

  /// 当前工具
  final AnnotationToolKind tool;

  /// 当前颜色（与 Web 端色板一致）
  final String color;

  /// 线宽（与 Web 端一致固定 3）
  final double width;

  AnnotationState copyWith({
    List<AnnotationStroke>? strokes,
    List<LaserDot>? laserDots,
    bool? whiteboard,
    AnnotationToolKind? tool,
    String? color,
    double? width,
  }) {
    return AnnotationState(
      strokes: strokes ?? this.strokes,
      laserDots: laserDots ?? this.laserDots,
      whiteboard: whiteboard ?? this.whiteboard,
      tool: tool ?? this.tool,
      color: color ?? this.color,
      width: width ?? this.width,
    );
  }
}

/// 视频标注控制器
///
/// 协议完全复用 Web 端（topic=`annotation` + 归一化坐标），实现跨端互通。
/// 标注模式本身是**本地 UI 状态**，不通过 Data Channel 广播。
class AnnotationController extends FamilyNotifier<AnnotationState, String> {
  /// 当前 LiveKit 房间（由 RoomController 在连接成功后注入）
  Room? _room;

  /// 正在绘制的草稿笔迹
  AnnotationStroke? _draft;

  /// 激光笔节流发送时间
  DateTime _lastLaserSent = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  AnnotationState build(String meetingId) => const AnnotationState();

  /// 数据通道监听句柄，解绑时取消
  CancelListenFunc? _dataListener;

  /// 绑定房间并监听远端标注消息
  void attach(Room room) {
    // 重连时会重复 attach，同一房间只注册一次监听
    if (identical(_room, room)) return;
    detach();
    _room = room;
    // 新版 SDK 使用强类型事件：room.events.on<DataReceivedEvent>
    _dataListener = room.events.on<DataReceivedEvent>(_onDataReceived);
  }

  /// 解绑房间（离开会议室时调用）
  void detach() {
    _dataListener?.call();
    _dataListener = null;
    _room = null;
    _draft = null;
    _lastLaserSent = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// 切换工具
  void setTool(AnnotationToolKind tool) {
    state = state.copyWith(tool: tool);
  }

  /// 切换颜色
  void setColor(String color) {
    state = state.copyWith(color: color);
  }

  /// 开始一条笔迹（参数为归一化坐标）
  void beginStroke(double x, double y) {
    final tool = state.tool;
    if (tool == AnnotationToolKind.laser) {
      addLaserPoint(x, y);
      return;
    }
    _draft = AnnotationStroke(
      tool: tool.name,
      color: state.color,
      width: state.width,
      points: [
        [x, y],
        [x, y],
      ],
    );
    state = state.copyWith(strokes: [...state.strokes, _draft!]);
  }

  /// 拖拽过程中更新笔迹（画笔追加点；矩形/圆形只更新终点）
  void updateStroke(double x, double y) {
    final tool = state.tool;
    if (tool == AnnotationToolKind.laser) {
      addLaserPoint(x, y);
      return;
    }
    final draft = _draft;
    if (draft == null) return;

    final strokes = List<AnnotationStroke>.from(state.strokes);
    if (strokes.isNotEmpty) {
      if (tool == AnnotationToolKind.pen) {
        strokes[strokes.length - 1] = AnnotationStroke(
          tool: draft.tool,
          color: draft.color,
          width: draft.width,
          points: [...draft.points, [x, y]],
        );
      } else {
        // 矩形 / 圆形：始终用起点 + 当前点
        final start = draft.points.first;
        strokes[strokes.length - 1] = AnnotationStroke(
          tool: draft.tool,
          color: draft.color,
          width: draft.width,
          points: [
            start,
            [x, y],
          ],
        );
      }
      _draft = strokes.last;
      state = state.copyWith(strokes: strokes);
    }
  }

  /// 结束一条笔迹并广播
  void endStroke() {
    final draft = _draft;
    _draft = null;
    if (draft == null) return;
    if (draft.points.length >= 2) {
      _publish(AnnotationMessage.stroke(draft));
    }
  }

  /// 追加激光笔点位（节流广播，本地立即显示）
  void addLaserPoint(double x, double y) {
    final now = DateTime.now();
    final dots = [...state.laserDots, LaserDot(x: x, y: y, receivedAt: now)];
    // 本地只保留最近 3 秒，避免列表无限增长
    final alive = dots
        .where((d) => now.difference(d.receivedAt).inMilliseconds < 3000)
        .toList();
    state = state.copyWith(laserDots: alive);

    // 60ms 节流，与 Web 端一致；只发送最近 6 个点
    if (now.difference(_lastLaserSent).inMilliseconds >= 60) {
      _lastLaserSent = now;
      _publish(AnnotationMessage.laser(alive.length > 6
          ? alive.sublist(alive.length - 6)
          : alive));
    }
  }

  /// 清空所有标注（本地 + 广播）
  void clearAll() {
    _draft = null;
    state = state.copyWith(strokes: const [], laserDots: const []);
    _publish(AnnotationMessage.clear());
  }

  /// 切换白板模式（本地 + 广播）
  void toggleWhiteboard() {
    final next = !state.whiteboard;
    state = state.copyWith(whiteboard: next);
    _publish(AnnotationMessage.whiteboard(next));
  }

  /// 发送 Data Channel 消息（失败静默，避免打断会议）
  Future<void> _publish(AnnotationMessage message) async {
    final room = _room;
    if (room == null) return;
    try {
      await room.localParticipant?.publishData(
        message.encode(),
        reliable: true,
        topic: AnnotationProtocol.topic,
      );
    } catch (_) {
      // 数据通道暂不可用（重连中）时忽略
    }
  }

  /// 接收远端标注消息
  void _onDataReceived(DataReceivedEvent event) {
    if (event.topic != AnnotationProtocol.topic) return;

    final message = AnnotationMessage.tryDecode(utf8.decode(event.data));
    if (message == null) return;

    switch (message.kind) {
      case 'stroke':
        final stroke = message.stroke;
        if (stroke != null) {
          state = state.copyWith(strokes: [...state.strokes, stroke]);
        }
        break;
      case 'clear':
        state = state.copyWith(strokes: const [], laserDots: const []);
        break;
      case 'whiteboard':
        state = state.copyWith(whiteboard: message.on ?? false);
        break;
      case 'laser':
        final incoming = message.pts ?? const <LaserDot>[];
        if (incoming.isEmpty) break;
        final now = DateTime.now();
        final merged = [...state.laserDots, ...incoming]
            .where((d) => now.difference(d.receivedAt).inMilliseconds < 3000)
            .toList();
        state = state.copyWith(laserDots: merged);
        break;
    }
  }
}

/// 标注控制器 Provider（每个会议一个实例）
final annotationControllerProvider = NotifierProvider.family<AnnotationController,
    AnnotationState, String>(AnnotationController.new);
