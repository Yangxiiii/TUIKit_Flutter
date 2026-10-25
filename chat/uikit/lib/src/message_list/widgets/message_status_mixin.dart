import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';

/// 分别渲染发送进度、失败提示和阅读回执，成功发送本身不显示小勾。
mixin MessageStatusMixin {
  /// 仅在回执开启、消息已发送且请求了回执时，允许展示己方消息的阅读状态。
  static bool shouldShowReadReceipt({
    required MessageInfo message,
    required bool enableReadReceipt,
    bool isInMergedDetailView = false,
  }) {
    if (isInMergedDetailView) return false;
    if (!enableReadReceipt) return false;
    if (!message.isSentBySelf) return false;
    if (!message.needReadReceipt) return false;
    if (message.status != MessageStatus.sendSuccess) return false;
    if (message.messageType == MessageType.tips) return false;
    return true;
  }

  /// 在气泡外显示发送进度或失败提示，阅读状态由独立回执控件展示。
  Widget? buildOutsideBubbleStatusIndicator({
    required MessageInfo message,
    required SemanticColorScheme colorsTheme,
    VoidCallback? onResendTap,
  }) {
    switch (message.status) {
      case MessageStatus.sendFail:
      case MessageStatus.violation:
        return Semantics(
          identifier: 'tim.message.retry.${message.msgID}',
          button: true,
          child: GestureDetector(
            onTap: onResendTap,
            child: Icon(
              AppIcons.error,
              size: 18,
              color: colorsTheme.textColorError,
            ),
          ),
        );
      case MessageStatus.sending:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1,
            valueColor:
                AlwaysStoppedAnimation<Color>(colorsTheme.textColorSecondary),
          ),
        );
      default:
        return null;
    }
  }

  /// Check if message has error status (sendFail or violation)
  ///
  /// 检查消息是否有错误状态（发送失败或违规）
  bool hasErrorStatus(MessageInfo message) {
    return message.status == MessageStatus.sendFail ||
        message.status == MessageStatus.violation;
  }

  /// Check if message status should be shown outside bubble
  ///
  /// 检查消息状态是否应该显示在气泡之外
  bool shouldShowStatusOutsideBubble(MessageInfo message) {
    return message.status == MessageStatus.sendFail ||
        message.status == MessageStatus.violation ||
        message.status == MessageStatus.sending;
  }

  Widget buildMessageStatusIndicator({
    required MessageInfo message,
    required bool isSelf,
    required SemanticColorScheme colorsTheme,
    bool isOverlay = false,
    VoidCallback? onResendTap,
    bool enableReadReceipt = false,
    bool isInMergedDetailView = false,
  }) {
    if (!isSelf) return const SizedBox.shrink();

    switch (message.status) {
      case MessageStatus.sendSuccess:
        // 阅读回执在气泡外独立展示，发送成功不生成气泡内状态图标。
        return const SizedBox.shrink();
      case MessageStatus.sending:
      case MessageStatus.sendFail:
      case MessageStatus.violation:
        // These status icons are now shown outside the bubble in message_item.dart
        //
        // 这些状态图标现在在 message_item.dart 中显示在气泡外
        return const SizedBox.shrink();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget buildMessageTimeIndicator({
    required DateTime? dateTime,
    required SemanticColorScheme colorsTheme,
    bool isOverlay = false,
    bool isSelf = false,
  }) {
    if (dateTime == null) return const SizedBox.shrink();

    Color textColor = isOverlay
        ? colorsTheme.textColorAntiPrimary
        : (isSelf
            ? colorsTheme.textColorAntiSecondary
            : colorsTheme.textColorTertiary);

    return Text(
      _formatMessageTime(dateTime),
      style: FontScheme.caption3Regular.copyWith(
        color: textColor,
        height: 1.5,
      ),
    );
  }

  List<Widget> buildStatusAndTimeWidgets({
    required MessageInfo message,
    required bool isSelf,
    required SemanticColorScheme colors,
    bool isOverlay = false,
    VoidCallback? onResendTap,
    bool isShowTimeInBubble = true,
    bool enableReadReceipt = false,
    bool isInMergedDetailView = false,
  }) {
    final widgets = <Widget>[];

    final statusWidget = buildMessageStatusIndicator(
      message: message,
      isSelf: isSelf,
      colorsTheme: colors,
      isOverlay: isOverlay,
      onResendTap: onResendTap,
      enableReadReceipt: enableReadReceipt,
      isInMergedDetailView: isInMergedDetailView,
    );

    if (statusWidget is! SizedBox || statusWidget.child != null) {
      widgets.add(statusWidget);
      widgets.add(const SizedBox(width: 3));
    }

    if (isShowTimeInBubble) {
      DateTime dateTime =
          DateTime.fromMillisecondsSinceEpoch((message.timestamp ?? 0) * 1000);
      final timeWidget = buildMessageTimeIndicator(
        dateTime: dateTime,
        colorsTheme: colors,
        isOverlay: isOverlay,
        isSelf: isSelf,
      );

      if (timeWidget is! SizedBox || timeWidget.child != null) {
        widgets.add(timeWidget);
      }
    }

    return widgets;
  }

  String _formatMessageTime(DateTime dateTime) {
    return "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
  }

  /// 在气泡外显示阅读回执：单聊使用已读/未读图标，群聊保留人数和详情入口。
  /// 仅展示开启回执且发送成功的己方消息；无回执的历史消息不补造阅读状态。
  Widget? buildOutsideReadReceiptIndicator({
    required MessageInfo message,
    required SemanticColorScheme colorsTheme,
    required AppLocalizedText locale,
    required bool enableReadReceipt,
    bool isInMergedDetailView = false,
    VoidCallback? onTap,
  }) {
    if (!shouldShowReadReceipt(
      message: message,
      enableReadReceipt: enableReadReceipt,
      isInMergedDetailView: isInMergedDetailView,
    )) {
      return null;
    }

    final isGroup = message.conversationType == ConversationType.group;
    if (!isGroup) {
      // 发送成功只是展示回执的前提，小勾必须随对方阅读回执变化。
      final isRead = message.readReceiptInfo?.isPeerRead == true;
      return Icon(
        isRead ? AppIcons.read : AppIcons.unread,
        size: 18,
        color: isRead
            ? colorsTheme.textColorSuccess
            : colorsTheme.textColorSecondary,
        semanticLabel: isRead ? locale.groupReadBy : locale.groupDeliveredTo,
      );
    }

    String text;
    Color textColor;
    // 群聊保留原有全部已读、部分已读和无人已读的统计含义。
    final readCount = message.readReceiptInfo?.readCount ?? 0;
    final unreadCount = message.readReceiptInfo?.unreadCount ?? 0;
    final totalCount = readCount + unreadCount;
    if (totalCount > 0 && readCount == totalCount) {
      text = locale.readReceiptAllRead;
      textColor = colorsTheme.textColorSecondary;
    } else if (readCount > 0) {
      text = locale.readReceiptNPersonRead(readCount);
      textColor = colorsTheme.buttonColorPrimaryDefault;
    } else {
      text = locale.groupDeliveredTo;
      textColor = colorsTheme.buttonColorPrimaryDefault;
    }

    final textWidget = Text(
      text,
      style: FontScheme.caption3Regular.copyWith(
        color: textColor,
      ),
    );

    // 群聊人数仍可打开回执详情，单聊图标只用于状态展示。
    if (onTap != null) {
      return Semantics(
        identifier: 'chat.message.read_receipt.${message.msgID}',
        child: GestureDetector(onTap: onTap, child: textWidget),
      );
    }

    return textWidget;
  }
}
