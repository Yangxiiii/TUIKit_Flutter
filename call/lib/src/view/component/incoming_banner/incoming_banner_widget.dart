import 'dart:ui' show ImageFilter;

import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_calls_uikit/src/manager/call_manager.dart';

/// 在聊天上方展示来电资料与接听/拒绝入口，操作沿用同一 SDK 通话。
class IncomingBannerWidget extends StatelessWidget {
  const IncomingBannerWidget({super.key, this.onShowCalling, this.onCloseAll});

  /// 展开当前通话，不重新拨号。
  final VoidCallback? onShowCalling;

  /// 拒绝成功后关闭来电浮层。
  final VoidCallback? onCloseAll;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([
          CallStore.shared.state.activeCall,
          CallStore.shared.state.allParticipants
        ]),
        builder: (context, _) {
          final call = CallStore.shared.state.activeCall.value;
          if (call.callId.isEmpty) return const SizedBox.shrink();
          final inviter = CallStore.shared.state.allParticipants.value
              .where((p) => p.id == call.inviterId)
              .firstOrNull;
          final name = inviter == null
              ? call.inviterId
              : inviter.remark.isNotEmpty
                  ? inviter.remark
                  : inviter.name.isNotEmpty
                      ? inviter.name
                      : inviter.id;
          return IncomingBannerContent(
            userId: call.inviterId,
            name: name,
            avatarUrl: inviter?.avatarURL,
            video: call.mediaType == CallMediaType.video,
            onShowCalling: onShowCalling,
            onReject: () async {
              if (await CallManager.instance.reject()) onCloseAll?.call();
            },
            onAccept: () async {
              if (await CallManager.instance.accept()) onShowCalling?.call();
            },
          );
        },
      );
}

/// 单聊来电横幅的共享布局，操作与资料由当前平台通话层提供。
class IncomingBannerContent extends StatelessWidget {
  const IncomingBannerContent({
    super.key,
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.video,
    required this.onShowCalling,
    required this.onReject,
    required this.onAccept,
  });

  /// 横幅与屏幕两侧的逻辑像素边距。
  static const horizontalInset = 12.0;

  /// 横幅顶部相对系统状态栏底部的逻辑像素偏移。
  static const topGap = 4.24;

  /// 设计稿中横幅的外框高度。
  static const height = 74.0;

  /// 用来电者标识复用消息列表的头像缓存。
  final String userId;
  final String name;
  final String? avatarUrl;
  final bool video;
  final VoidCallback? onShowCalling;
  final VoidCallback onReject;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final text = AppLocalization.of(context);
    final colors = context.appColors;
    // 毛玻璃只作用于圆角横幅内的宿主背景。
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Material(
          color: colors.scrim,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                // 长名称在资料区截断，尾部两个操作始终各占 40 像素。
                Expanded(child: _buildCaller(context)),
                const SizedBox(width: 16),
                _action(context, 'reject', text.callRejectAction,
                    AppIcons.phone2, colors.danger, onReject),
                const SizedBox(width: 16),
                _action(context, 'accept', text.callAcceptAction,
                    AppIcons.phone3, colors.success, onAccept),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// 资料区单独响应展开通话，头像和两行文案保持设计稿的左对齐。
  Widget _buildCaller(BuildContext context) {
    final text = AppLocalization.of(context);
    final colors = context.appColors;
    return Semantics(
      identifier: 'call.banner.open',
      button: true,
      onTap: onShowCalling,
      child: InkWell(
        excludeFromSemantics: true,
        onTap: onShowCalling,
        child: Row(children: [
          AppUserAvatar(userId: userId, name: name, url: avatarUrl, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      color: colors.onScrim,
                    )),
                Text(
                    video
                        ? text.callInvitedToVideoCall
                        : text.callInvitedToAudioCall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: colors.onScrimSecondary,
                    )),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  /// 圆钮的视觉边界就是命中区域，标识直接挂在对应操作上。
  Widget _action(BuildContext context, String id, String label, IconData icon,
          Color background, VoidCallback onTap) =>
      Semantics(
        identifier: 'call.banner.$id',
        label: label,
        button: true,
        onTap: onTap,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            excludeFromSemantics: true,
            child: SizedBox.square(
              dimension: 40,
              child: Center(
                child: Icon(icon, size: 24, color: context.appColors.onScrim),
              ),
            ),
          ),
        ),
      );
}
