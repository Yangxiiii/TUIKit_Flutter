import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/view/callview/core/common/widget/controls_button.dart';

void main() {
  testWidgets('通话按钮标识保留点击动作、读屏说明和 72 像素圆形画面', (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: ControlsButton(
      icon: AppIcons.micOn,
      tips: '麦克风已开',
      semanticsIdentifier: 'call.microphone',
      backgroundColor: Colors.white,
      imgColor: Colors.black,
      textColor: Colors.black,
      onTap: () => taps++,
    ))));
    final target = find.bySemanticsIdentifier('call.microphone');
    expect(target, findsOneWidget);
    expect(
        tester
            .getSemantics(target)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue);
    expect(
        tester.getSize(find
            .ancestor(
                of: find.byIcon(AppIcons.micOn),
                matching: find.byType(SizedBox))
            .first),
        const Size(72, 72));
    await tester.tap(target);
    expect(taps, 1);
    semantics.dispose();
  });
}
