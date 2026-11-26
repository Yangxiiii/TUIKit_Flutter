import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 群通话页头两侧动作的纯展示层，生产与离线预览共用同一位置和资源。
class GroupCallHeaderActions extends StatelessWidget {
  const GroupCallHeaderActions({
    super.key,
    required this.showMinimize,
    required this.showInvite,
    this.incoming = false,
    required this.inviteEnabled,
    required this.onMinimize,
    this.onInvite,
  });

  /// 跟随宿主浮窗能力，允许缩小有效通话及可重呼结果。
  final bool showMinimize;

  /// 通话中的主界面和可重呼结果页均可显示选人入口。
  final bool showInvite;

  /// 待接听页沿用重叠窗口图标，接通场景使用收缩箭头。
  final bool incoming;

  /// 有效通话可追加邀请，已超时的场次只为下一次呼叫选人。
  final bool inviteEnabled;

  /// 路由或预览提供动作，本组件不调用 SDK。
  final VoidCallback onMinimize;

  /// 由上层决定追加邀请或暂存重呼名单，展示层只转交点击。
  final VoidCallback? onInvite;

  @override
  // 宿主提供全屏约束，左右动作分别定位，不占据标题与媒体的布局空间。
  Widget build(BuildContext context) => Stack(
    children: [
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
                color: context.appColors.onScrim,
              ),
            ),
          ),
        ),
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
              icon: Icon(
                AppIcons.userRoundPlus,
                size: 24,
                color: context.appColors.onScrim,
              ),
            ),
          ),
        ),
    ],
  );
}
