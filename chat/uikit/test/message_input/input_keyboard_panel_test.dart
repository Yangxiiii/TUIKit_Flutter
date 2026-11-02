import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_input/input_keyboard_panel.dart';

void main() {
  testWidgets('快速往返切换取消迟到hide，尺寸稳定后接受较矮的输入法', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final focus = FocusNode();
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return Scaffold(body: TextField(focusNode: focus));
    })));
    focus.requestFocus();
    await tester.pump();
    var changes = 0;
    final panel =
        InputKeyboardPanel(view: View.of(context), onChanged: () => changes++);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();
    tester.testTextInput.log.clear();
    panel.showEmoji(focus);
    panel.showSystem(focus);
    await tester.pump();
    expect(
        tester.testTextInput.log.any((call) => call.method == 'TextInput.hide'),
        isFalse);
    expect(
        tester.testTextInput.log.any((call) => call.method == 'TextInput.show'),
        isTrue);
    panel.showEmoji(focus);
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pump();
    expect(panel.height, 320);
    expect(panel.remainingHeight, 320);
    panel.showSystem(focus);
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump(const Duration(milliseconds: 16));
    expect(panel.remainingHeight, 80);
    await tester.pump(const Duration(milliseconds: 100));
    expect(panel.hasReservedSpace, isFalse);
    expect(panel.height, 240);
    expect(changes, greaterThan(0));
    panel.dispose();
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
    tester.view.resetViewInsets();
    expect(tester.takeException(), isNull);
  });

  testWidgets('销毁后取消尺寸延迟和显示请求，不影响下一个页面的输入', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final focus = FocusNode();
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return Scaffold(body: TextField(focusNode: focus));
    })));
    focus.requestFocus();
    await tester.pump();
    var changes = 0;
    final panel =
        InputKeyboardPanel(view: View.of(context), onChanged: () => changes++);
    panel.showEmoji(focus);
    tester.view.viewInsets = const FakeViewPadding(bottom: 100);
    panel.showSystem(focus);
    final original = changes;
    tester.testTextInput.log.clear();
    panel.dispose();
    await tester.pump(const Duration(milliseconds: 150));
    expect(changes, original);
    expect(
        tester.testTextInput.log.where((call) =>
            call.method == 'TextInput.show' || call.method == 'TextInput.hide'),
        isEmpty);
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
    tester.view.resetViewInsets();
    expect(tester.takeException(), isNull);
  });
}
