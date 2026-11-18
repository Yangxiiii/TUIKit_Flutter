import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/manager/group_call_result_tracker.dart';
import 'package:tencent_calls_uikit/src/state/group_call_snapshot.dart';

void main() {
  test('本人迟到接通、离开重入累计本人区间，重复结束不重复发布', () async {
    final session = GroupCallSession();
    var now = DateTime.utc(2026);
    final reports = <GroupCallResultReport>[];
    final tracker = GroupCallResultTracker(
      session: session,
      accountId: () => 'peer',
      now: () => now,
    )..setHandler((report) async => reports.add(report));
    void begin({String? attemptId}) => session.begin(
        callId: 'call',
        attemptId: attemptId,
        groupId: '',
        groupName: '',
        inviterId: 'caller',
        mediaType: CallMediaType.audio,
        memberIds: ['caller', 'peer', 'other']);
    begin(attemptId: 'attempt');
    session.updateMember('other', GroupCallMemberStatus.joined);
    now = now.add(const Duration(seconds: 20));
    session.updateMember('peer', GroupCallMemberStatus.joined);
    now = now.add(const Duration(seconds: 12));
    session.end('call', CallEndReason.hangup, isCaller: false);
    await tracker.onEnded('call', CallEndReason.hangup);
    await tracker.onEnded('call', CallEndReason.hangup);
    expect(reports.single.durationSeconds, 12);
    expect(reports.single.outcome, GroupCallResultOutcome.completed);
    now = now.add(const Duration(seconds: 50));
    begin();
    session.updateMember('peer', GroupCallMemberStatus.joined);
    now = now.add(const Duration(seconds: 8));
    session.end('call', CallEndReason.hangup, isCaller: false);
    await tracker.onEnded('call', CallEndReason.hangup);
    expect(reports.last.durationSeconds, 20);
    expect(reports.last.revision, 2);
    expect(reports.last.reporterId, 'peer');
    expect(reports.last.attemptId, 'attempt');
    tracker.dispose();
    session.dispose();
  });

  test('主叫等待不计时，首位被叫接通后累计，拒绝结果保持真实', () async {
    final session = GroupCallSession();
    var now = DateTime.utc(2026);
    final reports = <GroupCallResultReport>[];
    final tracker = GroupCallResultTracker(
      session: session,
      accountId: () => 'caller',
      now: () => now,
    )..setHandler((report) async => reports.add(report));
    session.begin(
        callId: 'call',
        groupId: 'group',
        groupName: '',
        inviterId: 'caller',
        mediaType: CallMediaType.video,
        memberIds: ['caller', 'peer', 'rejected']);
    now = now.add(const Duration(seconds: 40));
    session.updateMember('rejected', GroupCallMemberStatus.rejected);
    session.updateMember('peer', GroupCallMemberStatus.joined);
    now = now.add(const Duration(seconds: 15));
    session.end('call', CallEndReason.hangup, isCaller: true);
    await tracker.onEnded('call', CallEndReason.hangup);
    expect(reports.single.durationSeconds, 15);
    expect(reports.single.invitationResults['rejected'],
        GroupCallMemberStatus.rejected);
    expect(() => reports.single.participantIds.add('outsider'),
        throwsUnsupportedError);
    tracker.dispose();
    session.dispose();
  });

  test('未接通按SDK原因记录，切号后旧场次不能以新账号发布', () async {
    final session = GroupCallSession();
    var account = 'caller';
    final reports = <GroupCallResultReport>[];
    final tracker =
        GroupCallResultTracker(session: session, accountId: () => account)
          ..setHandler((report) async => reports.add(report));
    session.begin(
        callId: 'call',
        groupId: '',
        groupName: '',
        inviterId: 'caller',
        mediaType: CallMediaType.audio,
        memberIds: ['caller', 'peer']);
    session.end('call', CallEndReason.noResponse, isCaller: true);
    await tracker.onEnded('call', CallEndReason.noResponse);
    expect(reports.single.durationSeconds, 0);
    expect(reports.single.outcome, GroupCallResultOutcome.unanswered);
    account = 'peer';
    await tracker.onEnded('call', CallEndReason.noResponse);
    expect(reports, hasLength(1));
    account = 'caller';
    await tracker.onEnded('call', CallEndReason.noResponse);
    expect(reports, hasLength(1));
    session.begin(
        callId: 'new-call',
        groupId: '',
        groupName: '',
        inviterId: 'caller',
        mediaType: CallMediaType.audio,
        memberIds: ['caller', 'peer']);
    session.end('new-call', CallEndReason.noResponse, isCaller: true);
    await tracker.onEnded('new-call', CallEndReason.noResponse);
    expect(reports, hasLength(2));
    tracker.dispose();
    session.dispose();
  });
}
