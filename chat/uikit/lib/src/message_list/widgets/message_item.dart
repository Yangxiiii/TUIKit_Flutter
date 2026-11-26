import '../../chat_display_name.dart';
import 'message_confirmation.dart';
import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart' hide AlertDialog;
import 'package:tencent_chat_uikit/src/navigation/chat_uikit_navigation.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/asr_display_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/big_file_message.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/calling_message_data_provider.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/group_call_record_message.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_resender.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_utils.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/oa_announcement_message.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/translation_display_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_attachments.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_status_mixin.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_read_receipt_view.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_tooltip.dart';
import 'message_types/oa_announcement_message_card.dart';
import 'message_location_widgets.dart';

/// 组合消息头像、正文与回执；多选切换保留气泡锚点，消息项间距由列表负责。
class MessageItem extends StatelessWidget with MessageStatusMixin {
  /// 当前消息、发送状态及阅读回执，状态标记和正文共用此数据。
  final MessageInfo message;

  /// 同组后续消息隐藏头像和群聊名称，保留头像列及独立气泡。
  final bool isContinuation;

  /// 删除成功后通知列表移除尚未被 SDK 接管的本地候选。
  final VoidCallback? onDeleted;

  /// 当前消息所属会话，供菜单和消息定位使用。
  final String conversationID;

  /// 群聊可显示发送人昵称；单聊仍使用同一消息布局。
  final bool isGroup;

  /// 列表分配的消息可用宽度，单位为逻辑像素。
  final double maxWidth;

  /// 在线会话的媒体加载和消息操作入口，离线时只读取本地展示数据。
  final MessageListStore? messageListStore;

  /// 定位命中时绘制整行背景，正文配色和消息状态照常显示。
  final bool isHighlighted;

  /// 内容到列表边缘的横向内边距，独立嵌入时由其宿主管理。
  final double horizontalPadding;

  /// 头像点击交给会话页打开资料。
  final OnUserClick? onUserClick;

  /// 已确认在群的成员头像长按时，向输入栏传递该成员的身份和名称。
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

  /// 建群草稿中仅由整行响应勾选，气泡仍可加载在线媒体。
  final bool selectionOnly;

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

  /// Web 回复的快照，非空时优先于原生引用的当前正文。
  final MessageQuoteInfo? replyQuote;

  /// 单条原消息的直接回复入口，跟随气泡方向对齐。
  final Widget? replyIndicator;

  /// In merged detail view: the bundle's full message list, used as the
  /// static data source for image / video viewers when [isInMergedDetailView]
  /// is true. The page's MessageListStore is empty in that mode, so the
  /// viewer needs this fallback list to render any media at all.
  ///
  /// 在合并详情视图中：捆绑包的完整消息列表，当 [isInMergedDetailView] 为 true 时，用作图片/视频查看器的静态数据源。在该模式下，页面的 MessageListStore
  /// 是空的，因此查看器需要这个备用列表来渲染任何媒体。
  final List<MessageInfo>? mergedMediaMessages;

  /// 在线会话到达 SDK 历史边缘后，沿用宿主的归档查询。
  final ChatOlderMessagesLoader? loadOlderMedia;

  const MessageItem({
    super.key,
    required this.message,
    this.isContinuation = false,
    this.onDeleted,
    required this.conversationID,
    this.isGroup = false,
    this.maxWidth = 200,
    required this.messageListStore,
    required this.isHighlighted,
    this.horizontalPadding = 0,
    this.onUserClick,
    this.onUserLongPress,
    this.onCallMessageClick,
    this.customActions = const [],
    required this.config,
    this.isMultiSelectMode = false,
    this.selectionOnly = false,
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
    this.replyQuote,
    this.replyIndicator,
    this.mergedMediaMessages,
    this.loadOlderMedia,
  });

  @override
  Widget build(BuildContext context) => MessageLocationRow(
        highlighted: isHighlighted,
        horizontalPadding: horizontalPadding,
        child: _buildRow(context),
      );

  /// 先识别消息身份和方向，再将正文放入相应的头像与状态布局。
  Widget _buildRow(BuildContext context) {
    // isSelf 只决定气泡方向；个人通话报告的实际发送者可能是显示在左侧的被叫。
    bool isSelf = message.isSentBySelf;
    // SDK 创建及发送回调中的 faceUrl 可能为空或滞后，不能覆盖已填充的发送者头像。
    final senderAvatarURL = message.from.avatarURL;
    String? avatarURL = senderAvatarURL?.isNotEmpty == true
        ? senderAvatarURL
        // 旧消息的发送者可能没有复制头像，从原始 SDK 消息补齐。
        // ignore: invalid_use_of_internal_member
        : message.rawMessage?.faceUrl;
    // 群聊宿主可以按群策略显示名称，标题与文字头像沿用同一份结果。
    final groupName = isGroup ? config.groupSenderName?.call(message) : null;
    var senderName = groupName ?? chatSenderDisplayName(context, message);
    final provider = CallingMessageDataProvider(message, context);
    if (provider.isCallingSignal && provider.excludeFromHistory) {
      return const SizedBox.shrink();
    }
    final isOutgoingCall = provider.isOutgoingCall;
    final record = provider.personalRecord;
    if (record != null) {
      // 报告由本人发送，但气泡代表原始来电；不能把被叫本人的头像当作发起人。
      avatarURL = record.callerAvatarURL;
      senderName = AppUserAvatarScope.personName(
        context,
        record.callerId,
        groupId: isGroup ? message.to : null,
        fallback: record.callerName,
      );
    }

    // 通话方向跟随发起人，建群草稿沿用消息头像以保留整行勾选。
    if (isOutgoingCall != null) {
      if (provider.content.isEmpty) {
        return Container();
      }

      isSelf = isOutgoingCall;
      if (!isSelf &&
          !isGroup &&
          record == null &&
          messageListStore != null &&
          !selectionOnly) {
        return _buildWithConversationInfo(isSelf, avatarURL, senderName);
      }
    }

    final messageBubble = _buildMessageBubble(context, isSelf);

    if (message.messageType == MessageType.tips ||
        message.status == MessageStatus.revoked ||
        MessageUtil.isSystemStyleCustomMessagePayload(message, context)) {
      // Check if system messages should be shown
      //
      // 检查是否应该显示系统消息
      if (!config.isShowSystemMessage) {
        return const SizedBox.shrink();
      }
      return IgnorePointer(ignoring: selectionOnly, child: messageBubble);
    }

    // 公告身份来自已校验的消息类型，不显示后台账号的员工头像和资料入口。
    if (OaAnnouncementMessage.fromConversation(message, conversationID) !=
        null) {
      return _buildSelectableRow(_buildAnnouncementRow(context, messageBubble));
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

  /// 固定通知头像与类型名，卡片在剩余消息列内适配窄屏和多选布局。
  Widget _buildAnnouncementRow(BuildContext context, Widget messageBubble) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OaAnnouncementAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '公告',
                  style: TextStyle(
                    color: context.appColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                messageBubble,
              ],
            ),
          ),
        ],
      );

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
            // 勾选由整行处理，内层仍渲染媒体但不能打开预览、菜单或重发。
            child: IgnorePointer(ignoring: selectionOnly, child: messageRow),
          ),
        ],
      ),
    );
  }

  /// Build menu callbacks
  ///
  /// 构建菜单回调
  MessageMenuCallbacks? _buildMenuCallbacks(BuildContext context) {
    final store = messageListStore;
    if (store == null || isMultiSelectMode) {
      // Disable menu in multi-select mode
      //
      // 在多选模式下禁用菜单
      return null;
    }
    return DefaultMessageMenuCallbacks(
      context: context,
      messageListStore: store,
      messageActionStore: MessageActionStore.create(message),
      onDeleted: onDeleted,
      conversationID: conversationID,
      config: config,
      onMultiSelectTriggered: onEnterMultiSelectMode,
      onQuoteMessageCallback: onQuoteMessage,
    );
  }

  /// 重发只允许 SDK 标记为本人发送的失败消息，展示方向和头像不能授予发送权限。
  bool get _canResend =>
      message.isSentBySelf &&
      message.status == MessageStatus.sendFail &&
      messageListStore != null &&
      !isInMergedDetailView &&
      !isMultiSelectMode &&
      !selectionOnly;

  /// 现有失败图标只打开确认，确认前后均复核所有权和状态，不启用失败长按菜单。
  void _showResendConfirmDialog(BuildContext context) async {
    if (!_canResend) return;
    await confirmMessageAction(
      context,
      messageId: message.msgID,
      isDelete: false,
      isEligible: () => _canResend,
      execute: _handleResendMessage,
    );
  }

  /// 本地上传失败恢复同一任务，SDK失败消息校验后由重发器替换旧行。
  Future<void> _handleResendMessage() async {
    if (!_canResend) return;
    // 上传前的失败行没有SDK消息ID，先恢复宿主任务，不能调用SDK删除或重发。
    final transfer = config.fileTransfers[message.msgID];
    if (transfer != null) {
      await transfer.retry?.call();
      return;
    }
    await MessageResender.resend(
        message: message,
        conversationID: conversationID,
        mediaSender: config.mediaSender);
  }

  /// 发送状态按 SDK 真实所有权显示；通话来去方向只影响此指示器放在气泡哪一侧。
  Widget? _buildSendStatus(BuildContext context, SemanticColorScheme colors) {
    if (!message.isSentBySelf || isInMergedDetailView) return null;
    return buildOutsideBubbleStatusIndicator(
        message: message,
        colorsTheme: colors,
        onResendTap:
            _canResend ? () => _showResendConfirmDialog(context) : null);
  }

  /// Show read receipt detail page (group messages only)
  ///
  /// 显示已读回执详情页（仅限群组消息）
  void _showReadReceiptDetail(BuildContext context) {
    final store = messageListStore;
    if (store == null) return;
    final messageActionStore = MessageActionStore.create(message);

    context.pushChatUIKitPage(
      MessageReadReceiptView(
        messageActionStore: messageActionStore,
        messageListStore: store,
        message: message,
      ),
    );
  }

  /// 宿主回执与原生回执共用发送状态判断，多选时禁止打开详情。
  Widget? _buildReadReceipt(BuildContext context, SemanticColorScheme colors,
      AppLocalizedText locale) {
    final builder = config.groupReadReceiptBuilder;
    final store = messageListStore;
    if (isGroup && builder != null) {
      // 历史选择和合并转发没有可以打开的实时回执入口。
      if (store == null ||
          isMultiSelectMode ||
          selectionOnly ||
          !MessageStatusMixin.shouldShowReadReceipt(
            message: message,
            enableReadReceipt: config.enableReadReceipt,
            isInMergedDetailView: isInMergedDetailView,
          )) {
        return null;
      }
      return builder(context, message, store);
    }
    return buildOutsideReadReceiptIndicator(
      message: message,
      colorsTheme: colors,
      locale: locale,
      enableReadReceipt: config.enableReadReceipt,
      isInMergedDetailView: isInMergedDetailView,
      onTap: () => _showReadReceiptDetail(context),
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
          senderName = chatConversationDisplayName(context, conversationInfo,
              fallback: defaultSenderName);
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

  /// 隐藏组内头像时仍占据原列宽度，后续气泡不向头像位置偏移。
  Widget _groupAvatar(Widget avatar) => Visibility(
        visible: !isContinuation,
        maintainSize: true,
        maintainState: true,
        maintainAnimation: true,
        child: avatar,
      );

  /// 群聊只在组首显示发送者名称，避免重复昵称撑开连续气泡的间距。
  bool get _showsSenderName => !isGroup || !isContinuation;

  /// 单聊媒体卡片的发送提示和回执共用一列，状态切换时保持正文可用宽度。
  Widget? _mediaStatusLane(Widget? indicator,
      {required bool isSelf, required bool beforeBubble}) {
    if (!isSelf ||
        isGroup ||
        message.conversationType == ConversationType.group ||
        isInMergedDetailView) {
      return null;
    }
    final payload = message.messagePayload;
    final stableMedia = switch (message.messageType) {
      MessageType.file || MessageType.image || MessageType.video => true,
      MessageType.custom => payload is CustomMessagePayload &&
          BigFileMessage.tryParse(payload.customData) != null,
      _ => false,
    };
    if (!stableMedia) return null;
    return Padding(
      padding: beforeBubble
          ? const EdgeInsets.only(right: 8)
          : const EdgeInsets.only(left: 8),
      child: SizedBox(
        width: 18,
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: indicator,
        ),
      ),
    );
  }

  /// 网络与缓存入口共用同一气泡，表情回应随正文刷新。
  Widget _buildMessageBubble(BuildContext context, bool isSelf) {
    final bubble = _withReactionBar(
      context,
      isSelf,
      (bar) => MessageBubble(
        reactionBar: bar,
        message: message,
        conversationID: conversationID,
        isSelf: isSelf,
        maxWidth: maxWidth,
        config: config,
        messageListStore: messageListStore,
        customActions: customActions,
        menuCallbacks: _buildMenuCallbacks(context),
        isInMergedDetailView: isInMergedDetailView,
        asrDisplayManager: asrDisplayManager,
        onAsrBubbleLongPress: onAsrBubbleLongPress,
        translationDisplayManager: translationDisplayManager,
        onTranslationBubbleLongPress: onTranslationBubbleLongPress,
        onCallMessageClick: onCallMessageClick,
        onQuotePreviewTap: onQuotePreviewTap,
        replyQuote: replyQuote,
        mergedMediaMessages: mergedMediaMessages,
        loadOlderMedia: loadOlderMedia,
      ),
    );
    return config.messageContentWrapper?.call(context, message, bubble) ??
        bubble;
  }

  /// 通话资料异步补齐后仍使用相同菜单回调，删除与聚合规则不随布局路径丢失。
  Widget _buildMessageLayout(
      bool isSelf, String? avatarUrl, String senderName, BuildContext context) {
    final messageBubble = _buildMessageBubble(context, isSelf);

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

  /// 卡片仍沿用双侧消息的头像、回执和多选入口。
  Widget _buildTwoSidedLayout(
      BuildContext context, Widget messageBubble, bool isSelf,
      [String? avatarUrl, String? senderName]) {
    final standaloneCard =
        config.useStandaloneCardLayout?.call(message) ?? false;
    return Row(
      mainAxisAlignment:
          isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: isSelf
          ? _buildSelfMessage(context, messageBubble, avatarUrl, senderName,
              standaloneCard: standaloneCard)
          : _buildOtherMessage(context, messageBubble, avatarUrl, senderName,
              standaloneCard: standaloneCard),
    );
  }

  /// 个人记录的头像操作仍指向原始发起人，不能误打开本端报告者的名片。
  String get _displaySenderId =>
      GroupCallRecordMessage.fromMessage(
              message, LoginStore.shared.loginState.loginUserInfo?.userID ?? '')
          ?.callerId ??
      message.from.userID;

  /// 各种对齐方式共用头像交互。多选时头像仅用于切换消息选择。
  Widget _buildSenderAvatar(
      BuildContext context, String? avatarUrl, String senderName,
      {required bool isSelf}) {
    final userID = _displaySenderId;
    final openContact = isGroup
        ? config.onGroupSenderAvatarTap
        : config.onDirectSenderAvatarTap;
    final fallbackTap = isSelf ? null : onUserClick;
    // 转发详情只读，多选优先勾选消息，普通聊天由宿主打开名片。
    final tap = switch ((isInMergedDetailView, isMultiSelectMode)) {
      (true, _) => null,
      (_, true) => onToggleSelection,
      _ when userID.trim().isEmpty => null,
      _ when openContact != null => () => openContact(context, userID),
      _ when fallbackTap != null => () => fallbackTap(userID),
      _ => null,
    };
    // 历史消息会保留已退群成员的头像，长按资格以当前群名单为准。
    final mention = isGroup &&
            !isSelf &&
            !isInMergedDetailView &&
            !isMultiSelectMode &&
            config.avatarMentionMemberIds.contains(userID)
        ? onUserLongPress
        : null;
    final avatar = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: tap,
      onLongPress: mention == null ? null : () => mention(userID, senderName),
      child: Avatar(
        size: AvatarSize.s,
        userID: userID,
        content: AvatarImageContent(url: avatarUrl, name: senderName),
      ),
    );
    return _groupAvatar(
      message.msgID.isNotEmpty &&
              (mention != null ||
                  (openContact != null && tap != null && !isMultiSelectMode))
          ? Semantics(
              identifier: 'tim.message.avatar.${message.msgID}',
              child: avatar,
            )
          : avatar,
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

    // 详情沿用来源头像和昵称布局，只在交互入口限制操作。
    final shouldShowAvatar = config.isShowLeftAvatar;
    final shouldShowNickname = config.isShowLeftNickname && _showsSenderName;

    final statusIndicator = _buildSendStatus(context, colors);

    // 己方气泡才有回执，发送提示仍占用独立的位置。
    final readReceiptIndicator =
        isSelf ? _buildReadReceipt(context, colors, locale) : null;

    final attachment = _buildAttachmentIfAny(isSelf);
    final mediaStatus = _mediaStatusLane(
        statusIndicator ?? readReceiptIndicator,
        isSelf: isSelf,
        beforeBubble: false);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (shouldShowAvatar)
            _buildSenderAvatar(context, displayAvatarUrl, displaySenderName,
                isSelf: isSelf),
          if (shouldShowAvatar) SizedBox(width: config.avatarSpacing),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (shouldShowNickname && displaySenderName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, top: 8, bottom: 4),
                    child: _wrapSenderName(
                      context,
                      Text('$displaySenderName:',
                          style: FontScheme.caption3Regular),
                    ),
                  ),
                // 气泡外分别承载发送提示和阅读回执。
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(child: messageBubble),
                    if (mediaStatus != null) mediaStatus,
                    if (mediaStatus == null && statusIndicator != null) ...[
                      const SizedBox(width: 6),
                      statusIndicator,
                    ],
                    if (mediaStatus == null &&
                        readReceiptIndicator != null) ...[
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
                if (replyIndicator != null) replyIndicator!,
                if (attachment != null) attachment,
                // Violation hint text below the bubble
                //
                // 气泡下方的违规提示文本
                _buildViolationHintText(context),
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

    final statusIndicator = _buildSendStatus(context, colors);

    // 己方气泡才有回执，发送提示仍占用独立的位置。
    final readReceiptIndicator =
        isSelf ? _buildReadReceipt(context, colors, locale) : null;

    final attachment = _buildAttachmentIfAny(isSelf);
    final mediaStatus = _mediaStatusLane(
        statusIndicator ?? readReceiptIndicator,
        isSelf: isSelf,
        beforeBubble: true);

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
                if (config.isShowRightNickname &&
                    _showsSenderName &&
                    displaySenderName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 2, top: 8, bottom: 4),
                    child: _wrapSenderName(
                      context,
                      Text('$displaySenderName:',
                          style: FontScheme.caption3Regular),
                    ),
                  ),
                _buildRightBubbleRow(
                  context,
                  messageBubble,
                  mediaStatus: mediaStatus,
                  receipt: readReceiptIndicator,
                  status: statusIndicator,
                  statusGap: 6,
                  isSelf: isSelf,
                ),
                if (replyIndicator != null) replyIndicator!,
                if (attachment != null) attachment,
                // Violation hint text below the bubble
                //
                // 气泡下方的违规提示文本
                _buildViolationHintText(context),
              ],
            ),
          ),
          if (config.isShowLeftAvatar) SizedBox(width: config.avatarSpacing),
          if (config.isShowLeftAvatar)
            _buildSenderAvatar(context, displayAvatarUrl, displaySenderName,
                isSelf: isSelf),
        ],
      ),
    );
  }

  /// 己方语音及通话记录把发送状态和回执放在正文右侧。
  Widget _buildRightBubbleRow(
    BuildContext context,
    Widget bubble, {
    required Widget? mediaStatus,
    required Widget? receipt,
    required Widget? status,
    required double statusGap,
    required bool isSelf,
  }) {
    final trailing = isSelf &&
        (receipt != null || status != null) &&
        (message.messageType == MessageType.audio ||
            (message.messageType == MessageType.custom &&
                CallingMessageDataProvider(message, context).isCallingSignal));
    final body = Flexible(child: bubble);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (trailing) body,
        if (mediaStatus != null) mediaStatus,
        if (mediaStatus == null && receipt != null) ...[
          if (trailing) const SizedBox(width: 4),
          receipt,
          if (!trailing) const SizedBox(width: 4),
        ],
        if (mediaStatus == null && status != null) ...[
          if (trailing) SizedBox(width: statusGap),
          status,
          if (!trailing) SizedBox(width: statusGap),
        ],
        if (!trailing) body,
      ],
    );
  }

  /// 己方消息共用头像列，发送状态和回执由正文旁的空间承载。
  List<Widget> _buildSelfMessage(BuildContext context, Widget messageBubble,
      String? avatarUrl, String? senderName,
      {required bool standaloneCard}) {
    final displayAvatarUrl = avatarUrl ?? message.from.avatarURL;
    final displaySenderName =
        senderName ?? ChatUtil.getMessageSenderName(message);
    final colors = SemanticColorScheme.of(context);
    final locale = AppLocalization.of(context);

    final statusIndicator = _buildSendStatus(context, colors);

    final readReceiptIndicator = _buildReadReceipt(context, colors, locale);

    final attachment = _buildAttachmentIfAny(true);
    final mediaStatus = _mediaStatusLane(
        statusIndicator ?? readReceiptIndicator,
        isSelf: true,
        beforeBubble: true);

    // 普通消息按对侧头像对齐，独立卡片和回复可以使用这段留白。
    final needLeftSpacer =
        !standaloneCard && config.isShowLeftAvatar && replyQuote == null;
    final leftSpacerWidth =
        needLeftSpacer ? AvatarSize.s.value + config.avatarSpacing : 0.0;

    return [
      if (needLeftSpacer) SizedBox(width: leftSpacerWidth),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!standaloneCard &&
                config.isShowRightNickname &&
                _showsSenderName &&
                displaySenderName.isNotEmpty)
              _buildSenderLabel(context, displaySenderName, isSelf: true),
            _buildRightBubbleRow(
              context,
              messageBubble,
              mediaStatus: mediaStatus,
              receipt: readReceiptIndicator,
              status: statusIndicator,
              statusGap: 8,
              isSelf: true,
            ),
            // 计数独立占一行，避免把正文旁的回执拉到计数的底部。
            if (replyIndicator != null) replyIndicator!,
            if (attachment != null) attachment,
            // Violation hint text below the bubble
            //
            // 气泡下方的违规提示文字
            _buildViolationHintText(context),
          ],
        ),
      ),
      if (config.isShowRightAvatar) SizedBox(width: config.avatarSpacing),
      if (config.isShowRightAvatar)
        _buildSenderAvatar(context, displayAvatarUrl, displaySenderName,
            isSelf: true),
    ];
  }

  /// 对方卡片以头像列为起点，正文可用宽度由发送侧头像和状态决定。
  List<Widget> _buildOtherMessage(BuildContext context, Widget messageBubble,
      String? avatarUrl, String? senderName,
      {required bool standaloneCard}) {
    final displayAvatarUrl = avatarUrl ?? message.from.avatarURL;
    final displaySenderName =
        senderName ?? ChatUtil.getMessageSenderName(message);
    final attachment = _buildAttachmentIfAny(false);
    final statusIndicator =
        _buildSendStatus(context, SemanticColorScheme.of(context));

    return [
      if (config.isShowLeftAvatar)
        _buildSenderAvatar(context, displayAvatarUrl, displaySenderName,
            isSelf: false),
      if (config.isShowLeftAvatar) SizedBox(width: config.avatarSpacing),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!standaloneCard &&
                config.isShowLeftNickname &&
                _showsSenderName &&
                displaySenderName.isNotEmpty)
              _buildSenderLabel(context, displaySenderName, isSelf: false),
            // 被叫本人发送的个人报告保持左侧头像和气泡，发送失败仍在气泡外提供恢复。
            if (statusIndicator == null)
              messageBubble
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(child: messageBubble),
                  const SizedBox(width: 6),
                  statusIndicator,
                ],
              ),
            if (replyIndicator != null) replyIndicator!,
            if (attachment != null) attachment,
            // Violation hint text below the bubble
            //
            // 气泡下方的违规提示文字
            _buildViolationHintText(context),
          ],
        ),
      ),
      // 对方普通消息按己方头像对齐，独立卡片和回复可以使用这段留白。
      if (!standaloneCard && config.isShowRightAvatar && replyQuote == null)
        SizedBox(width: AvatarSize.s.value + config.avatarSpacing),
    ];
  }

  /// 群聊名称与头像顶部对齐，超出气泡可用宽度时单行省略。
  Widget _buildSenderLabel(BuildContext context, String name,
      {required bool isSelf}) {
    final useGroupNameStyle = isGroup && config.groupSenderName != null;
    return Padding(
      padding: isGroup
          ? EdgeInsets.only(bottom: useGroupNameStyle ? 4 : 6)
          : EdgeInsets.only(
              left: isSelf ? 0 : 2, right: isSelf ? 2 : 0, top: 8, bottom: 4),
      child: _wrapSenderName(
        context,
        Text(
          isGroup ? name : '$name:',
          style: isGroup
              ? FontScheme.caption3Regular.copyWith(
                  color: SemanticColorScheme.of(context).textColorSecondary,
                  fontSize: useGroupNameStyle ? 12 : null,
                  height: useGroupNameStyle ? 20 / 12 : null,
                )
              : FontScheme.caption3Regular,
          maxLines: isGroup ? 1 : null,
          overflow: isGroup ? TextOverflow.ellipsis : null,
        ),
      ),
    );
  }

  /// 保留 UIKit 的昵称样式和布局约束，只由宿主补充关联标记。
  Widget _wrapSenderName(BuildContext context, Widget child) =>
      config.senderNameWrapper?.call(context, message, child) ?? child;

  /// 由宿主订阅云回应并组装气泡，旧群聊回应仍可打开原生明细。
  Widget _withReactionBar(
      BuildContext context, bool isSelf, Widget Function(Widget?) buildBubble) {
    if (!config.isSupportReaction ||
        message.status == MessageStatus.revoked ||
        message.messageType == MessageType.tips ||
        MessageUtil.isSystemStyleCustomMessagePayload(message, context) ||
        OaAnnouncementMessage.fromConversation(message, conversationID) !=
            null) {
      return buildBubble(null);
    }
    final isLeft = switch (config.alignment) {
      AppBuilder.MESSAGE_ALIGNMENT_LEFT => true,
      AppBuilder.MESSAGE_ALIGNMENT_RIGHT => false,
      _ => !isSelf,
    };
    final reaction = config.reactionConfig;
    if (reaction != null) {
      return reaction.buildBar(
        context,
        message,
        isLeft,
        buildBubble: buildBubble,
        showNativeDetails: isGroup && messageListStore != null
            ? () => _showReactionDetailSheet(context)
            : null,
      );
    }
    if (message.reactionList.isEmpty) return buildBubble(null);
    return buildBubble(MessageReactionBar(
      messageId: message.msgID,
      reactionList: message.reactionList,
      isSelf: isSelf,
      onClick: () => _showReactionDetailSheet(context),
    ));
  }

  void _showReactionDetailSheet(BuildContext context) {
    if (messageListStore == null) return;
    final messageActionStore = MessageActionStore.create(message);
    final currentUserID = LoginStore.shared.loginState.loginUserInfo?.userID;

    ReactionDetailSheet.show(
      context: context,
      reactionList: message.reactionList,
      groupId: isGroup ? message.to : null,
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
      // 接管云回复后由胶囊负责撤销，旧群聊明细只用于查看成员。
      allowRemove: !isInMergedDetailView && config.reactionConfig == null,
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
