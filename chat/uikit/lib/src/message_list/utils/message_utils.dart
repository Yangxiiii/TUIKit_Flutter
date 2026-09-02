import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:tencent_chat_uikit/src/common/utils/uikit_util.dart';
import 'package:flutter/cupertino.dart';

import 'calling_message_data_provider.dart';

class MessageUtil {
  static String getSystemInfoDisplayString(
      List<GroupTipsInfo> groupTipsInfo, BuildContext context) {
    if (groupTipsInfo.isEmpty) {
      return '';
    }

    List<String> displayStrings = [];
    for (GroupTipsInfo groupTipsInfo in groupTipsInfo) {
      String displayString =
          getSingleSystemInfoDisplayString(groupTipsInfo, context);
      if (displayString.isNotEmpty) {
        displayStrings.add(displayString);
      }
    }

    return displayStrings.join(',');
  }

  static String getSingleSystemInfoDisplayString(
      GroupTipsInfo groupTipsInfo, BuildContext context) {
    return switch (groupTipsInfo) {
      Unknown() => AppLocalization.of(context).unknown,
      JoinGroup() => getJoinGroupDisplayString(groupTipsInfo, context),
      InviteToGroup() => getInviteToGroupDisplayString(groupTipsInfo, context),
      QuitGroup() => getQuitGroupDisplayString(groupTipsInfo, context),
      KickedFromGroup() =>
        getKickedFromGroupDisplayString(groupTipsInfo, context),
      SetGroupAdmin() => getSetGroupAdminDisplayString(groupTipsInfo, context),
      CancelGroupAdmin() =>
        getCancelGroupAdminDisplayString(groupTipsInfo, context),
      ChangeGroupName() =>
        getChangeGroupNameDisplayString(groupTipsInfo, context),
      ChangeGroupAvatar() =>
        getChangeGroupAvatarDisplayString(groupTipsInfo, context),
      ChangeGroupNotification() =>
        getChangeGroupNotificationDisplayString(groupTipsInfo, context),
      ChangeGroupIntroduction() =>
        getChangeGroupIntroductionDisplayString(groupTipsInfo, context),
      ChangeGroupOwner() =>
        getChangeGroupOwnerDisplayString(groupTipsInfo, context),
      ChangeGroupMuteAll() =>
        getChangeGroupMuteAllDisplayString(groupTipsInfo, context),
      ChangeJoinGroupApproval() =>
        getChangeJoinGroupApprovalDisplayString(groupTipsInfo, context),
      ChangeInviteToGroupApproval() =>
        getChangeInviteToGroupApprovalDisplayString(groupTipsInfo, context),
      MuteGroupMember() =>
        getMuteGroupMemberDisplayString(groupTipsInfo, context),
      PinGroupMessage() =>
        getPinGroupMessageDisplayString(groupTipsInfo, context),
      UnpinGroupMessage() =>
        getUnpinGroupMessageDisplayString(groupTipsInfo, context),
    };
  }

  /// Build revoke display string from MessageInfo's revokerInfo and revokeReason.
  ///
  /// "self" must be determined by comparing against the **currently logged-in
  /// user**, not the message's sender. Comparing against `messageInfo.from`
  /// is wrong because the common case is `revokerInfo.userID == from.userID`
  /// (a user revoking their own message) — for the receiving side that
  /// should display "对方撤回了一条消息", not "你撤回了一条消息".
  ///
  /// 根据 MessageInfo 的 revokerInfo 和 revokeReason 构建撤回显示字符串。
  ///
  /// “自己”必须通过与**当前登录用户**比较来确定，而不是消息的发送者。不要只比对 `messageInfo.from`。
  ///
  /// （用户撤回自己的消息）——针对接收方
  static String getRevokeDisplayString(
      MessageInfo messageInfo, BuildContext context) {
    AppLocalizedText? localizations = AppLocalization.of(context);
    String content = '';

    final revokerInfo = messageInfo.revokerInfo;
    final reason = messageInfo.revokeReason ?? '';
    final loginUserID = LoginStore.shared.loginState.loginUserInfo?.userID;

    final bool revokedBySelf;
    if (loginUserID != null &&
        loginUserID.isNotEmpty &&
        revokerInfo != null &&
        revokerInfo.userID.isNotEmpty) {
      revokedBySelf = revokerInfo.userID == loginUserID;
    } else {
      // Fallback: when revoker info is unavailable, fall back to the message
      // sender — for self-sent messages the original sender is the only one
      // typically allowed to revoke, so this still gives a sensible result.
      //
      // 备用方案：当撤回者信息不可用时，退而求其次使用消息发送者——对于自己发送的消息，原发送者通常是唯一被允许撤回的人，所以仍然可以得到合理的结果。
      revokedBySelf = messageInfo.isSentBySelf;
    }

    if (revokedBySelf) {
      content = localizations.messageRevokedBySelf;
    } else {
      if (messageInfo.conversationType == ConversationType.group) {
        final nickname = revokerInfo?.nickname;
        final userID = revokerInfo?.userID ?? '';
        final revokerName =
            (nickname != null && nickname.isNotEmpty) ? nickname : userID;
        if (revokerName.isEmpty) {
          content = localizations.messageRevokedByOther;
        } else {
          content = localizations.messageRevokedByUser(revokerName);
        }
      } else {
        content = localizations.messageRevokedByOther;
      }
    }

    if (reason.isNotEmpty) {
      content = '$content: $reason';
    }

    return content;
  }

  static String getJoinGroupDisplayString(
      JoinGroup systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    return localizations.groupMemberJoined(
        UIKitUtil.memberDisplayName(systemMessage.joinMember));
  }

  static String getInviteToGroupDisplayString(
      InviteToGroup systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    final inviteesShowName = systemMessage.invitees
        .map((m) => UIKitUtil.memberDisplayName(m))
        .join('、');
    return localizations.groupMemberInvited(
        UIKitUtil.memberDisplayName(systemMessage.inviter), inviteesShowName);
  }

  static String getQuitGroupDisplayString(
      QuitGroup systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    return localizations
        .groupMemberQuit(UIKitUtil.memberDisplayName(systemMessage.quitMember));
  }

  static String getKickedFromGroupDisplayString(
      KickedFromGroup systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    final kickedShowName = systemMessage.kickedMembers
        .map((m) => UIKitUtil.memberDisplayName(m))
        .join('、');
    return localizations.groupMemberKicked(
        UIKitUtil.memberDisplayName(systemMessage.opUser), kickedShowName);
  }

  static String getSetGroupAdminDisplayString(
      SetGroupAdmin systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    final showName = systemMessage.setAdminMembers
        .map((m) => UIKitUtil.memberDisplayName(m))
        .join('、');
    return localizations.groupAdminSet(showName);
  }

  static String getCancelGroupAdminDisplayString(
      CancelGroupAdmin systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    final showName = systemMessage.cancelAdminMembers
        .map((m) => UIKitUtil.memberDisplayName(m))
        .join('、');
    return localizations.groupAdminCancelled(showName);
  }

  static String getMuteGroupMemberDisplayString(
      MuteGroupMember systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    int muteTime = systemMessage.muteTime;
    String memberShowName = systemMessage.mutedGroupMembers
        .map((m) => UIKitUtil.memberDisplayName(m))
        .join('、');
    bool isSelfMuted = systemMessage.isSelfMuted;
    String actualShowName = isSelfMuted ? localizations.you : memberShowName;

    if (muteTime == 0) {
      final action = localizations.unmuted;
      return "$actualShowName $action";
    } else {
      final action = localizations.muted;
      final duration = formatMuteTime(muteTime, context);
      return "$actualShowName $action$duration";
    }
  }

  static String getPinGroupMessageDisplayString(
      PinGroupMessage systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    return localizations
        .groupMessagePinned(UIKitUtil.memberDisplayName(systemMessage.opUser));
  }

  static String getUnpinGroupMessageDisplayString(
      UnpinGroupMessage systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    return localizations.groupMessageUnpinned(
        UIKitUtil.memberDisplayName(systemMessage.opUser));
  }

  static String getChangeGroupNameDisplayString(
      ChangeGroupName systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    return '${UIKitUtil.memberDisplayName(systemMessage.opUser)} ${localizations.groupNameChangedTo} ${systemMessage.groupName}';
  }

  static String getChangeGroupAvatarDisplayString(
      ChangeGroupAvatar systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    return '${UIKitUtil.memberDisplayName(systemMessage.opUser)} ${localizations.groupAvatarChanged}';
  }

  static String getChangeGroupNotificationDisplayString(
      ChangeGroupNotification systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    String operator = UIKitUtil.memberDisplayName(systemMessage.opUser);
    String groupNotice = systemMessage.groupNotification;
    if (groupNotice.isNotEmpty) {
      return '$operator ${localizations.groupNoticeChangedTo} $groupNotice';
    } else {
      return '$operator ${localizations.groupNoticeDeleted}';
    }
  }

  static String getChangeGroupIntroductionDisplayString(
      ChangeGroupIntroduction systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    String operator = UIKitUtil.memberDisplayName(systemMessage.opUser);
    String groupIntroduction = systemMessage.groupIntroduction;
    if (groupIntroduction.isNotEmpty) {
      return '$operator ${localizations.groupIntroChangedTo} $groupIntroduction';
    } else {
      return '$operator ${localizations.groupIntroDeleted}';
    }
  }

  static String getChangeGroupOwnerDisplayString(
      ChangeGroupOwner systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    return '${UIKitUtil.memberDisplayName(systemMessage.opUser)} ${localizations.groupOwnerTransferredTo} ${systemMessage.groupOwner}';
  }

  static String getChangeGroupMuteAllDisplayString(
      ChangeGroupMuteAll systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    String operator = UIKitUtil.memberDisplayName(systemMessage.opUser);
    bool isMuteAll = systemMessage.isMuteAll;
    return '$operator ${isMuteAll ? localizations.groupMuteAllEnabled : localizations.groupMuteAllDisabled}';
  }

  static String getChangeJoinGroupApprovalDisplayString(
      ChangeJoinGroupApproval systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    String operator = UIKitUtil.memberDisplayName(systemMessage.opUser);
    String approvalDesc;
    switch (systemMessage.groupJoinOption) {
      case GroupJoinOption.forbid:
        approvalDesc = localizations.groupJoinForbidden;
        break;
      case GroupJoinOption.auth:
        approvalDesc = localizations.groupJoinApproval;
        break;
      case GroupJoinOption.any:
        approvalDesc = localizations.groupJoinFree;
        break;
    }
    return '$operator ${localizations.groupJoinMethodChangedTo} $approvalDesc';
  }

  static String getChangeInviteToGroupApprovalDisplayString(
      ChangeInviteToGroupApproval systemMessage, BuildContext context) {
    AppLocalizedText localizations = AppLocalization.of(context);
    String operator = UIKitUtil.memberDisplayName(systemMessage.opUser);
    String approvalDesc;
    switch (systemMessage.groupInviteOption) {
      case GroupInviteOption.forbid:
        approvalDesc = localizations.groupInviteForbidden;
        break;
      case GroupInviteOption.auth:
        approvalDesc = localizations.groupInviteApproval;
        break;
      case GroupInviteOption.any:
        approvalDesc = localizations.groupInviteFree;
        break;
    }
    return '$operator ${localizations.groupInviteMethodChangedTo} $approvalDesc';
  }

  static String getMessageAbstract(
      MessageInfo? messageInfo, BuildContext context,
      {bool showMergedTitle = false}) {
    if (messageInfo == null) return '';

    if (!context.mounted) {
      return '';
    }

    AppLocalizedText? localizations = AppLocalization.of(context);

    // Revoked messages show revoke info directly
    //
    // 被撤回的消息会直接显示撤回信息
    if (messageInfo.status == MessageStatus.revoked) {
      return getRevokeDisplayString(messageInfo, context);
    }

    switch (messageInfo.messageType) {
      case MessageType.text:
        final textPayload = messageInfo.messagePayload as TextMessagePayload?;
        return textPayload?.text ?? '';

      case MessageType.image:
        return localizations.messageTypeImage;

      case MessageType.audio:
        return localizations.messageTypeVoice;

      case MessageType.file:
        return localizations.messageTypeFile;

      case MessageType.video:
        return localizations.messageTypeVideo;

      case MessageType.face:
        return localizations.messageTypeSticker;

      case MessageType.custom:
        final customPayload =
            messageInfo.messagePayload as CustomMessagePayload?;
        if (customPayload == null) {
          return localizations.messageTypeCustom;
        }

        CallingMessageDataProvider provider =
            CallingMessageDataProvider(messageInfo, context);
        if (provider.isCallingSignal) {
          return provider.content;
        }

        final customInfo =
            ChatUtil.jsonData2Dictionary(customPayload.customData);
        if (customInfo != null && customInfo['businessID'] == 'group_create') {
          final sender = customInfo['opUser'] ?? '';
          final cmd = customInfo['cmd'] is int ? customInfo['cmd'] : 0;
          if (cmd == 1) {
            return '$sender ${localizations.createCommunity}';
          } else {
            return '$sender ${localizations.createGroupTips}';
          }
        }

        return localizations.messageTypeCustom;

      case MessageType.tips:
        final tipsPayload = messageInfo.messagePayload as TipsMessagePayload?;
        return getSystemInfoDisplayString(
            tipsPayload?.groupTips ?? [], context);

      case MessageType.merged:
        if (showMergedTitle) {
          final mergedPayload =
              messageInfo.messagePayload as MergedMessagePayload?;
          final title = mergedPayload?.title;
          if (title != null && title.isNotEmpty) {
            return title;
          }
        }
        return '[${localizations.chatHistory}]';

      default:
        return '';
    }
  }

  static String formatMuteTime(int seconds, BuildContext context) {
    if (seconds <= 0) return '';

    if (!context.mounted) {
      return '';
    }

    AppLocalizedText localizations = AppLocalization.of(context);

    String timeStr = '$seconds${localizations.second}';

    if (seconds > 60) {
      int second = seconds % 60;
      int min = seconds ~/ 60;
      timeStr = '$min${localizations.min}$second${localizations.second}';

      if (min > 60) {
        min = (seconds ~/ 60) % 60;
        int hour = (seconds ~/ 60) ~/ 60;
        timeStr =
            '$hour${localizations.hour}$min${localizations.min}$second${localizations.second}';

        if (hour % 24 == 0) {
          int day = ((seconds ~/ 60) ~/ 60) ~/ 24;
          timeStr = '$day${localizations.day}';
        } else if (hour > 24) {
          hour = ((seconds ~/ 60) ~/ 60) % 24;
          int day = ((seconds ~/ 60) ~/ 60) ~/ 24;
          timeStr =
              '$day${localizations.day}$hour${localizations.hour}$min${localizations.min}$second${localizations.second}';
        }
      }
    }

    return timeStr;
  }

  static bool isSystemStyleCustomMessagePayload(
      MessageInfo message, BuildContext context) {
    if (message.messageType == MessageType.custom) {
      try {
        final customPayloadData =
            (message.messagePayload as CustomMessagePayload?)?.customData;
        final customInfo = ChatUtil.jsonData2Dictionary(customPayloadData);
        if (customInfo != null) {
          if (customInfo['businessID'] == 'group_create') {
            return true;
          }

          final callingProvider = CallingMessageDataProvider(message, context);
          if (callingProvider.isCallingSignal &&
              callingProvider.participantType == CallParticipantType.group) {
            return true;
          }
        }
      } catch (e) {
        debugPrint('isSystemStyleCustomMessagePayload error: $e');
      }
    }

    return false;
  }
}
