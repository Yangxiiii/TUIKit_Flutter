import 'dart:ui' as ui;

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/float/call_compact_widget.dart';

void main() {
  testWidgets('语音小窗裁掉路由背景的黑角，卡片外仍绘制阴影', (tester) async {
    final captureKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: captureKey,
          child: ColoredBox(
            color: Colors.white,
            child: SizedBox.square(
              dimension: 200,
              child: Center(
                child: SizedBox.square(
                  dimension: CallCompactAudioContent.dimension,
                  child: CallCompactAudioSurface(
                    child: Navigator(
                      onGenerateRoute: (_) => PageRouteBuilder<void>(
                        pageBuilder: (_, __, ___) =>
                            const ColoredBox(color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 用黑色路由背景放大漏色，直接核对卡片内外的实际绘制像素。
    final boundary =
        captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = boundary.toImageSync();
    addTearDown(image.dispose);
    final data = (await tester
        .runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    int redAt(int x, int y) => data.getUint8((y * image.width + x) * 4);
    expect(redAt(100, 100), 0);
    for (final (x, y) in [(60, 60), (139, 60), (60, 139), (139, 139)]) {
      expect(redAt(x, y), greaterThan(200));
    }
    expect(redAt(100, 147), inInclusiveRange(200, 254));
    expect(redAt(10, 195), 255);
  });

  test('主叫振铃阶段没有呼叫标识也可以操作原浮窗', () {
    final self = _Participant('caller', CallParticipantStatus.waiting);

    bool matches(_Call call, {bool current = true, String expectedId = ''}) =>
        matchesFloatingCall(
          expectedId: expectedId,
          call: call,
          self: self,
          isCurrentPresentation: current,
        );

    expect(matches(_Call('')), isTrue);
    // 同一个浮层收到 SDK 补填的标识后，原来的操作仍然有效。
    expect(matches(_Call('sdk-id')), isTrue);
    expect(matches(_Call('sdk-id'), current: false), isFalse);
    expect(matches(_Call('new-id'), expectedId: 'old-id'), isFalse);
    expect(matches(_Call('', inviterId: 'peer')), isFalse);
    expect(matches(_Call('', mediaType: CallMediaType.video)), isFalse);
  });
}

class _Call extends Fake implements CallInfo {
  _Call(this.callId,
      {this.inviterId = 'caller', this.mediaType = CallMediaType.audio});

  @override
  final String callId;

  @override
  final String inviterId;

  @override
  final CallMediaType mediaType;

  @override
  String get chatGroupId => '';

  @override
  List<String> get inviteeIds => const ['peer'];
}

class _Participant extends Fake implements CallParticipantInfo {
  _Participant(this.id, this.status);

  @override
  final String id;

  @override
  final CallParticipantStatus status;
}
