import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../participant/call_participant_pane.dart';
import 'call_grid_waiting_widget.dart';
import 'group_call_media.dart';
import 'group_call_member.dart';

/// 群通话纯展示骨架，生产 SDK 适配页与离线视觉验证共用同一布局。
class GroupCallScene extends StatelessWidget {
  const GroupCallScene(
      {super.key,
      required this.title,
      required this.status,
      required this.members,
      required this.inviterId,
      required this.selfId,
      required this.incoming,
      required this.video,
      required this.controls,
      required this.videoBuilder,
      this.initialFocusedId,
      this.onManage,
      this.onRetry});

  /// 群名由宿主提供，临时多人使用明确的通话形态名称。
  final String title;

  /// 真实等待状态、结束状态或 SDK 已接通时长。
  final Widget status;

  /// 当前场次的只读成员投影，最多绘制九人。
  final List<GroupCallMember> members;

  /// 用于来电资料与成员预览过滤，不推导主持权限。
  final String inviterId, selfId;

  /// 被叫未接听时使用邀请资料布局。
  final bool incoming;

  /// 邀请显示语音或视频类型。
  final bool video;

  /// 按生命周期展示的设备、接听和结束操作。
  final Widget controls;

  /// 每个成员只挂载一个视频视图。
  final Widget Function(String id) videoBuilder;

  /// 仅恢复展示选择，未提供时从宫格开始。
  final String? initialFocusedId;

  /// 展开当前真实成员管理面板。
  final VoidCallback? onManage;

  /// 有效场次内的重新邀请；已结束时为空。
  final ValueChanged<String>? onRetry;

  @override
  Widget build(BuildContext context) {
    final inviter =
        members.where((member) => member.id == inviterId).firstOrNull;
    final background = inviter ?? members.firstOrNull;
    // 背景铺满屏幕，内容单独遵循安全区；来电与接通共用底部操作位置。
    return Stack(fit: StackFit.expand, children: [
      if (incoming)
        CallParticipantPane(
            userId: background?.id ?? '',
            name: background?.name ?? '',
            avatarUrl: background?.avatarUrl ?? '',
            hasVideo: false,
            showAvatar: false,
            video: const SizedBox.shrink())
      else
        ColoredBox(color: context.appColors.groupCallBackground),
      SafeArea(
          // 源稿底部安全区为34像素；设备需要更大留白时继续采用实际系统边距。
          minimum: const EdgeInsets.only(bottom: 34),
          child: Column(children: [
            if (incoming) const SizedBox(height: 48) else _header(context),
            // 媒体区吸收屏幕余高，底部操作区保持设计尺寸。
            Expanded(
                child: incoming && inviter != null
                    ? CallGridWaitingWidget(
                        inviter: inviter,
                        video: video,
                        members: members
                            .where((member) => member.id != selfId)
                            .toList())
                    : Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 20),
                        child: GroupCallMedia(
                            initialFocusedId: initialFocusedId,
                            members: members,
                            videoBuilder: videoBuilder,
                            onRetry: onRetry))),
            Padding(
                padding: EdgeInsets.only(top: 12, bottom: incoming ? 50 : 16),
                child: controls),
          ])),
    ]);
  }

  /// 标题先给两侧动作预留空间；Stack 占满宽度，管理入口相对屏幕右侧定位。
  Widget _header(BuildContext context) => SizedBox(
      width: double.infinity,
      height: 48,
      child: Stack(alignment: Alignment.center, children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 96),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 16, color: context.appColors.onScrim)),
              status,
            ])),
        if (!incoming && onManage != null)
          Positioned(
              right: 52,
              child: Semantics(
                  identifier: 'call.group.manageMembers',
                  child: IconButton(
                      tooltip: '管理成员',
                      onPressed: onManage,
                      icon: Icon(AppIcons.group,
                          size: 24, color: context.appColors.onScrim)))),
      ]));
}
