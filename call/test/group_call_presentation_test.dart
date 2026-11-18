import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_presentation.dart';

void main() {
  test('等待阶段空ID在同场补齐后保留操作，旧浮层与新场次均拒绝', () {
    bool matches({int epoch = 7, String id = '', bool current = true}) =>
        isCurrentGroupCallPresentation(
            capturedEpoch: 7,
            currentEpoch: epoch,
            capturedCallId: '',
            currentCallId: id,
            presentationIsCurrent: current);
    expect(matches(), isTrue);
    expect(matches(id: 'assigned'), isTrue);
    expect(matches(epoch: 8, id: 'new'), isFalse);
    expect(matches(id: 'assigned', current: false), isFalse);
  });

  test('已知ID的弹层不能接受同代次其他ID或已清空通话', () {
    for (final id in ['', 'another']) {
      expect(
          isCurrentGroupCallPresentation(
              capturedEpoch: 7,
              currentEpoch: 7,
              capturedCallId: 'assigned',
              currentCallId: id,
              presentationIsCurrent: true),
          isFalse);
    }
  });
}
