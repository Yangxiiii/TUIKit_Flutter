import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import 'group_call_dots.dart';
import 'group_call_member.dart';

/// 成员画面显示实际视频或同源头像，并用真实音量和邀请状态覆盖轻量标记。
class GroupCallMemberTile extends StatelessWidget {
  const GroupCallMemberTile({
    super.key,
    required this.member,
    required this.video,
    this.onTap,
    this.onRetry,
    this.selected = false,
    this.thumbnail = false,
    this.mainView = false,
    this.showVideo = true,
  });

  /// 从当前场次事实映射的成员资料。
  final GroupCallMember member;

  /// 每个用户只允许一个真实视频视图，缩略选中项不重复挂载。
  final Widget video;

  /// 切换大画面或回到宫格。
  final VoidCallback? onTap;

  /// 当前有效场次允许重新邀请时提供。
  final VoidCallback? onRetry;

  /// 当前大画面对应的缩略卡使用绿色边框。
  final bool selected;

  /// 缩略条使用独立可访问标识，不改变实际成员状态。
  final bool thumbnail;

  /// 大画面的麦克风与姓名并排；宫格和缩略图仍使用右上角状态。
  final bool mainView;

  /// 大画面的同人缩略卡只绘头像，避免争抢同一原生纹理。
  final bool showVideo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final speaking = member.joined && member.microphoneOn && member.volume > 0;
    return Semantics(
      identifier:
          '${thumbnail ? 'call.group.thumbnail' : 'call.group.member'}.${member.id}',
      label: '${member.name}，${member.statusLabel}',
      selected: selected,
      button: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(fit: StackFit.expand, children: [
          // 视频保持绑定；摄像头关闭时只切换覆盖内容，避免开关触发纹理重建。
          Visibility(
            visible: showVideo && member.cameraOn && member.joined,
            maintainState: true,
            child: video,
          ),
          if (!showVideo || !member.cameraOn || !member.joined)
            LayoutBuilder(
                builder: (context, constraints) => FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: AppUserAvatar(
                        userId: member.id,
                        name: member.name,
                        url: member.avatarUrl,
                        size: constraints.maxWidth,
                        borderRadius: BorderRadius.zero,
                      ),
                    )),
          if (!member.joined)
            ColoredBox(color: colors.scrim.withValues(alpha: .55)),
          if (!member.joined)
            Positioned(
                left: 4,
                top: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                      color: colors.scrim.withValues(alpha: .4),
                      borderRadius: BorderRadius.circular(3)),
                  child: Text('未加入',
                      style: TextStyle(color: colors.onScrim, fontSize: 10)),
                )),
          if (member.joined && !mainView)
            Positioned(right: 5, top: 5, child: _microphone(context)),
          if (!member.joined)
            Center(
                child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: member.status == GroupCallMemberStatus.waiting
                  ? const GroupCallDots(key: ValueKey('waiting'))
                  : _invitationResult(context),
            )),
          Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Align(
                  alignment: Alignment.centerLeft, child: _nameStrip(context))),
          if (selected || speaking)
            IgnorePointer(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        border: Border.all(color: colors.success, width: 2)))),
        ]),
      ),
    );
  }

  /// 姓名蒙层在左下角随文字收缩，长姓名最多占卡片宽度并省略。
  Widget _nameStrip(BuildContext context) => Container(
        color: context.appColors.scrim.withValues(alpha: .5),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
              child: Text(member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.appColors.onScrim,
                      fontSize: 12,
                      height: 16 / 12))),
          if (mainView && member.joined) ...[
            const SizedBox(width: 8),
            _microphone(context),
          ],
        ]),
      );

  /// 终态与重呼动作分别呈现，重呼的标识、读屏名称和操作保持在同一节点。
  Widget _invitationResult(BuildContext context) => Column(
        key: ValueKey(member.status),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(member.statusLabel,
              style: TextStyle(color: context.appColors.onScrim, fontSize: 12)),
          if (member.canRetry && onRetry != null)
            Semantics(
              identifier: 'call.group.reinvite.${member.id}',
              label: '重新呼叫${member.name}',
              container: true,
              button: true,
              onTap: onRetry,
              excludeSemantics: true,
              child: IconButton(
                tooltip: '重新呼叫',
                visualDensity: VisualDensity.compact,
                iconSize: 24,
                onPressed: onRetry,
                icon: Icon(AppIcons.phone3, color: context.appColors.onScrim),
              ),
            ),
        ],
      );

  /// 麦克风绿色填充以50%为起点，只有实际采集音量大于0时才运动。
  Widget _microphone(BuildContext context) {
    final colors = context.appColors;
    if (!member.microphoneOn) {
      return Icon(AppIcons.micOff, size: 18, color: colors.danger);
    }
    final level = member.volume.clamp(0, 100) / 100;
    return Stack(children: [
      Icon(AppIcons.mic, size: 18, color: colors.onScrim),
      Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 18 * (.5 + level * .5),
          child: ClipRect(
              child: OverflowBox(
                  alignment: Alignment.bottomCenter,
                  minHeight: 18,
                  maxHeight: 18,
                  child: Icon(AppIcons.mic, size: 18, color: colors.success)))),
    ]);
  }
}
