import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_actions_scope.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_confirmation.dart';

void main() {
  testWidgets('重发和删除精确正文、尺寸及无标题，取消零调用，重复确认只执行一次', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext target;
    final guard = ActionGuard();
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeFactory.create(
          const AppNormalColorScheme(), Brightness.light),
      navigatorObservers: [AppDialog.observer],
      builder: AppDialog.init(),
      home: MessageActionsScope(
          config: null,
          actionGuard: guard,
          showActions: (message, key, items, reaction) {},
          onMessagesChanged: (_) {},
          child: Builder(builder: (context) {
            target = context;
            return const SizedBox.expand();
          })),
    ));
    var calls = 0;
    for (final isDelete in [false, true]) {
      Future<void> open(
              {Future<void> Function()? execute, bool Function()? eligible}) =>
          confirmMessageAction(target,
              messageId: 'target',
              isDelete: isDelete,
              isEligible: eligible ?? () => true,
              execute: execute ??
                  () async {
                    calls++;
                  });
      final canceled = open();
      await tester.pumpAndSettle();
      final content = isDelete ? '删除的消息将从你的会话记录中消失，但仍对会话对象可见。' : '发送失败，重发该消息？';
      expect(find.text(content, findRichText: true), findsOneWidget);
      expect(find.text('弹窗标题'), findsNothing);
      expect(find.byType(VerticalDivider), findsOneWidget);
      final id = 'tim.message.${isDelete ? 'delete' : 'retry'}.confirm';
      Finder control(String suffix) => find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.identifier == '$id.$suffix');
      final material = find
          .ancestor(of: control('content'), matching: find.byType(Material))
          .first;
      expect(tester.getSize(material).width, 342);
      expect(tester.getSize(material).height, isDelete ? 144 : 120);
      await tester.tap(control('cancel'));
      await tester.pumpAndSettle();
      await canceled;
      expect(calls, isDelete ? 1 : 0);
      final gate = Completer<void>();
      Future<void> execute() async {
        calls++;
        await gate.future;
      }

      final first = open(execute: execute);
      final duplicate = open(execute: execute);
      await tester.pumpAndSettle();
      expect(control('content'), findsOneWidget);
      await tester.tap(control('confirm'));
      await tester.pumpAndSettle();
      expect(calls, isDelete ? 2 : 1);
      gate.complete();
      await Future.wait([first, duplicate]);
    }
    var eligible = true;
    final stale = confirmMessageAction(target,
        messageId: 'stale',
        isDelete: false,
        isEligible: () => eligible,
        execute: () async {
          calls++;
        });
    await tester.pumpAndSettle();
    eligible = false;
    await tester.tap(find.byWidgetPredicate((w) =>
        w is Semantics &&
        w.properties.identifier == 'tim.message.retry.confirm.confirm'));
    await tester.pumpAndSettle();
    await stale;
    expect(calls, 2);
    // 执行失败也必须释放相同消息的守卫，下一次点击能够重新确认。
    for (final fail in [true, false]) {
      final retry = confirmMessageAction(target,
          messageId: 'failure-release',
          isDelete: false,
          isEligible: () => true,
          execute: () async {
            calls++;
            if (fail) throw StateError('模拟发送失败');
          });
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate((w) =>
          w is Semantics &&
          w.properties.identifier == 'tim.message.retry.confirm.confirm'));
      await tester.pumpAndSettle();
      await retry;
    }
    expect(calls, 4);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.takeException(), isNull);
  });
}
