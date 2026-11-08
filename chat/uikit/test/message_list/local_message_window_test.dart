import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/local_message_window.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_utils.dart';

MessageInfo message(String id, int? timestamp,
        {String sender = 'peer',
        MessageStatus status = MessageStatus.sendSuccess,
        MessageType type = MessageType.text}) =>
    MessageInfo(
        msgID: id,
        timestamp: timestamp,
        from: MessageSenderInfo(userID: sender),
        status: status,
        messageType: type);

void main() {
  test('本地与SDK去重且SDK对象优先，已交接消息删除后不被本地复活', () {
    final window = LocalMessageWindow();
    final local = message('same', 100);
    window.seed([message('old', 90), local]);
    final remote = message('same', 100, status: MessageStatus.revoked);
    final live = message('live', 110);
    final merged = window.merge([live, remote, remote]);
    expect(merged.map((m) => m.msgID), ['live', 'same', 'old']);
    expect(merged[1], same(remote));
    expect(window.merge([live]).map((m) => m.msgID), ['live', 'old']);
    window.delete(['old']);
    window.seed([message('old', 90)]);
    expect(window.merge([]), isEmpty);
  });

  test('云端空页仍保留本地，读取期间撤回和删除不被迟到结果覆盖', () {
    final window = LocalMessageWindow();
    window.revoke('recalled');
    window.delete(['deleted']);
    window.seed([message('recalled', 100), message('deleted', 90)]);
    expect(window.merge([]).single.status, MessageStatus.revoked);
    expect(window.merge([message('recalled', 100)]).single.status,
        MessageStatus.revoked);
    window.clear();
    expect(window.merge([]), isEmpty);
  });

  test('本机撤回及退出快照优先于迟到普通状态，重新进入不恢复原文', () {
    final window = LocalMessageWindow();
    window.seed([message('same', 100)]);
    final recalled = message('same', 100, status: MessageStatus.revoked);
    final snapshot = window.merge([recalled]);
    window.update(message('same', 100));
    expect(window.merge([]).single.status, MessageStatus.revoked);
    window.clear();
    expect(window.merge([message('same', 100)]).single.status,
        MessageStatus.revoked);

    final reopened = LocalMessageWindow();
    reopened.reconcileRevocations(snapshot);
    final stale = message('same', 100);
    expect(reopened.merge([stale]).single.status, MessageStatus.revoked);
    expect(LocalMessageWindow().merge([message('same', 100)]).single.status,
        MessageStatus.sendSuccess);
    final deleted = message('same', 100, status: MessageStatus.deleted);
    reopened.reconcileRevocations([deleted]);
    expect(deleted.status, MessageStatus.deleted);
    reopened.seed([deleted]);
    reopened.revoke('same');
    expect(deleted.status, MessageStatus.deleted);
  });

  test('同批旧副本排在撤回状态前面时也不能恢复正文', () {
    final window = LocalMessageWindow();
    final stale = message('same', 100);
    window.seed([
      stale,
      message('same', 100, status: MessageStatus.revoked),
    ]);
    expect(window.merge([]).single.status, MessageStatus.revoked);
    final unidentified = message('', 100);
    window.reconcileRevocations([
      unidentified,
      message('', 100, status: MessageStatus.revoked),
    ]);
    expect(unidentified.status, MessageStatus.sendSuccess);
  });

  testWidgets('头像聚合跨类型但在换人、撤回、61秒、跨日和未知时间断组', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final context = tester.element(find.byType(SizedBox));
    bool isContinuation(MessageInfo older, MessageInfo current) =>
        MessageUtil.isAvatarContinuation(older, current, context);
    final start = DateTime(2026, 10, 30, 12).millisecondsSinceEpoch ~/ 1000;
    final older = message('a', start);
    expect(
        isContinuation(
            older, message('b', start + 60, type: MessageType.image)),
        isTrue);
    expect(isContinuation(older, message('b', start)), isTrue);
    expect(isContinuation(older, message('b', start + 61)), isFalse);
    expect(isContinuation(older, message('b', start - 1)), isFalse);
    expect(isContinuation(older, message('b', start + 1, sender: 'other')),
        isFalse);
    expect(
        isContinuation(
            older, message('b', start + 1, status: MessageStatus.revoked)),
        isFalse);
    expect(isContinuation(older, message('b', null)), isFalse);
    final midnight = DateTime(2026, 10, 31).millisecondsSinceEpoch ~/ 1000;
    expect(isContinuation(message('a', midnight - 1), message('b', midnight)),
        isFalse);
    expect(
        isContinuation(older, message('b', start + 1, type: MessageType.tips)),
        isFalse);
  });
}
