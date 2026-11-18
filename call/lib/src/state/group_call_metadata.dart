import 'dart:convert';
import 'dart:math';

import 'package:atomic_x_core/atomicxcore.dart' show CallMediaType;

/// 通知宿主 SDK 已成功提交一次多人呼叫，振铃阶段用请求标识关联气泡。
typedef GroupCallStartedHandler = Future<void> Function(
  String groupId,
  String callerId,
  CallMediaType mediaType,
  List<String> inviteeIds,
  String attemptId,
);

/// 兼容只有一名受邀者的临时多人展示标识，不作为身份、群关系或会控权限依据。
class GroupCallMetadata {
  const GroupCallMetadata._();

  /// 宿主发起临时多人时放入 CallParams.userData 的展示元数据。
  static const temporaryMultiUserData = '{"zdoaCallScene":"multi","version":1}';

  /// 生成本次呼叫的展示标识，重呼使用新值；服务器入会仍使用真实 callId。
  static String newAttemptId() {
    final random = Random.secure();
    return List.generate(16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// 呼叫时随 SDK 邀请透传，群主叫和初始受邀端用同一标识匹配气泡。
  static String withAttempt(String userData, String id) => jsonEncode({
        if (_decode(userData) case final data?) ...data,
        'oaCallAttemptId': id,
      });

  /// 仅接受当前格式的展示标识，其他端发起的通话可能没有此字段。
  static String? attemptId(String userData) {
    final id = _decode(userData)?['oaCallAttemptId'];
    return id is String && RegExp(r'^[0-9a-f]{32}$').hasMatch(id) ? id : null;
  }

  /// 仅识别当前版本的明确标识；不解析失败、未知版本和其他业务载荷。
  static bool isTemporaryMulti(String userData) {
    final value = _decode(userData);
    return value?['version'] == 1 && value?['zdoaCallScene'] == 'multi';
  }

  /// 其他调用方可以使用非 JSON 透传，展示解析忽略此类载荷。
  static Map<String, dynamic>? _decode(String userData) {
    if (userData.isEmpty) return null;
    try {
      final value = jsonDecode(userData);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }
}
