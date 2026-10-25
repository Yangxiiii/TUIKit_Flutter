import 'dart:async';
import 'package:tencent_chat_uikit/src/message_input/widget/message_edit_limit_dialog.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text/extended_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text_field/extended_text_field.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_chat_uikit/src/message_input/widget/message_edit_composer.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_action_sheet.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_actions_scope.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_overlay_avoider.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_tooltip.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/text_message_widget.dart';

Widget _host(Widget body) => MaterialApp(
      theme: AppThemeFactory.create(
          const AppNormalColorScheme(), Brightness.light),
      home: Scaffold(resizeToAvoidBottomInset: false, body: body),
    );

void main() {
  test('只有实际遮挡才计算16像素留白，未遮挡但距离不足也不移动', () {
    expect(messageOverlayLift(messageBottom: 500, overlayTop: 400), 116);
    expect(messageOverlayLift(messageBottom: 400, overlayTop: 400), 0);
    expect(messageOverlayLift(messageBottom: 399, overlayTop: 400), 0);
    expect(messageOverlayLift(messageBottom: 200, overlayTop: 400), 0);
  });

  testWidgets('遮挡后气泡底部距浮层16，重测不累加，关闭恢复原位置', (tester) async {
    final controller = MessageOverlayController();
    final bubble = GlobalKey();
    await tester.pumpWidget(_host(MessageOverlayAvoider(
      controller: controller,
      child: SizedBox.expand(
          child: Stack(children: [
        Positioned(
            top: 350,
            left: 10,
            child: SizedBox(key: bubble, width: 100, height: 50)),
      ])),
    )));
    final original = tester.getBottomLeft(find.byKey(bubble)).dy;
    controller.avoid(bubble, 300);
    await tester.pump();
    await tester.pump();
    expect(tester.getBottomLeft(find.byKey(bubble)).dy, 284);
    await tester.pumpWidget(_host(MessageOverlayAvoider(
      controller: controller,
      child: SizedBox.expand(
          child: Stack(children: [
        Positioned(
            top: 350,
            left: 10,
            child: SizedBox(key: bubble, width: 100, height: 50)),
      ])),
    )));
    await tester.pump();
    expect(tester.getBottomLeft(find.byKey(bubble)).dy, 284);
    controller.clear();
    await tester.pump();
    await tester.pump();
    expect(tester.getBottomLeft(find.byKey(bubble)).dy, original);
    controller.avoid(bubble, original + 1);
    await tester.pump();
    await tester.pump();
    expect(tester.getBottomLeft(find.byKey(bubble)).dy, original);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('编辑失败保留输入，并发确认只提交一次，取消不保存', (tester) async {
    final gate = Completer<String?>();
    var calls = 0, cancelled = 0;
    await tester.pumpWidget(_host(Align(
      alignment: Alignment.bottomCenter,
      child: MessageEditComposer(
          text: '原文',
          onCancel: () => cancelled++,
          onBounds: (_) {},
          onSave: (text) {
            calls++;
            return gate.future;
          }),
    )));
    await tester.pump();
    tester.testTextInput.enterText('保留这段修改');
    await tester.pump();
    final confirm = find.byWidgetPredicate((w) =>
        w is Semantics && w.properties.identifier == 'tim.message.editSave');
    await tester.tap(confirm);
    await tester.tap(confirm);
    await tester.pump();
    expect(calls, 1);
    gate.complete('编辑内容保存失败，请稍后重试');
    await tester.pump();
    expect(
        tester
            .widget<ExtendedTextField>(find.byType(ExtendedTextField))
            .controller!
            .text,
        '保留这段修改');
    final cancel = find.byWidgetPredicate((w) =>
        w is Semantics && w.properties.identifier == 'tim.message.editCancel');
    await tester.tap(cancel);
    expect(cancelled, 1);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('原文与空白不能提交，普通发送入口不出现在编辑区', (tester) async {
    var saves = 0;
    await tester.pumpWidget(_host(Align(
      alignment: Alignment.bottomCenter,
      child: MessageEditComposer(
          text: '原文',
          onCancel: () {},
          onBounds: (_) {},
          onSave: (_) async {
            saves++;
            return null;
          }),
    )));
    final confirm = find.byWidgetPredicate((w) =>
        w is Semantics && w.properties.identifier == 'tim.message.editSave');
    await tester.tap(confirm);
    expect(saves, 0);
    await tester.pump();
    tester.testTextInput.enterText('  ');
    await tester.pump();
    await tester.tap(confirm);
    expect(saves, 0);
    expect(find.text('发送'), findsNothing);
  });

  testWidgets('已编辑标识仅附加展示，不写入原文本消息', (tester) async {
    final message = MessageInfo(
        msgID: 'edited',
        messageType: MessageType.text,
        messagePayload: TextMessagePayload(text: '正文'),
        status: MessageStatus.sendSuccess);
    await tester.pumpWidget(_host(MessageActionsScope(
      config: ChatMessageEditConfig(
          canEdit: (_) => true,
          prepare: (_) async => (text: '正文', error: null),
          save: (id, text) async => null,
          onMessageWindowChanged: (_) {},
          editedMessageIds: {'edited'}),
      showActions: (message, key, items, reaction) {},
      onMessagesChanged: (_) {},
      child: Align(
          alignment: Alignment.topLeft,
          child: TextMessageWidget(
              message: message,
              isSelf: false,
              maxWidth: 350,
              config: const ChatMessageListConfig())),
    )));
    final rendered = tester.widget<ExtendedText>(find.byType(ExtendedText));
    expect(rendered.textSpan!.toPlainText(), contains('(已编辑)'));
    expect((message.messagePayload as TextMessagePayload).text, '正文');
    expect(tester.takeException(), isNull);
  });

  testWidgets('底部面板分组及编辑入口顺序，已有复制回调可继续使用', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var copied = 0, closed = 0;
    await tester.pumpWidget(_host(Align(
        alignment: Alignment.bottomCenter,
        child: MessageActionSheet(
          items: [
            MessageMenuItem(id: 'edit', title: '编辑消息', onTap: () {}),
            MessageMenuItem(id: 'copy', title: '复制', onTap: () => copied++),
            MessageMenuItem(title: '翻译', onTap: () {}),
            MessageMenuItem(title: '从当前听', onTap: () {}),
            MessageMenuItem(title: '其他扩展操作', onTap: () {}),
          ],
          onClose: () => closed++,
          onBounds: (_) {},
        ))));
    await tester.pumpAndSettle();
    for (final text in [
      '回复',
      '转发',
      '标记',
      '复制',
      '撤回',
      '编辑消息',
      '加急',
      '多选',
      '置顶消息',
      'Pin',
      '删除'
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(tester.getTopLeft(find.text('编辑消息')).dy,
        greaterThan(tester.getTopLeft(find.text('撤回')).dy));
    expect(tester.getTopLeft(find.text('编辑消息')).dy,
        lessThan(tester.getTopLeft(find.text('加急')).dy));
    expect(tester.getSize(find.byType(MessageActionSheet)).height, 541);
    expect(find.text('翻译'), findsNothing);
    expect(find.text('从当前听'), findsNothing);
    expect(find.text('其他扩展操作'), findsNothing);
    expect(find.byType(ListTile), findsNothing);
    expect(
        find.descendant(
            of: find.byWidgetPredicate((w) =>
                w is Semantics &&
                w.properties.identifier == 'tim.message.action.multiSelect'),
            matching: find.byIcon(AppIcons.multipleChoice)),
        findsOneWidget);
    expect(find.byIcon(AppIcons.selected), findsNothing);
    await tester.tap(find.text('复制'));
    expect(copied, 1);
    expect(closed, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('已打开菜单跨过编辑时限后保留编辑行并禁用提交', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var edits = 0;
    await tester.pumpWidget(_host(Align(
      alignment: Alignment.bottomCenter,
      child: MessageActionSheet(
          items: [
            MessageMenuItem(id: 'edit', title: '编辑消息', onTap: () => edits++)
          ],
          editExpiresAt: DateTime.now().add(const Duration(seconds: 1)),
          onClose: () {},
          onBounds: (_) {}),
    )));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('编辑消息'), findsOneWidget);
    await tester.tap(find.text('编辑消息'));
    expect(edits, 0);
  });
  testWidgets('上限提示使用20次，确认只关闭提示路由', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const MessageEditLimitDialog()),
              child: const Text('打开提示'),
            ))));
    await tester.tap(find.text('打开提示'));
    await tester.pumpAndSettle();
    expect(find.text('单条消息最多编辑20次'), findsOneWidget);
    expect(find.textContaining('120次'), findsNothing);
    final content = find
        .descendant(of: find.byType(Dialog), matching: find.byType(SizedBox))
        .first;
    expect(tester.getSize(content), const Size(342, 120));
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageEditLimitDialog), findsNothing);
    expect(find.text('打开提示'), findsOneWidget);
  });
  testWidgets('底部路由动画结束后报告实际顶部，单行编辑区为104高', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    double? top;
    await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => MessageActionSheet(
                      items: const [],
                      onClose: () {},
                      onBounds: (bounds) => top = bounds.top)),
              child: const Text('打开面板'),
            ))));
    await tester.tap(find.text('打开面板'));
    await tester.pumpAndSettle();
    expect(top, 303);
    await tester.pumpWidget(_host(Align(
        alignment: Alignment.bottomCenter,
        child: MessageEditComposer(
            text: '单行',
            onCancel: () {},
            onSave: (_) async => null,
            onBounds: (_) {}))));
    await tester.pump();
    expect(tester.getSize(find.byType(MessageEditComposer)).height, 104);
  });
}
