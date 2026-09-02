import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart' hide AlertDialog;
import 'package:flutter/services.dart';
import 'super_tooltip.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_resender.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_picker_model.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/asr_display_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/calling_message_data_provider.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/recent_emoji_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/translation_display_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/translation_text_parser.dart';
import 'package:tencent_chat_uikit/src/message_list/listen/listen_from_here_controller.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/forward/forward_service.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_read_receipt_view.dart';

import 'message_tooltip.dart';
import 'quote_message_preview.dart';
import 'message_types/call_message_widget.dart';
import 'message_types/file_message_widget.dart';
import 'message_types/image_message_widget.dart';
import 'message_types/merged_message_widget.dart';
import 'message_types/sound_message_widget.dart';
import 'message_types/text_message_widget.dart';
import 'message_types/video_message_widget.dart';

class DefaultMessageMenuCallbacks implements MessageMenuCallbacks {
  final BuildContext context;
  final MessageListStore messageListStore;
  final String conversationID;
  final MessageListConfigProtocol config;
  MessageActionStore messageActionStore;
  final VoidCallback? onMultiSelectTriggered;
  final void Function(MessageInfo message)? onQuoteMessageCallback;

  DefaultMessageMenuCallbacks({
    required this.context,
    required this.messageListStore,
    required this.messageActionStore,
    required this.conversationID,
    required this.config,
    this.onMultiSelectTriggered,
    this.onQuoteMessageCallback,
  });

  @override
  void onCopyMessage(MessageInfo message) {
    Clipboard.setData(ClipboardData(
        text: (message.messagePayload as TextMessagePayload?)?.text ?? ""));
  }

  @override
  void onDeleteMessage(MessageInfo message) {
    messageActionStore.delete();
  }

  @override
  void onRecallMessage(MessageInfo message) {
    messageActionStore.revoke();
  }

  @override
  void onForwardMessage(MessageInfo message) {
    // Validate message status first
    //
    // 先验证消息状态。
    final statusError =
        ForwardService.validateMessagesStatus(context, [message]);
    if (statusError != null) {
      Toast.error(context, statusError);
      return;
    }

    ForwardService.forwardSingleMessage(
      context: context,
      message: message,
      messageListStore: messageListStore,
      config: config,
      excludeConversationID: conversationID,
    );
  }

  @override
  void onQuoteMessage(MessageInfo message) {
    onQuoteMessageCallback?.call(message);
  }

  @override
  void onMultiSelectMessage(MessageInfo message) {
    onMultiSelectTriggered?.call();
  }

  @override
  void onResendMessage(MessageInfo message) {}
}

class MessageBubble extends StatefulWidget {
  final MessageInfo message;
  final String conversationID;
  final bool isSelf;
  final double maxWidth;
  final MessageListStore messageListStore;
  final MessageMenuCallbacks? menuCallbacks;
  final bool isHighlighted;
  final VoidCallback? onHighlightComplete;
  final List<MessageCustomAction> customActions;
  final MessageListConfigProtocol config;
  // Merged detail view mode - disables long press menu and read receipt
  //
  // 合并详情视图模式——禁用长按菜单和已读回执。
  final bool isInMergedDetailView;
  // ASR display manager for voice-to-text feature
  //
  // 语音转文本功能的ASR显示管理器
  final AsrDisplayManager? asrDisplayManager;
  // Callback when ASR text bubble is long pressed, provides message and GlobalKey for positioning popup menu
  //
  // 当ASR文本气泡被长按时的回调，提供消息和用于定位弹出菜单的GlobalKey
  final void Function(MessageInfo message, GlobalKey asrBubbleKey)?
      onAsrBubbleLongPress;
  // Translation display manager for text translation feature
  //
  // 文本翻译功能的翻译显示管理器
  final TranslationDisplayManager? translationDisplayManager;
  // Callback when translation bubble is long pressed, provides message and GlobalKey for positioning popup menu
  //
  // 当翻译气泡被长按时的回调，提供消息和用于定位弹出菜单的GlobalKey
  final void Function(MessageInfo message, GlobalKey translationBubbleKey)?
      onTranslationBubbleLongPress;
  // Callback when call message is clicked in C2C conversation
  //
  // 在C2C对话中点击通话消息时的回调
  final void Function(String userID, bool isVideoCall)? onCallMessageClick;
  // Callback when quote preview is tapped (for navigation to quoted message)
  //
  // 点击引用预览时的回调（用于导航到被引用的消息）
  final void Function(MessageInfo message)? onQuotePreviewTap;

  /// In merged detail view: the bundle's full message list, used as the
  /// static data source for image / video viewers (the page's
  /// MessageListStore is empty in this mode).
  ///
  /// 在合并详情视图中：bundle的完整消息列表，用作图片/视频查看器的静态数据源（该模式下页面的MessageListStore为空）。
  final List<MessageInfo>? mergedMediaMessages;

  const MessageBubble({
    super.key,
    required this.message,
    required this.conversationID,
    required this.isSelf,
    required this.maxWidth,
    required this.config,
    required this.messageListStore,
    this.menuCallbacks,
    this.isHighlighted = false,
    this.onHighlightComplete,
    this.customActions = const [],
    this.isInMergedDetailView = false,
    this.asrDisplayManager,
    this.onAsrBubbleLongPress,
    this.translationDisplayManager,
    this.onTranslationBubbleLongPress,
    this.onCallMessageClick,
    this.onQuotePreviewTap,
    this.mergedMediaMessages,
  });

  @override
  State<StatefulWidget> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late MessageMenuCallbacks _menuCallbacks;
  final GlobalKey _messageKey = GlobalKey();
  SuperTooltip? tooltip;

  late AnimationController _highlightAnimationController;

  late AppLocalizedText atomicLocal;

  @override
  void initState() {
    super.initState();
    _menuCallbacks = widget.menuCallbacks ??
        DefaultMessageMenuCallbacks(
          context: context,
          messageListStore: widget.messageListStore,
          messageActionStore: MessageActionStore.create(widget.message),
          conversationID: widget.conversationID,
          config: widget.config,
        );

    _highlightAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _highlightAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          widget.onHighlightComplete != null) {
        widget.onHighlightComplete!();
      }
    });

    if (widget.isHighlighted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _highlightAnimationController.forward(from: 0.0);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    atomicLocal = AppLocalization.of(context);
  }

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isHighlighted && !_highlightAnimationController.isAnimating) {
      _highlightAnimationController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _highlightAnimationController.dispose();
    if (tooltip?.isOpen ?? false) {
      tooltip?.close();
    }
    super.dispose();
  }

  void _showResendConfirmDialog() {
    AtomicAlertDialog.showWithConfig(
      context,
      config: AlertDialogConfig(
        title: atomicLocal.resendTips,
        cancelConfig: ButtonConfig(text: atomicLocal.cancel),
        confirmConfig: ButtonConfig(
          text: atomicLocal.confirm,
          type: TextColorPreset.blue,
          onClick: _handleResendMessage,
        ),
      ),
    );
  }

  void _handleResendMessage() {
    MessageResender.resend(
      message: widget.message,
      conversationID: widget.conversationID,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorsTheme = SemanticColorScheme.of(context);

    Widget backgroundBuilder(Widget child) {
      if (widget.isHighlighted) {
        return AnimatedBuilder(
          animation: _highlightAnimationController,
          builder: (context, animChild) {
            final colorAnimation = ColorTween(
              begin: _getBubbleColor(colorsTheme),
              end: colorsTheme.textColorWarning,
            ).animate(CurvedAnimation(
              parent: _highlightAnimationController,
              curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
            ));
            final reverseColorAnimation = ColorTween(
              begin: colorsTheme.textColorWarning,
              end: _getBubbleColor(colorsTheme),
            ).animate(CurvedAnimation(
              parent: _highlightAnimationController,
              curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
            ));

            return Container(
              decoration: BoxDecoration(
                color: _highlightAnimationController.value <= 0.5
                    ? colorAnimation.value
                    : reverseColorAnimation.value,
                borderRadius: _getBubbleBorderRadius(),
              ),
              child: animChild,
            );
          },
          child: child,
        );
      }
      return Container(
        decoration: BoxDecoration(
          color: _getBubbleColor(colorsTheme),
          borderRadius: _getBubbleBorderRadius(),
        ),
        child: child,
      );
    }

    if (widget.message.status == MessageStatus.revoked) {
      return SystemMessageWidget(
        message: widget.message,
      );
    }

    Widget messageWidget;

    switch (widget.message.messageType) {
      case MessageType.text:
        messageWidget = TextMessageWidget(
          message: widget.message,
          isSelf: widget.isSelf,
          maxWidth: widget.maxWidth,
          config: widget.config,
          onLongPress:
              widget.message.quoteInfo != null ? null : _longPressCallback,
          bubbleKey: widget.message.quoteInfo != null ? null : _messageKey,
          backgroundBuilder: widget.message.quoteInfo != null
              ? (child) => child
              : backgroundBuilder,
          onResendTap: widget.message.status == MessageStatus.sendFail
              ? _showResendConfirmDialog
              : null,
          isInMergedDetailView: widget.isInMergedDetailView,
        );
        break;

      case MessageType.image:
        messageWidget = _wrapMediaHighlight(
          ImageMessageWidget(
            message: widget.message,
            conversationID: widget.conversationID,
            isSelf: widget.isSelf,
            maxWidth: widget.maxWidth,
            config: widget.config,
            onLongPress: _longPressCallback,
            messageListStore: widget.messageListStore,
            isInMergedDetailView: widget.isInMergedDetailView,
            mergedMediaMessages: widget.mergedMediaMessages,
            bubbleKey: _messageKey,
          ),
          colorsTheme,
        );
        break;

      case MessageType.video:
        messageWidget = _wrapMediaHighlight(
          VideoMessageWidget(
            message: widget.message,
            conversationID: widget.conversationID,
            isSelf: widget.isSelf,
            maxWidth: widget.maxWidth,
            config: widget.config,
            onLongPress: _longPressCallback,
            messageListStore: widget.messageListStore,
            isInMergedDetailView: widget.isInMergedDetailView,
            mergedMediaMessages: widget.mergedMediaMessages,
            bubbleKey: _messageKey,
          ),
          colorsTheme,
        );
        break;

      case MessageType.audio:
        if (widget.isHighlighted) {
          messageWidget = AnimatedBuilder(
            animation: _highlightAnimationController,
            builder: (context, _) {
              return SoundMessageWidget(
                message: widget.message,
                isSelf: widget.isSelf,
                maxWidth: widget.maxWidth,
                config: widget.config,
                onLongPress: _longPressCallback,
                messageListStore: widget.messageListStore,
                isInMergedDetailView: widget.isInMergedDetailView,
                bubbleKey: _messageKey,
                bubbleColor: _animatedBubbleColor(colorsTheme),
              );
            },
          );
        } else {
          messageWidget = SoundMessageWidget(
            message: widget.message,
            isSelf: widget.isSelf,
            maxWidth: widget.maxWidth,
            config: widget.config,
            onLongPress: _longPressCallback,
            messageListStore: widget.messageListStore,
            isInMergedDetailView: widget.isInMergedDetailView,
            bubbleKey: _messageKey,
          );
        }
        break;

      case MessageType.file:
        if (widget.isHighlighted) {
          messageWidget = AnimatedBuilder(
            animation: _highlightAnimationController,
            builder: (context, _) {
              return FileMessageWidget(
                message: widget.message,
                isSelf: widget.isSelf,
                maxWidth: widget.maxWidth,
                config: widget.config,
                onLongPress: _longPressCallback,
                messageListStore: widget.messageListStore,
                isInMergedDetailView: widget.isInMergedDetailView,
                bubbleKey: _messageKey,
                bubbleColor: _animatedBubbleColor(colorsTheme),
              );
            },
          );
        } else {
          messageWidget = FileMessageWidget(
            message: widget.message,
            isSelf: widget.isSelf,
            maxWidth: widget.maxWidth,
            config: widget.config,
            onLongPress: _longPressCallback,
            messageListStore: widget.messageListStore,
            isInMergedDetailView: widget.isInMergedDetailView,
            bubbleKey: _messageKey,
          );
        }
        break;

      case MessageType.tips:
        messageWidget = SystemMessageWidget(
          message: widget.message,
        );
        break;

      case MessageType.custom:
        CallingMessageDataProvider provider =
            CallingMessageDataProvider(widget.message, context);
        if (provider.isCallingSignal) {
          messageWidget = CallMessageWidget(
            message: widget.message,
            isSelf: widget.isSelf,
            maxWidth: widget.maxWidth,
            isInMergedDetailView: widget.isInMergedDetailView,
            config: widget.config,
            onCallMessageClick: widget.onCallMessageClick,
          );
        } else {
          messageWidget = CustomMessageWidget(
            message: widget.message,
            isSelf: widget.isSelf,
            maxWidth: widget.maxWidth,
            onLongPress: _longPressCallback,
            messageListStore: widget.messageListStore,
          );
        }
        break;

      case MessageType.merged:
        if (widget.isHighlighted) {
          // Same pattern as audio / file: drive the bubble's background
          // colour through the highlight animation by re-passing
          // `_animatedBubbleColor` on every tick. MergedMessageWidget
          // forwards this into its outer Container's decoration.color
          // so the warning flash actually replaces the default bubble
          // colour rather than being painted under it (which the merged
          // bubble would have hidden).
          //
          // 和音频/文件同样的模式：通过在每次动画帧中重新传递`_animatedBubbleColor`来驱动气泡背景颜色的高亮动画。MergedMessageWidget 会把它传到外层 Container
          // 的 decoration.color，这样警告闪烁实际上是替换默认气泡颜色，而不是在其下层绘制（否则合并气泡会遮挡）。
          messageWidget = AnimatedBuilder(
            animation: _highlightAnimationController,
            builder: (context, _) {
              return MergedMessageWidget(
                message: widget.message,
                isSelf: widget.isSelf,
                maxWidth: widget.maxWidth,
                config: widget.config,
                onLongPress: _longPressCallback,
                bubbleKey: _messageKey,
                messageListStore: widget.messageListStore,
                isInMergedDetailView: widget.isInMergedDetailView,
                bubbleColor: _animatedBubbleColor(colorsTheme),
              );
            },
          );
        } else {
          messageWidget = MergedMessageWidget(
            message: widget.message,
            isSelf: widget.isSelf,
            maxWidth: widget.maxWidth,
            config: widget.config,
            onLongPress: _longPressCallback,
            bubbleKey: _messageKey,
            messageListStore: widget.messageListStore,
            isInMergedDetailView: widget.isInMergedDetailView,
          );
        }
        break;

      default:
        if (!widget.config.isShowUnsupportMessage) {
          return const SizedBox.shrink();
        }
        messageWidget = _buildUnsupportedMessage(context);
    }

    // Wrap with quote message preview if this message has quoteInfo
    // The quote preview is placed INSIDE the bubble (same background)
    //
    // 如果消息有 quoteInfo，就用引用消息预览包裹。引用预览放在气泡内部（同样的背景）。
    if (widget.message.quoteInfo != null) {
      final quotePreview = QuoteMessagePreview(
        quoteInfo: widget.message.quoteInfo!,
        maxWidth: widget.maxWidth * 0.7,
        onTap: widget.onQuotePreviewTap != null
            ? () => widget.onQuotePreviewTap!(widget.message)
            : null,
      );
      final colorsTheme = SemanticColorScheme.of(context);
      final columnChild = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          quotePreview,
          messageWidget,
        ],
      );
      Widget bubbleContainer;
      if (widget.isHighlighted) {
        // Apply highlight animation to the outer bubble container
        //
        // 对外层气泡容器应用高亮动画。
        bubbleContainer = AnimatedBuilder(
          animation: _highlightAnimationController,
          builder: (context, animChild) {
            final colorAnimation = ColorTween(
              begin: _getBubbleColor(colorsTheme),
              end: colorsTheme.textColorWarning,
            ).animate(CurvedAnimation(
              parent: _highlightAnimationController,
              curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
            ));
            final reverseColorAnimation = ColorTween(
              begin: colorsTheme.textColorWarning,
              end: _getBubbleColor(colorsTheme),
            ).animate(CurvedAnimation(
              parent: _highlightAnimationController,
              curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
            ));
            return Container(
              constraints: BoxConstraints(maxWidth: widget.maxWidth * 0.7),
              decoration: BoxDecoration(
                color: _highlightAnimationController.value <= 0.5
                    ? colorAnimation.value
                    : reverseColorAnimation.value,
                borderRadius: _getBubbleBorderRadius(),
              ),
              child: animChild,
            );
          },
          child: columnChild,
        );
      } else {
        bubbleContainer = Container(
          constraints: BoxConstraints(maxWidth: widget.maxWidth * 0.7),
          decoration: BoxDecoration(
            color: _getBubbleColor(colorsTheme),
            borderRadius: _getBubbleBorderRadius(),
          ),
          child: columnChild,
        );
      }
      messageWidget = GestureDetector(
        onLongPress: _longPressCallback,
        child: bubbleContainer,
      );
    }

    return messageWidget;
  }

  void _handleLongPress() {
    _onOpenToolTip();
  }

  /// Get long press callback - returns null if in merged detail view
  ///
  /// 获取长按回调——如果在合并详情视图中返回 null。
  VoidCallback? get _longPressCallback =>
      widget.isInMergedDetailView ? null : _handleLongPress;

  /// Compute animated bubble color for highlight effect (used by audio/file widgets)
  ///
  /// 计算用于高亮效果的动画气泡颜色（音频/文件控件使用）。
  Color _animatedBubbleColor(SemanticColorScheme colorsTheme) {
    final baseColor = _getBubbleColor(colorsTheme);
    final highlightColor = colorsTheme.textColorWarning;
    final t = _highlightAnimationController.value;
    if (t <= 0.5) {
      // 0.0 -> 0.4: ease in to highlight
      //
      // 0.0 -> 0.4：缓入高亮。
      final progress = (t / 0.4).clamp(0.0, 1.0);
      return Color.lerp(
          baseColor, highlightColor, Curves.easeIn.transform(progress))!;
    } else {
      // 0.6 -> 1.0: ease out back to base
      //
      // 0.6 -> 1.0：缓出回到基础颜色。
      final progress = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
      return Color.lerp(
          highlightColor, baseColor, Curves.easeOut.transform(progress))!;
    }
  }

  /// Wrap a media child (image / video) with a translucent highlight
  /// overlay animation. Media payloads don't have a bubble background of
  /// their own — the image/video fills the entire bubble area, so the
  /// bubble-colour animation used for text / audio / file / merged is
  /// invisible behind the media. Instead we overlay a semi-transparent
  /// warning-coloured rectangle that fades in, holds, then fades back
  /// out, on the same curve as the bubble-colour animation.
  ///
  /// The overlay is wrapped in [IgnorePointer] so it doesn't eat taps
  /// (the underlying tap → open-image-viewer flow still works).
  ///
  /// 给媒体子元素（图片/视频）加一个半透明高亮覆盖动画。媒体内容本身没有气泡背景——图片/视频会填满整个气泡区域，所以用于文本/音频/文件/合并消息的气泡颜色动画在媒体背后不可见。我们改为叠加一个半透明的警告色矩形，它会淡入、保持一段时间，然后再淡出，动画曲线与气泡颜色动画一致。
  ///
  /// 覆盖层使用了[IgnorePointer]包装，所以不会拦截点击（底层点击 → 打开图片查看器流程仍然有效）。
  Widget _wrapMediaHighlight(Widget child, SemanticColorScheme colorsTheme) {
    if (!widget.isHighlighted) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _highlightAnimationController,
              builder: (context, _) {
                return Container(
                  decoration: BoxDecoration(
                    color: colorsTheme.textColorWarning.withValues(
                      alpha: _mediaHighlightOverlayAlpha(
                          _highlightAnimationController.value),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Eased-in / hold / eased-out alpha curve for the media highlight
  /// overlay. Matches the timing of the bubble-colour animation:
  ///   t ∈ [0.0, 0.4): ease in to peak
  ///   t ∈ [0.4, 0.6): hold at peak
  ///   t ∈ [0.6, 1.0]: ease out to 0
  ///
  /// 媒体高亮覆盖层的透明度曲线为渐入/保持/渐出，时间与气泡颜色动画一致：t ∈ [0.0, 0.4)：渐入到高峰 t ∈ [0.4, 0.6)：保持高峰 t ∈ [0.6, 1.0]：渐出到0
  double _mediaHighlightOverlayAlpha(double t) {
    const peak = 0.4;
    if (t <= 0.4) {
      return Curves.easeIn.transform((t / 0.4).clamp(0.0, 1.0)) * peak;
    }
    if (t < 0.6) {
      return peak;
    }
    return (1 - Curves.easeOut.transform(((t - 0.6) / 0.4).clamp(0.0, 1.0))) *
        peak;
  }

  void _onOpenToolTip() {
    if (tooltip != null && tooltip!.isOpen) {
      tooltip!.close();
      return;
    }
    tooltip = null;

    final colorsTheme = SemanticColorScheme.of(context);
    final isSelf = widget.isSelf;

    // Estimated menu height including reaction picker
    //
    // 预计菜单高度，包括表情反应选择器
    const estimatedMenuHeight = 120.0;
    // Minimum top padding to avoid going above message_list area (considering app bar, status bar, etc.)
    //
    // 为了避免超出 message_list 区域的最小顶部内边距（考虑应用栏、状态栏等）
    const minTopPadding = 100.0;
    // Minimum bottom padding to avoid going below message_list area (considering input bar, etc.)
    //
    // 为了避免低于 message_list 区域的最小底部内边距（考虑输入栏等）
    const minBottomPadding = 120.0;
    // Minimum horizontal padding to prevent tooltip from touching screen edges
    //
    // 防止Tooltip触碰屏幕边缘的最小水平内边距
    const minHorizontalPadding = 8.0;

    TooltipDirection popupDirection = TooltipDirection.up;
    double arrowTipDistance = 15;
    bool hasArrow = true;
    Offset? customTargetCenter;

    RenderBox? box =
        _messageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      double screenHeight = MediaQuery.of(context).size.height;
      Offset offset = box.localToGlobal(Offset.zero);
      double boxWidth = box.size.width;
      double boxHeight = box.size.height;

      // Bubble top Y position (relative to screen)
      //
      // 气泡的顶部 Y 位置（相对于屏幕）
      double bubbleTopY = offset.dy;
      // Bubble bottom Y position (relative to screen)
      //
      // 气泡的底部 Y 位置（相对于屏幕）
      double bubbleBottomY = offset.dy + boxHeight;

      // Anchor X to the bubble's horizontal center. The arrow inside
      // SuperTooltip will then point straight down (or up) to this X,
      // so it visually originates from the bubble's center.
      //
      // We intentionally don't pass `left`/`right` to SuperTooltip:
      // when both sides are pinned, `_PopupBallonLayoutDelegate` uses
      // `_left` verbatim regardless of the menu's actual width, which
      // produces a menu rect that does NOT contain targetX — that's
      // what was making the arrow render as a long diagonal tether
      // from the menu's edge to the bubble. The default layout
      // (no left/right) centers the menu on targetX and clamps it to
      // the screen's outside padding, so the menu rect always
      // contains targetX and the arrow stays as a short triangle
      // anchored at the bubble's center.
      //
      // 将锚点 X 定位到气泡的水平中心。SuperTooltip 内的箭头会直接指向这个 X，从而在视觉上看起来是从气泡中心出来的。
      //
      // 我们故意不把 `left`/`right` 传给 SuperTooltip：当两边都固定时，`_PopupBallonLayoutDelegate` 会直接使用
      // `_left`，而不管菜单的实际宽度，这会产生一个不包含 targetX 的菜单矩形——这就是为什么箭头会从菜单边缘拉出一条长斜线到气泡的原因。默认布局（不设置 left/right）会把菜单在
      // targetX 上居中，并限制在屏幕的外部间距内，所以菜单矩形总是包含 targetX，箭头保持为一个短三角，锚定在气泡中心。
      final double targetX = offset.dx + boxWidth / 2;

      // Calculate available space:
      // - Space above bubble top: from minTopPadding to bubble top
      // - Space below bubble bottom: from bubble bottom to (screenHeight - minBottomPadding)
      //
      // 计算可用空间：- 气泡顶部上方的空间：从 minTopPadding 到气泡顶部 - 气泡底部下方的空间：从气泡底部到（screenHeight - minBottomPadding）
      double spaceAboveBubbleTop = bubbleTopY - minTopPadding;
      double spaceBelowBubbleBottom =
          (screenHeight - minBottomPadding) - bubbleBottomY;

      // Priority 1: If there's enough space above the bubble top, show tooltip above
      //
      // 优先级 1：如果气泡顶部上方有足够空间，就在上方显示提示
      if (spaceAboveBubbleTop >= estimatedMenuHeight) {
        popupDirection = TooltipDirection.up;
        hasArrow = true;
        arrowTipDistance = 15;
        // Use bubble top as target center (not bubble center) so tooltip appears above the visible top
        //
        // 使用气泡顶部作为目标中心（不是气泡中心），这样提示会出现在可见顶部上方
        customTargetCenter = Offset(targetX, bubbleTopY);
      }
      // Priority 2: If there's enough space below the bubble bottom, show tooltip below
      //
      // 优先级2：如果气泡底部下方有足够空间，提示显示在下方
      else if (spaceBelowBubbleBottom >= estimatedMenuHeight) {
        popupDirection = TooltipDirection.down;
        hasArrow = true;
        arrowTipDistance = 15;
        // Use bubble bottom as target center so tooltip appears below the visible bottom
        //
        // 使用气泡底部作为目标中心，这样提示会出现在可见底部下方
        customTargetCenter = Offset(targetX, bubbleBottomY);
      }
      // Priority 3: Not enough space above or below, show at the bottom of message_list
      //
      // 优先级3：上下都没有足够空间，显示在 message_list 底部
      else {
        popupDirection = TooltipDirection.up;
        hasArrow = false;
        arrowTipDistance = 0;
        // Position tooltip at the bottom of message_list area (but not exceeding it)
        // The tooltip will be placed above this target center point
        //
        // 将提示定位在 message_list 区域底部（但不超出），提示会放在这个目标中心点上方
        double targetY = screenHeight - minBottomPadding;
        customTargetCenter = Offset(targetX, targetY);
      }
    }

    final menuItems = _buildMenuItems();

    tooltip = SuperTooltip(
      popupDirection: popupDirection,
      minimumOutSidePadding: minHorizontalPadding,
      arrowTipDistance: arrowTipDistance,
      arrowBaseWidth: hasArrow ? 10 : 0,
      arrowLength: hasArrow ? 10 : 0,
      hasArrow: hasArrow,
      borderColor: colorsTheme.bgColorDefault,
      backgroundColor: colorsTheme.bgColorDialog,
      shadowColor: colorsTheme.shadowColor,
      hasShadow: true,
      borderWidth: 1.0,
      showCloseButton: ShowCloseButton.none,
      touchThroughAreaShape: ClipAreaShape.rectangle,
      content: MessageTooltip(
        menuItems: menuItems,
        message: widget.message,
        onCloseTooltip: () => tooltip?.close(),
        isSelf: isSelf,
        // Violation messages should not show reaction picker
        //
        // 违规消息不应该显示表情选择器
        showReactionPicker: widget.config.isSupportReaction &&
            widget.message.status != MessageStatus.violation,
        onReactionSelected: widget.config.isSupportReaction &&
                widget.message.status != MessageStatus.violation
            ? _handleReactionSelected
            : null,
      ),
    );

    tooltip?.show(context, targetCenter: customTargetCenter);
  }

  /// 提交或撤销消息回应，SDK 拒绝操作时仅记录控制台日志。
  Future<void> _handleReactionSelected(EmojiPickerModelItem emoji) async {
    final messageActionStore = MessageActionStore.create(widget.message);
    // 已回应同一表情时再次点击表示撤销，否则新增回应。
    final existingReaction = widget.message.reactionList.firstWhere(
      (r) => r.reactionID == emoji.name && r.reactedByMyself,
      orElse: () => MessageReaction(
        reactionID: '',
        totalUserCount: 0,
        partialUserList: [],
        reactedByMyself: false,
      ),
    );

    final isRemoving = existingReaction.reactionID.isNotEmpty;
    final result = isRemoving
        ? await messageActionStore.removeReaction(reactionID: emoji.name)
        : await messageActionStore.addReaction(reactionID: emoji.name);
    if (!mounted) return;

    if (!result.isSuccess) {
      debugPrint(
        '消息回应失败：errorCode=${result.errorCode}, '
        'errorMessage=${result.errorMessage}',
      );
      return;
    }

    if (!isRemoving) {
      await RecentEmojiManager.addRecentEmoji(emoji.name);
    }
  }

  List<MessageMenuItem> _buildMenuItems() {
    final items = <MessageMenuItem>[];

    items.addAll(_buildMenuItemsForMessageType(widget.message.messageType));

    return items;
  }

  List<MessageMenuItem> _buildMenuItemsForMessageType(MessageType messageType) {
    final items = <MessageMenuItem>[];

    switch (messageType) {
      case MessageType.text:
        items.addAll(_buildTextMessagePayloadMenuItems());
        break;
      case MessageType.image:
        items.addAll(_buildImageMessagePayloadMenuItems());
        break;
      case MessageType.video:
        items.addAll(_buildVideoMessagePayloadMenuItems());
        break;
      case MessageType.audio:
        items.addAll(_buildSoundMessageMenuItems());
        break;
      case MessageType.file:
        items.addAll(_buildFileMessagePayloadMenuItems());
        break;
      case MessageType.custom:
        items.addAll(_buildCustomMessagePayloadMenuItems());
        break;
      default:
        items.addAll(_buildCommonMenuItems());
    }

    return items;
  }

  List<MessageMenuItem> _buildTextMessagePayloadMenuItems() {
    final items = <MessageMenuItem>[];

    // Translate menu item
    //
    // 翻译菜单项
    if (_shouldShowTranslateMenuItem()) {
      items.add(MessageMenuItem(
        title: atomicLocal.translate,
        assetName: 'chat_assets/icon/translate.svg',
        package: 'tencent_chat_uikit',
        icon: Icons.translate,
        onTap: () => _handleTranslateText(),
      ));
    }

    items.addAll(_buildCommonMenuItems(includeCopy: true));

    return items;
  }

  /// Check if "Translate" menu item should be shown
  ///
  /// 检查是否该显示“翻译”菜单项
  bool _shouldShowTranslateMenuItem() {
    // Check if translate feature is enabled in config
    //
    // 检查配置中是否开启了翻译功能
    if (!widget.config.isSupportTranslate) return false;

    // Only for text messages
    //
    // 仅适用于文本消息
    if (widget.message.messageType != MessageType.text) return false;

    // Only for successfully sent messages
    //
    // 仅适用于成功发送的消息
    if (widget.message.status != MessageStatus.sendSuccess) return false;

    // Violation messages cannot be translated
    //
    // 违规消息不能翻译
    if (widget.message.status == MessageStatus.violation) return false;

    final hasTranslation =
        (widget.message.messagePayload as TextMessagePayload?)
                ?.translatedText
                ?.isNotEmpty ==
            true;
    final messageID = widget.message.msgID ?? '';
    final isHidden =
        widget.translationDisplayManager?.isHidden(messageID) ?? false;

    // Show menu when: no translation OR translation is hidden
    //
    // 当没有翻译或翻译被隐藏时显示菜单
    return !hasTranslation || isHidden;
  }

  /// Handle translate text action
  ///
  /// 处理翻译文本操作
  void _handleTranslateText() async {
    final messageID = widget.message.msgID ?? '';
    final hasTranslation =
        (widget.message.messagePayload as TextMessagePayload?)
                ?.translatedText
                ?.isNotEmpty ==
            true;

    // Check if target language has changed
    //
    // 检查目标语言是否已更改
    final cachedLanguage =
        (widget.message.messagePayload as TextMessagePayload?)
            ?.translateLanguage;
    final currentTargetLanguage =
        AppBuilder.getInstance().translateConfig.targetLanguage;
    final languageChanged = hasTranslation &&
        cachedLanguage != null &&
        cachedLanguage != currentTargetLanguage;

    // If already has translation and language not changed, just show it again
    if (hasTranslation && !languageChanged) {
      widget.translationDisplayManager?.show(messageID);
      return;
    }

    // Set translating state (this also removes from hidden set)
    //
    // 设置翻译状态（这也会从隐藏集合中移除）
    widget.translationDisplayManager?.setTranslating(messageID, true);

    // Get the text to translate
    //
    // 获取要翻译的文本
    final text =
        (widget.message.messagePayload as TextMessagePayload?)?.text ?? '';
    if (text.isEmpty) {
      widget.translationDisplayManager?.setTranslating(messageID, false);
      return;
    }

    // Get @ user names first, then parse and translate
    //
    // 先获取@用户名，然后解析并翻译
    final allMembersText = atomicLocal.messageInputAllMembers;
    final atUserNames = await TranslationTextParser.getAtUserNames(
      widget.message,
      allMembersText: allMembersText,
    );

    _performTranslation(text: text, atUserNames: atUserNames);
  }

  /// Perform the actual translation
  ///
  /// 执行实际翻译
  void _performTranslation({required String text, List<String>? atUserNames}) {
    final messageID = widget.message.msgID ?? '';

    // Parse text to separate emoji and @ from translatable text
    //
    // 解析文本以分离表情和@符号与可翻译文本
    final splitResult = TranslationTextParser.splitTextByEmojiAndAtUsers(
      text,
      atUserNames: atUserNames,
    );
    final textArray = (splitResult?[TranslationTextParser.kSplitStringTextKey]
            as List<String>?) ??
        [];

    // If nothing to translate (pure emoji/@ message), clear translating state
    if (textArray.isEmpty) {
      widget.translationDisplayManager?.setTranslating(messageID, false);
      return;
    }

    // Call the API - use target language from AppBuilder settings
    //
    // 调用API - 使用AppBuilder设置中的目标语言
    final messageActionStore = MessageActionStore.create(widget.message);
    final targetLanguage =
        AppBuilder.getInstance().translateConfig.targetLanguage;
    messageActionStore
        .translateText(
      sourceTextList: textArray,
      targetLanguage: targetLanguage,
    )
        .then((result) {
      // Clear translating state
      //
      // 清除翻译状态
      widget.translationDisplayManager?.setTranslating(messageID, false);

      if (!result.isSuccess) {
        // Show error toast using base_component Toast
        //
        // 使用base_component Toast显示错误提示
        if (mounted) {
          Toast.error(context, atomicLocal.translateFailed);
        }
      }
      // On success, translatedText will be updated in message and shown by default
      //
      // 成功时，translatedText会在消息中更新并默认显示
    });
  }

  List<MessageMenuItem> _buildImageMessagePayloadMenuItems() {
    final items = <MessageMenuItem>[];

    items.addAll(_buildCommonMenuItems());

    return items;
  }

  List<MessageMenuItem> _buildVideoMessagePayloadMenuItems() {
    final items = <MessageMenuItem>[];

    items.addAll(_buildCommonMenuItems());

    return items;
  }

  List<MessageMenuItem> _buildSoundMessageMenuItems() {
    final items = <MessageMenuItem>[];

    // Convert to text menu item
    //
    // 转换为文本菜单项
    if (_shouldShowConvertToTextMenuItem()) {
      items.add(MessageMenuItem(
        title: atomicLocal.convertToText,
        icon: Icons.text_fields,
        onTap: () => _handleConvertVoiceToText(),
      ));
    }

    items.addAll(_buildCommonMenuItems());

    return items;
  }

  /// Check if "Convert to Text" menu item should be shown
  ///
  /// 检查是否应显示“转换为文本”菜单项
  bool _shouldShowConvertToTextMenuItem() {
    // Only for sound messages
    //
    // 仅针对语音消息
    if (widget.message.messageType != MessageType.audio) return false;

    // Only for successfully sent messages
    //
    // 仅针对成功发送的消息
    if (widget.message.status != MessageStatus.sendSuccess) return false;

    // If already converted and not hidden in this session, hide the menu item
    final hasAsrText = (widget.message.messagePayload as AudioMessagePayload?)
            ?.asrText
            ?.isNotEmpty ==
        true;
    final messageID = widget.message.msgID ?? '';
    final isHidden = widget.asrDisplayManager?.isHidden(messageID) ?? false;

    // Show menu when: no asrText OR asrText exists but hidden in this session
    //
    // 当没有 asrText 或 asrText 在本次会话中被隐藏时显示菜单
    return !hasAsrText || isHidden;
  }

  /// Handle convert voice to text action
  ///
  /// 处理语音转文字操作
  void _handleConvertVoiceToText() {
    final messageID = widget.message.msgID ?? '';
    final hasAsrText = (widget.message.messagePayload as AudioMessagePayload?)
            ?.asrText
            ?.isNotEmpty ==
        true;

    // If already has asrText but was hidden, just show it again
    if (hasAsrText) {
      widget.asrDisplayManager?.show(messageID);
      return;
    }

    // Set converting state (this also removes from hidden set)`
    //
    // 设置转换状态（这也会从隐藏集合中移除）
    widget.asrDisplayManager?.setConverting(messageID, true);

    // Call the API
    //
    // 调用 API
    final messageActionStore = MessageActionStore.create(widget.message);
    messageActionStore.convertVoiceToText(language: '').then((result) async {
      // Clear converting state
      //
      // 清除转换状态
      widget.asrDisplayManager?.setConverting(messageID, false);

      if (!result.isSuccess) {
        // Show error toast
        //
        // 显示错误提示
        if (mounted) {
          Toast.error(context, atomicLocal.convertToTextFailed);
        }
      } else {
        // Wait for next frame to ensure messageListStore has been updated via notificationCenter
        //
        // 等待下一帧以确保 messageListStore 已通过 notificationCenter 更新
        await Future.delayed(Duration.zero);
        if (!mounted) return;

        // On success, check if asrText is empty from the latest state in messageListStore
        //
        // 成功时，检查 messageListStore 中最新状态的 asrText 是否为空
        final messageList = widget.messageListStore.state.messageList.value;
        final updatedMessage = messageList.firstWhere(
          (msg) => msg.msgID == messageID,
          orElse: () => widget.message,
        );
        final asrText =
            (updatedMessage.messagePayload as AudioMessagePayload?)?.asrText ??
                '';

        if (asrText.isEmpty) {
          // Voice message has no content, show error toast and collapse ASR bubble
          //
          // 语音消息没有内容，显示错误提示并折叠 ASR 气泡
          if (mounted) {
            Toast.error(context, atomicLocal.convertToTextFailed);
          }
          widget.asrDisplayManager?.hide(messageID);
        }
      }
    });
  }

  List<MessageMenuItem> _buildFileMessagePayloadMenuItems() {
    final items = <MessageMenuItem>[];

    items.addAll(_buildCommonMenuItems());

    return items;
  }

  List<MessageMenuItem> _buildCustomMessagePayloadMenuItems() {
    final items = <MessageMenuItem>[];

    items.addAll(_buildCommonMenuItems());

    return items;
  }

  List<MessageMenuItem> _buildCommonMenuItems({bool includeCopy = false}) {
    final items = <MessageMenuItem>[];

    // Multi-select button
    //
    // 多选按钮
    if (widget.config.isSupportMultiSelect) {
      items.add(MessageMenuItem(
        title: _getMultiSelectText(),
        assetName: 'chat_assets/icon/multi_select.svg',
        package: 'tencent_chat_uikit',
        icon: Icons.checklist,
        onTap: () => _menuCallbacks.onMultiSelectMessage(widget.message),
      ));
    }

    // Forward button
    //
    // 转发按钮
    if (widget.config.isSupportForward) {
      final isSentSuccess = widget.message.status == MessageStatus.sendSuccess;
      // Violation messages cannot be forwarded
      //
      // 违规消息不能转发
      final isNotViolation = widget.message.status != MessageStatus.violation;
      if (isSentSuccess && isNotViolation) {
        items.add(MessageMenuItem(
          title: atomicLocal.forward,
          assetName: 'chat_assets/icon/forward.svg',
          package: 'tencent_chat_uikit',
          icon: Icons.shortcut,
          onTap: () => _menuCallbacks.onForwardMessage(widget.message),
        ));
      }
    }

    // Quote button
    //
    // 引用按钮
    if (widget.config.isSupportQuote) {
      final isSentSuccess = widget.message.status == MessageStatus.sendSuccess;
      final isNotViolation = widget.message.status != MessageStatus.violation;
      if (isSentSuccess && isNotViolation) {
        items.add(MessageMenuItem(
          title: atomicLocal.quote,
          assetName: 'chat_assets/icon/quote.svg',
          package: 'tencent_chat_uikit',
          icon: Icons.format_quote,
          onTap: () => _menuCallbacks.onQuoteMessage(widget.message),
        ));
      }
    }

    // Copy button (only for text messages)
    // Violation messages cannot be copied
    //
    // 复制按钮（仅限文本消息）违规消息不能复制
    if (includeCopy &&
        widget.config.isSupportCopy &&
        widget.message.status != MessageStatus.violation) {
      items.add(MessageMenuItem(
        title: atomicLocal.copy,
        assetName: 'chat_assets/icon/copy.svg',
        package: 'tencent_chat_uikit',
        icon: Icons.copy,
        onTap: () => _menuCallbacks.onCopyMessage(widget.message),
      ));
    }

    // Recall button
    //
    // 撤回按钮
    if (widget.config.isSupportRecall && widget.isSelf) {
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      final isWithin2Minutes =
          (now - (widget.message.timestamp ?? 0)) <= 2 * 60;
      final isSentSuccess = widget.message.status == MessageStatus.sendSuccess;
      // Violation messages cannot be revoked
      //
      // 违规消息不能撤回
      final isNotViolation = widget.message.status != MessageStatus.violation;

      if (isWithin2Minutes && isSentSuccess && isNotViolation) {
        items.add(MessageMenuItem(
          title: atomicLocal.recall,
          assetName: 'chat_assets/icon/revoke.svg',
          package: 'tencent_chat_uikit',
          icon: Icons.undo,
          onTap: () => _menuCallbacks.onRecallMessage(widget.message),
        ));
      }
    }

    // Delete button
    //
    // 删除按钮
    if (widget.config.isSupportDelete) {
      items.add(MessageMenuItem(
        title: atomicLocal.delete,
        assetName: 'chat_assets/icon/delete.svg',
        package: 'tencent_chat_uikit',
        icon: Icons.delete_outline,
        isDestructive: true,
        onTap: () => _menuCallbacks.onDeleteMessage(widget.message),
      ));
    }

    // Listen-from-here button (all message types).
    //
    // 从这里开始听按钮（所有消息类型）
    items.add(MessageMenuItem(
      title: AppLocalization.of(context).listenFromHere,
      assetName: 'chat_assets/icon/listen_from_here.svg',
      package: 'tencent_chat_uikit',
      icon: Icons.headset_outlined,
      onTap: () {
        ListenFromHereController.instance.start(
          messages: widget.messageListStore.state.messageList.value,
          fromMessageId: widget.message.msgID,
          l: AppLocalization.of(context),
        );
      },
    ));

    // Add custom actions
    //
    // 添加自定义操作
    for (final customAction in widget.customActions) {
      items.add(MessageMenuItem(
        title: customAction.title,
        assetName:
            customAction.assetName.isNotEmpty ? customAction.assetName : null,
        package: customAction.package,
        icon: customAction.systemIconFallback,
        onTap: () => customAction.action(widget.message),
      ));
    }

    return items;
  }

  String _getMultiSelectText() {
    return atomicLocal.multiSelect;
  }

  Widget _buildUnsupportedMessage(BuildContext context) {
    final colorsTheme = SemanticColorScheme.of(context);

    return GestureDetector(
      onLongPress: _longPressCallback,
      child: Container(
        key: _messageKey,
        constraints: BoxConstraints(
          maxWidth: _getBubbleMaxWidth(),
        ),
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: widget.isSelf
              ? colorsTheme.bgColorBubbleOwn
              : colorsTheme.bgColorBubbleReciprocal,
          borderRadius: _getBubbleBorderRadius(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: colorsTheme.textColorSecondary,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              atomicLocal.unknown,
              style: FontScheme.caption2Regular.copyWith(
                color: colorsTheme.textColorSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBubbleColor(SemanticColorScheme colorsTheme) {
    if (widget.isSelf) {
      return colorsTheme.bgColorBubbleOwn;
    } else {
      return colorsTheme.bgColorBubbleReciprocal;
    }
  }

  double _getBubbleMaxWidth() {
    switch (widget.config.alignment) {
      case 'left':
      case 'right':
        return widget.maxWidth * 0.7;
      case 'two-sided':
      default:
        return widget.maxWidth * 0.7;
    }
  }

  BorderRadius _getBubbleBorderRadius() {
    switch (widget.config.alignment) {
      case 'left':
        return const BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
          bottomLeft: Radius.circular(0),
          bottomRight: Radius.circular(10),
        );
      case 'right':
        return const BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
          bottomLeft: Radius.circular(10),
          bottomRight: Radius.circular(0),
        );
      case 'two-sided':
      default:
        if (widget.isSelf) {
          return const BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(10),
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(0),
          );
        } else {
          return const BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(10),
            bottomLeft: Radius.circular(0),
            bottomRight: Radius.circular(10),
          );
        }
    }
  }
}
