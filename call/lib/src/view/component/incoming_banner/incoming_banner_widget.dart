import 'dart:ui' show ImageFilter;

import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_calls_uikit/src/manager/call_manager.dart';
import 'package:tencent_calls_uikit/src/state/global_state.dart';

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
      CallStore.shared.state.allParticipants,
      GlobalState.instance.groupCall,
    ]),
    builder: (context, _) {
      final call = CallStore.shared.state.activeCall.value;
      if (call.callId.isEmpty) return const SizedBox.shrink();
      final epoch = CallManager.instance.sessionEpoch;
      bool isCurrent() =>
          context.mounted &&
          epoch == CallManager.instance.sessionEpoch &&
          call.callId == CallStore.shared.state.activeCall.value.callId;
      final group = GlobalState.instance.groupCall.value;
      // G21 展示邀请人资料；真实群名属于场次信息，不能替换邀请人姓名。
      final inviter = CallStore.shared.state.allParticipants.value
          .where((p) => p.id == call.inviterId)
          .firstOrNull;
      final name = AppUserAvatarScope.personName(
        context,
        call.inviterId,
        nickname: inviter?.name,
        groupId: call.chatGroupId,
      );
      return IncomingBannerContent(
        userId: call.inviterId,
        name: name,
        avatarUrl: inviter?.avatarURL,
        video: call.mediaType == CallMediaType.video,
        multi:
            call.chatGroupId.isNotEmpty ||
            call.inviteeIds.length > 1 ||
            (group != null && !group.ended && group.callId == call.callId),
        onShowCalling: () {
          if (isCurrent()) onShowCalling?.call();
        },
        onReject: () async {
          if (!isCurrent()) return;
          final rejected = await CallManager.instance.reject();
          // SDK 可能先清空旧通话；迟到结果只能关闭旧场次或已清空的浮层。
          final currentId = CallStore.shared.state.activeCall.value.callId;
          if (rejected &&
              context.mounted &&
              epoch == CallManager.instance.sessionEpoch &&
              (currentId.isEmpty || currentId == call.callId)) {
            onCloseAll?.call();
          }
        },
        onAccept: () async {
          if (!isCurrent()) return;
          if (await CallManager.instance.accept() && isCurrent()) {
            onShowCalling?.call();
          }
        },
      );
    },
  );
}

/// 单聊及多人来电横幅的共享布局，操作与邀请人资料由当前平台通话层提供。
class IncomingBannerContent extends StatelessWidget {
  const IncomingBannerContent({
    super.key,
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.video,
    this.multi = false,
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

  /// 邀请人的真实显示名称，缺少资料时由调用方使用账号标识。
  final String name;

  /// 邀请人的 SDK 头像；缺失时保留基础头像组件的默认显示。
  final String? avatarUrl;

  /// 当前邀请是否为视频，用于选择副标题和接听图标。
  final bool video;

  /// 群来源或明确临时多人场景；只影响文案，不授予任何会控权限。
  final bool multi;

  /// 点击邀请人资料后展开同一场通话。
  final VoidCallback? onShowCalling;

  /// 拒绝当前邀请，结果由平台通话层处理。
  final VoidCallback onReject;

  /// 接听当前邀请，权限及 SDK 失败由平台通话层处理。
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
              child: Row(
                children: [
                  // 长名称在资料区截断，尾部两个操作始终各占 40 像素。
                  Expanded(child: _buildCaller(context)),
                  const SizedBox(width: 16),
                  _action(
                    'reject',
                    text.callRejectAction,
                    'call_assets/hangup.png',
                    colors.danger,
                    onReject,
                  ),
                  const SizedBox(width: 16),
                  _action(
                    'accept',
                    text.callAcceptAction,
                    'call_assets/dialing.png',
                    colors.success,
                    onAccept,
                    icon: video
                        ? Icon(
                            AppIcons.cameraOn,
                            size: 24,
                            color: colors.onScrim,
                          )
                        : null,
                  ),
                ],
              ),
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
        child: Row(
          children: [
            AppUserAvatar(userId: userId, name: name, url: avatarUrl, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      color: colors.onScrim,
                    ),
                  ),
                  Text(
                    multi
                        ? video
                              ? text.invitedToMultiVideoCall
                              : text.invitedToMultiAudioCall
                        : video
                        ? text.callInvitedToVideoCall
                        : text.callInvitedToAudioCall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: colors.onScrimSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 实心圆钮复用 40 像素命中区域和独立语义，视频接听可覆盖电话图样。
  Widget _action(
    String id,
    String label,
    String imagePath,
    Color background,
    VoidCallback onTap, {
    Widget? icon,
  }) => Semantics(
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
          child: icon ??
              Ink.image(
                image: AssetImage(imagePath, package: 'tuikit_atomic_x'),
                fit: BoxFit.contain,
              ),
        ),
      ),
    ),
  );
}
