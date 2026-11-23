import 'package:app_core/app_core.dart' show formatPersonName;
import 'package:app_ui/app_ui.dart' show AppUserAvatarScope;
import 'package:flutter/widgets.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

/// 汇总聊天组件共用的群成员显示规则和 SDK 使用回调。
class UIKitUtil {
  static RegExp urlReg = RegExp(
      r"([hH][tT]{2}[pP]:\/\/|[hH][tT]{2}[pP][sS]:\/\/|[wW]{3}.|[wW][aA][pP].|[fF][tT][pP].|[fF][iI][lL][eE].)[-A-Za-z0-9+&@#/%?=~_|!:,.;]+[-A-Za-z0-9+&@#/%=~_|]");

  /// 使用群成员快照中的名片和昵称；有页面上下文时补齐个人实名。
  static String memberDisplayName(
    GroupMember member, {
    BuildContext? context,
    String? groupId,
  }) =>
      context == null
          ? formatPersonName(null, member.nickname,
              groupNickname: member.nameCard, fallback: member.userID)
          : AppUserAvatarScope.personName(
              context,
              member.userID,
              nickname: member.nickname,
              groupId: groupId,
              groupNickname: member.nameCard,
            );

  static void reportChatInvokeCall() {
    TencentImSDKPlugin.v2TIMManager.callExperimentalAPI(
      api: 'report_tuifeature_usage',
      param: {
        'report_tuifeature_usage_uicomponent_type': 1020,
      },
    );
  }
}
