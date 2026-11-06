import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/calling_message_data_provider.dart';

void main() {
  testWidgets('离线通话载荷保留媒体、时长与列表摘要，拒绝异常 JSON', (tester) async {
    late BuildContext page;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      page = context;
      return const SizedBox();
    })));
    MessageInfo message(String raw) => MessageInfo(
        messageType: MessageType.custom,
        messagePayload: CustomMessagePayload(customData: raw));
    for (final (type, prefix) in [(1, '[语音通话]'), (2, '[视频通话]')]) {
      final info = message(jsonEncode({
        'actionType': 1,
        'groupID': '',
        'inviteeList': ['peer'],
        'data': jsonEncode(
            {'businessID': 'av_call', 'call_type': type, 'call_end': 600})
      }));
      final parsed = CallingMessageDataProvider(info, page);
      expect(parsed.isCallingSignal, isTrue);
      expect(parsed.content, '通话时长 10:00');
      expect(MessageUtil.getMessageAbstract(info, page), '$prefix 通话时长 10:00');
    }
    for (final raw in [
      '{',
      '[]',
      '{}',
      '{"data":4}',
      '{"data":"[]"}',
      '{"data":{"businessID":"av_call","data":5}}'
    ]) {
      expect(CallingMessageDataProvider(message(raw), page).isCallingSignal,
          isFalse);
    }
  });

  testWidgets('异常时长不伪造通话时长，取消与超时仍保持不同事件', (tester) async {
    late BuildContext page;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      page = context;
      return const SizedBox();
    })));
    CallingMessageDataProvider parse(int action, Map<String, Object?> data) =>
        CallingMessageDataProvider(
            MessageInfo(
                messageType: MessageType.custom,
                messagePayload: CustomMessagePayload(
                    customData: jsonEncode({
                  'actionType': action,
                  'data': jsonEncode(
                      {'businessID': 'av_call', 'call_type': 1, ...data})
                }))),
            page);
    expect(parse(1, {'call_end': 'invalid'}).content,
        AppLocalization.of(page).callEndedTheCall);
    expect(parse(2, {}).protocolType, CallProtocolType.cancel);
    expect(parse(5, {}).protocolType, CallProtocolType.timeout);
    expect(parse(2, {}).content, isNot(parse(5, {}).content));
  });
}
