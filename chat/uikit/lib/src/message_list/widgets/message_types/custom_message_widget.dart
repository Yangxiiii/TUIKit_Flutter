import '../../../message_input/mention/message_mentions.dart';
import '../../utils/sticky_message_event.dart';
import '../../utils/conversation_notice.dart';
import '../../utils/message_utils.dart';
import 'dart:io';
import '../../../message_input/pending_rich_content_message.dart';
import 'package:app_ui/app_ui.dart' as app;
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/rich_content_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/big_file_message.dart';
import 'chat_mention_span.dart';
import 'file_message_widget.dart';
import 'rich_content_video_preview.dart';
import '../../utils/rich_content_media_viewer.dart';
import '../../message_history_config.dart';
import '../chat_media_placeholder.dart';
import '../image_viewer_manager.dart';
import 'system_message_widget.dart';

part 'rich_content_body.dart';

/// 按业务标识展示自定义消息，并在通用气泡中显示纯文本自定义数据。
class CustomMessageWidget extends StatelessWidget {
  /// 待展示的消息，图文协议从其自定义数据字段中解析。
  final MessageInfo message;
  final bool isSelf;

  /// 气泡可用的最大宽度，单位为逻辑像素。
  final double maxWidth;

  /// 复用消息列表的对齐和圆角配置，使图文消息与普通聊天气泡一致。
  final MessageListConfigProtocol config;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final MessageListStore? messageListStore;

  /// 普通聊天可浏览同一会话的媒体，静态窗口传入已展示的快照。
  final ({
    String conversationId,
    List<MessageInfo>? presetMessages,
    ChatOlderMessagesLoader? loadOlderMedia,
  })? conversationMedia;

  /// 回复详情与聊天气泡共用附件解析和预览，详情正文使用独立排版。
  final ({Widget? receipt})? replyDetail;

  const CustomMessageWidget({
    super.key,
    required this.message,
    required this.isSelf,
    required this.maxWidth,
    this.config = const ChatMessageListConfig(),
    this.onTap,
    this.onLongPress,
    this.messageListStore,
    this.replyDetail,
    this.conversationMedia,
  });

  @override
  Widget build(BuildContext context) {
    final notice = ConversationNotice.fromMessage(message);
    if (notice != null) {
      if (notice.type == 'group.created') {
        final groupId = message.conversationType == ConversationType.group
            ? message.to
            : null;
        return ConversationPeopleNotice(
          key: ValueKey(notice.eventId),
          parts: [
            for (final (text: text, userId: id) in notice.groupCreationParts())
              (
                text: id == null
                    ? text
                    : app.AppUserAvatarScope.personName(context, id,
                        groupId: groupId, fallback: text),
                userId: id,
              ),
          ],
          semanticsPrefix: 'tim.groupCreation.${notice.eventId}',
          onPersonTap: config.onGroupInfoOperatorTap,
        );
      }
      // 手机号查看沿用建群通知的姓名样式，显示服务端提供的姓名快照。
      if (notice.isPhoneView) {
        return ConversationPeopleNotice(
          parts: notice.phoneViewParts(),
          semanticsPrefix: 'tim.phoneView.${message.msgID}',
          onPersonTap: config.onPhoneViewPersonTap,
        );
      }
      // 欢迎语随聊天列表居中排版，群名仅用主题色强调。
      final welcome = notice.groupWelcomeParts;
      if (welcome != null) {
        final colors = app.AppColorBuildContext(context).appColors;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: welcome.prefix),
                TextSpan(
                  text: welcome.groupName,
                  style: TextStyle(color: colors.chatMention),
                ),
                TextSpan(text: welcome.suffix),
              ]),
              textAlign: TextAlign.center,
              style: FontScheme.caption3Regular.copyWith(
                color: colors.textSecondary,
                height: 19 / 12,
              ),
            ),
          ),
        );
      }
      // 仅离群通知校验群管理权限，邀请与管理员变更按原始投递范围展示。
      if (notice.isGroupDeparture && !config.showGroupDepartureNotices) {
        return const SizedBox.shrink();
      }
      if (notice.isGroupDeparture ||
          notice.isGroupInvitation ||
          notice.isGroupAdminChange) {
        final builder = config.groupMemberNoticeBuilder;
        if (builder != null) return builder(context, notice);
      }
      final text = MessageUtil.conversationNoticeText(notice);
      if (text.isEmpty) return const SizedBox.shrink();
      return SystemMessageWidget(
        message: message,
        customContent: text,
        operator: notice.descriptionOperator(),
        onOperatorTap: config.onGroupInfoOperatorTap,
      );
    }
    final event = StickyMessageEvent.fromMessage(message);
    if (event != null) {
      if (event.isControl) return const SizedBox.shrink();
      final colors = app.AppColorBuildContext(context).appColors;
      // 系统提示只展示姓名和动作，不增加头像、普通气泡或编辑入口。
      return Center(
          child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: event.operatorName,
                    style: TextStyle(color: colors.primary)),
                TextSpan(
                    text: ' ${event.actionText}',
                    style: TextStyle(color: colors.textSecondary)),
              ]),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, height: 19 / 12)));
    }
    final colors = SemanticColorScheme.of(context);
    final atomicLocale = AppLocalization.of(context);
    final customMessage = (message.messagePayload as CustomMessagePayload?);
    // 发送中的本地气泡直接读取内存草稿，不放宽远端消息协议对 URL 的校验。
    if (customMessage is PendingRichContentMessage) {
      return _buildRichContentMessage(
          context, colors, customMessage.draft.localPreview,
          localPreview: true);
    }
    // 自定义数据可以直接携带正文，只有 JSON 对象才进入应用的业务协议解析。
    final data = customMessage?.customData ?? '';
    final prefix = data.trimLeft();
    final hasObjectPrefix = prefix.startsWith('{');
    final file = hasObjectPrefix ? BigFileMessage.tryParse(data) : null;
    if (file != null) {
      return FileMessageWidget(
          message: message,
          isSelf: isSelf,
          maxWidth: maxWidth,
          config: config,
          onLongPress: onLongPress,
          messageListStore: messageListStore,
          bigFile: file);
    }

    final customContent =
        hasObjectPrefix ? ChatUtil.jsonData2Dictionary(data) : null;
    if (customContent?['businessID'] ==
        ConversationNotice.legacyGroupCreationBusinessId) {
      return const SizedBox.shrink();
    }

    if (customContent?['businessID'] == RichContentMessage.businessID) {
      final richContent =
          RichContentMessage.tryParse(customMessage?.customData);
      if (richContent != null) {
        return _buildRichContentMessage(context, colors, richContent);
      }
    }

    // 未知或损坏的结构化数据仍显示通用标签，纯文本原样展示。
    final displayText =
        prefix.isEmpty || hasObjectPrefix || prefix.startsWith('[')
            ? atomicLocale.messageTypeCustom
            : data;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: _buildDefaultCustomMessagePayload(colors, displayText),
    );
  }

  /// 按正文顺序展示文字、图片、视频及普通文件，媒体点击定位到共用预览器。
  Widget _buildRichContentMessage(
    BuildContext context,
    SemanticColorScheme colors,
    RichContentMessage content, {
    bool localPreview = false,
  }) {
    final detail = replyDetail;
    final receipt = detail?.receipt;
    final foreground = detail != null
        ? app.AppColorBuildContext(context).appColors.textPrimary
        : isSelf
            ? colors.textColorAntiPrimary
            : colors.textColorPrimary;
    final textStyle = detail == null
        ? FontScheme.caption1Regular.copyWith(color: foreground)
        : TextStyle(fontSize: 14, height: 20 / 14, color: foreground);
    // 只有一个普通文件时由卡片自己形成气泡，混排时继续用图文容器保持正文顺序。
    final onlyFile = switch (content.blocks.singleOrNull) {
      RichFileBlock(:final mimeType) => !mimeType.startsWith('video/'),
      _ => false,
    };
    final wrapInBubble = detail == null && !onlyFile;
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: wrapInBubble ? maxWidth * 0.7 : maxWidth,
        ),
        padding: wrapInBubble
            ? const EdgeInsets.fromLTRB(16, 8, 16, 8)
            : EdgeInsets.zero,
        // 富文本外框沿用普通文字气泡的四角设置，收发方向只影响摆放位置。
        decoration: wrapInBubble
            ? BoxDecoration(
                color: isSelf
                    ? colors.bgColorBubbleOwn
                    : colors.bgColorBubbleReciprocal,
                borderRadius:
                    BorderRadius.circular(config.textBubbleCornerRadius),
              )
            : null,
        child: RichContentBody._(
          content: content,
          textStyle: textStyle,
          maxMediaWidth: onlyFile
              ? maxWidth
              : detail == null
                  ? maxWidth * 0.7 - 24
                  : (maxWidth < 208 ? maxWidth : 208),
          message: message,
          conversationMedia: conversationMedia,
          config: config,
          isSelf: isSelf,
          receipt: receipt,
          localPreview: localPreview,
          mediaRadius: detail == null ? 8 : 0,
        ),
      ),
    );
  }

  Widget _buildDefaultCustomMessagePayload(
    SemanticColorScheme colorsTheme,
    String displayText,
  ) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: maxWidth * 0.7,
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: isSelf
            ? colorsTheme.buttonColorPrimaryDefault
            : colorsTheme.bgColorDefault,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        displayText,
        style: FontScheme.caption2Medium.copyWith(
          color: isSelf
              ? colorsTheme.textColorAntiPrimary
              : colorsTheme.textColorPrimary,
        ),
      ),
    );
  }
}
