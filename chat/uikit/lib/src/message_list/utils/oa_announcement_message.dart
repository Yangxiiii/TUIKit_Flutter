import 'dart:convert';

import 'package:app_core/app_core.dart' show formatPersonName;
import 'package:atomic_x_core/atomicxcore.dart';

/// 识别单聊中的公告通知协议，卡片、会话摘要与搜索复用同一解析结果。
final class OaAnnouncementMessage {
  const OaAnnouncementMessage._(
    this.id,
    this.title,
    this.summary,
    this.realName,
    this.nickname,
  );

  /// 公告业务主键按原字符串传给详情入口，不与 IM 消息 ID 混用。
  final String id;

  /// 公告标题独立于正文摘要，列表和搜索结果使用同一标题。
  final String title;

  /// 消息携带的摘要文本，不把它当成尚未取得的完整详情。
  final String summary;

  /// 发布人姓名快照；缺失时为空，不查询员工资料补全。
  final String realName;

  /// 发布人昵称快照；缺失时为空，不影响公告主键及正文展示。
  final String nickname;

  /// 通知列表只显示标题，不添加群公告前缀或使用摘要替换标题。
  String get preview => title;

  /// 姓名与昵称分别来自消息快照，缺少一项时不产生空括号。
  String get publisherName => formatPersonName(realName, nickname);

  /// 仅在正常单聊消息中识别公告，不依赖固定的后台账号。
  static OaAnnouncementMessage? fromMessage(MessageInfo? message) {
    final payload = message?.messagePayload;
    if (message?.conversationType != ConversationType.c2c ||
        message?.messageType != MessageType.custom ||
        message?.status == MessageStatus.revoked ||
        message?.status == MessageStatus.deleted ||
        message?.status == MessageStatus.violation ||
        payload is! CustomMessagePayload) {
      return null;
    }
    return tryParse(payload.customData);
  }

  /// 仅接受包含对端的单聊会话标识，再沿用消息类型和状态校验。
  static OaAnnouncementMessage? fromConversation(
    MessageInfo? message,
    String conversationId,
  ) =>
      conversationId.startsWith('c2c_') && conversationId.length > 4
          ? fromMessage(message)
          : null;

  /// 多业务自定义消息需先判别版本再校验动态载荷，未知格式交还通用兜底。
  static OaAnnouncementMessage? tryParse(String? raw) {
    if (raw == null || !raw.trimLeft().startsWith('{')) return null;
    try {
      final root = jsonDecode(raw);
      if (root is! Map<String, dynamic> ||
          root['businessID'] != 'oa_announcement' ||
          root['version'] is! int ||
          root['version'] != 1) {
        return null;
      }
      // ID 不经过数字转换；姓名快照允许缺失，非字符串字段不能强制显示为文本。
      final payload = root['payload'];
      if (payload is! Map<String, dynamic>) return null;
      final id = payload['id'];
      final title = payload['title'];
      final summary = payload['summary'];
      final realName = payload['realName'] ?? '';
      final nickname = payload['nickname'] ?? '';
      if (id is! String ||
          id.trim().isEmpty ||
          title is! String ||
          title.trim().isEmpty ||
          summary is! String ||
          realName is! String ||
          nickname is! String) {
        return null;
      }
      return OaAnnouncementMessage._(id, title, summary, realName, nickname);
    } on FormatException {
      return null;
    }
  }
}
