import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'voice_video_android_preview.dart' as preview;

void main() {
  testWidgets('独立预览从本地菜单进入生产布局，不依赖腾讯登录或真实接口', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    preview.main();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('语音主叫等待'));
    await tester.pumpAndSettle();
    expect(find.text('正在呼叫...'), findsOneWidget);
    expect(find.bySemanticsIdentifier('call.microphone'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('call.microphone'));
    await tester.pump();
    expect(find.text('麦克风已关'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
