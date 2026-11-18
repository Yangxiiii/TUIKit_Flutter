import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/manager/call_duration_limit.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/hint/timer_widget.dart';

void main() {
  test('单聊及群通话本端接通满一小时后结束，同一通话并发更新只执行一次', () async {
    final pending = Completer<void>();
    var calls = 0;
    final limit = CallDurationLimit(onLimit: () {
      calls++;
      return pending.future;
    });
    await limit.update(callId: 'a', seconds: 3599, connected: true);
    await limit.update(callId: 'a', seconds: 3600, connected: false);
    expect(calls, 0);
    final ending = limit.update(callId: 'a', seconds: 3600, connected: true);
    await limit.update(callId: 'a', seconds: 3601, connected: true);
    expect(calls, 1);
    pending.complete();
    await ending;
    await limit.update(callId: 'a', seconds: 3602, connected: true);
    expect(calls, 1);
    await limit.update(callId: 'b', seconds: 3600, connected: true);
    expect(calls, 2);
  });

  test('结束失败向上传递且可重试，登出清理后不保留旧通话', () async {
    var calls = 0;
    final limit = CallDurationLimit(onLimit: () async {
      calls++;
      if (calls == 1) throw StateError('hangup failed');
    });
    await expectLater(limit.update(callId: 'a', seconds: 3600, connected: true),
        throwsStateError);
    expect(limit.isEnding('a'), isFalse);
    await limit.update(callId: 'a', seconds: 3601, connected: true);
    expect(limit.isEnding('a'), isTrue);
    limit.reset();
    expect(limit.isEnding('a'), isFalse);
    expect(calls, 2);
  });

  test('晚加入使用房间绝对截止，交接和重入不能重新计满一小时', () async {
    var now = DateTime.utc(2026, 11, 17);
    final deadline = now.add(const Duration(hours: 1)).millisecondsSinceEpoch;
    now = now.add(const Duration(minutes: 50));
    var elapsed = Duration.zero;
    var calls = 0;
    final limit = CallDurationLimit(
        onLimit: () async => calls++, now: () => now, elapsed: () => elapsed);
    await limit.update(
        callId: 'room',
        seconds: 0,
        connected: true,
        deadlineMs: deadline,
        sessionId: 'late');
    now = now.add(const Duration(minutes: 10));
    elapsed = const Duration(minutes: 10);
    await limit.update(
        callId: 'room',
        seconds: 600,
        connected: true,
        deadlineMs: deadline,
        sessionId: 'late');
    expect(calls, 1);
    await limit.update(
        callId: 'room',
        seconds: 0,
        connected: true,
        deadlineMs: deadline,
        sessionId: 'reentered');
    expect(calls, 2);
  });

  test('系统时钟回退及较晚截止同步不能扩大已有单调预算', () async {
    var now = DateTime.utc(2026, 11, 17);
    final deadline =
        now.add(const Duration(minutes: 10)).millisecondsSinceEpoch;
    var elapsed = Duration.zero;
    var calls = 0;
    final limit = CallDurationLimit(
        onLimit: () async => calls++, now: () => now, elapsed: () => elapsed);
    await limit.update(
        callId: 'room', seconds: 0, connected: true, deadlineMs: deadline);
    now = now.subtract(const Duration(hours: 3));
    elapsed = const Duration(minutes: 9);
    await limit.update(
        callId: 'room',
        seconds: 540,
        connected: true,
        deadlineMs: deadline + 3600000);
    expect(calls, 0);
    elapsed = const Duration(minutes: 10);
    await limit.update(
        callId: 'room', seconds: 600, connected: true, deadlineMs: deadline);
    expect(calls, 1);
  });

  test('计时保留累计分钟与输入下界', () {
    const timer = TimerWidget();
    expect(timer.formatDuration(-1), '00:00');
    expect(timer.formatDuration(3), '00:03');
    expect(timer.formatDuration(599), '09:59');
    expect(timer.formatDuration(3600), '60:00');
    expect(timer.formatDuration(3600, showHours: true), '01:00:00');
  });
}
