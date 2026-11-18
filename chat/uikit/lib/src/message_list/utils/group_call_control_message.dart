import 'dart:convert';

import 'package:atomic_x_core/atomicxcore.dart';

/// 识别仅供通话控制通道消费的在线消息，不负责指令校验或设备状态。
abstract final class GroupCallControlMessage {
  /// 与可见通话记录及旧邀请协议区分，所有控制、回执、策略共用此标识。
  static const protocol = 'zd.group-call.control.v1';

  /// 只读取外层协议；损坏的控制内容仍应隔离，具体字段由通话层拒绝。
  static bool isPayload(String? data) {
    if (data == null || data.isEmpty) return false;
    try {
      final value = jsonDecode(data);
      return value is Map && value['protocol'] == protocol;
    } on FormatException {
      return false;
    }
  }

  /// 聊天气泡、摘要和宿主缓存统一使用同一识别规则。
  static bool isMessage(MessageInfo message) {
    final payload = message.messagePayload;
    return payload is CustomMessagePayload && isPayload(payload.customData);
  }
}
