import 'dart:convert';

import 'package:atomic_x_core/atomicxcore.dart';

import 'rich_content_message.dart';

/// 从当前群会话的自定义消息读取公告卡片，供消息行和会话摘要共用。
final class GroupAnnouncementMessage {
  const GroupAnnouncementMessage._(
      this.announcementId, this.groupId, this.summary);

  /// 公告 ID 按协议保留为字符串，避免大整数在跨端转换时丢失精度。
  final String announcementId;

  /// 原始群 ID，用于校验卡片与会话的归属。
  final String groupId;

  /// 卡片、置顶和会话列表共用的纯文本摘要，可由公告内容块提取。
  final String summary;

  /// 撤回、删除、违规、跨群或不符合 v1 格式的消息回退到既有消息处理。
  static GroupAnnouncementMessage? fromConversation(
    MessageInfo? message,
    String conversationId,
  ) {
    final payload = message?.messagePayload;
    final sourceGroup = message?.conversationType == ConversationType.group
        ? message?.to
        : null;
    if (!conversationId.startsWith('group_') ||
        message?.conversationType == ConversationType.c2c ||
        (sourceGroup?.isNotEmpty == true &&
            'group_$sourceGroup' != conversationId) ||
        message?.messageType != MessageType.custom ||
        message?.status == MessageStatus.revoked ||
        message?.status == MessageStatus.deleted ||
        message?.status == MessageStatus.violation ||
        payload is! CustomMessagePayload ||
        !payload.customData.trimLeft().startsWith('{')) {
      return null;
    }

    // 先按业务类型与版本识别动态载荷，再核对当前群，失败时不能产生详情入口。
    try {
      final root = jsonDecode(payload.customData);
      if (root is! Map<String, dynamic> ||
          root['businessID'] != 'oa_group_announcement' ||
          root['version'] is! int ||
          root['version'] != 1) {
        return null;
      }
      final data = root['payload'];
      if (data is! Map<String, dynamic>) return null;
      final id = data['announcementId'];
      final group = data['groupId'];
      final summary = data['summary'];
      final content = data['content'];
      if (id is! String ||
          id.trim().isEmpty ||
          group is! String ||
          group.trim().isEmpty ||
          'group_$group' != conversationId ||
          (summary is! String && content is! String)) {
        return null;
      }
      // 新卡片可携带完整内容，旧卡片只带摘要。正文不可用时仍保留详情入口。
      final preview =
          _readSummary(content) ?? _readSummary(summary) ?? '公告内容暂无法显示';
      return GroupAnnouncementMessage._(id, group, preview);
    } on FormatException {
      return null;
    }
  }

  /// 复用聊天的内容块与摘要规则，为紧凑卡片保留正文和媒体类型。
  static String? _readSummary(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    // 识别内容块数组，同时保留旧摘要中单独出现的「[图片]」等文本。
    final isStructured =
        text.startsWith('{') || RegExp(r'^\[\s*(?:\{|\[|\]|")').hasMatch(text);
    if (!isStructured) return text.isEmpty ? null : value;

    // 降级时不把 JSON 显示给用户，优先回到消息自带的摘要。
    final parsed = RichContentMessage.tryParse(text, allowBareBlocks: true);
    final preview =
        parsed?.plainTextForForward.replaceAll(RegExp(r'\s+'), ' ').trim();
    return preview == null || preview.isEmpty ? null : preview;
  }

  /// 为会话列表生成带公告标记的纯文本。
  String get preview => '[群公告]$summary';
}
