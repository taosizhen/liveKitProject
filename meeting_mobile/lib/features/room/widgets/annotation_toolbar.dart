import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation_controller.dart';

/// 标注工具面板（FAB + 底部弹出面板）
///
/// Web 端色板为 6 色，移动端保持一致以保证跨端观感统一。
class AnnotationToolbar extends ConsumerStatefulWidget {
  const AnnotationToolbar({
    super.key,
    required this.meetingId,
    required this.onExit,
  });

  final String meetingId;

  /// 退出标注模式（由 RoomScreen 恢复原布局）
  final VoidCallback onExit;

  @override
  ConsumerState<AnnotationToolbar> createState() => _AnnotationToolbarState();
}

class _AnnotationToolbarState extends ConsumerState<AnnotationToolbar> {
  /// 与 Web 端一致的 6 色调色板
  static const List<String> _palette = [
    '#ef4444',
    '#f59e0b',
    '#22c55e',
    '#3b82f6',
    '#a855f7',
    '#ffffff',
  ];

  bool _panelOpen = true;

  /// 解析色板颜色
  Color _toColor(String hex) {
    var value = hex.replaceAll('#', '');
    if (value.length == 6) value = 'FF$value';
    return Color(int.tryParse(value, radix: 16) ?? 0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(annotationControllerProvider(widget.meetingId));
    final controller =
        ref.read(annotationControllerProvider(widget.meetingId).notifier);

    return Stack(
      children: [
        // 悬浮按钮：收起 / 展开面板
        Positioned(
          right: 14,
          bottom: _panelOpen ? 168 : 14,
          child: FloatingActionButton.small(
            heroTag: 'annotation-fab',
            backgroundColor: const Color(0xFF6366F1),
            onPressed: () => setState(() => _panelOpen = !_panelOpen),
            child: Icon(
              _panelOpen ? Icons.close_rounded : Icons.edit_rounded,
              color: Colors.white,
            ),
          ),
        ),
        if (_panelOpen)
          Positioned(
            left: 8,
            right: 8,
            bottom: 12,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xF20F172A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _toolButton(
                          icon: Icons.edit_rounded,
                          active: state.tool == AnnotationToolKind.pen,
                          onTap: () =>
                              controller.setTool(AnnotationToolKind.pen),
                        ),
                        _toolButton(
                          icon: Icons.crop_square_rounded,
                          active: state.tool == AnnotationToolKind.rect,
                          onTap: () =>
                              controller.setTool(AnnotationToolKind.rect),
                        ),
                        _toolButton(
                          icon: Icons.circle_outlined,
                          active: state.tool == AnnotationToolKind.circle,
                          onTap: () =>
                              controller.setTool(AnnotationToolKind.circle),
                        ),
                        _toolButton(
                          icon: Icons.ads_click_rounded,
                          active: state.tool == AnnotationToolKind.laser,
                          onTap: () =>
                              controller.setTool(AnnotationToolKind.laser),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 1,
                          height: 24,
                          color: Colors.white24,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: _palette.map((hex) {
                              final selected = state.color == hex;
                              return GestureDetector(
                                onTap: () => controller.setColor(hex),
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: _toColor(hex),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selected
                                          ? Colors.white
                                          : Colors.white24,
                                      width: selected ? 2.5 : 1,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _actionButton(
                          icon: Icons.insert_drive_file_outlined,
                          label: '白板',
                          active: state.whiteboard,
                          onTap: controller.toggleWhiteboard,
                        ),
                        const SizedBox(width: 8),
                        _actionButton(
                          icon: Icons.delete_outline_rounded,
                          label: '清空',
                          onTap: controller.clearAll,
                        ),
                        const Spacer(),
                        _actionButton(
                          icon: Icons.close_rounded,
                          label: '退出标注',
                          danger: true,
                          onTap: widget.onExit,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 工具按钮
  Widget _toolButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF6366F1) : Colors.white10,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }

  /// 文字操作按钮
  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    bool danger = false,
  }) {
    final color = danger
        ? const Color(0xFFFCA5A5)
        : (active ? const Color(0xFFA5B4FC) : Colors.white70);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: danger ? const Color(0x33EF4444) : Colors.white10,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}
