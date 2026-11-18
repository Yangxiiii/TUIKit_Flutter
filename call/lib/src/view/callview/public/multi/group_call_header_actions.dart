import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 群通话页头两侧动作的纯展示层，生产与离线预览共用同一位置和资源。
class GroupCallHeaderActions extends StatelessWidget {
  const GroupCallHeaderActions(
      {super.key,
      required this.showMinimize,
      required this.showInvite,
      this.incoming = false,
      required this.inviteEnabled,
      required this.onMinimize,
      required this.onInvite});

  /// 跟随宿主浮窗能力，已结束结果页不再最小化。
  final bool showMinimize;

  /// 被叫待接听与已结束阶段不追加邀请。
  final bool showInvite;

  /// 待接听页沿用重叠窗口图标，接通场景使用收缩箭头。
  final bool incoming;

  /// SDK 分配有效场次标识后才允许打开选人器。
  final bool inviteEnabled;

  /// 路由或预览提供动作，本组件不调用 SDK。
  final VoidCallback onMinimize, onInvite;

  @override
  // 宿主提供全屏约束，左右动作分别定位，不占据标题与媒体的布局空间。
  Widget build(BuildContext context) => Stack(children: [
        if (showMinimize)
          Positioned(
              left: 12,
              top: MediaQuery.paddingOf(context).top + 8,
              width: 40,
              height: 40,
              child: Semantics(
                  identifier: 'call.minimize',
                  child: IconButton(
                      tooltip: '最小化通话',
                      onPressed: onMinimize,
                      icon: Icon(
                          incoming ? AppIcons.copy : AppIcons.collapseModal,
                          size: 24,
                          color: context.appColors.onScrim)))),
        if (showInvite)
          Positioned(
              right: 12,
              top: MediaQuery.paddingOf(context).top + 8,
              width: 40,
              height: 40,
              child: Semantics(
                  identifier: 'call.group.invite',
                  child: IconButton(
                      tooltip: '添加成员',
                      onPressed: inviteEnabled ? onInvite : null,
                      icon: Icon(AppIcons.userRoundPlus,
                          size: 24, color: context.appColors.onScrim)))),
      ]);
}
