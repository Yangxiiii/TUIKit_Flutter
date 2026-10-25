import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart' hide AlertDialog;
import 'package:tencent_chat_uikit/src/navigation/chat_uikit_navigation.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/asr_display_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/calling_message_data_provider.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_resender.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_utils.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/translation_display_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_attachments.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_status_mixin.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_read_receipt_view.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_tooltip.dart';

/// 组合消息头像、正文与回执；多选切换保留气泡锚点，消息项间距由列表负责。
class MessageItem extends StatelessWidget with MessageStatusMixin {
  /// 当前消息、发送状态及阅读回执，状态标记和正文共用此数据。
  final MessageInfo message;

  /// 当前消息所属会话，供菜单和消息定位使用。
  final String conversationID;

  /// 群聊可显示发送人昵称；单聊仍使用同一消息布局。
  final bool isGroup;

  /// 列表分配的消息可用宽度，单位为逻辑像素。
  final double maxWidth;

  /// 当前会话的消息操作入口，展示组件不创建独立消息状态。
  final MessageListStore messageListStore;

  /// 定位命中时播放气泡高亮，不改变消息本身的发送状态。
  final bool isHighlighted;

  /// 高亮结束后通知列表释放定位状态。
  final VoidCallback? onHighlightComplete;

  /// 头像点击交给会话页打开资料。
  final OnUserClick? onUserClick;

  /// Callback when user long presses on avatar (for @ mention feature)
  ///
  /// 用户长按头像时的回调（用于@提及功能）
  final OnUserLongPress? onUserLongPress;

  /// Callback when call message is clicked in C2C conversation
  ///
  /// C2C会话中点击通话消息时的回调
  final OnCallMessageClick? onCallMessageClick;

  /// 当前消息允许附加的菜单操作。
  final List<MessageCustomAction> customActions;

  /// 宿主指定的布局、头像、气泡和回执能力。
  final MessageListConfigProtocol config;

  /// 当前列表是否处于多选，仅改变复选框和点击行为，不重建消息气泡。
  final bool isMultiSelectMode;

  /// 当前消息是否被显式选中，不由长按自动设置。
  final bool isSelected;

  /// 多选模式内点击消息切换选中状态。
  final VoidCallback? onToggleSelection;

  /// 仅由操作面板中的“多选”动作调用，长按本身不调用此入口。
  final VoidCallback? onEnterMultiSelectMode;

  // Merged detail view mode - disables long press menu and read receipt
  //
  // 合并详情视图模式——禁用长按菜单和已读回执
  final bool isInMergedDetailView;

  // ASR display manager for voice-to-text feature
  //
  // 语音转文字功能的ASR显示管理器
  final AsrDisplayManager? asrDisplayManager;
  // Callback when ASR text bubble is long pressed, provides message and GlobalKey for positioning popup menu
  //
  // ASR文字气泡被长按时的回调，提供消息和GlobalKey以定位弹出菜单
  final void Function(MessageInfo message, GlobalKey asrBubbleKey)?
      onAsrBubbleLongPress;

  // Translation display manager for text translation feature
  //
  // 文本翻译功能的翻译显示管理器
  final TranslationDisplayManager? translationDisplayManager;
  // Callback when translation bubble is long pressed, provides message and GlobalKey for positioning popup menu
  //
  // 翻译气泡被长按时的回调，提供消息和GlobalKey以定位弹出菜单
  final void Function(MessageInfo message, GlobalKey translationBubbleKey)?
      onTranslationBubbleLongPress;

  // Callback when quote preview is tapped (for navigation to quoted message)
  //
  // 点击引用预览时的回调（用于导航到被引用消息）
  final void Function(MessageInfo message)? onQuotePreviewTap;

  // Callback when "Quote" is selected from long-press menu
  //
  // 从长按菜单选择“引用”时的回调
  final void Function(MessageInfo message)? onQuoteMessage;

  /// In merged detail view: the bundle's full message list, used as the
  /// static data source for image / video viewers when [isInMergedDetailView]
  /// is true. The page's MessageListStore is empty in that mode, so the
  /// viewer needs this fallback list to render any media at all.
  ///
  /// 在合并详情视图中：捆绑包的完整消息列表，当 [isInMergedDetailView] 为 true 时，用作图片/视频查看器的静态数据源。在该模式下，页面的 MessageListStore
  /// 是空的，因此查看器需要这个备用列表来渲染任何媒体。
  final List<MessageInfo>? mergedMediaMessages;

  const MessageItem({
    super.key,
    required this.message,
    required this.conversationID,
    this.isGroup = false,
    this.maxWidth = 200,
    required this.messageListStore,
    required this.isHighlighted,
    this.onHighlightComplete,
    this.onUserClick,
    this.onUserLongPress,
    this.onCallMessageClick,
    this.customActions = const [],
    required this.config,
    this.isMultiSelectMode = false,
    this.isSelected = false,
    this.onToggleSelection,
    this.onEnterMultiSelectMode,
    this.isInMergedDetailView = false,
    this.asrDisplayManager,
    this.onAsrBubbleLongPress,
    this.translationDisplayManager,
    this.onTranslationBubbleLongPress,
    this.onQuotePreviewTap,
    this.onQuoteMessage,
    this.mergedMediaMessages,
  });

  @override
  Widget build(BuildContext context) {
    bool isSelf = message.isSentBySelf;
    String? avatarURL = message.rawMessage?.faceUrl;
    String senderName = ChatUtil.getMessageSenderName(message);
    CallingMessageDataProvider provider =
        CallingMessageDataProvider(message, context);

    if (provider.isCallingSignal &&
        provider.participantType == CallParticipantType.c2c) {
      if (provider.content.isEmpty) {
        return Container();
      }

      isSelf = provider.direction == CallMessageDirection.outcoming;
      if (!isSelf) {
        return _buildWithConversationInfo(isSelf, avatarURL, senderName);
      }
    }

    Widget messageBubble = MessageBubble(
      message: message,
      conversationID: conversationID,
      isSelf: isSelf,
      maxWidth: maxWidth,
      config: config,
      messageListStore: messageListStore,
      isHighlighted: isHighlighted,
      onHighlightComplete: onHighlightComplete,
      customActions: customActions,
      menuCallbacks: _buildMenuCallbacks(context),
      isInMergedDetailView: isInMergedDetailView,
      asrDisplayManager: asrDisplayManager,
      onAsrBubbleLongPress: onAsrBubbleLongPress,
      translationDisplayManager: translationDisplayManager,
      onTranslationBubbleLongPress: onTranslationBubbleLongPress,
      onCallMessageClick: onCallMessageClick,
      onQuotePreviewTap: onQuotePreviewTap,
      mergedMediaMessages: mergedMediaMessages,
    );

    if (message.messageType == MessageType.tips ||
        message.status == MessageStatus.revoked ||
        MessageUtil.isSystemStyleCustomMessagePayload(message, context)) {
      // Check if system messages should be shown
      //
      // 检查是否应该显示系统消息
      if (!config.isShowSystemMessage) {
        return const SizedBox.shrink();
      }
      return messageBubble;
    }

    // In merged detail view, always use left-aligned layout
    //
    // 在合并详情视图中，总是使用左对齐布局
    if (isInMergedDetailView) {
      return _buildLeftAlignedLayout(
          context, messageBubble, isSelf, avatarURL, senderName);
    }

    Widget messageRow;
    switch (config.alignment) {
      case AppBuilder.MESSAGE_ALIGNMENT_TWO_SIDED:
        messageRow = _buildTwoSidedLayout(
            context, messageBubble, isSelf, avatarURL, senderName);
        break;
      case AppBuilder.MESSAGE_ALIGNMENT_LEFT:
        messageRow = _buildLeftAlignedLayout(
            context, messageBubble, isSelf, avatarURL, senderName);
        break;
      case AppBuilder.MESSAGE_ALIGNMENT_RIGHT:
        messageRow = _buildRightAlignedLayout(
            context, messageBubble, isSelf, avatarURL, senderName);
        break;
      default:
        messageRow = _buildTwoSidedLayout(
            context, messageBubble, isSelf, avatarURL, senderName);
    }

    // 模式切换保持相同父级结构，防止气泡重建后丢失弹窗避让所用的锚点。
    return _buildSelectableRow(messageRow);
  }

  /// 多选只增加复选框及点击行为，正文使用稳定键保留气泡状态和定位锚点。
  Widget _buildSelectableRow(Widget messageRow) {
    return GestureDetector(
      onTap: isMultiSelectMode ? onToggleSelection : null,
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isMultiSelectMode) ...[
            MessageCheckbox(isSelected: isSelected, isEnabled: true),
            const SizedBox(width: 8),
          ],
          Expanded(
            key: const ValueKey('messageContent'),
            child: messageRow,
          ),
        ],
      ),
    );
  }

  /// Build menu callbacks
  ///
  /// 构建菜单回调
  MessageMenuCallbacks? _buildMenuCallbacks(BuildContext context) {
    if (isMultiSelectMode) {
      // Disable menu in multi-select mode
      //
      // 在多选模式下禁用菜单
      return null;
    }
    return DefaultMessageMenuCallbacks(
      context: context,
      messageListStore: messageListStore,
      messageActionStore: MessageActionStore.create(message),
      conversationID: conversationID,
      config: config,
      onMultiSelectTriggered: onEnterMultiSelectMode,
      onQuoteMessageCallback: onQuoteMessage,
    );
  }

  /// Show resend confirmation dialog
  ///
  /// 显示重新发送确认对话框
  void _showResendConfirmDialog(BuildContext context) {
    final locale = AppLocalization.of(context);
    AtomicAlertDialog.showWithConfig(
      context,
      config: AlertDialogConfig(
        title: locale.resendTips,
        cancelConfig: ButtonConfig(text: locale.cancel),
        confirmConfig: ButtonConfig(
          text: locale.confirm,
          type: TextColorPreset.blue,
          onClick: () => _handleResendMessage(),
        ),
      ),
    );
  }

  /// 本地上传失败恢复同一任务，SDK失败消息校验后由重发器替换旧行。
  void _handleResendMessage() {
    // 上传前的失败行没有SDK消息ID，先恢复宿主任务，不能调用SDK删除或重发。
    final transfer = config.fileTransfers[message.msgID];
    if (transfer != null) {
      transfer.retry?.call();
      return;
    }
    MessageResender.resend(
        message: message,
        conversationID: conversationID,
        mediaSender: config.mediaSender);
  }

  /// Show read receipt detail page (group messages only)
  ///
  /// 显示已读回执详情页（仅限群组消息）
  void _showReadReceiptDetail(BuildContext context) {
    final messageActionStore = MessageActionStore.create(message);

    context.pushChatUIKitPage(
      MessageReadReceiptView(
        messageActionStore: messageActionStore,
        messageListStore: messageListStore,
        message: message,
      ),
    );
  }

  Widget _buildWithConversationInfo(
      bool isSelf, String? defaultAvatarURL, String defaultSenderName) {
    return FutureBuilder<ConversationInfo?>(
      future: _fetchConversationInfo(),
      builder: (context, snapshot) {
        String? avatarURL = defaultAvatarURL;
        String senderName = defaultSenderName;

        if (snapshot.hasData && snapshot.data != null) {
          final conversationInfo = snapshot.data!;
          avatarURL = conversationInfo.avatarURL ?? defaultAvatarURL;
          senderName = conversationInfo.title ?? defaultSenderName;
        }

        return _buildMessageLayout(isSelf, avatarURL, senderName, context);
      },
    );
  }

  Future<ConversationInfo?> _fetchConversationInfo() async {
    try {
      ConversationListStore conversationListStore =
          ConversationListStore.create();
      final result = await conversationListStore.getConversationInfo(
          conversationID: conversationID);
      if (result.isSuccess && result.conversationInfo != null) {
        return result.conversationInfo;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching conversation info: $e');
      return null;
    }
  }

  Widget _buildMessageLayout(
      bool isSelf, String? avatarUrl, String senderName, BuildContext context) {
    Widget messageBubble = MessageBubble(
      message: message,
      conversationID: conversationID,
      isSelf: isSelf,
      maxWidth: maxWidth,
      config: config,
      messageListStore: messageListStore,
      isHighlighted: isHighlighted,
      onHighlightComplete: onHighlightComplete,
      customActions: customActions,
      isInMergedDetailView: isInMergedDetailView,
      asrDisplayManager: asrDisplayManager,
      onAsrBubbleLongPress: onAsrBubbleLongPress,
      translationDisplayManager: translationDisplayManager,
      onTranslationBubbleLongPress: onTranslationBubbleLongPress,
      onCallMessageClick: onCallMessageClick,
      onQuotePreviewTap: onQuotePreviewTap,
      mergedMediaMessages: mergedMediaMessages,
    );

    if (message.messageType == MessageType.tips ||
        message.status == MessageStatus.revoked ||
        MessageUtil.isSystemStyleCustomMessagePayload(message, context)) {
      // Check if system messages should be shown
      //
      // 检查是否应该显示系统消息
      if (!config.isShowSystemMessage) {
        return const SizedBox.shrink();
      }
      return messageBubble;
    }

    switch (config.alignment) {
      case AppBuilder.MESSAGE_ALIGNMENT_TWO_SIDED:
        return _buildTwoSidedLayout(
            context, messageBubble, isSelf, avatarUrl, senderName);
      case AppBuilder.MESSAGE_ALIGNMENT_LEFT:
        return _buildLeftAlignedLayout(
            context, messageBubble, isSelf, avatarUrl, senderName);
      case AppBuilder.MESSAGE_ALIGNMENT_RIGHT:
        return _buildRightAlignedLayout(
            context, messageBubble, isSelf, avatarUrl, senderName);
      default:
        return _buildTwoSidedLayout(
            context, messageBubble, isSelf, avatarUrl, senderName);
    }
  }

  /// Build the optional attachment widget (ASR / translation bubble) that
  /// hangs below the main bubble. See `MessageAttachmentBuilder` for why
  /// this lives here instead of inside `SoundMessageWidget` /
  /// `TextMessageWidget`.
  ///
  /// 构建可选附件组件（ASR / 翻译气泡），挂在主消息气泡下方。为什么放在这里而不是 `SoundMessageWidget` / `TextMessageWidget` 内可以看
  /// `MessageAttachmentBuilder`。
  Widget? _buildAttachmentIfAny(bool isSelf) {
    return MessageAttachmentBuilder.buildIfAny(
      message: message,
      isSelf: isSelf,
      maxWidth: maxWidth,
      config: config,
      isInMergedDetailView: isInMergedDetailView,
      asrDisplayManager: asrDisplayManager,
      onAsrBubbleLongPress: onAsrBubbleLongPress,
      translationDisplayManager: translationDisplayManager,
      onTranslationBubbleLongPress: onTranslationBubbleLongPress,
    );
  }

  Widget _buildTwoSidedLayout(
      BuildContext context, Widget messageBubble, bool isSelf,
      [String? avatarUrl, String? senderName]) {
    return Row(
      mainAxisAlignment:
          isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: isSelf
          ? _buildSelfMessage(context, messageBubble, avatarUrl, senderName)
          : _buildOtherMessage(context, messageBubble, avatarUrl, senderName),
    );
  }

  Widget _buildLeftAlignedLayout(
      BuildContext context, Widget messageBubble, bool isSelf,
      [String? avatarUrl, String? senderName]) {
    final displayAvatarUrl = avatarUrl ?? message.from.avatarURL;
    final displaySenderName =
        senderName ?? ChatUtil.getMessageSenderName(message);
    final colors = SemanticColorScheme.of(context);
    final locale = AppLocalization.of(context);

    // In merged detail view: always show avatar, disable click, hide nickname
    //
    // 在合并详情视图中：始终显示头像，禁用点击，隐藏昵称
    final shouldShowAvatar = isInMergedDetailView || config.isShowLeftAvatar;
    final shouldShowNickname =
        !isInMergedDetailView && config.isShowLeftNickname;

    // Build status indicator if needed (only for self messages)
    //
    // 如果需要，为自己发送的消息构建状态指示器
    final statusIndicator = isSelf
        ? buildOutsideBubbleStatusIndicator(
            message: message,
            colorsTheme: colors,
            onResendTap: message.status == MessageStatus.sendFail
                ? () => _showResendConfirmDialog(context)
                : null,
          )
        : null;

    // 仅为己方消息展示阅读回执，单聊使用图标，群聊保留人数。
    final readReceiptIndicator = isSelf
        ? buildOutsideReadReceiptIndicator(
            message: message,
            colorsTheme: colors,
            locale: locale,
            enableReadReceipt: config.enableReadReceipt,
            isInMergedDetailView: isInMergedDetailView,
            onTap: () => _showReadReceiptDetail(context),
          )
        : null;

    final attachment = _buildAttachmentIfAny(isSelf);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (shouldShowAvatar)
            GestureDetector(
              onTap: isInMergedDetailView
                  ? null
                  : () {
                      // Disable avatar click in multi-select mode
                      //
                      // 多选模式下禁用头像点击
                      if (isMultiSelectMode) {
                        onToggleSelection?.call();
                        return;
                      }
                      if (!isSelf && onUserClick != null) {
                        onUserClick!(message.from.userID);
                      }
                    },
              onLongPress: isInMergedDetailView || isSelf
                  ? null
                  : () {
                      // Disable avatar long press in multi-select mode
                      //
                      // 在多选模式下禁用头像长按
                      if (isMultiSelectMode) return;
                      // Trigger @ mention callback
                      //
                      // 触发@提及回调
                      if (onUserLongPress != null) {
                        onUserLongPress!(
                            message.from.userID, displaySenderName);
                      }
                    },
              child: Avatar(
                content: AvatarImageContent(
                    url: displayAvatarUrl, name: displaySenderName),
              ),
            ),
          if (shouldShowAvatar) SizedBox(width: config.avatarSpacing),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (shouldShowNickname && displaySenderName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, top: 8, bottom: 4),
                    child: Text(
                      '$displaySenderName:',
                      style: FontScheme.caption3Regular,
                    ),
                  ),
                // 气泡外分别承载发送提示和阅读回执。
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(child: messageBubble),
                    if (statusIndicator != null) ...[
                      const SizedBox(width: 6),
                      statusIndicator,
                    ],
                    if (readReceiptIndicator != null) ...[
                      const SizedBox(width: 4),
                      readReceiptIndicator,
                    ],
                  ],
                ),
                // ASR / translation bubble (when present) hangs *below*
                // the row so it doesn't shift the receipt down — see
                // Bug-956459.
                //
                // ASR/翻译气泡（存在时）挂在行*下方*，不会把回执往下推——见
                if (attachment != null) attachment,
                // Violation hint text below the bubble
                //
                // 气泡下方的违规提示文本
                _buildViolationHintText(context),
                // Reaction bar for left-aligned layout
                //
                // 左对齐布局的反应条
                if (config.isSupportReaction && message.reactionList.isNotEmpty)
                  _buildReactionBar(context, isLeft: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightAlignedLayout(
      BuildContext context, Widget messageBubble, bool isSelf,
      [String? avatarUrl, String? senderName]) {
    final displayAvatarUrl = avatarUrl ?? message.from.avatarURL;
    final displaySenderName =
        senderName ?? ChatUtil.getMessageSenderName(message);
    final colors = SemanticColorScheme.of(context);
    final locale = AppLocalization.of(context);

    // Build status indicator if needed (only for self messages)
    //
    // 根据需要构建状态指示器（仅限自己消息）
    final statusIndicator = isSelf
        ? buildOutsideBubbleStatusIndicator(
            message: message,
            colorsTheme: colors,
            onResendTap: message.status == MessageStatus.sendFail
                ? () => _showResendConfirmDialog(context)
                : null,
          )
        : null;

    // 仅为己方消息展示阅读回执，单聊使用图标，群聊保留人数。
    final readReceiptIndicator = isSelf
        ? buildOutsideReadReceiptIndicator(
            message: message,
            colorsTheme: colors,
            locale: locale,
            enableReadReceipt: config.enableReadReceipt,
            isInMergedDetailView: isInMergedDetailView,
            onTap: () => _showReadReceiptDetail(context),
          )
        : null;

    final attachment = _buildAttachmentIfAny(isSelf);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (config.isShowRightNickname && displaySenderName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 2, top: 8, bottom: 4),
                    child: Text(
                      '$displaySenderName:',
                      style: FontScheme.caption3Regular,
                    ),
                  ),
                // 己方气泡左侧依次承载阅读回执和发送提示。
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (readReceiptIndicator != null) ...[
                      readReceiptIndicator,
                      const SizedBox(width: 4),
                    ],
                    if (statusIndicator != null) ...[
                      statusIndicator,
                      const SizedBox(width: 6),
                    ],
                    Flexible(child: messageBubble),
                  ],
                ),
                if (attachment != null) attachment,
                // Violation hint text below the bubble
                //
                // 气泡下方的违规提示文本
                _buildViolationHintText(context),
                // Reaction bar for right-aligned layout
                //
                // 右对齐布局的反应条
                if (config.isSupportReaction && message.reactionList.isNotEmpty)
                  _buildReactionBar(context, isLeft: false),
              ],
            ),
          ),
          if (config.isShowLeftAvatar) SizedBox(width: config.avatarSpacing),
          if (config.isShowLeftAvatar)
            GestureDetector(
              onTap: () {
                // Disable avatar click in multi-select mode
                //
                // 在多选模式下禁用头像点击
                if (isMultiSelectMode) {
                  onToggleSelection?.call();
                  return;
                }
                if (!isSelf && onUserClick != null) {
                  onUserClick!(message.from.userID);
                }
              },
              child: Avatar(
                content: AvatarImageContent(
                    url: displayAvatarUrl, name: displaySenderName),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildSelfMessage(BuildContext context, Widget messageBubble,
      [String? avatarUrl, String? senderName]) {
    final displayAvatarUrl = avatarUrl ?? message.from.avatarURL;
    final displaySenderName =
        senderName ?? ChatUtil.getMessageSenderName(message);
    final colors = SemanticColorScheme.of(context);
    final locale = AppLocalization.of(context);

    // Build status indicator if needed
    //
    // 根据需要构建状态指示器
    final statusIndicator = buildOutsideBubbleStatusIndicator(
      message: message,
      colorsTheme: colors,
      onResendTap: message.status == MessageStatus.sendFail
          ? () => _showResendConfirmDialog(context)
          : null,
    );

    // 阅读回执显示在己方气泡左侧，与发送进度和失败提示分别处理。
    final readReceiptIndicator = buildOutsideReadReceiptIndicator(
      message: message,
      colorsTheme: colors,
      locale: locale,
      enableReadReceipt: config.enableReadReceipt,
      isInMergedDetailView: isInMergedDetailView,
      onTap: () => _showReadReceiptDetail(context),
    );

    final attachment = _buildAttachmentIfAny(true);

    // When the other side's left avatar is shown, add a left spacer for self messages
    // so the bubble's left edge aligns with other-message bubble's left edge
    // and doesn't overlap with the other side's avatar.
    //
    // 当显示对方的左边头像时，为自己消息添加左侧间隔，这样气泡的左边缘就能和对方消息气泡的左边缘对齐，不会覆盖对方的头像。
    final needLeftSpacer = config.isShowLeftAvatar;
    final leftSpacerWidth =
        needLeftSpacer ? AvatarSize.m.value + config.avatarSpacing : 0.0;

    return [
      if (needLeftSpacer) SizedBox(width: leftSpacerWidth),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (config.isShowRightNickname && displaySenderName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 2, top: 8, bottom: 4),
                child: Text(
                  '$displaySenderName:',
                  style: FontScheme.caption3Regular,
                ),
              ),
            // 己方气泡左侧依次承载阅读回执和发送提示。
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (readReceiptIndicator != null) ...[
                  readReceiptIndicator,
                  const SizedBox(width: 4),
                ],
                if (statusIndicator != null) ...[
                  statusIndicator,
                  const SizedBox(width: 8),
                ],
                Flexible(child: messageBubble),
              ],
            ),
            if (attachment != null) attachment,
            // Violation hint text below the bubble
            //
            // 气泡下方的违规提示文字
            _buildViolationHintText(context),
            // Reaction bar for self messages (right aligned)
            //
            // 自己消息的反应条（右对齐）
            if (config.isSupportReaction && message.reactionList.isNotEmpty)
              _buildReactionBar(context, isLeft: false),
          ],
        ),
      ),
      if (config.isShowRightAvatar) SizedBox(width: config.avatarSpacing),
      if (config.isShowRightAvatar)
        Avatar(
          content: AvatarImageContent(
              url: displayAvatarUrl, name: displaySenderName),
        ),
    ];
  }

  List<Widget> _buildOtherMessage(BuildContext context, Widget messageBubble,
      [String? avatarUrl, String? senderName]) {
    final displayAvatarUrl = avatarUrl ?? message.from.avatarURL;
    final displaySenderName =
        senderName ?? ChatUtil.getMessageSenderName(message);
    final attachment = _buildAttachmentIfAny(false);

    return [
      if (config.isShowLeftAvatar)
        GestureDetector(
          onTap: () {
            // Disable avatar click in multi-select mode
            //
            // 多选模式下禁用头像点击
            if (isMultiSelectMode) {
              onToggleSelection?.call();
              return;
            }
            if (onUserClick != null) {
              onUserClick!(message.from.userID);
            }
          },
          onLongPress: () {
            // Disable avatar long press in multi-select mode
            //
            // 多选模式下禁用头像长按
            if (isMultiSelectMode) return;
            // Trigger @ mention callback
            //
            // 触发 @ 提及回调
            if (onUserLongPress != null) {
              onUserLongPress!(message.from.userID, displaySenderName);
            }
          },
          child: Avatar(
            content: AvatarImageContent(
                url: displayAvatarUrl, name: displaySenderName),
          ),
        ),
      if (config.isShowLeftAvatar) SizedBox(width: config.avatarSpacing),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (config.isShowLeftNickname && displaySenderName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 2, top: 8, bottom: 4),
                child: Text(
                  '$displaySenderName:',
                  style: FontScheme.caption3Regular,
                ),
              ),
            messageBubble,
            if (attachment != null) attachment,
            // Violation hint text below the bubble
            //
            // 气泡下方的违规提示文字
            _buildViolationHintText(context),
            // Reaction bar for other messages (left aligned)
            //
            // 对方消息的反应条（左对齐）
            if (config.isSupportReaction && message.reactionList.isNotEmpty)
              _buildReactionBar(context, isLeft: true),
          ],
        ),
      ),
      // When self's right avatar is shown, add a right spacer for other messages
      // so the bubble's right edge aligns with self-message bubble's right edge
      // and doesn't overlap with self's avatar.
      //
      // 当显示自己的右边头像时，为对方消息添加右侧间隔，这样气泡的右边缘就能和自己消息气泡的右边缘对齐，不会覆盖自己的头像。
      if (config.isShowRightAvatar)
        SizedBox(width: AvatarSize.m.value + config.avatarSpacing),
    ];
  }

  Widget _buildReactionBar(BuildContext context, {required bool isLeft}) {
    return MessageReactionBar(
      reactionList: message.reactionList,
      isLeft: isLeft,
      onClick: () => _showReactionDetailSheet(context),
    );
  }

  void _showReactionDetailSheet(BuildContext context) {
    final messageActionStore = MessageActionStore.create(message);
    final currentUserID = LoginStore.shared.loginState.loginUserInfo?.userID;

    ReactionDetailSheet.show(
      context: context,
      reactionList: message.reactionList,
      currentUserID: currentUserID,
      onFetchUsers: (reactionID) {
        messageActionStore.loadReactionUsers(
          reactionID: reactionID,
          count: 20,
        );
      },
      onRemoveReaction: (reactionID) {
        messageActionStore.removeReaction(reactionID: reactionID);
        Navigator.of(context).pop();
      },
      // Disable remove reaction in merged message detail view
      //
      // 合并消息详情视图中禁用移除反应
      allowRemove: !isInMergedDetailView,
    );
  }

  /// Build violation hint text widget
  ///
  /// 构建违规提示文本Widget
  Widget _buildViolationHintText(BuildContext context) {
    if (message.status != MessageStatus.violation) {
      return const SizedBox.shrink();
    }

    final colors = SemanticColorScheme.of(context);
    final locale = AppLocalization.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        locale.messageTypeSecurityStrike,
        style: FontScheme.caption3Regular.copyWith(
          color: colors.textColorError,
        ),
      ),
    );
  }
}
