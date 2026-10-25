import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_action_sheet.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_recall_notice.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_tooltip.dart';

Widget _host(Widget body) => MaterialApp(
      theme: AppThemeFactory.create(
          const AppNormalColorScheme(), Brightness.light),
      home: Scaffold(body: body),
    );

void main() {
  test('菜单资格拒绝未来、120秒、他人和未知自定义协议', () {
    final now = DateTime.utc(2026, 10, 25);
    final message = MessageInfo(
      msgID: 'message',
      isSentBySelf: true,
      conversationType: ConversationType.c2c,
      status: MessageStatus.sendSuccess,
      messageType: MessageType.text,
      timestamp: now.millisecondsSinceEpoch ~/ 1000 - 119,
    );
    expect(ChatMessageRecallConfig.isEligible(message, now), isTrue);
    for (final age in [-1, 120]) {
      message.timestamp = now.millisecondsSinceEpoch ~/ 1000 - age;
      expect(ChatMessageRecallConfig.isEligible(message, now), isFalse);
    }
    message.timestamp = now.millisecondsSinceEpoch ~/ 1000;
    message.isSentBySelf = false;
    expect(ChatMessageRecallConfig.isEligible(message, now), isFalse);
    message.isSentBySelf = true;
    message.messageType = MessageType.custom;
    message.messagePayload =
        CustomMessagePayload(customData: '{"businessID":"av_call"}');
    expect(ChatMessageRecallConfig.isEligible(message, now), isFalse);
  });

  test('图文撤回草稿保留块顺序和远端附件，持久化往返无需重复上传', () {
    const message = RichContentMessage([
      RichTextBlock('**原文**\n'),
      RichImageBlock('https://example.com/image.png', 100, 200),
      RichFileBlock(
          'https://example.com/file.pdf', '文档.pdf', 123, 'application/pdf'),
    ]);
    final draft = RichContentDraft.fromMessage(message);
    expect(draft.canSend, isTrue);
    expect(draft.toMessage()!.toCustomData(), message.toCustomData());
    final restored =
        RichContentDraft.tryParsePersisted(draft.toPersistedString());
    expect(restored!.canSend, isTrue);
    expect(restored.toMessage()!.toCustomData(), message.toCustomData());
    expect(
        ChatMessageRecallConfig.supportsCustomMessage(message.toCustomData()),
        isTrue);
  });

  testWidgets('本人提示和蓝色链接同列居中，到期只移除链接且无气泡背景', (tester) async {
    var edits = 0;
    await tester.pumpWidget(_host(MessageRecallNotice(
      messageId: 'id',
      text: '你撤回了一条消息',
      editableUntil: DateTime.now().add(const Duration(seconds: 1)),
      onReedit: () => edits++,
    )));
    expect(find.text('你撤回了一条消息'), findsOneWidget);
    expect(find.text(' 重新编辑'), findsOneWidget);
    final semantics = find.byWidgetPredicate((w) =>
        w is Semantics && w.properties.identifier == 'tim.message.reedit.id');
    expect(semantics, findsOneWidget);
    await tester.tap(semantics);
    expect(edits, 1);
    final linkStyle = tester.widget<Text>(find.text(' 重新编辑')).style!;
    final context = tester.element(find.byType(MessageRecallNotice));
    expect(linkStyle.color, context.appColors.primary);
    expect(
        find.descendant(
            of: find.byType(MessageRecallNotice),
            matching: find.byType(Container)),
        findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(' 重新编辑'), findsNothing);
    expect(find.text('你撤回了一条消息'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('他人提示包含姓名，不显示头像、重新编辑或额外时间', (tester) async {
    final message = MessageInfo(
        isSentBySelf: false,
        from: MessageSenderInfo(userID: 'peer', nickname: '姓名(昵称)'));
    await tester.pumpWidget(_host(MessageRecallNotice(
        messageId: 'id', text: chatMessageRecallText(message))));
    expect(find.text('“姓名(昵称)” 撤回了一条消息'), findsOneWidget);
    expect(find.text(' 重新编辑'), findsNothing);
    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets('菜单只在具有回调且未到期时显示撤回，超时从分组移除', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(Align(
      alignment: Alignment.bottomCenter,
      child: MessageActionSheet(
        items: [MessageMenuItem(id: 'recall', title: '撤回', onTap: () {})],
        recallExpiresAt: DateTime.now().add(const Duration(seconds: 1)),
        onClose: () {},
        onBounds: (_) {},
      ),
    )));
    await tester.pump();
    expect(find.text('撤回'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('撤回'), findsNothing);
    await tester.pumpWidget(_host(
        MessageActionSheet(items: const [], onClose: () {}, onBounds: (_) {})));
    await tester.pump();
    expect(find.text('撤回'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
