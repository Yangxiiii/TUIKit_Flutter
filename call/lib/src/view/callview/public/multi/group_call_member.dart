/// 群通话展示状态，由SDK事件和当前场次邀请快照投影，不自行驱动信令。
enum GroupCallMemberStatus {
  waiting,
  joined,
  rejected,
  noResponse,
  busy,
  left,
  canceled
}

/// 成员卡与管理列表共用的不可变展示资料，不保存第二套可变通话状态。
class GroupCallMember {
  const GroupCallMember({
    required this.id,
    required this.name,
    this.avatarUrl = '',
    this.subtitle = '',
    required this.status,
    this.microphoneOn = false,
    this.cameraOn = false,
    this.volume = 0,
    this.joinedOrder = 0,
    this.invitedOrder = 0,
  });

  /// 腾讯用户标识，也是视频纹理与可访问控件的稳定标识。
  final String id;

  /// 经SDK资料解析后的展示姓名，不从未知自定义字段拼接职务。
  final String name;

  /// 与消息列表共用的实际头像地址。
  final String avatarUrl;

  /// 有可信机构和岗位资料时展示，缺失则为空。
  final String subtitle;

  /// 当前场次内的个人邀请结果。
  final GroupCallMemberStatus status;

  /// 本端来自DeviceStore，远端来自SDK音频可用事件。
  final bool microphoneOn;

  /// 本端来自DeviceStore，远端来自SDK视频可用事件。
  final bool cameraOn;

  /// SDK上报的实际音量，展示时限制在0至100。
  final int volume;

  /// 当前场次实际加入顺序，用于管理页倒序，未知时为0。
  final int joinedOrder;

  /// 当前场次邀请顺序，用于未加入分组倒序，未知时为0。
  final int invitedOrder;

  /// 只有在场成员可以切换大画面和操作本人设备。
  bool get joined => status == GroupCallMemberStatus.joined;

  /// 终态成员允许在仍有效的场次内重新邀请，等待中不得重复发信令。
  bool get canRetry => switch (status) {
        GroupCallMemberStatus.rejected ||
        GroupCallMemberStatus.noResponse ||
        GroupCallMemberStatus.busy ||
        GroupCallMemberStatus.left ||
        GroupCallMemberStatus.canceled =>
          true,
        _ => false,
      };

  /// 显示真实邀请结果，不由本地等待时间推断超时。
  String get statusLabel => switch (status) {
        GroupCallMemberStatus.waiting => '呼叫中',
        GroupCallMemberStatus.joined => '已加入',
        GroupCallMemberStatus.rejected => '已拒绝',
        GroupCallMemberStatus.noResponse => '已超时',
        GroupCallMemberStatus.busy => '忙线',
        GroupCallMemberStatus.left => '已离开',
        GroupCallMemberStatus.canceled => '已取消',
      };
}
