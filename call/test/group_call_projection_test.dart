import 'package:flutter_test/flutter_test.dart';
import 'package:tuikit_atomic_x/atomicx.dart';
import 'package:tencent_calls_uikit/src/state/group_call_snapshot.dart'
    as session;
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_projection.dart';

import 'support/call_fakes.dart';

/// 补全展示投影需要的媒体资料，不创建或登录 SDK。
class _MediaParticipant extends FakeParticipant {
  _MediaParticipant(super.id, {super.status});

  @override
  String get remark => '';

  @override
  bool get isMicrophoneOpened => false;

  @override
  bool get isCameraOpened => false;
}

void main() {
  test('机构岗位只映射本场真实资料，缺失留空且资料键不会新增成员', () {
    final snapshot = session.GroupCallSnapshot(
        callId: 'call',
        groupId: 'group',
        groupName: '群名',
        inviterId: 'self',
        mediaType: CallMediaType.video,
        members: const [
          session.GroupCallMember(
              id: 'invited',
              name: '李楠',
              status: session.GroupCallMemberStatus.waiting)
        ],
        subtitleById: const {
          'invited': '研发部 / 工程师',
          'unknown': '其他机构'
        });
    final result = projectGroupCallMembers(
        snapshot: snapshot,
        call: FakeCallInfo(callId: 'call'),
        self: _MediaParticipant('self'),
        participants: [_MediaParticipant('invited')],
        microphoneOn: true,
        cameraOn: false,
        volumes: const {});
    final invited = result.singleWhere((member) => member.id == 'invited');
    expect(invited.name, '李楠');
    expect(invited.subtitle, '研发部 / 工程师');
    expect(
        result.singleWhere((member) => member.id == 'self').subtitle, isEmpty);
    expect(result.map((member) => member.id), ['self', 'invited']);
  });

  test('后来接通成员移到等待成员之前，分组内邀请顺序与输入快照不变', () {
    final snapshot = session.GroupCallSnapshot(
        callId: 'call',
        groupId: 'group',
        groupName: '群名',
        inviterId: 'self',
        mediaType: CallMediaType.video,
        members: ['self', 'waiting', 'late', 'rejected']
            .map((id) => session.GroupCallMember(
                id: id,
                status: id == 'rejected'
                    ? session.GroupCallMemberStatus.rejected
                    : session.GroupCallMemberStatus.waiting))
            .toList());
    final result = projectGroupCallMembers(
        snapshot: snapshot,
        call: FakeCallInfo(callId: 'call'),
        self: _MediaParticipant('self'),
        participants: [
          _MediaParticipant('waiting'),
          _MediaParticipant('late', status: CallParticipantStatus.accept)
        ],
        microphoneOn: true,
        cameraOn: false,
        volumes: {'late': 60});
    expect(result.map((member) => member.id),
        ['self', 'late', 'waiting', 'rejected']);
    expect(result[1].volume, 60);
    expect(result[3].statusLabel, '已拒绝');
    expect(snapshot.members.map((member) => member.id),
        ['self', 'waiting', 'late', 'rejected']);
  });
}
