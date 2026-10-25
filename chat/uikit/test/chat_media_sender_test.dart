import 'dart:async';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:atomic_x_core/impl/message/message_input_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_list_store_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_input/chat_media_sender.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/big_file_message.dart';

class _Input implements MessageInputStore {
  int calls = 0;
  final payload = CustomMessagePayload(
      customData: const BigFileMessage(
              url: 'https://files.test/a', name: 'a.pdf', size: 1)
          .toCustomData(),
      extensionInfo: 'task');
  @override
  Future<CompletionHandler> sendMessage(
      {required SendMessagePayload payload, SendMessageOption? option}) async {
    calls++;
    notificationCenter.post(
        MessageSendNotifyKey.messageSendBegin,
        MessageSendEventData(
            conversationID: 'c2c_other',
            message:
                MessageInfo(msgID: 'other', messagePayload: this.payload)));
    notificationCenter.post(
        MessageSendNotifyKey.messageSendBegin,
        MessageSendEventData(
            conversationID: 'c2c_peer',
            message: MessageInfo(msgID: 'real', messagePayload: this.payload)));
    await Future<void>.delayed(Duration.zero);
    return CompletionHandler();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('占位仅匹配同会话同任务SDK消息，发送结束取消监听，失败行删除发生在发送边界', () async {
    final input = _Input();
    final created = <String>[];
    var deleted = 0;
    final option = SendMessageOption(
        offlinePushInfo: OfflinePushInfo(description: '[图片]'));
    await sendChatMedia(
        message: MessageInfo(),
        payload: CustomSendMessagePayload(
            customData: input.payload.customData, extensionInfo: 'task'),
        option: option,
        conversationID: 'c2c_peer',
        store: input,
        beforeSend: () async {
          deleted++;
        },
        sender: (request) => request.send(request.payload,
            onCreated: (m) => created.add(m.msgID)));
    expect(created, ['real']);
    expect(deleted, 1);
    expect(option.offlinePushInfo!.description, '[文件]');
    notificationCenter.post(
        MessageSendNotifyKey.messageSendBegin,
        MessageSendEventData(
            conversationID: 'c2c_peer',
            message:
                MessageInfo(msgID: 'late', messagePayload: input.payload)));
    await Future<void>.delayed(Duration.zero);
    expect(created, ['real']);
  });
}
