import 'dart:convert';

/// 视频标注跨端协议（与 Web 端 `AnnotationLayer.tsx` 严格一致）
///
/// Data Channel topic 固定为 `annotation`，消息体：
/// - `{ src:'annotation', k:'stroke', s:{tool,color,width,points,text?} }`
/// - `{ src:'annotation', k:'clear' }`
/// - `{ src:'annotation', k:'whiteboard', on:boolean }`
/// - `{ src:'annotation', k:'laser', pts:[{p:[x,y], at:number}] }`
///
/// 所有坐标均为归一化坐标 `[0..1]`，这是 Web ↔ Flutter 互通的唯一方式。
class AnnotationProtocol {
  /// Data Channel topic，禁止修改
  static const String topic = 'annotation';

  /// 消息来源标记
  static const String src = 'annotation';
}

/// 一条静态笔迹（持久保留到 clear）
class AnnotationStroke {
  const AnnotationStroke({
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
    this.text,
  });

  /// pen / rect / circle（移动端不提供 arrow、text）
  final String tool;
  final String color;
  final double width;

  /// 归一化坐标点列表：[[x, y], ...]
  final List<List<double>> points;
  final String? text;

  /// 序列化为 Web 端可识别的 JSON
  Map<String, dynamic> toJson() => {
        'tool': tool,
        'color': color,
        'width': width,
        'points': points,
        if (text != null) 'text': text,
      };

  /// 从远端消息解析
  factory AnnotationStroke.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'];
    return AnnotationStroke(
      tool: (json['tool'] as String?) ?? 'pen',
      color: (json['color'] as String?) ?? '#ef4444',
      width: (json['width'] as num?)?.toDouble() ?? 3,
      points: rawPoints is List
          ? rawPoints
              .whereType<List>()
              .map((p) => [
                    (p.isNotEmpty ? (p[0] as num).toDouble() : 0.0),
                    (p.length > 1 ? (p[1] as num).toDouble() : 0.0),
                  ])
              .toList()
          : const [],
      text: json['text'] as String?,
    );
  }
}

/// 激光笔轨迹点（本地 1.5 秒后自动淡出）
class LaserDot {
  const LaserDot({
    required this.x,
    required this.y,
    required this.receivedAt,
  });

  final double x;
  final double y;

  /// 本地接收时刻（不使用对端时间戳，避免跨端时钟差异）
  final DateTime receivedAt;
}

/// 标注消息（发往 / 收到）
class AnnotationMessage {
  const AnnotationMessage({
    required this.kind,
    this.stroke,
    this.on,
    this.pts,
  });

  /// stroke / clear / whiteboard / laser
  final String kind;
  final AnnotationStroke? stroke;
  final bool? on;
  final List<LaserDot>? pts;

  /// 构造笔迹消息
  factory AnnotationMessage.stroke(AnnotationStroke stroke) =>
      AnnotationMessage(kind: 'stroke', stroke: stroke);

  /// 构造清空消息
  factory AnnotationMessage.clear() =>
      const AnnotationMessage(kind: 'clear');

  /// 构造白板开关消息
  factory AnnotationMessage.whiteboard(bool on) =>
      AnnotationMessage(kind: 'whiteboard', on: on);

  /// 构造激光笔消息
  factory AnnotationMessage.laser(List<LaserDot> pts) =>
      AnnotationMessage(kind: 'laser', pts: pts);

  /// 编码为 UTF-8 JSON 字节，通过 `publishData(topic: 'annotation')` 发送
  List<int> encode() {
    final map = <String, dynamic>{
      'src': AnnotationProtocol.src,
      'k': kind,
    };
    if (stroke != null) map['s'] = stroke!.toJson();
    if (on != null) map['on'] = on;
    if (pts != null) {
      map['pts'] = pts!
          .map((d) => {
                'p': [d.x, d.y],
                // Web 端只做相对淡出，此值仅在本地有意义
                'at': d.receivedAt.millisecondsSinceEpoch,
              })
          .toList();
    }
    return utf8.encode(jsonEncode(map));
  }

  /// 解析远端 Data Channel 数据；非标注消息返回 null
  static AnnotationMessage? tryDecode(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return null;
      if (json['src'] != AnnotationProtocol.src) return null;
      final kind = json['k'] as String?;
      if (kind == null) return null;
      switch (kind) {
        case 'stroke':
          final raw = json['s'];
          if (raw is! Map<String, dynamic>) return null;
          return AnnotationMessage.stroke(AnnotationStroke.fromJson(raw));
        case 'clear':
          return AnnotationMessage.clear();
        case 'whiteboard':
          return AnnotationMessage.whiteboard((json['on'] as bool?) ?? false);
        case 'laser':
          final rawPts = json['pts'];
          if (rawPts is! List) return AnnotationMessage.laser(const []);
          final now = DateTime.now();
          final dots = <LaserDot>[];
          for (final item in rawPts) {
            if (item is! Map<String, dynamic>) continue;
            final p = item['p'];
            if (p is! List || p.length < 2) continue;
            dots.add(LaserDot(
              x: (p[0] as num).toDouble(),
              y: (p[1] as num).toDouble(),
              receivedAt: now,
            ));
          }
          return AnnotationMessage.laser(dots);
        default:
          return null;
      }
    } catch (_) {
      // 非标注消息或格式异常，忽略
      return null;
    }
  }
}
