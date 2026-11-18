import 'dart:convert';

import 'package:atomic_x_core/atomicxcore.dart';

/// 识别仅供通话控制通道消费的在线消息，不负责指令校验或设备状态。
abstract final class GroupCallControlMessage {
  /// 指令、回执和策略共用该标识，版本无效的会控载荷也不进入普通聊天。
  static const businessID = 'oa_group_call_control';

  /// 按协议标识隔离会控，具体字段由通话层校验。
  /// 聊天入口也识别一层自定义元素包装，会控收发只接受直接协议。
  static bool isPayload(String? data, {bool allowWrappedData = false}) {
    if (data == null || data.isEmpty) return false;
    try {
      final value = jsonDecode(data);
      if (value is! Map) return false;
      if (value['businessID'] == businessID) return true;
      // 二次识别使用默认参数，限制为一层 IM 自定义元素包装。
      final wrapped = value['data'];
      return allowWrappedData && wrapped is String && isPayload(wrapped);
    } on FormatException {
      return false;
    }
  }

  /// 聊天气泡、摘要和宿主缓存统一使用同一识别规则。
  static bool isMessage(MessageInfo message) {
    final payload = message.messagePayload;
    return payload is CustomMessagePayload &&
        isPayload(payload.customData, allowWrappedData: true);
  }
}
