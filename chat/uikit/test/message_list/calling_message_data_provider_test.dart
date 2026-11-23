import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/calling_message_data_provider.dart'
    show CallProtocolType;
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';

void main() {
  testWidgets('群通话发起及挂断信令不占消息行或摘要，保留普通消息及单聊通话', (tester) async {
    MessageInfo signal(String id, String group, Object data) => MessageInfo(
          msgID: id,
          to: group,
          from: MessageSenderInfo(userID: 'caller'),
          messageType: MessageType.custom,
          messagePayload: CustomMessagePayload(
              customData: jsonEncode({
            'businessID': 1,
            'actionType': 1,
            'groupID': group,
            'inviteeList': ['peer'],
            'data': data,
          })),
        );
    final audio = signal('audio-start', 'group',
        jsonEncode({'businessID': 'av_call', 'call_type': 1}));
    final video = signal('video-start', 'group', {
      'businessID': 'rtc_call',
      'data': {'cmd': 'videoCall', 'inviter': 'caller'},
    });
    final result = jsonEncode({
      'businessID': 'rtc_call',
      'version': 4,
      'call_type': 1,
      'call_end': 0,
      'data': {
        'cmd': 'hangup',
        'inviter': 'caller',
        'excludeFromHistoryMessage': false,
      },
    });
    final hangup = signal('hangup', 'group', result);
    final direct = signal('direct', '', result);
    final text = MessageInfo(
      msgID: 'text',
      messageType: MessageType.text,
      messagePayload: TextMessagePayload(text: '普通群消息'),
    );
    late BuildContext page;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Column(children: [
            Builder(builder: (context) {
              page = context;
              return MessageList(
                conversationID: 'group_group',
                config: const ChatMessageListConfig(),
                offlineMessages: [text, hangup, video, audio],
              );
            }),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<MessageItem>(find.byType(MessageItem))
            .map((item) => item.message.msgID),
        ['text']);
    for (final message in [audio, video, hangup]) {
      expect(CallingMessageDataProvider.isSdkGroupCallSignal(message), isTrue);
      for (final viewer in ['caller', 'peer']) {
        final parsed =
            CallingMessageDataProvider(message, page, viewerId: viewer);
        expect(parsed.excludeFromHistory, isTrue);
        expect(parsed.content, isEmpty);
      }
      expect(MessageUtil.getMessageAbstract(message, page), isEmpty);
    }
    expect(CallingMessageDataProvider.isSdkGroupCallSignal(direct), isFalse);
    expect(CallingMessageDataProvider(direct, page, viewerId: 'peer').content,
        '通话时长 00:00');
  });

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
      for (final (seconds, label) in [
        (5, '00:05'),
        (600, '10:00'),
        (3599, '59:59'),
        (3600, '1:00:00'),
        (3601, '1:00:00')
      ]) {
        final info = message(jsonEncode({
          'actionType': 1,
          'groupID': '',
          'inviteeList': ['peer'],
          'data': jsonEncode({
            'businessID': 'av_call',
            'call_type': type,
            'call_end': seconds,
          }),
        }));
        final parsed = CallingMessageDataProvider(info, page);
        expect(parsed.isCallingSignal, isTrue);
        expect(parsed.content, '通话时长 $label');
        expect(
            MessageUtil.getMessageAbstract(info, page), '$prefix 通话时长 $label');
      }
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
    final multi = message(jsonEncode({
      'actionType': 1,
      'groupID': '',
      'inviteeList': ['peer', 'another'],
      'data': jsonEncode({'businessID': 'av_call', 'call_type': 1}),
    }));
    expect(
        CallingMessageDataProvider(multi, page).isTemporaryMultiParty, isTrue);
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
