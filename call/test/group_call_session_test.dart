import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/state/group_call_snapshot.dart';
import 'package:tuikit_atomic_x/atomicx.dart';
import 'support/call_fakes.dart';

void main() {
  late GroupCallSession session;
  setUp(() {
    session = GroupCallSession()
      ..begin(
          callId: 'first',
          groupId: 'group',
          groupName: '研发',
          inviterId: 'self',
          mediaType: CallMediaType.audio,
          memberIds: ['self', 'a', 'b', 'a', '']);
  });
  tearDown(() => session.dispose());

  test('成员拒绝或离开后保留资料；重复邀请只恢复该成员的等待状态', () {
    session
        .sync(FakeCallInfo(callId: 'first', mediaType: CallMediaType.audio), [
      FakeParticipant('a',
          name: '成员甲', avatarURL: 'https://example.test/a.png'),
    ]);
    session.updateMember('a', GroupCallMemberStatus.rejected);
    session.sync(
        FakeCallInfo(callId: 'first', mediaType: CallMediaType.audio), []);
    expect(session.value!.members.length, 3);
    final member =
        session.value!.members.singleWhere((member) => member.id == 'a');
    expect(member.status, GroupCallMemberStatus.rejected);
    expect(member.name, '成员甲');
    session.updateMember('a', GroupCallMemberStatus.waiting);
    expect(
        session.value!.members.singleWhere((member) => member.id == 'a').status,
        GroupCallMemberStatus.waiting);
  });

  test('加入序号只由真实事件递增，资料列表、重复事件及重入保持正确边界', () {
    final call = FakeCallInfo(callId: 'first', mediaType: CallMediaType.audio);
    session.sync(
        call, [FakeParticipant('a', status: CallParticipantStatus.accept)]);
    expect(session.value!.members.singleWhere((m) => m.id == 'a').joinOrder, 0);
    session.updateMember('a', GroupCallMemberStatus.joined);
    session.updateMember('a', GroupCallMemberStatus.joined);
    expect(session.value!.members.singleWhere((m) => m.id == 'a').joinOrder, 1);
    session.updateMember('b', GroupCallMemberStatus.joined);
    session.updateMember('a', GroupCallMemberStatus.left);
    session.sync(
        call, [FakeParticipant('a', status: CallParticipantStatus.accept)]);
    session.updateMember('a', GroupCallMemberStatus.joined);
    expect(session.value!.members.singleWhere((m) => m.id == 'a').joinOrder, 3);
    session.end('first', CallEndReason.noResponse, isCaller: true);
    expect(session.value!.canRetry, isFalse);
  });

  test('SDK 全员未接结束后冻结快照，只允许原主叫重新发起', () {
    session.end('first', CallEndReason.noResponse, isCaller: true);
    expect(session.value!.ended, isTrue);
    expect(session.value!.canRetry, isTrue);
    expect(
        session.value!.members
            .where((m) => m.status == GroupCallMemberStatus.noResponse)
            .length,
        2);
    final frozen = session.value;
    session.updateMember('a', GroupCallMemberStatus.joined);
    session.sync(
        FakeCallInfo(
            callId: 'first', mediaType: CallMediaType.audio, startTime: 123),
        []);
    expect(session.value, same(frozen));
  });

  test('接通过、非主叫和其他场次的结束都不能生成重呼结果', () {
    session.end('old', CallEndReason.noResponse, isCaller: true);
    expect(session.value!.ended, isFalse);
    session.sync(
        FakeCallInfo(
            callId: 'first', mediaType: CallMediaType.audio, startTime: 123),
        []);
    session.end('first', CallEndReason.noResponse, isCaller: true);
    expect(session.value!.canRetry, isFalse);
    session.begin(
        callId: 'next',
        groupId: '',
        groupName: '',
        inviterId: 'other',
        mediaType: CallMediaType.video,
        memberIds: ['self', 'other']);
    session.end('next', CallEndReason.noResponse, isCaller: false);
    expect(session.value!.canRetry, isFalse);
  });

  test('旧场资料及空 SDK 状态不能污染新场次，清理后不再接受旧成员事件', () {
    final initial = session.value;
    session.sync(FakeCallInfo(callId: 'old', mediaType: CallMediaType.video),
        [FakeParticipant('stranger')]);
    session.sync(FakeCallInfo(), []);
    expect(session.value, same(initial));
    session.clear();
    session.updateMember('a', GroupCallMemberStatus.joined);
    expect(session.value, isNull);
  });
}
