import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/manager/group_call_recording.dart';

void main() {
  test('一次通话可保存多个片段，结束失败仍保留同一个片段 ID', () async {
    final start = DateTime.utc(2026, 11, 18);
    var now = start.add(const Duration(seconds: 80));
    final recording = GroupCallRecording(now: () => now);
    addTearDown(recording.dispose);
    final requests = <(String, int, String?)>[];
    var fail = false;
    recording.setHandler((callId, seconds, id) async {
      requests.add((callId, seconds, id));
      if (fail) throw StateError('保存失败');
      return id ?? 'record-${requests.length}';
    });
    Future<bool> toggle() => recording.toggle(
          callId: 'call',
          connectedAtMs: start.millisecondsSinceEpoch,
        );

    expect(await toggle(), isFalse);
    expect(recording.isRecording('call'), isTrue);
    now = start.add(const Duration(seconds: 225));
    fail = true;
    await expectLater(toggle(), throwsStateError);
    expect(recording.isRecording('call'), isTrue);
    fail = false;
    expect(await toggle(), isTrue);
    expect(recording.isRecording('call'), isFalse);
    now = start.add(const Duration(seconds: 250));
    await toggle();
    await recording.end('call');
    expect(requests, [
      ('call', 80, null),
      ('call', 225, 'record-1'),
      ('call', 225, 'record-1'),
      ('call', 250, null),
      ('call', 250, 'record-4'),
    ]);
  });

  test('开始回包晚于挂断时按已锁定的结束秒数收尾', () async {
    final start = DateTime.utc(2026, 11, 18);
    var now = start.add(const Duration(seconds: 80));
    final started = Completer<String>();
    final recording = GroupCallRecording(now: () => now);
    addTearDown(recording.dispose);
    final requests = <(String, int, String?)>[];
    recording.setHandler((callId, seconds, id) async {
      requests.add((callId, seconds, id));
      return id ?? await started.future;
    });
    final pending = recording.toggle(
      callId: 'old',
      connectedAtMs: start.millisecondsSinceEpoch,
    );
    expect(recording.isPending('old'), isTrue);
    expect(recording.isRecording('old'), isFalse);
    now = start.add(const Duration(seconds: 82));
    await recording.end('old');
    now = start.add(const Duration(seconds: 90));
    started.complete('saved');
    await pending;
    expect(recording.isRecording('old'), isFalse);
    expect(recording.isRecording('new'), isFalse);
    expect(requests, [('old', 80, null), ('old', 82, 'saved')]);
  });
}
