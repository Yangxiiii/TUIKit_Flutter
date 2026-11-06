import 'dart:convert';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/call_message_widget.dart';

void main() {
  testWidgets('没有 rawMessage 的双方语音/视频记录仍按原媒体和公开对端字段回拨', (tester) async {
    for (final self in [false, true]) {
      for (final video in [false, true]) {
        String? target;
        bool? media;
        final message = MessageInfo(
          msgID: 'record',
          isSentBySelf: self,
          from: MessageSenderInfo(userID: self ? 'self' : 'peer'),
          to: self ? 'peer' : 'self',
          status: MessageStatus.sendSuccess,
          messageType: MessageType.custom,
          messagePayload: CustomMessagePayload(
              customData: jsonEncode({
            'actionType': 1,
            'data': jsonEncode({
              'businessID': 'av_call',
              'call_type': video ? 2 : 1,
              'call_end': 3
            })
          })),
        );
        await tester.pumpWidget(MaterialApp(
          theme: AppThemeFactory.create(
              const AppNormalColorScheme(), Brightness.light),
          home: Center(
              child: CallMessageWidget(
                  message: message,
                  isSelf: self,
                  maxWidth: 390,
                  config: const ChatMessageListConfig(),
                  onCallMessageClick: (user, type) {
                    target = user;
                    media = type;
                  })),
        ));
        await tester.tap(find.bySemanticsIdentifier('tim.message.call.record'));
        expect(target, 'peer');
        expect(media, video);
      }
    }
  });
}
