import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';

import 'room_controller.dart';
import 'widgets/annotation_canvas.dart';
import 'widgets/annotation_toolbar.dart';
import 'widgets/chat_panel.dart';
import 'widgets/members_panel.dart';
import 'widgets/room_bottom_bar.dart';
import 'widgets/thumbnail_strip.dart';

/// 会议室页面
///
/// 布局规则（与 Web 端一致）：
/// - 普通模式：主画面 + 缩略图条 + 底部工具栏
/// - 标注模式：**只保留主画面并铺满舞台区**，隐藏缩略图/侧栏/本地小窗，
///   退出标注时恢复进入前的布局
class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key, required this.meetingId, this.title});

  final String meetingId;
  final String? title;

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen>
    with WidgetsBindingObserver {
  /// 是否处于标注模式（本地 UI 状态，不广播）
  bool _annotating = false;
  bool _showChat = false;
  bool _showMembers = false;

  // 进入标注前的面板状态，退出时还原
  bool _chatBeforeAnnotation = false;
  bool _membersBeforeAnnotation = false;

  /// 提前捕获控制器，避免 dispose 阶段再访问已失效的 ref
  late final RoomController _roomController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _roomController = ref.read(roomControllerProvider(widget.meetingId).notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _roomController.connect();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 兜底释资源：正常路径已在 _hangup 中退会，这里覆盖路由被外部替换的情况
    _roomController.leaveRoom();
    super.dispose();
  }

  /// 前后台切换处理
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller =
        ref.read(roomControllerProvider(widget.meetingId).notifier);
    if (state == AppLifecycleState.paused) {
      controller.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      controller.onAppResumed();
    }
  }

  /// 进入标注模式：主画面全屏，隐藏其他画面与侧栏
  void _enterAnnotation() {
    _chatBeforeAnnotation = _showChat;
    _membersBeforeAnnotation = _showMembers;
    setState(() {
      _showChat = false;
      _showMembers = false;
      _annotating = true;
    });
  }

  /// 退出标注模式：恢复进入前的布局
  void _exitAnnotation() {
    setState(() {
      _annotating = false;
      _showChat = _chatBeforeAnnotation;
      _showMembers = _membersBeforeAnnotation;
    });
  }

  /// 点击标注按钮
  void _toggleAnnotation() {
    if (_annotating) {
      _exitAnnotation();
    } else {
      _enterAnnotation();
    }
  }

  /// 挂断：先退出标注还原布局，再断开连接并返回
  Future<void> _hangup() async {
    if (_annotating) _exitAnnotation();
    await ref.read(roomControllerProvider(widget.meetingId).notifier).leaveRoom();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/meetings');
    }
  }

  /// 返回键同样走挂断流程
  Future<bool> _onWillPop() async {
    await _hangup();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(roomControllerProvider(widget.meetingId));

    // 一次性错误提示
    ref.listen<RoomState>(roomControllerProvider(widget.meetingId),
        (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error!)));
        ref
            .read(roomControllerProvider(widget.meetingId).notifier)
            .clearError();
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onWillPop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildTopBar(state),
                  Expanded(child: _buildStage(state)),
                  // 标注模式下隐藏缩略图（其他人画面）
                  if (!_annotating && state.thumbnails.isNotEmpty)
                    ThumbnailStrip(videos: state.thumbnails),
                  RoomBottomBar(
                    state: state,
                    annotationMode: _annotating,
                    onToggleMic: () => ref
                        .read(roomControllerProvider(widget.meetingId).notifier)
                        .toggleMicrophone(),
                    onToggleCamera: () => ref
                        .read(roomControllerProvider(widget.meetingId).notifier)
                        .toggleCamera(),
                    onToggleScreenShare: () => ref
                        .read(roomControllerProvider(widget.meetingId).notifier)
                        .toggleScreenShare(),
                    onToggleChat: () => setState(() => _showChat = !_showChat),
                    onToggleMembers: () =>
                        setState(() => _showMembers = !_showMembers),
                    onToggleAnnotation: _toggleAnnotation,
                    onHangup: _hangup,
                  ),
                ],
              ),
              // 成员侧栏
              if (_showMembers && !_annotating)
                Positioned.fill(
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _showMembers = false),
                          child: Container(color: Colors.black45),
                        ),
                      ),
                      MembersPanel(
                        members: state.members,
                        onClose: () => setState(() => _showMembers = false),
                      ),
                    ],
                  ),
                ),
              // 聊天面板
              if (_showChat && !_annotating)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: MediaQuery.of(context).size.height * 0.55,
                  child: ChatPanel(
                    meetingId: widget.meetingId,
                    onClose: () => setState(() => _showChat = false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部信息栏
  Widget _buildTopBar(RoomState state) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0xFF0F172A),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white70),
            tooltip: '离开会议',
            onPressed: _hangup,
          ),
          Expanded(
            child: Text(
              widget.title ?? '会议室',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white),
            ),
          ),
          if (_annotating)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF4338CA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.edit_rounded, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text('标注模式 · 单画面',
                      style: TextStyle(fontSize: 10, color: Colors.white)),
                ],
              ),
            ),
          const SizedBox(width: 8),
          const Icon(Icons.people_alt_outlined,
              size: 15, color: Color(0xFF94A3B8)),
          const SizedBox(width: 4),
          Text(
            '${state.participantCount}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  /// 舞台区（主画面 + 标注层）
  Widget _buildStage(RoomState state) {
    if (state.phase != RoomPhase.connected && state.mainTrack == null) {
      return _buildConnectingView(state);
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: state.mainTrack != null
                ? VideoTrackRenderer(
                    state.mainTrack!,
                    fit: VideoViewFit.contain,
                    mirrorMode: state.mainIsLocal && !state.mainIsScreenShare
                        ? VideoViewMirrorMode.mirror
                        : VideoViewMirrorMode.off,
                  )
                : _buildEmptyStage(state),
          ),
          // 标注画布严格铺在主画面矩形之上
          if (_annotating)
            Positioned.fill(
              child: AnnotationCanvas(meetingId: widget.meetingId),
            ),
          if (_annotating)
            AnnotationToolbar(
              meetingId: widget.meetingId,
              onExit: _exitAnnotation,
            ),
          // 主画面名字（非标注模式下显示）
          if (!_annotating)
            Positioned(
              left: 10,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  state.mainTitle,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 入会中 / 失败态
  Widget _buildConnectingView(RoomState state) {
    final failed = state.phase == RoomPhase.failed;
    final fetching = state.phase == RoomPhase.fetchingToken;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (failed)
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: Color(0xFF64748B))
          else
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            failed ? (state.error ?? '入会失败') : '正在进入会议…',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 10),
          if (!failed)
            Text(
              fetching
                  ? '① 获取入会凭证 ⟳　② 连接信令 ○'
                  : '① 获取入会凭证 ✓　② 连接信令 ⟳',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          if (failed) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () => ref
                      .read(roomControllerProvider(widget.meetingId).notifier)
                      .connect(),
                  child: const Text('重试'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _hangup,
                  child: const Text('返回列表'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 已连接但暂无画面
  Widget _buildEmptyStage(RoomState state) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off_rounded,
              size: 40, color: Color(0xFF475569)),
          const SizedBox(height: 10),
          Text(
            state.members.isEmpty ? '等待其他参会者加入…' : '等待画面…',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}
