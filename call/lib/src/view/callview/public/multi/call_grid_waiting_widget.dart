import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import 'group_call_dots.dart';
import 'group_call_member.dart';

/// 被叫全屏等待页，只展示邀请资料与成员预览，不提前显示设备控制。
class CallGridWaitingWidget extends StatelessWidget {
  const CallGridWaitingWidget(
      {super.key,
      required this.inviter,
      required this.members,
      required this.video});

  /// 来自本场邀请资料的发起人。
  final GroupCallMember inviter;

  /// 除本人之外的通话成员，按当前场次顺序预览前三名，余下显示真实数量。
  final List<GroupCallMember> members;

  /// SDK 媒体类型决定邀请文案。
  final bool video;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
              child: SizedBox(
                  width: constraints.maxWidth,
                  child: Column(children: [
                    SizedBox(height: constraints.maxHeight > 440 ? 69 : 12),
                    AppUserAvatar(
                        userId: inviter.id,
                        name: inviter.name,
                        url: inviter.avatarUrl,
                        size: 96),
                    const SizedBox(height: 20),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(inviter.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: colors.onScrim,
                                fontSize: 20,
                                height: 28 / 20))),
                    if (inviter.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(inviter.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: colors.onScrimSecondary,
                                  fontSize: 16,
                                  height: 22 / 16,
                                  letterSpacing: 0))),
                    ],
                    const SizedBox(height: 48),
                    Text('邀请你${video ? '视频' : '语音'}通话',
                        style: TextStyle(
                            color: colors.onScrimSecondary,
                            fontSize: 16,
                            height: 20 / 16,
                            letterSpacing: 0)),
                    const SizedBox(height: 24),
                    const GroupCallDots(),
                    if (members.isNotEmpty) ...[
                      const SizedBox(height: 60),
                      Text('通话成员',
                          style: TextStyle(
                              color: colors.onScrimSecondary,
                              fontSize: 16,
                              height: 20 / 16,
                              letterSpacing: 0)),
                      const SizedBox(height: 16),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: 9,
                          children: [
                            for (final member in members.take(3))
                              AppUserAvatar(
                                  userId: member.id,
                                  name: member.name,
                                  url: member.avatarUrl,
                                  size: 40),
                            if (members.length > 3)
                              Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      color: colors.scrim.withValues(alpha: .4),
                                      shape: BoxShape.circle),
                                  child: Text('+${members.length - 3}',
                                      style: TextStyle(
                                          color: colors.onScrim,
                                          fontSize: 14))),
                          ]),
                    ],
                    const SizedBox(height: 16),
                  ])),
            ));
  }
}
