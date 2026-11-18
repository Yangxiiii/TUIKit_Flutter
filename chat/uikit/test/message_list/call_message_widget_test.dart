import 'dart:convert';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/call_message_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/text_message_widget.dart';

void main() {
  testWidgets('群通话发起记录只对发起人和受邀者渲染普通气泡', (tester) async {
    final message = MessageInfo(
      msgID: 'start',
      from: MessageSenderInfo(userID: 'caller'),
      to: 'g',
      status: MessageStatus.sendSuccess,
      conversationType: ConversationType.group,
      messageType: MessageType.custom,
      messagePayload: CustomMessagePayload(
          customData: jsonEncode({
        'businessID': 'oa_group_call_start',
        'version': 1,
        'payload': {
          'groupId': 'g',
          'callerId': 'caller',
          'mediaType': 'video',
          'inviteeIds': ['callee'],
          'attemptId': 'current',
        },
      })),
    );
    final accepted = ValueNotifier<String?>(null);
    addTearDown(accepted.dispose);
    for (final viewer in ['caller', 'callee', 'other']) {
      var tapped = 0;
      accepted.value = 'previous';
      await tester.pumpWidget(MaterialApp(
        theme: AppThemeFactory.create(
            const AppNormalColorScheme(), Brightness.light),
        home: CallMessageWidget(
          message: message,
          isSelf: viewer == 'caller',
          maxWidth: 390,
          config: ChatMessageListConfig(
            acceptedCallAttempt: accepted,
            onGroupCallBubbleTap: (_) => tapped++,
          ),
          viewerId: viewer,
        ),
      ));
      final expected = viewer == 'other' ? findsNothing : findsOneWidget;
      expect(find.text('发起通话'), expected);
      expect(find.byType(TextMessageWidget), expected);
      expect(find.byIcon(AppIcons.cameraOn), expected);
      accepted.value = 'current';
      await tester.pump();
      expect(find.text('已接听'), expected);
      accepted.value = null;
      await tester.pump();
      expect(find.text('发起通话'), expected);
      if (viewer != 'other') {
        await tester.tap(find.bySemanticsIdentifier('tim.message.call.start'));
        expect(tapped, 1);
      }
    }
  });

  testWidgets('多人记录不能误回拨单一收发方', (tester) async {
    var callbacks = 0;
    final message = MessageInfo(
      msgID: 'multi',
      from: MessageSenderInfo(userID: 'peer'),
      to: 'self',
      messageType: MessageType.custom,
      messagePayload: CustomMessagePayload(
          customData: jsonEncode({
        'actionType': 1,
        'groupID': '',
        'inviteeList': ['self', 'another'],
        'data': jsonEncode({'businessID': 'av_call', 'call_type': 1}),
      })),
    );
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeFactory.create(
          const AppNormalColorScheme(), Brightness.light),
      home: CallMessageWidget(
          message: message,
          isSelf: false,
          maxWidth: 390,
          config: const ChatMessageListConfig(),
          onCallMessageClick: (_, __) {
            callbacks++;
          }),
    ));
    await tester.tap(find.bySemanticsIdentifier('tim.message.call.multi'));
    expect(callbacks, 0);
  });
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
