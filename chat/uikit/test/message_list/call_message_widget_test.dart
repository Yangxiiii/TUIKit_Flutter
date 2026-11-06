import 'dart:convert';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/call_message_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/text_message_widget.dart';

void main() {
  testWidgets('语音和视频记录复用普通气泡，离线消息仍按原媒体回拨', (tester) async {
    for (final self in [false, true]) {
      for (final video in [false, true]) {
        String? target;
        bool? media;
        final contentKey = GlobalKey();
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
                  config:
                      const ChatMessageListConfig(textBubbleCornerRadius: 23),
                  bubbleKey: contentKey,
                  onCallMessageClick: (user, type) {
                    target = user;
                    media = type;
                  })),
        ));
        final bubble = find.bySemanticsIdentifier('tim.message.call.record');
        final content = tester.widget<Container>(find.byKey(contentKey));
        expect(
            find.descendant(
                of: bubble, matching: find.byType(TextMessageWidget)),
            findsOneWidget);
        expect(content.padding,
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8));
        expect(content.constraints?.maxWidth, closeTo(390 * .9, .01));
        expect(tester.getSize(bubble).height, closeTo(40, .01));
        final decoration = tester
            .widget<Container>(
              find.descendant(
                of: bubble,
                matching: find.byWidgetPredicate((widget) =>
                    widget is Container && widget.decoration is BoxDecoration),
              ),
            )
            .decoration! as BoxDecoration;
        final colors = const AppNormalColorScheme();
        expect(decoration.color,
            self ? colors.chatOutgoingBubble : colors.chatIncomingBubble);
        expect(decoration.borderRadius, BorderRadius.circular(23));
        await tester.tap(bubble);
        expect(target, 'peer');
        expect(media, video);
      }
    }
  });
}
