import 'dart:async';
import 'package:app_core/app_core.dart';
import '../../audio_player/audio_player_platform.dart';
import '../utils/voice_message_media.dart';
import 'package:app_ui/app_ui.dart';
import '../utils/conversation_notice.dart';
import '../utils/group_announcement_message.dart';
import '../utils/message_utils.dart';
import '../utils/oa_announcement_message.dart';
import 'message_types/group_announcement_message_card.dart';
import 'message_types/oa_announcement_message_card.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart' hide AlertDialog;
import 'super_tooltip.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_resender.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_picker_model.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/asr_display_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/calling_message_data_provider.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/translation_display_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/translation_text_parser.dart';
import 'package:tencent_chat_uikit/src/message_list/listen/listen_from_here_controller.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/forward/forward_service.dart';

import 'message_tooltip.dart';
import '../../message_input/message_clipboard.dart';
import '../utils/sticky_message_event.dart';
import 'message_actions_scope.dart';
import 'message_confirmation.dart';
import 'message_recall_scope.dart';
import 'message_recall_notice.dart';
import '../message_recall_config.dart';
import 'quote_message_preview.dart';
import 'message_types/call_message_widget.dart';
import 'message_types/file_message_widget.dart';
import 'message_types/image_message_widget.dart';
import 'message_types/merged_message_widget.dart';
import 'message_types/sound_message_widget.dart';
import 'message_types/text_message_widget.dart';
import 'message_types/video_message_widget.dart';

/// 默认消息动作适配；宿主接入撤回时交由聊天页确认，保留其他UIKit动作。
class DefaultMessageMenuCallbacks implements MessageMenuCallbacks {
  /// 菜单所属页面，用于读取宿主动作范围及展示现有操作反馈。
  final BuildContext context;

  /// 当前会话的唯一消息列表Store，不另行维护一份消息集合。
  final MessageListStore messageListStore;

  /// 动作所属会话标识，用于转发来源和权限边界。
  final String conversationID;

  /// 宿主允许的复制、回复、转发等消息能力。
  final MessageListConfigProtocol config;

  /// 当前目标的公开AtomicX动作，撤回成功通过其通知更新本机列表。
  MessageActionStore messageActionStore;

  /// 明确点击多选时由外层切换模式，普通长按不触发。
  final VoidCallback? onMultiSelectTriggered;

  /// 交给聊天页设置输入引用，不由菜单管理输入控制器。
  final void Function(MessageInfo message)? onQuoteMessageCallback;

  /// SDK 删除成功后移除首屏本地候选，失败时不得提前清理。
  final VoidCallback? onDeleted;

  DefaultMessageMenuCallbacks({
    required this.context,
    required this.messageListStore,
    required this.messageActionStore,
    required this.conversationID,
    required this.config,
    this.onMultiSelectTriggered,
    this.onQuoteMessageCallback,
    this.onDeleted,
  });

  /// 系统剪贴板写入纯文本；原格式由聊天输入框按剪贴板条目恢复。
  @override
  void onCopyMessage(MessageInfo message) =>
      unawaited(copyLocally(context, conversationID, message));

  /// 复制来自当前气泡的正文和附件快照，离线也可使用系统剪贴板。
  static Future<void> copyLocally(
      BuildContext context, String conversationID, MessageInfo message) async {
    if (message.status == MessageStatus.violation) return;
    final copied = CopiedChatMessage.fromMessage(message);
    if (copied == null) return;
    try {
      await MessageClipboard.copy(copied, conversationID);
    } on Exception {
      if (context.mounted) Toast.error(context, '复制失败，请稍后重试');
    }
  }

  /// 保护操作提示；宿主开启成功态删除时先确认，SDK 成功后才清理关联置顶。
  @override
  void onDeleteMessage(MessageInfo message) async {
    if (StickyMessageEvent.fromMessage(message) != null ||
        ConversationNotice.fromMessage(message) != null) {
      return;
    }
    final scope = MessageActionsScope.maybeOf(context);
    if (scope?.enableSuccessfulDelete == true) {
      await confirmMessageAction(
        context,
        messageId: message.msgID,
        isDelete: true,
        isEligible: () => message.status == MessageStatus.sendSuccess,
        execute: () => _deleteMessage(message, scope),
      );
      return;
    }
    await _deleteMessage(message, scope);
  }

  /// 既有 SDK 删除成功后才通知列表与宿主；异常保留原消息并提示失败。
  Future<void> _deleteMessage(
      MessageInfo message, MessageActionsScope? scope) async {
    try {
      final localDelete = config.localDeleteHandler;
      if (localDelete != null) {
        final deleted = await localDelete([message]);
        // 本地删除与原SDK成功态共用候选清理回调，失败或空回执不得提前移除。
        if (deleted.contains(message.msgID)) onDeleted?.call();
        scope?.onMessagesDeleted?.call(deleted);
        return;
      }
      final result = await messageActionStore.delete();
      if (result.isSuccess) {
        onDeleted?.call();
        scope?.onMessagesDeleted?.call([message.msgID]);
      } else if (context.mounted) {
        Toast.error(context, '删除失败，请稍后重试');
      }
    } on Object {
      if (context.mounted) Toast.error(context, '删除失败，请稍后重试');
    }
  }

  /// 宿主接入时先确认并重查SDK；未接入的会话沿用UIKit原动作。
  @override
  void onRecallMessage(MessageInfo message) {
    final scope = MessageRecallScope.maybeOf(context);
    if (scope != null) {
      scope.onRecall(message);
      return;
    }
    messageActionStore.revoke();
  }

  @override
  void onForwardMessage(MessageInfo message) {
    // 接入宿主后由统一入口重查撤回和附件状态，旧快照不能提前决定转发资格。
    if (config.forwardHandler == null) {
      final statusError =
          ForwardService.validateMessagesStatus(context, [message]);
      if (statusError != null) {
        Toast.error(context, statusError);
        return;
      }
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

/// 按消息类型选择气泡内容，并统一承接高亮和长按操作。
class MessageBubble extends StatefulWidget {
  /// 当前消息类型、正文和发送结果的唯一数据来源。
  final MessageInfo message;

  /// 消息操作所属的会话，用于重发和菜单动作。
  final String conversationID;

  /// 是否为己方消息，决定气泡与操作的展示方向。
  final bool isSelf;

  /// 外层消息项分配的可用宽度，单位为逻辑像素。
  final double maxWidth;

  /// 在线会话的消息操作入口，离线气泡只消费已缓存的消息。
  final MessageListStore? messageListStore;

  /// 宿主可替换菜单操作；为空时使用默认消息菜单。
  final MessageMenuCallbacks? menuCallbacks;

  /// 当前消息允许附加的菜单操作。
  final List<MessageCustomAction> customActions;

  /// 宿主指定的气泡圆角、回执和可见能力。
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

  /// Web 回复保留发送时的引用摘要，原生引用继续走既有展示。
  final MessageQuoteInfo? replyQuote;

  /// 由消息行提供可见回应，与正文共享气泡背景。
  final Widget? reactionBar;

  /// 回复详情只展示当前消息内容，图文块可在正文旁显示回执。
  final ({Widget? receipt})? replyDetail;

  /// In merged detail view: the bundle's full message list, used as the
  /// static data source for image / video viewers (the page's
  /// MessageListStore is empty in this mode).
  ///
  /// 在合并详情视图中：bundle的完整消息列表，用作图片/视频查看器的静态数据源（该模式下页面的MessageListStore为空）。
  final List<MessageInfo>? mergedMediaMessages;

  /// 在线会话到达 SDK 历史边缘后，沿用宿主的归档查询。
  final ChatOlderMessagesLoader? loadOlderMedia;

  const MessageBubble({
    super.key,
    required this.message,
    required this.conversationID,
    required this.isSelf,
    required this.maxWidth,
    required this.config,
    required this.messageListStore,
    this.menuCallbacks,
    this.customActions = const [],
    this.isInMergedDetailView = false,
    this.asrDisplayManager,
    this.onAsrBubbleLongPress,
    this.translationDisplayManager,
    this.onTranslationBubbleLongPress,
    this.onCallMessageClick,
    this.onQuotePreviewTap,
    this.replyQuote,
    this.reactionBar,
    this.replyDetail,
    this.mergedMediaMessages,
    this.loadOlderMedia,
  });

  @override
  State<StatefulWidget> createState() => _MessageBubbleState();
}

/// 按消息类型渲染正文并管理气泡的菜单生命周期。
class _MessageBubbleState extends State<MessageBubble> {
  /// 回复详情已展示原消息，独立的聊天引用摘要只在其他入口渲染。
  MessageQuoteInfo? get _quoteInfo => widget.replyDetail == null
      ? widget.replyQuote ?? widget.message.quoteInfo
      : null;

  /// 当前消息及列表模式的菜单回调，保留气泡状态时仍随Widget更新替换。
  MessageMenuCallbacks? _menuCallbacks;
  final _voiceFallbackGuard = ActionGuard();
  ActionGuard get _voiceGuard =>
      MessageActionsScope.maybeOf(context)?.actionGuard ?? _voiceFallbackGuard;
  Object get _voiceRequestScope =>
      widget.asrDisplayManager ?? widget.messageListStore ?? this;

  /// 单聊与群聊共用语音菜单，并使用同一套转文字状态和反馈。
  bool get _isVoiceDesign =>
      widget.conversationID.startsWith('c2c_') ||
      widget.conversationID.startsWith('group_');

  final GlobalKey _messageKey = GlobalKey();
  SuperTooltip? tooltip;

  late AppLocalizedText atomicLocal;

  @override
  void initState() {
    super.initState();
    _menuCallbacks = _resolveMenuCallbacks();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    atomicLocal = AppLocalization.of(context);
  }

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 模式切换保留气泡状态后，菜单仍需使用当前消息和当前列表提供的业务回调。
    _menuCallbacks = _resolveMenuCallbacks();
  }

  /// 菜单回调随消息或列表模式更新；未由宿主提供时沿用SDK默认操作。
  MessageMenuCallbacks? _resolveMenuCallbacks() {
    final store = widget.messageListStore;
    if (store == null) return null;
    return widget.menuCallbacks ??
        DefaultMessageMenuCallbacks(
          context: context,
          messageListStore: store,
          messageActionStore: MessageActionStore.create(widget.message),
          conversationID: widget.conversationID,
          config: widget.config,
        );
  }

  @override
  void dispose() {
    if (tooltip?.isOpen ?? false) {
      tooltip?.close();
    }
    super.dispose();
  }

  /// 气泡内失败入口与外侧失败图标共用同一确认及防重流程。
  void _showResendConfirmDialog() async {
    if (widget.messageListStore == null) return;
    await confirmMessageAction(
      context,
      messageId: widget.message.msgID,
      isDelete: false,
      isEligible: () => widget.message.status == MessageStatus.sendFail,
      execute: () => MessageResender.resend(
        message: widget.message,
        conversationID: widget.conversationID,
        mediaSender: widget.config.mediaSender,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorsTheme = SemanticColorScheme.of(context);

    Widget backgroundBuilder(Widget child) {
      return Container(
        decoration: BoxDecoration(
          color: _getBubbleColor(colorsTheme),
          borderRadius: _getBubbleBorderRadius(),
        ),
        child: child,
      );
    }

    final reactionBar = widget.reactionBar == null
        ? null
        : Padding(
            // 回应胶囊从正文起点开始，收发两侧使用相同的内边距。
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: widget.reactionBar!,
          );
    final quoteInfo = _quoteInfo;
    final bodyReactionBar = quoteInfo == null ? reactionBar : null;

    // 文本和通话记录在原背景内追加回应，媒体和卡片由外层气泡承载。
    Widget withReactionBar(Widget child) {
      if (reactionBar == null) return child;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [child, reactionBar],
      );
    }

    Widget bodyBackground(Widget child) =>
        backgroundBuilder(withReactionBar(child));

    if (widget.message.status == MessageStatus.revoked) {
      final scope = MessageRecallScope.maybeOf(context);
      if (scope != null) {
        // 群管理员也可能撤回成员消息，群提示继续使用实际操作人和撤回原因。
        final text = widget.message.conversationType == ConversationType.group
            ? MessageUtil.getRevokeDisplayString(widget.message, context)
            : chatMessageRecallText(widget.message, context: context);
        return MessageRecallNotice(
          messageId: widget.message.msgID,
          text: text,
          editableUntil: scope.config.editableUntil(widget.message.msgID),
          onReedit: () => scope.onReedit(widget.message.msgID),
        );
      }
      return SystemMessageWidget(
        message: widget.message,
      );
    }

    final announcement = _groupAnnouncement;
    final notification = _oaAnnouncement;
    Widget messageWidget;
    // 仅未自行绘制回应的正文需要外层气泡承载。
    var bodyContainsReactions = false;

    final customContent = widget.message.messageType == MessageType.custom
        ? widget.config.customContentBuilder
            ?.call(context, widget.message, widget.maxWidth)
        : null;
    switch (widget.message.messageType) {
      case MessageType.text:
      case MessageType.face:
        final isFace = widget.message.messageType == MessageType.face;
        final payload = widget.message.messagePayload;
        // 外部表情编码可能未注册，保留原有不支持提示。
        if (isFace &&
            (payload is! FaceMessagePayload ||
                !EmojiManager.isOnlyEmojis(payload.faceData ?? ''))) {
          messageWidget = _buildUnsupportedMessage(context);
          break;
        }
        final hasQuote = quoteInfo != null;
        bodyContainsReactions = true;
        messageWidget = TextMessageWidget(
          message: widget.message,
          isSelf: widget.isSelf,
          maxWidth: widget.maxWidth,
          config: widget.config,
          onLongPress: hasQuote ? null : _longPressCallback,
          // 带引用的表情继续使用正文作为菜单锚点，背景由引用外层绘制。
          bubbleKey: !hasQuote || isFace ? _messageKey : null,
          backgroundBuilder: hasQuote ? (child) => child : bodyBackground,
          onResendTap: widget.message.status == MessageStatus.sendFail
              ? _showResendConfirmDialog
              : null,
          isInMergedDetailView: widget.isInMergedDetailView,
        );
        break;

      case MessageType.image:
        messageWidget = ImageMessageWidget(
          message: widget.message,
          conversationID: widget.conversationID,
          isSelf: widget.isSelf,
          maxWidth: widget.maxWidth,
          config: widget.config,
          onLongPress: _longPressCallback,
          messageListStore: widget.messageListStore,
          isInMergedDetailView: widget.isInMergedDetailView,
          mergedMediaMessages: widget.mergedMediaMessages,
          loadOlderMedia: widget.loadOlderMedia,
          localOnly: widget.messageListStore == null,
          bubbleKey: _messageKey,
        );
        break;

      case MessageType.video:
        messageWidget = VideoMessageWidget(
          message: widget.message,
          conversationID: widget.conversationID,
          isSelf: widget.isSelf,
          maxWidth: widget.maxWidth,
          config: widget.config,
          onLongPress: _longPressCallback,
          messageListStore: widget.messageListStore,
          isInMergedDetailView: widget.isInMergedDetailView,
          mergedMediaMessages: widget.mergedMediaMessages,
          loadOlderMedia: widget.loadOlderMedia,
          localOnly: widget.messageListStore == null,
          bubbleKey: _messageKey,
        );
        break;

      case MessageType.audio:
        bodyContainsReactions = true;
        messageWidget = SoundMessageWidget(
          message: widget.message,
          conversationID: widget.conversationID,
          asrDisplayManager: widget.asrDisplayManager,
          reactionBar: bodyReactionBar,
          onConvertToText: _handleConvertVoiceToText,
          isSelf: widget.isSelf,
          maxWidth: widget.maxWidth,
          config: widget.config,
          onLongPress: _longPressCallback,
          messageListStore: widget.messageListStore,
          isInMergedDetailView: widget.isInMergedDetailView,
          bubbleKey: _messageKey,
        );
        break;

      case MessageType.file:
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
        break;

      case MessageType.tips:
        messageWidget = SystemMessageWidget(
          message: widget.message,
          onOperatorTap: widget.config.onGroupInfoOperatorTap,
        );
        break;

      case MessageType.custom:
        if (customContent != null) {
          // 宿主只替换正文，原气泡继续处理长按菜单。
          messageWidget = GestureDetector(
            key: _messageKey,
            onLongPress: _longPressCallback,
            child: customContent,
          );
          break;
        }
        if (notification != null) {
          // 通知卡详情只传业务 ID，点击不改变业务已读状态。
          messageWidget = OaAnnouncementMessageCard(
            key: _messageKey,
            announcement: notification,
            maxWidth: widget.maxWidth,
            isRead: _readAnnouncementStatus(notification.id),
            // SDK 尚无消息 ID 时沿用公告业务 ID；正式重复通知仍由 IM 消息 ID 区分。
            detailIdentifier:
                'tim.assistant.detail.${Uri.encodeComponent(widget.message.msgID.isEmpty ? notification.id : widget.message.msgID)}',
            onOpen: () {
              final onOpen = widget.config.onOaAnnouncementTap;
              if (onOpen != null) {
                onOpen(context, notification.id);
              } else {
                Toast.info(context, '公告详情暂未开放');
              }
            },
          );
          break;
        }
        if (announcement != null) {
          // 群归属已校验，点击只传公告引用，详情正文交给宿主读取。
          final onOpen = widget.config.onGroupAnnouncementTap;
          messageWidget = GroupAnnouncementMessageCard(
            key: _quoteInfo != null ? null : _messageKey,
            summary: announcement.summary,
            maxWidth: widget.maxWidth,
            onOpen: onOpen == null ? null : () => onOpen(context, announcement),
            onLongPress: _longPressCallback,
          );
          break;
        }
        CallingMessageDataProvider provider =
            CallingMessageDataProvider(widget.message, context);
        if (provider.isCallingSignal) {
          bodyContainsReactions = true;
          messageWidget = CallMessageWidget(
            message: widget.message,
            isSelf: widget.isSelf,
            maxWidth: widget.maxWidth,
            bubbleKey: _quoteInfo != null ? null : _messageKey,
            backgroundBuilder:
                quoteInfo != null ? (child) => child : bodyBackground,
            isInMergedDetailView: widget.isInMergedDetailView,
            config: widget.config,
            onCallMessageClick: widget.onCallMessageClick,
          );
        } else {
          messageWidget = CustomMessageWidget(
            message: widget.message,
            isSelf: widget.isSelf,
            maxWidth: widget.maxWidth,
            config: widget.config,
            onLongPress: _longPressCallback,
            messageListStore: widget.messageListStore,
            replyDetail: widget.replyDetail,
            conversationMedia: !widget.isInMergedDetailView &&
                    widget.conversationID.isNotEmpty
                ? (
                    conversationId: widget.conversationID,
                    loadOlderMedia: widget.loadOlderMedia,
                    presetMessages: widget.mergedMediaMessages ??
                        (widget.messageListStore == null ||
                                widget.message.rawMessage == null
                            ? [widget.message]
                            : null),
                  )
                : null,
          );
        }
        break;

      case MessageType.merged:
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
        break;

      default:
        if (!widget.config.isShowUnsupportMessage) {
          return const SizedBox.shrink();
        }
        messageWidget = _buildUnsupportedMessage(context);
    }

    // 公告、宿主卡片和手机号通知可走本地路由，依赖 SDK 的正文操作在联网后恢复。
    if (widget.messageListStore == null &&
        announcement == null &&
        notification == null &&
        customContent == null &&
        const {MessageType.file, MessageType.audio, MessageType.custom}
            .contains(widget.message.messageType) &&
        !(widget.config.onPhoneViewPersonTap != null &&
            ConversationNotice.fromMessage(widget.message)?.isPhoneView ==
                true)) {
      messageWidget = IgnorePointer(child: messageWidget);
    }

    // 引用与正文共享气泡背景，Web 回复使用单行快照，定位仍交给原列表。
    if (quoteInfo != null) {
      // Web 引用使用消息行在头像和回执之外的可用宽度。
      final quoteWidth =
          widget.replyQuote == null ? _getBubbleMaxWidth() : widget.maxWidth;
      final quotePreview = QuoteMessagePreview(
        groupId: widget.message.conversationType == ConversationType.group
            ? widget.message.to
            : null,
        quoteInfo: quoteInfo,
        compactIdentifier: widget.replyQuote == null ||
                widget.message.msgID.isEmpty
            ? null
            : 'tim.reply.quote.${Uri.encodeComponent(widget.message.msgID)}',
        maxWidth: quoteWidth,
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
          if (reactionBar != null) reactionBar,
        ],
      );
      final bubbleContainer = Container(
        constraints: BoxConstraints(maxWidth: quoteWidth),
        decoration: BoxDecoration(
          color: _getBubbleColor(colorsTheme),
          borderRadius: _getBubbleBorderRadius(),
        ),
        child: columnChild,
      );
      messageWidget = GestureDetector(
        key: widget.replyQuote != null &&
                widget.message.messageType == MessageType.text
            ? _messageKey
            : null,
        onLongPress: _longPressCallback,
        child: bubbleContainer,
      );
    } else if (reactionBar != null && !bodyContainsReactions) {
      messageWidget = bodyBackground(messageWidget);
    }

    // 原消息与记录预览使用不同命名空间，稳定标识保留正文与原有长按动作。
    return Semantics(
      identifier: widget.message.msgID.isEmpty
          ? null
          : 'tim.${widget.isInMergedDetailView ? 'record' : 'chat'}.message.${Uri.encodeComponent(widget.message.msgID)}',
      onLongPress: _longPressCallback,
      child: messageWidget,
    );
  }

  void _handleLongPress() {
    _onOpenToolTip();
  }

  /// 合并详情、系统提示和公告通知只读，不能通过长按打开操作菜单。
  VoidCallback? get _longPressCallback => widget.isInMergedDetailView ||
          ConversationNotice.fromMessage(widget.message) != null ||
          _oaAnnouncement != null ||
          (widget.messageListStore == null && !_canCopy)
      ? null
      : _handleLongPress;

  /// 判定公告专用展示和操作权限时使用当前消息行的会话标识。
  GroupAnnouncementMessage? get _groupAnnouncement =>
      GroupAnnouncementMessage.fromConversation(
          widget.message, widget.conversationID);

  /// 单聊公告使用独立协议，不影响群公告或普通自定义消息的处理。
  OaAnnouncementMessage? get _oaAnnouncement =>
      OaAnnouncementMessage.fromConversation(
          widget.message, widget.conversationID);

  /// 可选业务状态读取失败时保持未知，避免影响消息历史展示。
  bool? _readAnnouncementStatus(String id) {
    try {
      return widget.config.oaAnnouncementReadStatus?.call(id);
    } catch (_) {
      return null;
    }
  }

  /// 消息复制只读取当前气泡，离线可沿用同一菜单动作。
  bool get _canCopy =>
      widget.config.isSupportCopy &&
      _groupAnnouncement == null &&
      widget.message.status != MessageStatus.violation &&
      CopiedChatMessage.supports(widget.message.messagePayload);

  /// 宿主启用编辑后使用底部操作面板，其余场景继续使用既有菜单。
  void _onOpenToolTip() {
    // 操作提示不可删除、撤回或再次置顶，不能进入普通消息菜单。
    if (StickyMessageEvent.fromMessage(widget.message) != null ||
        ConversationNotice.fromMessage(widget.message) != null) {
      return;
    }
    final canReact = widget.messageListStore != null &&
        widget.config.isSupportReaction &&
        widget.message.status != MessageStatus.violation;
    final scope = MessageActionsScope.maybeOf(context);
    if (scope != null) {
      // 气泡自身包含表情回应，外层消息行的回复计数和翻译不参与避让。
      scope.showActions(widget.message, _messageKey, context,
          _buildMenuItems(), canReact ? _handleReactionSelected : null);
      return;
    }
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
        showReactionPicker: canReact,
        onReactionSelected: canReact ? _handleReactionSelected : null,
      ),
    );

    tooltip?.show(context, targetCenter: customTargetCenter);
  }

  /// 两个表情选择入口共用同一提交路径，宿主可接管消息云字段写入。
  Future<void> _handleReactionSelected(EmojiPickerModelItem emoji) async {
    final reaction = widget.config.reactionConfig;
    if (reaction != null) {
      await reaction.select(widget.message, emoji.name);
      return;
    }
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
    // 离线保留复制入口，其余菜单由在线会话提供。
    if (widget.messageListStore == null) {
      return [
        if (_canCopy)
          _buildCopyMenuItem(() => DefaultMessageMenuCallbacks.copyLocally(
              context, widget.conversationID, widget.message)),
      ];
    }
    final items = <MessageMenuItem>[];

    items.addAll(_buildMenuItemsForMessageType(widget.message.messageType));

    return items;
  }

  /// 同一复制菜单适用于在线和离线气泡。
  MessageMenuItem _buildCopyMenuItem(VoidCallback onTap) => MessageMenuItem(
        title: atomicLocal.copy,
        id: 'copy',
        assetName: 'chat_assets/icon/copy.svg',
        package: 'tencent_chat_uikit',
        icon: Icons.copy,
        onTap: onTap,
      );

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

    items.addAll(_buildCommonMenuItems());

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
    final messageID = widget.message.msgID;
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
    final messageID = widget.message.msgID;
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
    final messageID = widget.message.msgID;

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

  /// 常规聊天语音面板独立展示播放方式和转文字，通用动作仍按消息资格展示。
  List<MessageMenuItem> _buildSoundMessageMenuItems() {
    final items = <MessageMenuItem>[];
    if (_isVoiceDesign) {
      final earpiece = AudioPlayerPlatform.earpieceMode.value;
      final text =
          (widget.message.messagePayload as AudioMessagePayload?)?.asrText ??
              '';
      final hidden =
          widget.asrDisplayManager?.isHidden(widget.message.msgID) ?? false;
      items.add(MessageMenuItem(
          id: 'audio-route',
          title: earpiece ? '扬声器播放' : '听筒播放',
          icon: earpiece ? AppIcons.voice4 : AppIcons.ear,
          onTap: () => unawaited(_switchVoiceRoute())));
      if (widget.message.status == MessageStatus.sendSuccess) {
        items.add(MessageMenuItem(
            id: 'voice-text',
            title: text.isNotEmpty && !hidden ? '取消转文字' : '语音转文字',
            icon: AppIcons.format,
            onTap: () {
              if (text.isNotEmpty && !hidden) {
                widget.asrDisplayManager?.hide(widget.message.msgID);
              } else {
                unawaited(_handleConvertVoiceToText());
              }
            }));
      }
    } else if (_shouldShowConvertToTextMenuItem()) {
      items.add(MessageMenuItem(
          title: atomicLocal.convertToText,
          icon: AppIcons.format,
          onTap: () => unawaited(_handleConvertVoiceToText())));
    }
    items.addAll(_buildCommonMenuItems());
    return items;
  }

  /// 原生接受路由配置后才显示成功提示，失败时保留菜单原模式。
  Future<void> _switchVoiceRoute() =>
      _voiceGuard.singleFlight<void>('chat.voice.route', () async {
        final next = !AudioPlayerPlatform.earpieceMode.value;
        try {
          await AudioPlayerPlatform.setEarpiece(next);
          if (mounted) {
            Toast.simple(context, next ? '已切换为听筒播放模式' : '已切换为扬声器播放模式');
          }
        } catch (_) {
          if (mounted) Toast.error(context, '播放方式切换失败，请重试');
        }
      });

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
    final messageID = widget.message.msgID;
    final isHidden = widget.asrDisplayManager?.isHidden(messageID) ?? false;

    // Show menu when: no asrText OR asrText exists but hidden in this session
    //
    // 当没有 asrText 或 asrText 在本次会话中被隐藏时显示菜单
    return !hasAsrText || isHidden;
  }

  /// 单聊与群聊识别失败时显示三秒纯文字，保留再次识别的入口。
  void _showAsrFailure(String message) {
    if (_isVoiceDesign) {
      Toast.simple(context, message, duration: const Duration(seconds: 3));
    } else {
      Toast.error(context, message, duration: const Duration(seconds: 3));
    }
  }

  /// 识别入口共用同消息守卫；缓存直接恢复，失败保留重试，资源过期与网络错误分开处理。
  Future<void> _handleConvertVoiceToText() => _voiceGuard.singleFlight<void>(
          ('chat.voice.asr', _voiceRequestScope, widget.message.msgID),
          () async {
        final id = widget.message.msgID;
        final userId = LoginStore.shared.loginState.loginUserInfo?.userID;
        final manager = widget.asrDisplayManager;
        if (manager?.isExpired(id) == true) {
          if (mounted) {
            _showAsrFailure('语音消息已过期，无法识别');
          }
          return;
        }
        final previousText =
            (widget.message.messagePayload as AudioMessagePayload?)?.asrText ??
                '';
        if (previousText.isNotEmpty) {
          manager?.setFailed(id, false);
          manager?.show(id);
          return;
        }
        manager?.setConverting(id, true);
        try {
          // 与播放按钮共享下载Future，防止两条入口重复写同一个SDK缓存文件。
          await _voiceGuard.singleFlight<String>(
              ('chat.voice.download', _voiceRequestScope, id),
              () => VoiceMessageMedia(widget.message).load());
          if (!mounted ||
              LoginStore.shared.loginState.loginUserInfo?.userID != userId) {
            return;
          }
          final result = await MessageActionStore.create(widget.message)
              .convertVoiceToText(language: '');
          // SDK通过通知更新消息正文，沿用其本地缓存，不再维护第二份识别文本。
          await Future<void>.delayed(Duration.zero);
          if (!mounted ||
              LoginStore.shared.loginState.loginUserInfo?.userID != userId) {
            return;
          }
          final updated = widget.messageListStore!.state.messageList.value
                  .where((message) => message.msgID == id)
                  .firstOrNull ??
              widget.message;
          final text =
              (updated.messagePayload as AudioMessagePayload?)?.asrText ?? '';
          if (!result.isSuccess || text.isEmpty) {
            manager?.setFailed(id, _isVoiceDesign);
            _showAsrFailure(
                _isVoiceDesign ? '无法识别' : atomicLocal.convertToTextFailed);
          } else {
            manager?.setFailed(id, false);
            manager?.show(id);
          }
        } on VoiceMediaFailure catch (error) {
          if (!mounted ||
              LoginStore.shared.loginState.loginUserInfo?.userID != userId) {
            return;
          }
          if (error.expired) {
            manager?.setExpired(id);
            unawaited(VoiceMessageMedia(widget.message)
                .markPlayed()
                .catchError((Object _) {}));
          } else {
            manager?.setFailed(id, _isVoiceDesign);
          }
          _showAsrFailure(error.expired
              ? '语音消息已过期，无法识别'
              : (_isVoiceDesign ? '无法识别' : atomicLocal.convertToTextFailed));
        } catch (_) {
          if (mounted) {
            manager?.setFailed(id, _isVoiceDesign);
            _showAsrFailure(
                _isVoiceDesign ? '无法识别' : atomicLocal.convertToTextFailed);
          }
        } finally {
          // 页面已销毁时管理器也可能已释放，迟到回调不得再次通知新列表。
          if (mounted) manager?.setConverting(id, false);
        }
      });

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

  List<MessageMenuItem> _buildCommonMenuItems() {
    final items = <MessageMenuItem>[];

    // Multi-select button
    //
    // 多选按钮
    if (widget.config.isSupportMultiSelect) {
      items.add(MessageMenuItem(
        title: _getMultiSelectText(),
        id: 'multiSelect',
        assetName: 'chat_assets/icon/multi_select.svg',
        package: 'tencent_chat_uikit',
        icon: Icons.checklist,
        onTap: () => _menuCallbacks?.onMultiSelectMessage(widget.message),
      ));
    }

    // Forward button
    //
    // 转发按钮
    // 群公告卡片的发布与撤回由公告服务处理，不开放普通消息转发。
    if (widget.config.isSupportForward && _groupAnnouncement == null) {
      final isSentSuccess = widget.message.status == MessageStatus.sendSuccess;
      // Violation messages cannot be forwarded
      //
      // 违规消息不能转发
      final isNotViolation = widget.message.status != MessageStatus.violation;
      if (isSentSuccess && isNotViolation) {
        items.add(MessageMenuItem(
          title: atomicLocal.forward,
          id: 'forward',
          assetName: 'chat_assets/icon/forward.svg',
          package: 'tencent_chat_uikit',
          icon: Icons.shortcut,
          onTap: () => _menuCallbacks?.onForwardMessage(widget.message),
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
          id: 'reply',
          icon: AppIcons.reply,
          onTap: () => _menuCallbacks?.onQuoteMessage(widget.message),
        ));
      }
    }

    // 纯文本和可还原的媒体共享复制入口，违规消息仍不可复制。
    if (_canCopy) {
      items.add(_buildCopyMenuItem(
          () => _menuCallbacks?.onCopyMessage(widget.message)));
    }

    // Recall button
    //
    // 撤回按钮
    if (widget.config.isSupportRecall &&
        widget.isSelf &&
        _groupAnnouncement == null) {
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      final age = now - (widget.message.timestamp ?? 0);
      final isWithin2Minutes = age >= 0 && age < 2 * 60;
      final isSentSuccess = widget.message.status == MessageStatus.sendSuccess;
      // Violation messages cannot be revoked
      //
      // 违规消息不能撤回
      final isNotViolation = widget.message.status != MessageStatus.violation;

      final scope = MessageRecallScope.maybeOf(context);
      final eligible = scope == null
          ? isWithin2Minutes && isSentSuccess && isNotViolation
          : scope.config.canRecall(widget.message);
      if (eligible) {
        items.add(MessageMenuItem(
          title: atomicLocal.recall,
          id: 'recall',
          assetName: 'chat_assets/icon/revoke.svg',
          package: 'tencent_chat_uikit',
          icon: Icons.undo,
          onTap: () => _menuCallbacks?.onRecallMessage(widget.message),
        ));
      }
    }

    // Delete button
    //
    // 删除按钮
    if (widget.config.isSupportDelete ||
        ((MessageActionsScope.maybeOf(context)?.enableSuccessfulDelete ??
                false) &&
            widget.message.status == MessageStatus.sendSuccess)) {
      items.add(MessageMenuItem(
        title: atomicLocal.delete,
        id: 'delete',
        assetName: 'chat_assets/icon/delete.svg',
        package: 'tencent_chat_uikit',
        icon: Icons.delete_outline,
        isDestructive: true,
        onTap: () => _menuCallbacks?.onDeleteMessage(widget.message),
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
          messages: widget.messageListStore!.state.messageList.value,
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

  /// 普通正文和高亮包裹层共用配置圆角，避免背景覆盖文字组件的四角设置。
  BorderRadius _getBubbleBorderRadius() =>
      BorderRadius.circular(widget.config.textBubbleCornerRadius);
}
