import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/annotation.dart';
import '../annotation_controller.dart';

/// 标注画布
///
/// 必须铺在**主画面矩形**之上（不能铺全屏根节点），否则与 Web 端归一化
/// 坐标基准不一致，笔迹会跨端错位。
class AnnotationCanvas extends ConsumerStatefulWidget {
  const AnnotationCanvas({super.key, required this.meetingId});

  final String meetingId;

  @override
  ConsumerState<AnnotationCanvas> createState() => _AnnotationCanvasState();
}

class _AnnotationCanvasState extends ConsumerState<AnnotationCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;

  @override
  void initState() {
    super.initState();
    // 激光笔轨迹需要持续重绘（1.5 秒淡出）
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// 把本地像素坐标转成 [0..1] 归一化坐标
  Offset _normalize(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) return Offset.zero;
    return Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final annotation = ref.watch(annotationControllerProvider(widget.meetingId));
    final controller =
        ref.read(annotationControllerProvider(widget.meetingId).notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            final p = _normalize(details.localPosition, size);
            controller.beginStroke(p.dx, p.dy);
          },
          onPanUpdate: (details) {
            final p = _normalize(details.localPosition, size);
            controller.updateStroke(p.dx, p.dy);
          },
          onPanEnd: (_) => controller.endStroke(),
          onPanCancel: () => controller.endStroke(),
          child: AnimatedBuilder(
            animation: _ticker,
            builder: (context, _) {
              return CustomPaint(
                size: size,
                painter: _AnnotationPainter(state: annotation),
              );
            },
          ),
        );
      },
    );
  }
}

/// 标注绘制器：按归一化坐标还原笔迹
class _AnnotationPainter extends CustomPainter {
  _AnnotationPainter({required this.state});

  final AnnotationState state;

  /// 激光笔存活时长
  static const int _laserTtlMs = 1500;

  @override
  void paint(Canvas canvas, Size size) {
    // 白板模式：先铺白底
    if (state.whiteboard) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.white,
      );
    }

    for (final stroke in state.strokes) {
      _paintStroke(canvas, size, stroke);
    }
    _paintLaser(canvas, size);
  }

  /// 绘制单条笔迹
  void _paintStroke(Canvas canvas, Size size, AnnotationStroke stroke) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = _parseColor(stroke.color)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    Offset pointAt(int index) {
      final p = stroke.points[index];
      return Offset(p[0] * size.width, p[1] * size.height);
    }

    switch (stroke.tool) {
      case 'rect':
        if (stroke.points.length < 2) return;
        canvas.drawRect(
          Rect.fromPoints(pointAt(0), pointAt(stroke.points.length - 1)),
          paint,
        );
        break;
      case 'circle':
        if (stroke.points.length < 2) return;
        canvas.drawOval(
          Rect.fromPoints(pointAt(0), pointAt(stroke.points.length - 1)),
          paint,
        );
        break;
      default:
        // 画笔
        if (stroke.points.length == 1) {
          canvas.drawCircle(pointAt(0), stroke.width / 2,
              paint..style = PaintingStyle.fill);
          return;
        }
        final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
        for (var i = 1; i < stroke.points.length; i++) {
          final p = pointAt(i);
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
        break;
    }
  }

  /// 绘制激光笔（按接收时间做 1.5 秒淡出）
  void _paintLaser(Canvas canvas, Size size) {
    final now = DateTime.now();
    for (final dot in state.laserDots) {
      final age = now.difference(dot.receivedAt).inMilliseconds;
      if (age > _laserTtlMs) continue;
      final opacity = (1 - age / _laserTtlMs).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(dot.x * size.width, dot.y * size.height),
        8,
        Paint()..color = const Color(0xFFEF4444).withOpacity(opacity),
      );
    }
  }

  /// 解析 #RRGGBB 颜色
  Color _parseColor(String hex) {
    var value = hex.replaceAll('#', '');
    if (value.length == 6) value = 'FF$value';
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? const Color(0xFFEF4444) : Color(parsed);
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) {
    // 激光笔与草稿笔迹每帧都可能变化，统一重绘
    return true;
  }
}
