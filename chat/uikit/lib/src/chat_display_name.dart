import 'package:app_core/app_core.dart' show formatPersonName;
import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/widgets.dart';

import 'message_list/utils/oa_announcement_message.dart';

/// 通过宿主个人资料展示消息作者，群昵称只在所属群的消息中生效。
String chatSenderDisplayName(
  BuildContext context,
  MessageInfo message, {
  String? groupId,
  bool lookup = true,
  bool showUserId = true,
}) {
  final sender = message.from;
  final isGroup =
      groupId != null || message.conversationType == ConversationType.group;
  final groupNickname = isGroup ? sender.nameCard : null;
  if (!lookup) {
    return formatPersonName(
      null,
      sender.nickname,
      groupNickname: groupNickname,
      fallback: showUserId ? sender.userID : null,
    );
  }
  final name = AppUserAvatarScope.personName(
    context,
    sender.userID,
    nickname: sender.nickname,
    groupId: groupId ?? (isGroup ? message.to : null),
    groupNickname: groupNickname,
  );
  return !showUserId && name == sender.userID ? '' : name;
}

/// 单聊会话标题解析为对方姓名，群聊与通知继续使用原始会话标题。
String chatConversationDisplayName(
  BuildContext context,
  ConversationInfo conversation, {
  String? realName,
  String? nickname,
  String? fallback,
}) {
  final id = conversation.conversationID;
  if (!id.startsWith('c2c_') ||
      OaAnnouncementMessage.fromMessage(conversation.lastMessage) != null)
    return conversation.title ?? fallback ?? '';
  return AppUserAvatarScope.personName(
    context,
    id.substring(4),
    realName: realName,
    nickname: nickname,
    fallback: conversation.title ?? fallback ?? id.substring(4),
  );
}
