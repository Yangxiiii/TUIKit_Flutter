import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_viewport_anchor.dart';
import 'package:tencent_chat_uikit/src/third_party/scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  test('历史分页窗口底部不等于会话最新位置', () {
    expect(
      isAtConversationLatest(
        isAtLoadedWindowBottom: true,
        hasNewerMessages: true,
      ),
      isFalse,
    );
    expect(
      isAtConversationLatest(
        isAtLoadedWindowBottom: true,
        hasNewerMessages: false,
      ),
      isTrue,
    );
  });

  test('优先保存最靠近视口顶部且完整可见的消息', () {
    final messages = [
      MessageInfo(msgID: 'partially-visible'),
      MessageInfo(msgID: 'anchor'),
      MessageInfo(msgID: 'below'),
    ];
    const positions = [
      ItemPosition(
        index: 0,
        itemLeadingEdge: -0.2,
        itemTrailingEdge: 0.1,
      ),
      ItemPosition(
        index: 1,
        itemLeadingEdge: 0.1,
        itemTrailingEdge: 0.3,
      ),
      ItemPosition(
        index: 2,
        itemLeadingEdge: 0.3,
        itemTrailingEdge: 0.6,
      ),
    ];

    final anchor = selectMessageViewportAnchor(
      messages: messages,
      positions: positions,
    );

    expect(anchor?.message.msgID, 'anchor');
    expect(anchor?.alignment, 0.1);
  });

  test('快照只保留锚点两侧指定数量的消息', () {
    final messages = List.generate(
      10,
      (index) => MessageInfo(msgID: '$index'),
    );
    final anchor = MessageViewportAnchor(
      message: messages[5],
      alignment: 0.2,
    );

    final snapshot = createMessageViewportSnapshot(
      messages: messages,
      anchor: anchor,
      messagesPerSide: 2,
    );

    expect(snapshot?.messages.map((message) => message.msgID), [
      '3',
      '4',
      '5',
      '6',
      '7',
    ]);
  });

  test('浏览一侧的未读消息不会清掉另一侧未读数', () {
    final older = consumeUnreadInVisibleRange(
      above: 20,
      below: 8,
      viewedMinSequence: 100,
      viewedMaxSequence: 100,
      visibleMinSequence: 95,
      visibleMaxSequence: 99,
    );
    expect(older.above, 15);
    expect(older.below, 8);

    // 回到已经浏览过的区间不能误消耗下方未读。
    final backtracked = consumeUnreadInVisibleRange(
      above: older.above,
      below: older.below,
      viewedMinSequence: older.viewedMinSequence,
      viewedMaxSequence: older.viewedMaxSequence,
      visibleMinSequence: 98,
      visibleMaxSequence: 100,
    );
    expect(backtracked.above, 15);
    expect(backtracked.below, 8);

    expect(
      consumeUnreadInVisibleRange(
        above: backtracked.above,
        below: backtracked.below,
        viewedMinSequence: backtracked.viewedMinSequence,
        viewedMaxSequence: backtracked.viewedMaxSequence,
        visibleMinSequence: 101,
        visibleMaxSequence: 103,
      ).below,
      5,
    );
  });
}
