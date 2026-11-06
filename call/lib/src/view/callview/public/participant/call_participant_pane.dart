import 'dart:math' as math;
import 'dart:ui';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 组合真实视频与消息列表同源头像；每个画面的开关独立决定，不遮盖另一端的视频。
class CallParticipantPane extends StatelessWidget {
  const CallParticipantPane({
    super.key,
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.hasVideo,
    required this.video,
    this.backgroundUserId,
    this.backgroundName,
    this.backgroundAvatarUrl,
    this.isMainView = true,
    this.showAvatar = true,
  });

  /// 当前画面的真实用户标识，用于复用头像 Sort 缓存。
  final String userId;

  /// 当前画面的展示名称，沿用备注优先规则。
  final String name;

  /// 当前画面的头像地址。
  final String avatarUrl;

  /// 当前画面是否有已开启的摄像头；不得使用另一端的开关代替。
  final bool hasVideo;

  /// SDK 的真实视频视图，有视频时直接绘制，不叠加头像背景。
  final Widget video;

  /// 主画面无摄像头时，使用对方资料铺满背景。
  final String? backgroundUserId;

  /// 对方背景头像的姓名回退。
  final String? backgroundName;

  /// 对方背景头像地址。
  final String? backgroundAvatarUrl;

  /// 主画面使用整页解码尺寸，小窗保留紧凑头像。
  final bool isMainView;

  /// 等待接听时由资料区显示头像，避免重叠绘制。
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      // 摄像头开关只切换可见性，沿用 SDK 持续挂载的视频视图，避免反复释放、重新绑定原生纹理。
      Visibility(visible: hasVideo, maintainState: true, child: video),
      if (!hasVideo)
        LayoutBuilder(builder: (context, constraints) {
          assert(constraints.hasBoundedWidth && constraints.hasBoundedHeight,
              '通话画面必须具有有限的宽高约束');
          final size = math.max(constraints.maxWidth, constraints.maxHeight);
          return ClipRect(
            child: Stack(fit: StackFit.expand, children: [
              ExcludeSemantics(
                  child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: AppUserAvatar(
                    userId: backgroundUserId ?? userId,
                    name: backgroundName ?? name,
                    url: backgroundAvatarUrl ?? avatarUrl,
                    size: size,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
              )),
              ColoredBox(color: context.appColors.scrim.withValues(alpha: .6)),
              if (showAvatar)
                Center(
                    child: AppUserAvatar(
                        userId: userId,
                        name: name,
                        url: avatarUrl,
                        size: isMainView
                            ? 96
                            : math.min(40, constraints.maxWidth * .5))),
            ]),
          );
        }),
    ]);
  }
}
