import 'package:app_ui/app_ui.dart';
import 'dart:convert';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/forward/forward_target_selector.dart';

/// Forward type
///
/// 转发类型
enum ForwardType {
  /// Forward separately
  ///
  /// 单独转发
  separate,

  /// Forward as merged
  ///
  /// 合并转发
  merged,
}

/// Forward service
///
/// 转发服务
class ForwardService {
  /// Group conversation ID prefix
  ///
  /// 群聊会话ID前缀
  static const String _groupConversationIDPrefix = 'group_';

  /// Maximum number of messages allowed for separate forwarding
  ///
  /// 允许单独转发的最大消息数
  static const int _forwardSeparateLimit = 30;

  // ==================== Validation Methods ====================
  //
  // ==================== 验证方法 ====================

  /// Validate if messages can be forwarded (all must be sendSuccess)
  /// Returns error message if validation fails, null if valid
  ///
  /// 验证消息是否可以转发（全部必须是发送成功） 如果验证失败返回错误信息，如果有效返回null
  static String? validateMessagesStatus(
      BuildContext context, List<MessageInfo> messages) {
    final locale = AppLocalization.of(context);
    final hasFailedMessage =
        messages.any((msg) => msg.status != MessageStatus.sendSuccess);
    if (hasFailedMessage) {
      return locale.forwardFailedMessageTip;
    }
    return null;
  }

  /// Validate if separate forward limit is exceeded
  /// Returns error message if validation fails, null if valid
  ///
  /// 验证是否超过单独转发限制 如果验证失败返回错误信息，如果有效返回null
  static String? validateSeparateForwardLimit(BuildContext context,
      List<MessageInfo> messages, ForwardType forwardType) {
    if (forwardType != ForwardType.separate) return null;

    final locale = AppLocalization.of(context);
    if (messages.length > _forwardSeparateLimit) {
      return locale.forwardSeparateLimitTip;
    }
    return null;
  }

  /// Execute single message forward flow
  /// Single message forward skips type selection and goes directly to conversation selector
  /// Note: Caller should validate message status before calling this method
  ///
  /// 执行单条消息转发流程 单条消息转发会跳过类型选择，直接进入会话选择器 注意：主叫方应在调用此方法前验证消息状态
  static Future<bool> forwardSingleMessage({
    required BuildContext context,
    required MessageInfo message,
    required MessageListStore messageListStore,
    required MessageListConfigProtocol config,
    String? excludeConversationID,
  }) async {
    // Single message: skip type selection, directly show forward target selector
    //
    // 单条消息：跳过类型选择，直接显示转发目标选择器
    final selectResult = await ForwardTargetSelectorPage.show(
      context,
    );
    if (selectResult == null || selectResult.conversationIDs.isEmpty) {
      return false;
    }

    // Execute forward (default to separate for single message)
    //
    // 执行转发（单条消息默认单独转发）
    final success = await _executeForward(
      context: context,
      messages: [message],
      messageListStore: messageListStore,
      forwardType: ForwardType.separate,
      targetConversationIDs: selectResult.conversationIDs,
      sourceConversationID: excludeConversationID,
      needReadReceipt: config.enableReadReceipt,
    );

    return success;
  }

  /// Select forward type (exposed for external validation flow)
  ///
  /// 选择转发类型（对外暴露用于验证流程）
  static Future<ForwardType?> showForwardTypeSelector(BuildContext context) {
    return _showForwardTypeSelector(context);
  }

  /// Execute multiple messages forward with pre-selected forward type
  /// Used when validation is done externally (e.g., from multi-select mode)
  ///
  /// 执行多条消息转发并预选转发类型 用于外部已完成验证的情况（例如多选模式）
  static Future<bool> forwardMessagesWithType({
    required BuildContext context,
    required List<MessageInfo> messages,
    required MessageListStore messageListStore,
    required MessageListConfigProtocol config,
    required ForwardType forwardType,
    String? sourceConversationID,
  }) async {
    if (messages.isEmpty) {
      return false;
    }

    // Select target conversations
    //
    // 选择目标会话
    final selectResult = await ForwardTargetSelectorPage.show(
      context,
    );
    if (selectResult == null || selectResult.conversationIDs.isEmpty) {
      return false;
    }

    // Execute forward
    //
    // 执行转发
    final success = await _executeForward(
      context: context,
      messages: messages,
      messageListStore: messageListStore,
      forwardType: forwardType,
      targetConversationIDs: selectResult.conversationIDs,
      sourceConversationID: sourceConversationID,
      needReadReceipt: config.enableReadReceipt,
    );

    return success;
  }

  /// Execute forward operation
  ///
  /// 执行转发操作
  static Future<bool> _executeForward({
    required BuildContext context,
    required List<MessageInfo> messages,
    required MessageListStore messageListStore,
    required ForwardType forwardType,
    required List<String> targetConversationIDs,
    String? sourceConversationID,
    required bool needReadReceipt,
    bool supportExtension = false,
    OfflinePushInfo? offlinePushInfo,
  }) async {
    try {
      // Build forward options
      //
      // 构建转发选项
      final forwardOption = ForwardMessageOption(
        forwardType: forwardType == ForwardType.separate
            ? MessageForwardType.separate
            : MessageForwardType.merged,
        mergedForwardInfo: forwardType == ForwardType.merged
            ? _buildMergedForwardInfo(context, messages, sourceConversationID)
            : null,
        sendMessageOption: SendMessageOption(
          needReadReceipt: needReadReceipt,
          isExtensionEnabled: supportExtension,
          offlinePushInfo: offlinePushInfo,
        ),
      );

      // Call SDK forward API for each target conversation
      //
      // 调用 SDK 转发接口对每个目标会话
      int failureCount = 0;
      for (final targetConversationID in targetConversationIDs) {
        final result = await messageListStore.forwardMessages(
          messageList: messages,
          option: forwardOption,
          conversationID: targetConversationID,
        );
        if (!result.isSuccess) {
          failureCount++;
        }
      }

      return failureCount == 0;
    } catch (e) {
      debugPrint('Forward error: $e');
      return false;
    }
  }

  /// Build merged forward info
  ///
  /// 构建合并转发信息
  static MergedForwardInfo _buildMergedForwardInfo(
    BuildContext context,
    List<MessageInfo> messages,
    String? conversationID,
  ) {
    final locale = AppLocalization.of(context);

    // Generate title
    //
    // 生成标题
    final title = _generateMergedTitle(locale, messages, conversationID);

    // Generate abstract list (max 4 items)
    //
    // 生成摘要列表（最多 4 项）
    final abstractList = _generateAbstractList(context, messages);

    // Compatible text
    //
    // 兼容文本
    final compatibleText = _getCompatibleText(locale);

    return MergedForwardInfo(
      title: title,
      abstractList: abstractList,
      compatibleText: compatibleText,
    );
  }

  /// Generate merged message title
  ///
  /// 生成合并消息标题
  static String _generateMergedTitle(
    AppLocalizedText locale,
    List<MessageInfo> messages,
    String? conversationID,
  ) {
    if (messages.isEmpty) {
      return locale.chatHistory;
    }

    // Check if it's a group chat (conversationID starts with "group_")
    //
    // 检查是否为群聊（conversationID 以 "group_" 开头）
    final isGroupChat =
        conversationID?.startsWith(_groupConversationIDPrefix) ?? false;

    if (isGroupChat) {
      // Group chat: return group chat history
      //
      // 群聊：返回群聊历史
      return locale.groupChatHistory;
    } else {
      // C2C chat: collect unique senders in order of appearance
      //
      // C2C 聊天：按出现顺序收集唯一发送者
      final senderNames = <String>[];
      final seenSenders = <String>{};

      for (final message in messages) {
        final sender = message.from.userID;
        if (!seenSenders.contains(sender)) {
          seenSenders.add(sender);
          // Use nickname, fallback to sender ID
          //
          // 使用昵称，如没有则使用发送者 ID
          final name = message.from.nickname ?? sender;
          senderNames.add(name);
        }
        // Only need at most 2 senders for C2C
        //
        // C2C 只需最多两个发送者
        if (senderNames.length >= 2) {
          break;
        }
      }

      if (senderNames.length == 2) {
        // Two senders: "A and B chat history"
        //
        // 两个发送者："A 和 B 的聊天记录"
        return locale.chatHistoryForSomebodyFormat(
            senderNames[0], senderNames[1]);
      } else if (senderNames.length == 1) {
        // One sender: "A's chat history"
        //
        // 一个发送者："A 的聊天记录"
        return locale.c2cChatHistoryFormat(senderNames[0]);
      } else {
        // Fallback
        return locale.chatHistory;
      }
    }
  }

  /// Generate abstract list
  ///
  /// 生成摘要列表
  static List<String> _generateAbstractList(
      BuildContext context, List<MessageInfo> messages) {
    final abstractList = <String>[];

    for (int i = 0; i < messages.length && abstractList.length < 4; i++) {
      final message = messages[i];
      final senderName = ChatUtil.getMessageSenderName(message);
      final content = _getMessageAbstract(context, message);

      if (content.isNotEmpty) {
        abstractList.add('$senderName: $content');
      }
    }

    return abstractList;
  }

  /// Get message abstract
  ///
  /// 获取消息摘要
  static String _getMessageAbstract(BuildContext context, MessageInfo message) {
    final locale = AppLocalization.of(context);
    switch (message.messageType) {
      case MessageType.text:
        return (message.messagePayload as TextMessagePayload?)?.text ?? '';
      case MessageType.image:
        return locale.messageTypeImage;
      case MessageType.video:
        return locale.messageTypeVideo;
      case MessageType.audio:
        return locale.messageTypeVoice;
      case MessageType.file:
        return locale.messageTypeFile;
      case MessageType.face:
        return locale.messageTypeSticker;
      case MessageType.merged:
        return '[${locale.chatHistory}]';
      case MessageType.custom:
        return locale.messageTypeCustom;
      default:
        return '';
    }
  }

  /// Get compatible text
  ///
  /// 获取兼容文本
  static String _getCompatibleText(AppLocalizedText locale) {
    return locale.forwardCompatibleText;
  }

  /// Show forward type selector using ActionSheet
  ///
  /// 使用 ActionSheet 显示转发类型选择器
  static Future<ForwardType?> _showForwardTypeSelector(
      BuildContext context) async {
    final locale = AppLocalization.of(context);
    ForwardType? selectedType;

    await ActionSheet.show(
      context,
      actions: [
        ActionSheetItem(
          title: locale.forwardIndividually,
          onTap: () {
            selectedType = ForwardType.separate;
          },
        ),
        ActionSheetItem(
          title: locale.forwardMerged,
          onTap: () {
            selectedType = ForwardType.merged;
          },
        ),
      ],
    );

    return selectedType;
  }

  /// Forward text as a text message (used for ASR text, translation text, etc.)
  /// Uses MessageInputStore.sendMessage to send text to each target conversation
  ///
  /// 将文本以短信方式转发（用于ASR文本、翻译文本等）。使用 MessageInputStore.sendMessage 将文本发送到每个目标会话
  static Future<bool> forwardText({
    required BuildContext context,
    required String text,
    String? excludeConversationID,
  }) async {
    if (text.isEmpty) {
      return false;
    }

    // Select target conversations
    //
    // 选择目标会话
    final selectResult = await ForwardTargetSelectorPage.show(
      context,
    );
    if (selectResult == null || selectResult.conversationIDs.isEmpty) {
      return false;
    }

    // Get conversation list store for fetching conversation info
    //
    // 获取会话列表存储以获取会话信息
    final conversationListStore = ConversationListStore.create();

    // Send text message to each target conversation using MessageInputStore
    //
    // 使用 MessageInputStore 向每个目标会话发送文本消息
    int failureCount = 0;

    for (final targetConversationID in selectResult.conversationIDs) {
      final messageInputStore =
          MessageInputStore.create(conversationID: targetConversationID);

      // Build text message
      //
      // 构建文本消息
      final textPayload = TextSendMessagePayload(text: text);

      // Create offline push info (same as Swift)
      //
      // 创建离线推送信息（与 Swift 相同）
      final tempMessageInfo = MessageInfo();
      tempMessageInfo.messageType = MessageType.text;
      tempMessageInfo.messagePayload = TextMessagePayload(text: text);
      final pushInfo = _createOfflinePushInfo(
        context: context,
        conversationID: targetConversationID,
        message: tempMessageInfo,
        conversationListStore: conversationListStore,
      );

      final result = await messageInputStore.sendMessage(
        payload: textPayload,
        option: SendMessageOption(offlinePushInfo: pushInfo),
      );
      if (!result.isSuccess) {
        failureCount++;
        debugPrint(
            'Failed to send text to $targetConversationID: ${result.errorCode}, ${result.errorMessage}');
      }
    }

    return failureCount == 0;
  }

  // ==================== Offline Push Info ====================
  //
  // ==================== 离线推送信息 ====================

  /// Create offline push info for a message
  ///
  /// 为消息创建离线推送信息
  static OfflinePushInfo _createOfflinePushInfo({
    required BuildContext context,
    String? conversationID,
    MessageInfo? message,
    ConversationListStore? conversationListStore,
  }) {
    final loginUserInfo = LoginStore.shared.loginState.loginUserInfo;
    final selfUserId = loginUserInfo?.userID ?? '';
    final selfName = loginUserInfo?.nickname ?? selfUserId;

    bool isGroup = false;
    String groupId = '';
    String title = selfName;
    String description = '';

    if (conversationID != null) {
      isGroup = conversationID.startsWith(_groupConversationIDPrefix);
      groupId = isGroup
          ? conversationID.substring(_groupConversationIDPrefix.length)
          : '';

      // Try to get chat name from conversation list
      //
      // 尝试从会话列表获取聊天名称
      String? chatName;
      if (conversationListStore != null) {
        final conversation = conversationListStore.state.conversationList.value
            .where((conv) => conv.conversationID == conversationID)
            .firstOrNull;
        if (conversation != null && (conversation.title?.isNotEmpty ?? false)) {
          chatName = conversation.title;
        }
      }

      title = isGroup ? (chatName ?? groupId) : selfName;
    }

    if (message != null) {
      description =
          _trimPushDescription(_getMessageTypeAbstract(context, message));
    }

    final ext = _createOfflinePushExtJson(
      isGroup: isGroup,
      senderId: isGroup ? groupId : selfUserId,
      senderNickName: title,
      faceUrl: loginUserInfo?.avatarURL,
      version: 1,
      action: 1,
      content: description,
      customData: null,
    );

    final pushInfo = OfflinePushInfo();
    pushInfo.title = title;
    pushInfo.description = description;
    pushInfo.extensionInfo = {
      'ext': ext,
      'AndroidOPPOChannelID': 'tuikit',
      'AndroidHuaWeiCategory': 'IM',
      'AndroidVIVOCategory': 'IM',
      'AndroidHonorImportance': 'NORMAL',
      'AndroidMeizuNotifyType': 1,
      'iOSInterruptionLevel': 'time-sensitive',
      'enableIOSBackgroundNotification': false,
    };

    return pushInfo;
  }

  /// Get message type abstract for push notification
  ///
  /// 获取推送通知的消息类型摘要
  static String _getMessageTypeAbstract(
      BuildContext context, MessageInfo message) {
    final locale = AppLocalization.of(context);
    switch (message.messageType) {
      case MessageType.text:
        // Convert emoji codes to localized names
        //
        // 将表情代码转换为本地化名称
        return EmojiManager.createLocalizedStringFromEmojiCodes(context,
            (message.messagePayload as TextMessagePayload?)?.text ?? '');
      case MessageType.image:
        return locale.messageTypeImage;
      case MessageType.video:
        return locale.messageTypeVideo;
      case MessageType.file:
        return locale.messageTypeFile;
      case MessageType.audio:
        return locale.messageTypeVoice;
      case MessageType.face:
        return locale.messageTypeSticker;
      case MessageType.merged:
        return '[${locale.chatHistory}]';
      default:
        return '';
    }
  }

  /// Trim push description to max length
  ///
  /// 将推送描述裁剪到最大长度
  static String _trimPushDescription(String text, {int maxLength = 50}) {
    final normalized = text.trim().replaceAll('\n', ' ').replaceAll('\r', ' ');
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return normalized.substring(0, maxLength);
  }

  /// Create offline push ext JSON string
  ///
  /// 创建离线推送扩展 JSON 字符串
  static String _createOfflinePushExtJson({
    required bool isGroup,
    required String senderId,
    required String senderNickName,
    String? faceUrl,
    required int version,
    required int action,
    String? content,
    String? customData,
  }) {
    final entity = <String, dynamic>{
      'sender': senderId,
      'nickname': senderNickName,
      'chatType': isGroup ? 2 : 1,
      'version': version,
      'action': action,
    };

    if (content != null && content.isNotEmpty) {
      entity['content'] = content;
    }
    if (faceUrl != null) {
      entity['faceUrl'] = faceUrl;
    }
    if (customData != null) {
      entity['customData'] = customData;
    }

    final timPushFeatures = <String, dynamic>{
      'fcmPushType': 'data',
      'fcmNotificationType': 'timpush',
    };

    final extDict = <String, dynamic>{
      'entity': entity,
      'timPushFeatures': timPushFeatures,
    };

    try {
      return jsonEncode(extDict);
    } catch (e) {
      return '{}';
    }
  }
}
