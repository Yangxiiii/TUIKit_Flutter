import 'package:flutter/foundation.dart';
import 'package:tuikit_atomic_x/atomicx.dart';

/// 来自 SDK 事件的邀请结果，结束记录仅供展示，不能代替有效通话。
enum GroupCallMemberStatus { waiting, joined, rejected, noResponse, busy, left }

/// 保留 SDK 移出实时成员列表后的展示资料与邀请结果。
@immutable
class GroupCallMember {
  const GroupCallMember(
      {required this.id,
      required this.status,
      this.name = '',
      this.avatarURL = '',
      this.joinOrder = 0});

  /// 腾讯用户 ID；同一场次按此字段去重。
  final String id;

  /// SDK 资料中的显示名称，空值由界面使用 ID 兜底。
  final String name;

  /// SDK 头像地址，不作为本地资源持久化。
  final String avatarURL;

  /// 最近一次真实成员事件；不由本地倒计时伪造超时。
  final GroupCallMemberStatus status;

  /// 本端收到真实加入事件的递增次序；零表示尚无该事件，不能推断跨端历史顺序。
  final int joinOrder;
}

/// 群及临时多人通话的只读展示快照，不持有媒体或 SDK 会话资源。
@immutable
class GroupCallSnapshot {
  GroupCallSnapshot(
      {required this.callId,
      required this.groupId,
      required this.groupName,
      required this.inviterId,
      required this.mediaType,
      required List<GroupCallMember> members,
      Map<String, String> subtitleById = const {},
      this.hasConnected = false,
      this.ended = false,
      this.canRetry = false})
      : members = List.unmodifiable(members),
        subtitleById = Map.unmodifiable(subtitleById);

  /// SDK 通话 ID；首次发起的等待阶段允许尚未分配。
  final String callId;

  /// 群来源 ID，独立多人通话为空。
  final String groupId;

  /// 宿主或腾讯群资料提供的真实群名称；尚未获取时为空。
  final String groupName;

  /// SDK 确认的发起人 ID。
  final String inviterId;

  /// 本场媒体类型，重呼使用相同选择发起新场次。
  final CallMediaType mediaType;

  /// 保持邀请顺序的成员快照，包含本人。
  final List<GroupCallMember> members;

  /// 宿主真实机构岗位资料，仅供显示；缺失时为空，不能作为角色或设备权限依据。
  final Map<String, String> subtitleById;

  /// 本端是否收到过真实接通确认。
  final bool hasConnected;

  /// SDK 已结束，仅允许展示结果及重新发起。
  final bool ended;

  /// 全场未接通结束且本端为原主叫时可重呼。
  final bool canRetry;
}

/// 根据 SDK 事件保留邀请结果；离开、拒接或超时不会删除成员的展示资料。
class GroupCallSession extends ValueNotifier<GroupCallSnapshot?> {
  GroupCallSession() : super(null);

  /// 新场次及清理递增，SDK 补填 callId 不改变此值，供迟到资料校验生命周期。
  int _generation = 0;

  /// 当前展示生命周期；不能用它替代腾讯场次 ID 或服务器入会资格。
  int get generation => _generation;

  /// 每场加入事件的本地顺序，重新发起后从零开始，不使用接口列表顺序代替。
  int _joinSequence = 0;

  /// 用真实加入/离开事件去重，避免资料列表先更新时丢失再次加入的次序。
  final Set<String> _joinedEventUsers = {};

  /// 新场次覆盖旧展示结果，参与者只接受非空且去重后的 ID。
  void begin(
      {required String callId,
      required String groupId,
      required String groupName,
      required String inviterId,
      required CallMediaType mediaType,
      required Iterable<String> memberIds}) {
    _generation++;
    _joinSequence = 0;
    _joinedEventUsers.clear();
    value = GroupCallSnapshot(
        callId: callId,
        groupId: groupId,
        groupName: groupName,
        inviterId: inviterId,
        mediaType: mediaType,
        members: memberIds
            .where((id) => id.isNotEmpty)
            .toSet()
            .map((id) =>
                GroupCallMember(id: id, status: GroupCallMemberStatus.waiting))
            .toList());
  }

  /// 实时状态只补齐本场资料；SDK 清理后的空场次不覆盖已结束的展示快照。
  void sync(CallInfo call, Iterable<CallParticipantInfo> participants) {
    final previous = value;
    if (previous == null ||
        previous.ended ||
        call.mediaType == null ||
        (previous.callId.isNotEmpty && call.callId != previous.callId)) {
      return;
    }
    // 资料更新补齐昵称与头像；被 SDK 移除的结果继续保留，列表顺序不等于加入顺序。
    final members = {for (final member in previous.members) member.id: member};
    for (final participant in participants) {
      if (participant.id.isEmpty) continue;
      final old = members[participant.id];
      members[participant.id] = GroupCallMember(
          id: participant.id,
          name: participant.name.isEmpty ? old?.name ?? '' : participant.name,
          avatarURL: participant.avatarURL.isEmpty
              ? old?.avatarURL ?? ''
              : participant.avatarURL,
          joinOrder: old?.joinOrder ?? 0,
          status: participant.status == CallParticipantStatus.accept
              ? GroupCallMemberStatus.joined
              : old?.status ?? GroupCallMemberStatus.waiting);
    }
    value = GroupCallSnapshot(
        callId: call.callId,
        groupId: previous.groupId,
        groupName: previous.groupName,
        inviterId: previous.inviterId,
        mediaType: call.mediaType!,
        members: members.values.toList(),
        subtitleById: previous.subtitleById,
        hasConnected: previous.hasConnected || call.startTime > 0);
  }

  /// 邀请或加入可新增成员，其余无 callId 回调只更新当前存续场次中已知的成员。
  void updateMember(String userId, GroupCallMemberStatus status) {
    final previous = value;
    if (previous == null || previous.ended || userId.isEmpty) return;
    final members = {for (final member in previous.members) member.id: member};
    final old = members[userId];
    if (old == null &&
        status != GroupCallMemberStatus.waiting &&
        status != GroupCallMemberStatus.joined) {
      return;
    }
    // 只依赖真实加入事件分配序号，重复事件不改变次序，离开后重入获得新序号。
    final isNewJoin =
        status == GroupCallMemberStatus.joined && _joinedEventUsers.add(userId);
    if (status != GroupCallMemberStatus.joined) {
      _joinedEventUsers.remove(userId);
    }
    members[userId] = GroupCallMember(
        id: userId,
        name: old?.name ?? '',
        avatarURL: old?.avatarURL ?? '',
        joinOrder: isNewJoin ? ++_joinSequence : old?.joinOrder ?? 0,
        status: status);
    value = GroupCallSnapshot(
        callId: previous.callId,
        groupId: previous.groupId,
        groupName: previous.groupName,
        inviterId: previous.inviterId,
        mediaType: previous.mediaType,
        members: members.values.toList(),
        subtitleById: previous.subtitleById,
        hasConnected:
            previous.hasConnected || status == GroupCallMemberStatus.joined);
  }

  /// 群名称只更新对应群的展示资料，不修改成员、媒体或权限。
  void updateGroupTitle(String groupId, String title) {
    final previous = value;
    if (previous == null ||
        previous.groupId != groupId ||
        previous.groupName == title) {
      return;
    }
    value = GroupCallSnapshot(
        callId: previous.callId,
        groupId: previous.groupId,
        groupName: title,
        inviterId: previous.inviterId,
        mediaType: previous.mediaType,
        members: previous.members,
        subtitleById: previous.subtitleById,
        hasConnected: previous.hasConnected,
        ended: previous.ended,
        canRetry: previous.canRetry);
  }

  /// 替换本场成员副标题，忽略未受邀用户和空白资料，不改写 SDK 姓名或权限。
  void updateMemberSubtitles(Map<String, String> subtitles) {
    final previous = value;
    if (previous == null) return;
    // 宿主可批量返回缓存资料，但本场仅接收已知成员的非空副标题。
    final memberIds = previous.members.map((member) => member.id).toSet();
    final accepted = <String, String>{
      for (final entry in subtitles.entries)
        if (memberIds.contains(entry.key) && entry.value.trim().isNotEmpty)
          entry.key: entry.value.trim(),
    };
    if (mapEquals(accepted, previous.subtitleById)) return;
    // 只替换展示字段，邀请结果、接通状态及重呼资格全部沿用 SDK 快照。
    value = GroupCallSnapshot(
        callId: previous.callId,
        groupId: previous.groupId,
        groupName: previous.groupName,
        inviterId: previous.inviterId,
        mediaType: previous.mediaType,
        members: previous.members,
        subtitleById: accepted,
        hasConnected: previous.hasConnected,
        ended: previous.ended,
        canRetry: previous.canRetry);
  }

  /// 结束事件冻结展示结果，等待中的成员只按 SDK 的结束原因收敛。
  void end(String callId, CallEndReason reason, {required bool isCaller}) {
    final previous = value;
    if (previous == null ||
        previous.ended ||
        (previous.callId.isNotEmpty && callId != previous.callId)) {
      return;
    }
    // 未接通结果仅由 SDK 结束原因收敛，本地没有振铃计时器或留房状态。
    final noAnswer =
        reason == CallEndReason.noResponse || reason == CallEndReason.offline;
    value = GroupCallSnapshot(
        callId: callId,
        groupId: previous.groupId,
        groupName: previous.groupName,
        inviterId: previous.inviterId,
        mediaType: previous.mediaType,
        subtitleById: previous.subtitleById,
        members: previous.members
            .map((member) => noAnswer &&
                    member.status == GroupCallMemberStatus.waiting &&
                    member.id != previous.inviterId
                ? GroupCallMember(
                    id: member.id,
                    name: member.name,
                    avatarURL: member.avatarURL,
                    joinOrder: member.joinOrder,
                    status: GroupCallMemberStatus.noResponse)
                : member)
            .toList(),
        hasConnected: previous.hasConnected,
        ended: true,
        canRetry: isCaller && !previous.hasConnected && noAnswer);
  }

  /// 新账号、新来电或用户关闭结果页后丢弃旧展示数据。
  void clear() {
    _generation++;
    value = null;
  }
}
