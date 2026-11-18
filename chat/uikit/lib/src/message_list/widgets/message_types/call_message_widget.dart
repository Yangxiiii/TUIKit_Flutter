import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/calling_message_data_provider.dart';

import 'system_message_widget.dart';
import 'text_message_widget.dart';

/// 用气泡展示群通话发起和个人通话记录，单聊旧记录可按原媒体类型回拨。
class CallMessageWidget extends StatelessWidget {
  const CallMessageWidget({
    super.key,
    required this.message,
    required this.isSelf,
    required this.maxWidth,
    required this.config,
    this.bubbleKey,
    this.backgroundBuilder,
    this.onResendTap,
    this.isInMergedDetailView = false,
    this.onCallMessageClick,
    this.viewerId,
  });

  /// 已有通话记录，回拨时从公开收发方字段读取对端。
  final MessageInfo message;

  /// 展示方向由外层提供，可与通话信令的实际发送方不同。
  final bool isSelf;

  /// 外层消息项分配的最大宽度，单位为逻辑像素。
  final double maxWidth;

  /// 聊天列表的气泡圆角、时间与回执配置。
  final MessageListConfigProtocol config;

  /// 供外层定位气泡正文的稳定锚点。
  final GlobalKey? bubbleKey;

  /// 由外层协调普通背景、引用及高亮。
  final BackgroundBuilder? backgroundBuilder;

  /// 由调用方处理失败消息重发。
  final VoidCallback? onResendTap;

  /// 合并详情中使用只读消息展示配置。
  final bool isInMergedDetailView;

  /// 点击单聊记录时传递对端用户标识及原媒体类型。
  final void Function(String userID, bool isVideoCall)? onCallMessageClick;

  /// 离线预览可显式提供查看账号；生产默认读取当前登录账号。
  final String? viewerId;

  @override
  Widget build(BuildContext context) {
    final provider =
        CallingMessageDataProvider(message, context, viewerId: viewerId);
    if (!provider.isCallingSignal || provider.content.isEmpty) {
      return Container();
    }

    // 腾讯原生群提示沿用系统样式，业务发起与个人结果使用普通气泡。
    final group = provider.participantType == CallParticipantType.group;
    if (group && provider.personalRecord == null && !provider.isCallStart) {
      return SystemMessageWidget(customContent: provider.content);
    }

    final isVideo = provider.streamMediaType == CallStreamMediaType.video;
    final invitationEnded = const [
      CallProtocolType.cancel,
      CallProtocolType.reject,
      CallProtocolType.timeout,
      CallProtocolType.lineBusy
    ].contains(provider.protocolType);
    final openGroupCall = config.onGroupCallBubbleTap;
    final accepted = config.acceptedCallAttempt;
    final attempt = provider.attemptId;
    return Semantics(
      identifier: 'tim.message.call.${message.msgID}',
      child: TextMessageWidget(
        message: message,
        isSelf: isSelf,
        maxWidth: maxWidth,
        config: config,
        bubbleKey: bubbleKey,
        backgroundBuilder: backgroundBuilder,
        onResendTap: onResendTap,
        isInMergedDetailView: isInMergedDetailView,
        onTap: group
            ? (openGroupCall == null ? null : () => openGroupCall(context))
            : provider.isTemporaryMultiParty
                ? null
                : () {
                    // 单聊旧记录继续向实际对端回拨。
                    final userId =
                        message.isSentBySelf ? message.to : message.from.userID;
                    if (userId.isNotEmpty) onCallMessageClick?.call(userId, isVideo);
                  },
        contentBuilder: (style) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                isVideo
                    ? AppIcons.cameraOn
                    : (invitationEnded ? AppIcons.phone2 : AppIcons.phone3),
                size: 20,
                color: style.color),
            const SizedBox(width: 8),
            Flexible(
              child: attempt == null || accepted == null
                  ? Text(provider.content, style: style)
                  : ValueListenableBuilder<String?>(
                      valueListenable: accepted,
                      builder: (_, confirmed, __) => Text(
                        confirmed == attempt ? '已接听' : provider.content,
                        style: style,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
