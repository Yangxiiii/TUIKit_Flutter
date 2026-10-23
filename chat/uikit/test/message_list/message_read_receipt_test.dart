import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_status_mixin.dart';

void main() {
  MessageInfo message({
    MessageStatus status = MessageStatus.sendSuccess,
    bool read = false,
    bool needsReceipt = true,
    bool isSelf = true,
    ConversationType type = ConversationType.c2c,
    int readCount = 0,
    int unreadCount = 0,
  }) =>
      MessageInfo(
        msgID: 'receipt-test',
        isSentBySelf: isSelf,
        conversationType: type,
        status: status,
        needReadReceipt: needsReceipt,
        readReceiptInfo: MessageReceipt(
          isPeerRead: read,
          readCount: readCount,
          unreadCount: unreadCount,
        ),
      );

  Future<void> mount(
    WidgetTester tester,
    MessageInfo info, {
    bool enabled = true,
    bool merged = false,
    VoidCallback? onTap,
  }) =>
      tester.pumpWidget(MaterialApp(
        theme: AppThemeFactory.create(
            const AppNormalColorScheme(), Brightness.light),
        home: Scaffold(
            body: _Receipt(
          message: info,
          enabled: enabled,
          merged: merged,
          onTap: onTap,
        )),
      ));

  testWidgets('发送成功但对方未读时只显示未读图标，回执更新后才变为已读', (tester) async {
    await mount(tester, message());
    expect(find.byIcon(AppIcons.unread), findsOneWidget);
    expect(find.byIcon(AppIcons.read), findsNothing);
    final unread = tester.widget<Icon>(find.byIcon(AppIcons.unread));
    expect(unread.semanticLabel, '未读');
    expect(unread.size, 18);
    await mount(tester, message(read: true));
    expect(find.byIcon(AppIcons.unread), findsNothing);
    expect(find.byIcon(AppIcons.read), findsOneWidget);
    final read = tester.widget<Icon>(find.byIcon(AppIcons.read));
    expect(read.semanticLabel, '已读');
    expect(read.color, isNot(unread.color));
  });

  testWidgets('未请求回执、开关关闭、对方消息及合并详情不显示阅读小勾', (tester) async {
    for (final info in [message(needsReceipt: false), message(isSelf: false)]) {
      await mount(tester, info);
      expect(find.byType(Icon), findsNothing);
    }
    await mount(tester, message(), enabled: false);
    expect(find.byType(Icon), findsNothing);
    await mount(tester, message(), merged: true);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('发送中和失败不显示阅读图标，失败仍可重试', (tester) async {
    var taps = 0;
    await mount(tester, message(status: MessageStatus.sending, read: true));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
    for (final status in [MessageStatus.sendFail, MessageStatus.violation]) {
      await mount(tester, message(status: status, read: true),
          onTap: () => taps++);
      expect(find.byIcon(AppIcons.error), findsOneWidget);
      expect(find.byIcon(AppIcons.read), findsNothing);
      expect(find.byIcon(AppIcons.unread), findsNothing);
      await tester.tap(find.byIcon(AppIcons.error));
    }
    expect(taps, 2);
  });

  testWidgets('群聊保留人数、全部已读及可点击详情', (tester) async {
    var taps = 0;
    await mount(tester,
        message(type: ConversationType.group, readCount: 2, unreadCount: 1),
        onTap: () => taps++);
    expect(find.text('2人已读'), findsOneWidget);
    expect(find.byIcon(AppIcons.read), findsNothing);
    await tester.tap(find.text('2人已读'));
    expect(taps, 1);
    await mount(tester, message(type: ConversationType.group, readCount: 3));
    expect(find.text('全部已读'), findsOneWidget);
    await mount(tester, message(type: ConversationType.group, unreadCount: 3));
    expect(find.text('未读'), findsOneWidget);
  });
}

/// 将真实发送提示和回执控件放在同一行，检查二者不会重复或混淆。
class _Receipt extends StatelessWidget with MessageStatusMixin {
  const _Receipt(
      {required this.message,
      required this.enabled,
      required this.merged,
      this.onTap});
  final MessageInfo message;
  final bool enabled;
  final bool merged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    final status = buildOutsideBubbleStatusIndicator(
        message: message, colorsTheme: colors, onResendTap: onTap);
    final receipt = buildOutsideReadReceiptIndicator(
      message: message,
      colorsTheme: colors,
      locale: AppLocalization.of(context),
      enableReadReceipt: enabled,
      isInMergedDetailView: merged,
      onTap: onTap,
    );
    return Row(
        children: [if (status != null) status, if (receipt != null) receipt]);
  }
}
