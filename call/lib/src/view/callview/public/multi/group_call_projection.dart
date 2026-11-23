import 'package:atomic_x_core/atomicxcore.dart';
import 'package:tencent_calls_uikit/src/state/group_call_snapshot.dart'
    as session;

import 'group_call_member.dart';

/// 将邀请历史和实时媒体事实合并成只读画面资料，不另建 SDK 生命周期。
List<GroupCallMember> projectGroupCallMembers({
  required session.GroupCallSnapshot? snapshot,
  required CallInfo call,
  required CallParticipantInfo self,
  required List<CallParticipantInfo> participants,
  required bool microphoneOn,
  required bool cameraOn,
  required Map<String, int> volumes,
  String Function(String id, String? nickname, String? fallback)? resolveName,
}) {
  final live = {for (final member in participants) member.id: member};
  if (self.id.isNotEmpty) live[self.id] = self;
  final history = {
    for (final member in snapshot?.members ?? <session.GroupCallMember>[])
      member.id: member,
  };
  final ids = {
    if (self.id.isNotEmpty) self.id,
    ...history.keys,
    ...live.keys,
  }.where((id) => id.isNotEmpty);
  final ended = snapshot?.ended ?? false;
  final members = ids.map((id) {
    final current = live[id];
    final previous = history[id];
    final name =
        resolveName?.call(id, current?.name, previous?.name) ??
        (current?.name.isNotEmpty == true
            ? current!.name
            : previous?.name.isNotEmpty == true
            ? previous!.name
            : id);
    var status = previous == null
        ? GroupCallMemberStatus.waiting
        : GroupCallMemberStatus.values.byName(previous.status.name);
    // 主叫本人已在本地准备画面，这不等同于对方接通，也不启动通话时长。
    if (!ended &&
        (current?.status == CallParticipantStatus.accept ||
            (id == self.id &&
                call.inviterId == self.id &&
                self.status != CallParticipantStatus.none))) {
      status = GroupCallMemberStatus.joined;
    }
    return GroupCallMember(
      id: id,
      name: name,
      subtitle: snapshot?.subtitleById[id] ?? '',
      avatarUrl: current?.avatarURL.isNotEmpty == true
          ? current!.avatarURL
          : previous?.avatarURL ?? '',
      status: status,
      joinedOrder: previous?.joinOrder ?? 0,
      microphoneOn:
          !ended &&
          (id == self.id ? microphoneOn : current?.isMicrophoneOpened ?? false),
      cameraOn:
          !ended &&
          (id == self.id ? cameraOn : current?.isCameraOpened ?? false),
      volume: ended ? 0 : volumes[id] ?? 0,
    );
  }).toList();
  // 已加入成员前移；分组内保留本场邀请顺序，不用排序伪造加入事件。
  return [
    ...members.where((member) => member.joined),
    ...members.where((member) => !member.joined),
  ];
}
