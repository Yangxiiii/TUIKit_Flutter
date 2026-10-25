import 'dart:convert';

import 'package:atomic_x_core/atomicxcore.dart';

import 'big_file_message.dart';
import 'rich_content_message.dart';

/// 识别置顶操作记录；动态多业务协议在入口校验，未知版本交还普通自定义消息。
final class StickyMessageEvent {
  const StickyMessageEvent(
      {required this.action,
      required this.messageId,
      required this.operatorName});

  /// 与富文本、大文件隔离的业务标识。
  static const businessID = 'oa_sticky_message';

  /// 当前协议仅接受整数版本1。
  static const version = 1;

  /// add/remove为历史提示；invalidate仅用于原消息失效后的静默状态同步。
  final String action;

  /// 操作目标的原始IM消息ID，不是置顶记录ID。
  final String messageId;

  /// 发送时的操作人展示名快照，不作为权限依据。
  final String operatorName;

  /// 控制事件不进入历史展示和会话摘要。
  bool get isControl => action == 'invalidate';

  /// 聊天提示和会话摘要使用相同文案。
  String get actionText => action == 'add' ? '置顶了内容' : '移除了置顶内容';

  /// 会话列表使用与聊天系统提示一致的完整文本。
  String get preview => isControl ? '' : '$operatorName $actionText';

  /// 生成与现有图文、大文件一致的信封，内容不包含本机路径或鉴权字段。
  String toCustomData() => jsonEncode({
        'businessID': businessID,
        'version': version,
        'payload': {
          'action': action,
          'messageId': messageId,
          'operatorName': operatorName
        }
      });

  /// 会话成员可发送任意JSON，必须逐层验证后才授予系统提示样式。
  static StickyMessageEvent? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> ||
          data['businessID'] != businessID ||
          data['version'] is! int ||
          data['version'] != version) {
        return null;
      }
      final payload = data['payload'];
      if (payload is! Map<String, dynamic>) return null;
      final action = payload['action'],
          id = payload['messageId'],
          name = payload['operatorName'];
      if ((action != 'add' && action != 'remove' && action != 'invalidate') ||
          id is! String ||
          id.trim().isEmpty ||
          name is! String ||
          name.trim().isEmpty) {
        return null;
      }
      return StickyMessageEvent(
          action: action as String, messageId: id, operatorName: name);
    } on FormatException {
      return null;
    }
  }

  /// 同一判别用于系统布局、摘要、时间分组和删除保护。
  static StickyMessageEvent? fromMessage(MessageInfo message) =>
      message.conversationType == ConversationType.group
          ? null
          : message.messagePayload is CustomMessagePayload
              ? tryParse(
                  (message.messagePayload as CustomMessagePayload).customData)
              : null;

  /// 仅成功消息可置顶；自定义类型必须是已知内容协议，操作提示和语音不得再次置顶。
  static bool canPin(MessageInfo message) {
    if (message.msgID.isEmpty ||
        message.status != MessageStatus.sendSuccess ||
        message.conversationType == ConversationType.group) {
      return false;
    }
    return switch (message.messageType) {
      MessageType.text ||
      MessageType.image ||
      MessageType.video ||
      MessageType.file ||
      MessageType.face =>
        true,
      MessageType.custom => message.messagePayload is CustomMessagePayload &&
          (BigFileMessage.tryParse(
                      (message.messagePayload as CustomMessagePayload)
                          .customData) !=
                  null ||
              RichContentMessage.tryParse(
                      (message.messagePayload as CustomMessagePayload)
                          .customData) !=
                  null),
      _ => false,
    };
  }
}
