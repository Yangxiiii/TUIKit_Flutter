import 'package:app_ui/app_ui.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';

import 'package:tencent_chat_uikit/src/message_list/utils/calling_message_data_provider.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_status_mixin.dart';
import 'system_message_widget.dart';

typedef BackgroundBuilder = Widget Function(Widget child);

/// 展示已有腾讯通话记录，点击时按原媒体类型和公开收发方字段回拨。
class CallMessageWidget extends StatefulWidget {
  final MessageInfo message;
  final bool isSelf;
  final double maxWidth;
  final MessageListStore? messageListStore;
  final GlobalKey? bubbleKey;
  final BackgroundBuilder? backgroundBuilder;
  final String alignment;
  final VoidCallback? onResendTap;
  final MessageListConfigProtocol config;
  final bool isInMergedDetailView;
  final void Function(String userID, bool isVideoCall)? onCallMessageClick;

  const CallMessageWidget({
    super.key,
    required this.message,
    required this.isSelf,
    required this.maxWidth,
    required this.config,
    this.messageListStore,
    this.bubbleKey,
    this.backgroundBuilder,
    this.alignment = AppBuilder.MESSAGE_ALIGNMENT_TWO_SIDED,
    this.onResendTap,
    this.isInMergedDetailView = false,
    this.onCallMessageClick,
  });

  @override
  State<CallMessageWidget> createState() => _CallMessageWidgetState();
}

/// 组合原消息状态和通话记录，回拨直接使用当前消息公开的对端资料。
class _CallMessageWidgetState extends State<CallMessageWidget>
    with MessageStatusMixin {
  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    final atomicLocale = AppLocalization.of(context);
    CallingMessageDataProvider provider =
        CallingMessageDataProvider(widget.message, context);
    if (!provider.isCallingSignal) {
      return Container();
    }

    if (provider.content.isEmpty) {
      return Container();
    }

    if (provider.participantType == CallParticipantType.group) {
      return SystemMessageWidget(
        customContent: provider.content,
      );
    }

    final content = Container(
      key: widget.bubbleKey,
      constraints: BoxConstraints(
        maxWidth: widget.maxWidth * 0.7,
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: _buildCallContentWithStatusAndTime(colors, atomicLocale, provider),
    );

    final bubble = widget.backgroundBuilder?.call(content) ??
        Container(
          decoration: BoxDecoration(
            color: _getBubbleColor(colors),
            borderRadius: _getBubbleBorderRadius(),
          ),
          child: content,
        );

    return GestureDetector(
      onTap: () {
        final isVideoCall =
            provider.streamMediaType == CallStreamMediaType.video;

        // 使用公开收发方字段，离线或重建消息不依赖 SDK 内部 rawMessage。
        final userID = widget.message.isSentBySelf
            ? widget.message.to
            : widget.message.from.userID;

        if (widget.onCallMessageClick != null && userID.isNotEmpty) {
          widget.onCallMessageClick!(userID, isVideoCall);
        }
      },
      child: Semantics(
          identifier: 'tim.message.call.${widget.message.msgID}',
          child: bubble),
    );
  }

  Widget _buildCallContentWithStatusAndTime(
    SemanticColorScheme colors,
    AppLocalizedText atomicLocale,
    CallingMessageDataProvider provider,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: _buildCallContent(colors, atomicLocale, provider),
        ),
        ...[
          const SizedBox(width: 8),
          ...buildStatusAndTimeWidgets(
            message: widget.message,
            isSelf: widget.isSelf,
            colors: colors,
            onResendTap: widget.onResendTap,
            isShowTimeInBubble: widget.config.isShowTimeInBubble,
            isInMergedDetailView: widget.isInMergedDetailView,
          ),
        ],
      ],
    );
  }

  Widget _buildCallContent(
    SemanticColorScheme colors,
    AppLocalizedText atomicLocale,
    CallingMessageDataProvider provider,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCallIcon(colors, provider),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            provider.content,
            style: FontScheme.caption2Medium.copyWith(
              color: widget.isSelf
                  ? colors.textColorAntiPrimary
                  : colors.textColorPrimary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCallIcon(
      SemanticColorScheme colors, CallingMessageDataProvider provider) {
    IconData iconData;

    if (provider.streamMediaType == CallStreamMediaType.audio) {
      iconData = AppIcons.phone3;
    } else {
      iconData = AppIcons.cameraOn;
    }

    return Icon(
      iconData,
      size: 20,
      color: widget.isSelf
          ? colors.textColorAntiPrimary
          : colors.textColorSecondary,
    );
  }

  Color _getBubbleColor(SemanticColorScheme colors) {
    if (widget.isSelf) {
      return colors.bgColorBubbleOwn;
    } else {
      return colors.bgColorBubbleReciprocal;
    }
  }

  BorderRadius _getBubbleBorderRadius() {
    switch (widget.alignment) {
      case 'left':
        return const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(0),
          bottomRight: Radius.circular(18),
        );
      case 'right':
        return const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(0),
        );
      case 'two-sided':
      default:
        if (widget.isSelf) {
          return const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(0),
          );
        } else {
          return const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(0),
            bottomRight: Radius.circular(18),
          );
        }
    }
  }
}
