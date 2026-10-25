import 'dart:convert';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_utils.dart';

void main() {
  test('操作事件往返与未知版本、损坏字段和其他业务隔离', () {
    for (final action in ['add', 'remove']) {
      final event = StickyMessageEvent(action: action, messageId: 'im:abc', operatorName: '姓名');
      expect(StickyMessageEvent.tryParse(event.toCustomData())!.preview, event.preview);
    }
    final source = jsonDecode(const StickyMessageEvent(action: 'add', messageId: 'im', operatorName: '姓名').toCustomData()) as Map<String, dynamic>;
    for (final raw in ['', '[]', '{', '{"businessID":"oa_big_file","version":1}', jsonEncode({...source, 'version': 1.0}),
      jsonEncode({...source, 'version': 2}), jsonEncode({...source, 'payload': {'action': 'delete', 'messageId': 'im', 'operatorName': '姓名'}}),
      jsonEncode({...source, 'payload': {'action': 'add', 'messageId': 123, 'operatorName': '姓名'}})]) {
      expect(StickyMessageEvent.tryParse(raw), isNull, reason: raw);
    }
  });

  test('语音、失败消息和操作事件不能置顶；正文和附件类型可以', () {
    final message = MessageInfo(msgID: 'im', status: MessageStatus.sendSuccess, conversationType: ConversationType.c2c);
    for (final type in [MessageType.text, MessageType.image, MessageType.video, MessageType.file, MessageType.face]) {
      message.messageType = type;
      expect(StickyMessageEvent.canPin(message), isTrue);
    }
    message.messageType = MessageType.audio;
    expect(StickyMessageEvent.canPin(message), isFalse);
    message.messageType = MessageType.custom;
    message.messagePayload = CustomMessagePayload(customData: const StickyMessageEvent(action: 'add', messageId: 'im', operatorName: '姓名').toCustomData());
    expect(StickyMessageEvent.canPin(message), isFalse);
    message.messageType = MessageType.text;
    message.status = MessageStatus.revoked;
    expect(StickyMessageEvent.canPin(message), isFalse);
  });

  testWidgets('置顶提示保持系统布局与统一摘要，不显示普通气泡、头像或时间', (tester) async {
    final message = MessageInfo(messageType: MessageType.custom, messagePayload: CustomMessagePayload(
      customData: const StickyMessageEvent(action: 'remove', messageId: 'im', operatorName: '杨洋阳').toCustomData()));
    await tester.pumpWidget(MaterialApp(theme: AppThemeFactory.create(const AppNormalColorScheme(), Brightness.light),
      home: Scaffold(body: CustomMessageWidget(message: message, isSelf: false, maxWidth: 358))));
    final context = tester.element(find.byType(CustomMessageWidget));
    expect(MessageUtil.isSystemStyleCustomMessagePayload(message, context), isTrue);
    expect(MessageUtil.getMessageAbstract(message, context), '杨洋阳 移除了置顶内容');
    expect(find.text('杨洋阳 移除了置顶内容', findRichText: true), findsOneWidget);
    expect(find.byType(CircleAvatar), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.text('重新编辑'), findsNothing);
    final text = tester.widget<Text>(find.byType(Text));
    expect(((text.textSpan! as TextSpan).children!.first as TextSpan).style!.color, context.appColors.primary);
  });

  testWidgets('原文失效控制包不生成可见提示或会话摘要', (tester) async {
    final message = MessageInfo(conversationType: ConversationType.c2c, messageType: MessageType.custom,
      messagePayload: CustomMessagePayload(customData: const StickyMessageEvent(
        action: 'invalidate', messageId: 'im', operatorName: '操作人').toCustomData()));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CustomMessageWidget(
      message: message, isSelf: false, maxWidth: 358))));
    expect(MessageUtil.getMessageAbstract(message, tester.element(find.byType(CustomMessageWidget))), '');
    expect(find.byType(Text), findsNothing);
  });
}
