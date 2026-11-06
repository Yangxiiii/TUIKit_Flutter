import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart' hide AlertDialog;
import 'package:flutter_test/flutter_test.dart';
import 'package:tuikit_atomic_x/base_component/basic_controls/alert_dialog.dart';

void main() {
  testWidgets('SDK 确认框复用公共外观并保留取消结果及危险操作', (tester) async {
    late BuildContext page;
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeFactory.create(
          const AppNormalColorScheme(), Brightness.light),
      home: Builder(builder: (context) {
        page = context;
        return const SizedBox();
      }),
    ));
    var confirmed = 0;
    final result = AlertDialog.show(page,
        title: '退出',
        content: '确认退出？',
        cancelText: '取消',
        confirmText: '退出',
        isDestructive: true,
        onConfirm: () => confirmed++);
    await tester.pumpAndSettle();
    expect(find.byType(AppAlertDialog), findsOneWidget);
    expect(
        tester
            .widget<AppAlertDialog>(find.byType(AppAlertDialog))
            .confirmBackgroundColor,
        const AppNormalColorScheme().danger);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
    expect(confirmed, 0);
  });

  testWidgets('SDK 倒计时取消仍只触发一次，并清理已卸载组件', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeFactory.create(
          const AppNormalColorScheme(), Brightness.light),
      home: AtomicAlertDialog(
          config: AlertDialogConfig(
              title: '等待',
              countdownDuration: 2,
              cancelConfig:
                  ButtonConfig(text: '取消', onClick: () => cancelled++))),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('取消 (1)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(cancelled, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(cancelled, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
