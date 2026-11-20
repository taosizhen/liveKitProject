import 'dart:convert';

/// 举手/点名跨端信令协议（与 Web 端 `useSignalChannel.ts` 严格一致）
///
/// Data Channel topic 固定为 `signal`，消息体（JSON 信封，src 固定 'signal'）：
/// - `{ src:'signal', k:'hand_raise', identity, name, ts }`
/// - `{ src:'signal', k:'hand_lower', identity, by?, ts }`
/// - `{ src:'signal', k:'hand_sync_req', identity, ts }`   新加入者请求同步
/// - `{ src:'signal', k:'designate', target, by, ts }`     主持人点名发言
/// - `{ src:'signal', k:'designate_ack', identity, ok, ts }` 被点名端回执
class SignalProtocol {
  /// Data Channel topic，禁止修改
  static const String topic = 'signal';

  /// 消息来源标记
  static const String src = 'signal';
}

/// 一条举手记录
class RaisedHand {
  const RaisedHand({
    required this.identity,
    required this.name,
    required this.ts,
  });

  final String identity;
  final String name;

  /// 举手时间戳（毫秒），列表按此升序排列
  final int ts;
}

/// 举手/点名信令消息（发往 / 收到）
class SignalMessage {
  const SignalMessage({
    required this.kind,
    this.identity,
    this.name,
    this.ts,
    this.target,
    this.by,
    this.ok,
  });

  /// hand_raise / hand_lower / hand_sync_req / designate / designate_ack
  final String kind;
  final String? identity;
  final String? name;
  final int? ts;
  final String? target;
  final String? by;
  final bool? ok;

  /// 编码为 UTF-8 JSON 字节，通过 `publishData(topic: 'signal')` 发送
  List<int> encode() {
    final map = <String, dynamic>{
      'src': SignalProtocol.src,
      'k': kind,
      if (identity != null) 'identity': identity,
      if (name != null) 'name': name,
      'ts': ts ?? DateTime.now().millisecondsSinceEpoch,
      if (target != null) 'target': target,
      if (by != null) 'by': by,
      if (ok != null) 'ok': ok,
    };
    return utf8.encode(jsonEncode(map));
  }

  /// 解析远端 Data Channel 数据；非 signal 消息返回 null
  static SignalMessage? tryDecode(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return null;
      if (json['src'] != SignalProtocol.src) return null;
      final kind = json['k'] as String?;
      if (kind == null) return null;
      return SignalMessage(
        kind: kind,
        identity: json['identity'] as String?,
        name: json['name'] as String?,
        ts: (json['ts'] as num?)?.toInt(),
        target: json['target'] as String?,
        by: json['by'] as String?,
        ok: json['ok'] as bool?,
      );
    } catch (_) {
      // 非信令消息或格式异常，忽略
      return null;
    }
  }
}
