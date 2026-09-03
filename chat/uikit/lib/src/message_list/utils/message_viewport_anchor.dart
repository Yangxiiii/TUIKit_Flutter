import 'package:atomic_x_core/atomicxcore.dart';
import 'package:tencent_chat_uikit/src/third_party/scrollable_positioned_list/scrollable_positioned_list.dart';

/// 用稳定消息标识保存会话离开前的视口位置。
class MessageViewportAnchor {
  const MessageViewportAnchor({
    required this.message,
    required this.alignment,
  });

  /// 作为 SDK 分页游标和列表恢复标识的可见消息。
  final MessageInfo message;

  /// 消息前缘相对视口的比例位置，取值限制在 0 到 1。
  final double alignment;
}

/// 保存单个会话可同步恢复的消息窗口与浏览锚点；仅在当前进程内使用。
typedef MessageViewportSnapshot = ({
  List<MessageInfo> messages,
  MessageViewportAnchor anchor,
  int unreadAboveCount,
  int unreadBelowCount,
  int? oldestUnreadSequence,
  int? viewedUnreadMinSequence,
  int? viewedUnreadMaxSequence,
});

/// 只有到达当前窗口底部且 SDK 没有更新分页时，才算到达会话最新位置。
bool isAtConversationLatest({
  required bool isAtLoadedWindowBottom,
  required bool hasNewerMessages,
}) =>
    isAtLoadedWindowBottom && !hasNewerMessages;

/// 扩展已浏览区间，并只消耗本次新进入视口一侧的未读消息。
({
  int above,
  int below,
  int? viewedMinSequence,
  int? viewedMaxSequence,
}) consumeUnreadInVisibleRange({
  required int above,
  required int below,
  required int? viewedMinSequence,
  required int? viewedMaxSequence,
  required int? visibleMinSequence,
  required int? visibleMaxSequence,
}) {
  if (visibleMinSequence == null || visibleMaxSequence == null) {
    return (
      above: above,
      below: below,
      viewedMinSequence: viewedMinSequence,
      viewedMaxSequence: viewedMaxSequence,
    );
  }

  var minSequence = viewedMinSequence ?? visibleMinSequence;
  var maxSequence = viewedMaxSequence ?? visibleMaxSequence;
  var remainingAbove = above;
  var remainingBelow = below;
  if (visibleMinSequence < minSequence) {
    remainingAbove -= minSequence - visibleMinSequence;
    minSequence = visibleMinSequence;
  }
  if (visibleMaxSequence > maxSequence) {
    remainingBelow -= visibleMaxSequence - maxSequence;
    maxSequence = visibleMaxSequence;
  }
  return (
    above: remainingAbove > 0 ? remainingAbove : 0,
    below: remainingBelow > 0 ? remainingBelow : 0,
    viewedMinSequence: minSequence,
    viewedMaxSequence: maxSequence,
  );
}

/// 从完整分页结果中截取锚点两侧的消息，避免进程缓存持有全部历史数据。
MessageViewportSnapshot? createMessageViewportSnapshot({
  required List<MessageInfo> messages,
  required MessageViewportAnchor anchor,
  required int messagesPerSide,
  int unreadAboveCount = 0,
  int unreadBelowCount = 0,
  int? oldestUnreadSequence,
  int? viewedUnreadMinSequence,
  int? viewedUnreadMaxSequence,
}) {
  final anchorIndex = messages.indexWhere(
    (message) => message.msgID == anchor.message.msgID,
  );
  if (anchorIndex == -1) return null;

  final start =
      anchorIndex > messagesPerSide ? anchorIndex - messagesPerSide : 0;
  final requestedEnd = anchorIndex + messagesPerSide + 1;
  final end = requestedEnd < messages.length ? requestedEnd : messages.length;
  return (
    messages: List<MessageInfo>.unmodifiable(messages.sublist(start, end)),
    anchor: anchor,
    unreadAboveCount: unreadAboveCount,
    unreadBelowCount: unreadBelowCount,
    oldestUnreadSequence: oldestUnreadSequence,
    viewedUnreadMinSequence: viewedUnreadMinSequence,
    viewedUnreadMaxSequence: viewedUnreadMaxSequence,
  );
}

/// 选择最靠近视口顶部且完整可见的消息作为恢复锚点。
MessageViewportAnchor? selectMessageViewportAnchor({
  required List<MessageInfo> messages,
  required Iterable<ItemPosition> positions,
}) {
  // 过滤已经离开视口、索引越界或缺少稳定 msgID 的位置上报。
  final visible = positions
      .where((position) =>
          position.index >= 0 &&
          position.index < messages.length &&
          messages[position.index].msgID.isNotEmpty &&
          position.itemTrailingEdge > 0 &&
          position.itemLeadingEdge < 1)
      .toList();
  if (visible.isEmpty) return null;

  // 优先选完整可见的顶部消息，避免恢复后首行只露出很小一部分。
  final fullyVisible = visible
      .where((position) =>
          position.itemLeadingEdge >= 0 && position.itemTrailingEdge <= 1)
      .toList();
  final candidates = fullyVisible.isEmpty ? visible : fullyVisible;
  candidates.sort(
    (a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge),
  );
  final position = candidates.first;
  return MessageViewportAnchor(
    message: messages[position.index],
    alignment: position.itemLeadingEdge.clamp(0.0, 1.0),
  );
}
