import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/big_file_message.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/upload_message_order.dart';

MessageInfo _upload(String id, int timestamp) => MessageInfo(
      msgID: id,
      isSentBySelf: true,
      messageType: MessageType.file,
      timestamp: timestamp,
      status: MessageStatus.sending,
    );

MessageInfo _sent(String id, String uploadId, int timestamp) => MessageInfo(
      msgID: id,
      isSentBySelf: true,
      messageType: MessageType.custom,
      timestamp: timestamp,
      messagePayload: CustomMessagePayload(
        extensionInfo: uploadId,
        customData: const BigFileMessage(
                url: 'https://files.example/attachment', name: 'file', size: 1)
            .toCustomData(),
      ),
    );

List<String> _ids(Iterable<MessageInfo> messages) =>
    messages.map((message) => message.msgID).toList();

void main() {
  test('后选文件先完成时，两个气泡均在原位接管并保留中间收到的消息', () {
    final order = UploadMessageOrder();
    final older = MessageInfo(msgID: 'older', timestamp: 99);
    final first = _upload('oa_upload_first', 100);
    final peer = MessageInfo(msgID: 'peer', timestamp: 100);
    final second = _upload('album_second', 100);
    final firstSent = _sent('first', first.msgID, 103);
    final secondSent = _sent('second', second.msgID, 102);

    order.apply([first, older]);
    expect(_ids(order.apply([second, peer, first, older])),
        ['album_second', 'peer', 'oa_upload_first', 'older']);
    expect(_ids(order.apply([secondSent, second, peer, first, older])),
        ['second', 'peer', 'oa_upload_first', 'older']);
    expect(_ids(order.apply([firstSent, secondSent, peer, first, older])),
        ['second', 'peer', 'first', 'older']);
    expect(order.apply([firstSent, secondSent, peer, older]),
        [secondSent, peer, firstSent, older]);
    expect(order.displayTimestamp(firstSent), first.timestamp);
    expect(firstSent.timestamp, 103);

    final forward = _sent('forward', first.msgID, 104);
    expect(_ids(order.apply([forward, firstSent, secondSent, peer, older])),
        ['forward', 'second', 'peer', 'first', 'older']);

    final revoked = MessageInfo(
        msgID: firstSent.msgID, timestamp: 103, status: MessageStatus.revoked);
    expect(order.apply([forward, revoked, secondSent, peer, older]),
        [forward, secondSent, peer, revoked, older]);
    expect(order.apply([forward, secondSent, peer, first, older]),
        [forward, secondSent, peer, older]);
  });

  test('相册占位更新或失败重试保持原位，加载旧历史仍按时间插入', () {
    final order = UploadMessageOrder();
    final first = _upload('album_first', 100);
    final second = _upload('oa_upload_second', 100);
    final history = MessageInfo(msgID: 'history', timestamp: 99);
    order.apply([first]);
    order.apply([second, first]);
    final updated = _upload(first.msgID, 100)..status = MessageStatus.sendFail;

    expect(order.apply([updated, second, history]), [second, updated, history]);
    expect(order.apply([second, history]), [second, history]);
  });
}
