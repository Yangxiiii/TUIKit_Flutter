import 'package:atomic_x_core/atomicxcore.dart';
import 'package:tencent_chat_uikit/src/message_input/mention/mention_info.dart';

/// 根据消息的 @ 列表判定当前用户收到的提醒类型。
GroupAtType? resolveGroupAtType(
  List<String> atUserList,
  String? currentUserID,
) {
  if (currentUserID == null || currentUserID.isEmpty) return null;

  final atMe = atUserList.contains(currentUserID);
  final atAll = atUserList.contains(MentionInfo.atAllUserID);
  if (atMe && atAll) return GroupAtType.atAllAtMe;
  if (atMe) return GroupAtType.atMe;
  if (atAll) return GroupAtType.atAll;
  return null;
}

/// 判定待查看的新消息是否位于已跳转消息之后。
bool isMessageAfterSequence(MessageInfo message, int sequence) {
  final messageSequence = message.sequence;
  return messageSequence == null || messageSequence > sequence;
}
