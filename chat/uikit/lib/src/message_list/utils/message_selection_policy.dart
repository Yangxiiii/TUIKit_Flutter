import 'package:atomic_x_core/atomicxcore.dart';

import 'sticky_message_event.dart';

/// 产品多选消息上限；合并与逐条共享同一选择集合，不采用SDK默认转发30条限制。
const chatMessageSelectionLimit = 100;

/// 语音等内容可选择后统一询问转发资格，撤回、删除及系统操作提醒不能进入集合。
bool canSelectChatMessage(MessageInfo message) =>
    message.msgID.isNotEmpty &&
    message.status != MessageStatus.revoked &&
    message.status != MessageStatus.deleted &&
    message.messageType != MessageType.tips &&
    StickyMessageEvent.fromMessage(message) == null;

/// 切换单条选择；超限不改变原集合，反选不受数量上限限制。
({Set<String> ids, bool limited}) toggleChatMessageSelection(
    Set<String> current, MessageInfo message) {
  final next = {...current};
  if (next.remove(message.msgID)) return (ids: next, limited: false);
  if (!canSelectChatMessage(message)) return (ids: next, limited: false);
  if (next.length >= chatMessageSelectionLimit) {
    return (ids: next, limited: true);
  }
  next.add(message.msgID);
  return (ids: next, limited: false);
}

/// 按当前窗口的显示顺序补选，保留已有选择，达到100项后只报告一次超限。
({Set<String> ids, bool limited}) selectChatMessagesBelow(
    Set<String> current, Iterable<MessageInfo> messages) {
  final next = {...current};
  var limited = false;
  for (final message in messages) {
    if (!canSelectChatMessage(message) || next.contains(message.msgID)) {
      continue;
    }
    if (next.length >= chatMessageSelectionLimit) {
      limited = true;
      continue;
    }
    next.add(message.msgID);
  }
  return (ids: next, limited: limited);
}

/// 撤回、删除或窗口替换后只保留当前可选标识；分页附加不会丢失仍在窗口中的选择。
Set<String> retainSelectableChatMessages(
    Set<String> current, Iterable<MessageInfo> messages) {
  final valid = {
    for (final message in messages)
      if (canSelectChatMessage(message)) message.msgID
  };
  return current.intersection(valid);
}
