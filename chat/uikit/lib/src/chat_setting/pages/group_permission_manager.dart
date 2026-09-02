import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/cupertino.dart';

enum GroupPermission {
  setGroupName,
  setGroupAvatar,
  sendMessage,
  setDoNotDisturb,
  pinGroup,
  setGroupNotice,
  setGroupManagement,
  getGroupType,
  setJoinGroupApprovalType,
  setInviteToGroupApprovalType,
  setGroupRemark,
  setBackground,
  getGroupMemberList,
  setGroupMemberRole,
  getGroupMemberInfo,
  removeGroupMember,
  addGroupMember,
  clearHistoryMessages,
  deleteAndQuit,
  transferOwner,
  dismissGroup,
  reportGroup,
}

class GroupPermissionManager {
  static const Map<GroupType, Map<GroupMemberRole, Map<GroupPermission, bool>>>
      _permissionMatrix = {
    GroupType.work: {
      GroupMemberRole.owner: {
        GroupPermission.setGroupName: true,
        GroupPermission.setGroupAvatar: true,
        GroupPermission.sendMessage: true,
        GroupPermission.setDoNotDisturb: true,
        GroupPermission.pinGroup: true,
        GroupPermission.setGroupNotice: true,
        GroupPermission.setGroupManagement: true,
        GroupPermission.getGroupType: true,
        GroupPermission.setJoinGroupApprovalType: true,
        GroupPermission.setInviteToGroupApprovalType: true,
        GroupPermission.setGroupRemark: true,
        GroupPermission.setBackground: true,
        GroupPermission.getGroupMemberList: true,
        GroupPermission.setGroupMemberRole:
            false, // no admin role in work group
        GroupPermission.getGroupMemberInfo: true,
        GroupPermission.removeGroupMember: true,
        GroupPermission.addGroupMember: true,
        GroupPermission.clearHistoryMessages: true,
        GroupPermission.deleteAndQuit: true,
        GroupPermission.transferOwner: true,
        GroupPermission.dismissGroup: false,
        GroupPermission.reportGroup: true,
      },
      GroupMemberRole.admin: {
        GroupPermission.setGroupName: false,
        GroupPermission.setGroupAvatar: false,
        GroupPermission.sendMessage: true,
        GroupPermission.setDoNotDisturb: true,
        GroupPermission.pinGroup: true,
        GroupPermission.setGroupNotice: false,
        GroupPermission.setGroupManagement: false,
        GroupPermission.getGroupType: true,
        GroupPermission.setJoinGroupApprovalType: true,
        GroupPermission.setInviteToGroupApprovalType: false,
        GroupPermission.setGroupRemark: true,
        GroupPermission.setBackground: true,
        GroupPermission.getGroupMemberList: true,
        GroupPermission.setGroupMemberRole: false,
        GroupPermission.getGroupMemberInfo: true,
        GroupPermission.removeGroupMember: false,
        GroupPermission.addGroupMember: true,
        GroupPermission.clearHistoryMessages: true,
        GroupPermission.deleteAndQuit: true,
        GroupPermission.transferOwner: false,
        GroupPermission.dismissGroup: false,
        GroupPermission.reportGroup: true,
      },
      GroupMemberRole.member: {
        GroupPermission.setGroupName: false,
        GroupPermission.setGroupAvatar: false,
        GroupPermission.sendMessage: true,
        GroupPermission.setDoNotDisturb: true,
        GroupPermission.pinGroup: true,
        GroupPermission.setGroupNotice: false,
        GroupPermission.setGroupManagement: false,
        GroupPermission.getGroupType: true,
        GroupPermission.setJoinGroupApprovalType: false,
        GroupPermission.setInviteToGroupApprovalType: false,
        GroupPermission.setGroupRemark: true,
        GroupPermission.setBackground: true,
        GroupPermission.getGroupMemberList: true,
        GroupPermission.setGroupMemberRole: false,
        GroupPermission.getGroupMemberInfo: true,
        GroupPermission.removeGroupMember: false,
        GroupPermission.addGroupMember: true,
        GroupPermission.clearHistoryMessages: true,
        GroupPermission.deleteAndQuit: true,
        GroupPermission.transferOwner: false,
        GroupPermission.dismissGroup: false,
        GroupPermission.reportGroup: true,
      },
    },
    GroupType.publicGroup: {
      GroupMemberRole.owner: {
        GroupPermission.setGroupName: true,
        GroupPermission.setGroupAvatar: true,
        GroupPermission.sendMessage: true,
        GroupPermission.setDoNotDisturb: true,
        GroupPermission.pinGroup: true,
        GroupPermission.setGroupNotice: true,
        GroupPermission.setGroupManagement: true,
        GroupPermission.getGroupType: true,
        GroupPermission.setJoinGroupApprovalType: true,
        GroupPermission.setInviteToGroupApprovalType: true,
        GroupPermission.setGroupRemark: true,
        GroupPermission.setBackground: true,
        GroupPermission.getGroupMemberList: true,
        GroupPermission.setGroupMemberRole: true, // Only owner can set roles
        GroupPermission.getGroupMemberInfo: true,
        GroupPermission.removeGroupMember: true,
        GroupPermission.addGroupMember: true,
        GroupPermission.clearHistoryMessages: true,
        GroupPermission.deleteAndQuit:
            false, // Owner cannot quit, must transfer ownership first
        GroupPermission.transferOwner: true,
        GroupPermission.dismissGroup: true,
        GroupPermission.reportGroup: true,
      },
      GroupMemberRole.admin: {
        GroupPermission.setGroupName: false,
        GroupPermission.setGroupAvatar: false,
        GroupPermission.sendMessage: true,
        GroupPermission.setDoNotDisturb: true,
        GroupPermission.pinGroup: true,
        GroupPermission.setGroupNotice: true,
        GroupPermission.setGroupManagement: true,
        GroupPermission.getGroupType: true,
        GroupPermission.setJoinGroupApprovalType: true,
        GroupPermission.setInviteToGroupApprovalType: true,
        GroupPermission.setGroupRemark: true,
        GroupPermission.setBackground: true,
        GroupPermission.getGroupMemberList: true,
        GroupPermission.setGroupMemberRole: false, // Only owner can set roles
        GroupPermission.getGroupMemberInfo: true,
        GroupPermission.removeGroupMember: true,
        GroupPermission.addGroupMember: true,
        GroupPermission.clearHistoryMessages: true,
        GroupPermission.deleteAndQuit: true,
        GroupPermission.transferOwner: false,
        GroupPermission.dismissGroup: false,
        GroupPermission.reportGroup: true,
      },
      GroupMemberRole.member: {
        GroupPermission.setGroupName: false,
        GroupPermission.setGroupAvatar: false,
        GroupPermission.sendMessage: true,
        GroupPermission.setDoNotDisturb: true,
        GroupPermission.pinGroup: true,
        GroupPermission.setGroupNotice: false,
        GroupPermission.setGroupManagement: false,
        GroupPermission.getGroupType: true,
        GroupPermission.setJoinGroupApprovalType: false,
        GroupPermission.setInviteToGroupApprovalType: false,
        GroupPermission.setGroupRemark: true,
        GroupPermission.setBackground: true,
        GroupPermission.getGroupMemberList: true,
        GroupPermission.setGroupMemberRole: false,
        GroupPermission.getGroupMemberInfo: true,
        GroupPermission.removeGroupMember: false,
        GroupPermission.addGroupMember: true,
        GroupPermission.clearHistoryMessages: true,
        GroupPermission.deleteAndQuit: true,
        GroupPermission.transferOwner: false,
        GroupPermission.dismissGroup: false,
        GroupPermission.reportGroup: true,
      },
    },
    GroupType.meeting: {
      GroupMemberRole.owner: {
        GroupPermission.setGroupName: true,
        GroupPermission.setGroupAvatar: true,
        GroupPermission.sendMessage: true,
        GroupPermission.setDoNotDisturb: false,
        GroupPermission.pinGroup: true,
        GroupPermission.setGroupNotice: true,
        GroupPermission.setGroupManagement: true,
        GroupPermission.getGroupType: true,
        GroupPermission.setJoinGroupApprovalType: false,
        GroupPermission.setInviteToGroupApprovalType: true,
        GroupPermission.setGroupRemark: true,
        GroupPermission.setBackground: true,
        GroupPermission.getGroupMemberList: true,
        GroupPermission.setGroupMemberRole: true, // Only owner can set roles
        GroupPermission.getGroupMemberInfo: true,
        GroupPermission.removeGroupMember: true,
        GroupPermission.addGroupMember: true,
        GroupPermission.clearHistoryMessages: true,
        GroupPermission.deleteAndQuit: false,
        GroupPermission.transferOwner: true,
        GroupPermission.dismissGroup: true,
        GroupPermission.reportGroup: true,
      },
      GroupMemberRole.admin: {
        GroupPermission.setGroupName: false,
        GroupPermission.setGroupAvatar: false,
        GroupPermission.sendMessage: true,
        GroupPermission.setDoNotDisturb: false,
        GroupPermission.pinGroup: true,
        GroupPermission.setGroupNotice: true,
        GroupPermission.setGroupManagement: true,
        GroupPermission.getGroupType: true,
        GroupPermission.setJoinGroupApprovalType: false,
        GroupPermission.setInviteToGroupApprovalType: true,
        GroupPermission.setGroupRemark: true,
        GroupPermission.setBackground: true,
        GroupPermission.getGroupMemberList: true,
        GroupPermission.setGroupMemberRole: false, // Only owner can set roles
        GroupPermission.getGroupMemberInfo: true,
        GroupPermission.removeGroupMember: true,
        GroupPermission.addGroupMember: true,
        GroupPermission.clearHistoryMessages: true,
        GroupPermission.deleteAndQuit: true,
        GroupPermission.transferOwner: false,
        GroupPermission.dismissGroup: false,
        GroupPermission.reportGroup: true,
      },
      GroupMemberRole.member: {
        GroupPermission.setGroupName: false,
        GroupPermission.setGroupAvatar: false,
        GroupPermission.sendMessage: true,
        GroupPermission.setDoNotDisturb: false,
        GroupPermission.pinGroup: true,
        GroupPermission.setGroupNotice: false,
        GroupPermission.setGroupManagement: false,
        GroupPermission.getGroupType: true,
        GroupPermission.setJoinGroupApprovalType: false,
        GroupPermission.setInviteToGroupApprovalType: false,
        GroupPermission.setGroupRemark: true,
        GroupPermission.setBackground: true,
        GroupPermission.getGroupMemberList: true,
        GroupPermission.setGroupMemberRole: false,
        GroupPermission.getGroupMemberInfo: true,
        GroupPermission.removeGroupMember: false,
        GroupPermission.addGroupMember: true,
        GroupPermission.clearHistoryMessages: true,
        GroupPermission.deleteAndQuit: true,
        GroupPermission.transferOwner: false,
        GroupPermission.dismissGroup: false,
        GroupPermission.reportGroup: true,
      },
    },
    GroupType.community: {
      GroupMemberRole.owner: {
        GroupPermission.setGroupName: true,
        GroupPermission.setGroupAvatar: true,
        GroupPermission.sendMessage: true,
        GroupPermission.setDoNotDisturb: true,
        GroupPermission.pinGroup: true,
        GroupPermission.setGroupNotice: true,
        GroupPermission.setGroupManagement: true,
        GroupPermission.getGroupType: true,
        GroupPermission.setJoinGroupApprovalType: true,
        GroupPermission.setInviteToGroupApprovalType: true,
        GroupPermission.setGroupRemark: true,
        GroupPermission.setBackground: true,
        GroupPermission.getGroupMemberList: true,
        GroupPermission.setGroupMemberRole: true,
        GroupPermission.getGroupMemberInfo: true,
        GroupPermission.removeGroupMember: true,
        GroupPermission.addGroupMember: true,
        GroupPermission.clearHistoryMessages: true,
        GroupPermission.deleteAndQuit: false,
        GroupPermission.transferOwner: true,
        GroupPermission.dismissGroup: true,
        GroupPermission.reportGroup: true,
      },
      GroupMemberRole.admin: {
        GroupPermission.setGroupName: false,
        GroupPermission.setGroupAvatar: false,
        GroupPermission.sendMessage: true,
        GroupPermission.setDoNotDisturb: true,
        GroupPermission.pinGroup: true,
        GroupPermission.setGroupNotice: true,
        GroupPermission.setGroupManagement: true,
        GroupPermission.getGroupType: true,
        GroupPermission.setJoinGroupApprovalType: true,
        GroupPermission.setInviteToGroupApprovalType: true,
        GroupPermission.setGroupRemark: true,
        GroupPermission.setBackground: true,
        GroupPermission.getGroupMemberList: true,
        GroupPermission.setGroupMemberRole: false, // Only owner can set roles
        GroupPermission.getGroupMemberInfo: true,
        GroupPermission.removeGroupMember: true,
        GroupPermission.addGroupMember: true,
        GroupPermission.clearHistoryMessages: true,
        GroupPermission.deleteAndQuit: true,
        GroupPermission.transferOwner: false,
        GroupPermission.dismissGroup: false,
        GroupPermission.reportGroup: true,
      },
      GroupMemberRole.member: {
        GroupPermission.setGroupName: false,
        GroupPermission.setGroupAvatar: false,
        GroupPermission.sendMessage: true,
        GroupPermission.setDoNotDisturb: true,
        GroupPermission.pinGroup: true,
        GroupPermission.setGroupNotice: false,
        GroupPermission.setGroupManagement: false,
        GroupPermission.getGroupType: true,
        GroupPermission.setJoinGroupApprovalType: false,
        GroupPermission.setInviteToGroupApprovalType: false,
        GroupPermission.setGroupRemark: true,
        GroupPermission.setBackground: true,
        GroupPermission.getGroupMemberList: true,
        GroupPermission.setGroupMemberRole: false,
        GroupPermission.getGroupMemberInfo: true,
        GroupPermission.removeGroupMember: false,
        GroupPermission.addGroupMember: true,
        GroupPermission.clearHistoryMessages: true,
        GroupPermission.deleteAndQuit: true,
        GroupPermission.transferOwner: false,
        GroupPermission.dismissGroup: false,
        GroupPermission.reportGroup: true,
      },
    },
    GroupType.avChatRoom: {
      GroupMemberRole.owner: {
        GroupPermission.setGroupName: true,
        GroupPermission.setGroupAvatar: true,
        GroupPermission.sendMessage: true,
        GroupPermission.setDoNotDisturb: true,
        GroupPermission.pinGroup: true,
        GroupPermission.setGroupNotice: true,
        GroupPermission.setGroupManagement: true,
        GroupPermission.getGroupType: true,
        GroupPermission.setJoinGroupApprovalType: false,
        GroupPermission.setInviteToGroupApprovalType: false,
        GroupPermission.setGroupRemark: true,
        GroupPermission.setBackground: true,
        GroupPermission.getGroupMemberList: false,
        GroupPermission.setGroupMemberRole: false,
        GroupPermission.getGroupMemberInfo: false,
        GroupPermission.removeGroupMember: false,
        GroupPermission.addGroupMember: false,
        GroupPermission.clearHistoryMessages: true,
        GroupPermission.deleteAndQuit: false,
        GroupPermission.transferOwner: false,
        GroupPermission.dismissGroup: true,
        GroupPermission.reportGroup: true,
      },
      GroupMemberRole.admin: {
        GroupPermission.setGroupName: false,
        GroupPermission.setGroupAvatar: false,
        GroupPermission.sendMessage: true,
        GroupPermission.setDoNotDisturb: true,
        GroupPermission.pinGroup: true,
        GroupPermission.setGroupNotice: false,
        GroupPermission.setGroupManagement: false,
        GroupPermission.getGroupType: true,
        GroupPermission.setJoinGroupApprovalType: false,
        GroupPermission.setInviteToGroupApprovalType: false,
        GroupPermission.setGroupRemark: true,
        GroupPermission.setBackground: true,
        GroupPermission.getGroupMemberList: false,
        GroupPermission.setGroupMemberRole: false,
        GroupPermission.getGroupMemberInfo: false,
        GroupPermission.removeGroupMember: false,
        GroupPermission.addGroupMember: false,
        GroupPermission.clearHistoryMessages: true,
        GroupPermission.deleteAndQuit: true,
        GroupPermission.transferOwner: false,
        GroupPermission.dismissGroup: false,
        GroupPermission.reportGroup: true,
      },
      GroupMemberRole.member: {
        GroupPermission.setGroupName: false,
        GroupPermission.setGroupAvatar: false,
        GroupPermission.sendMessage: true,
        GroupPermission.setDoNotDisturb: true,
        GroupPermission.pinGroup: true,
        GroupPermission.setGroupNotice: false,
        GroupPermission.setGroupManagement: false,
        GroupPermission.getGroupType: true,
        GroupPermission.setJoinGroupApprovalType: false,
        GroupPermission.setInviteToGroupApprovalType: false,
        GroupPermission.setGroupRemark: true,
        GroupPermission.setBackground: true,
        GroupPermission.getGroupMemberList: false,
        GroupPermission.setGroupMemberRole: false,
        GroupPermission.getGroupMemberInfo: false,
        GroupPermission.removeGroupMember: false,
        GroupPermission.addGroupMember: false,
        GroupPermission.clearHistoryMessages: true,
        GroupPermission.deleteAndQuit: true,
        GroupPermission.transferOwner: false,
        GroupPermission.dismissGroup: false,
        GroupPermission.reportGroup: true,
      },
    },
  };

  // MARK: - Public Methods
  //
  // 标记: - 公共方法

  static bool hasPermission({
    required GroupType groupType,
    required GroupMemberRole memberRole,
    required GroupPermission permission,
  }) {
    return _permissionMatrix[groupType]?[memberRole]?[permission] ?? false;
  }

  static List<GroupPermission> getAvailablePermissions({
    required GroupType groupType,
    required GroupMemberRole memberRole,
  }) {
    final rolePermissions = _permissionMatrix[groupType]?[memberRole];
    if (rolePermissions == null) return [];

    return rolePermissions.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
  }

  static bool canPerformAction({
    required GroupType groupType,
    required GroupMemberRole memberRole,
    required GroupPermission action,
  }) {
    return hasPermission(
      groupType: groupType,
      memberRole: memberRole,
      permission: action,
    );
  }

  static String getGroupTypeDescription(
      GroupType groupType, BuildContext context) {
    AppLocalizedText atomicLocale = AppLocalization.of(context);
    switch (groupType) {
      case GroupType.work:
        return atomicLocale.groupWork;
      case GroupType.publicGroup:
        return atomicLocale.groupPublic;
      case GroupType.meeting:
        return atomicLocale.groupMeeting;
      case GroupType.community:
        return atomicLocale.groupCommunity;
      case GroupType.avChatRoom:
        return atomicLocale.groupAVChatRoom;
      default:
        return atomicLocale.groupWork;
    }
  }

  static String getMemberRoleDescription(
      GroupMemberRole role, BuildContext context) {
    AppLocalizedText atomicLocale = AppLocalization.of(context);
    switch (role) {
      case GroupMemberRole.owner:
        return atomicLocale.groupOwner;
      case GroupMemberRole.admin:
        return atomicLocale.admin;
      case GroupMemberRole.member:
        return atomicLocale.groupMember;
      default:
        return atomicLocale.groupMember;
    }
  }
}
