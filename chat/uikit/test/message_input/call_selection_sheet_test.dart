import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_input/widget/call_selection_sheet.dart';

void main() {
  testWidgets('通话选择标题左对齐、两项48高且保留独立取消和三个分隔', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeFactory.create(
          const AppNormalColorScheme(), Brightness.light),
      home: const Scaffold(
          body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                  width: 390, child: CallSelectionSheet(name: '杨洋阳（一只羊）')))),
    ));
    final semantics = tester.ensureSemantics();
    expect(find.text('呼叫杨洋阳（一只羊）'), findsOneWidget);
    expect(find.text('语音通话'), findsOneWidget);
    expect(find.text('视频通话'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存图片'), findsNothing);
    expect(tester.getTopLeft(find.text('呼叫杨洋阳（一只羊）')).dx,
        tester.getTopLeft(find.byType(CallSelectionSheet)).dx + 16);
    for (final id in ['audio', 'video', 'cancel']) {
      final target = find.bySemanticsIdentifier('call.select.$id');
      expect(
          tester
              .getSize(find
                  .ancestor(of: target, matching: find.byType(TextButton))
                  .first)
              .height,
          48);
      expect(
          tester
              .getSemantics(target)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue);
    }
    expect(find.byType(Divider), findsOneWidget);
    expect(
        find
            .byType(DecoratedBox)
            .evaluate()
            .where((e) =>
                (e.widget as DecoratedBox).decoration is BoxDecoration &&
                ((e.widget as DecoratedBox).decoration as BoxDecoration)
                        .border !=
                    null)
            .length,
        3);
    semantics.dispose();
  });

  testWidgets('选择语音或视频返回正确媒体类型，取消不发起呼叫', (tester) async {
    CallMediaType? result;
    Future<void> open() async {
      result = await AppDialog.showSheet<CallMediaType>(
          showCloseButton: false, child: const CallSelectionSheet(name: '对端'));
    }

    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [AppDialog.observer],
      builder: AppDialog.init(),
      home:
          Scaffold(body: TextButton(onPressed: open, child: const Text('打开'))),
    ));
    for (final (id, expected) in [
      ('audio', CallMediaType.audio),
      ('video', CallMediaType.video),
      ('cancel', null)
    ]) {
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('call.select.$id'));
      await tester.pumpAndSettle();
      expect(result, expected);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
