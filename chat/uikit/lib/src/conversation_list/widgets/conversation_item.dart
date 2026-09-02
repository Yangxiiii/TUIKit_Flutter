import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart' hide CompletionHandler;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tuikit_atomic_x/base_component/utils/time_util.dart';
import 'package:tencent_chat_uikit/src/conversation_list/conversation_list.dart';
import 'package:tencent_chat_uikit/src/conversation_list/conversation_list_config.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_utils.dart';
import 'package:tencent_chat_uikit/src/third_party/flutter_swipe_action_cell/core/cell.dart';

/// 展示单条会话，并通过左滑提供置顶和删除操作。
class ConversationItem extends StatefulWidget {
  final ConversationInfo conversation;

  /// 会话行和滑动层背景；为空时沿用 TUIKit 默认列表颜色。
  final Color? backgroundColor;

  final VoidCallback? onTap;

  final VoidCallback? onLongPress;

  final VoidCallback? onPinToggle;

  final VoidCallback? onDelete;

  final VoidCallback? onClearHistory;

  final VoidCallback? onMarkAsRead;

  final VoidCallback? onMarkAsUnread;

  final List<ConversationCustomAction> customActions;

  final ConversationActionConfigProtocol config;

  const ConversationItem({
    super.key,
    required this.conversation,
    this.backgroundColor,
    this.onTap,
    this.onLongPress,
    this.onPinToggle,
    this.onDelete,
    this.onClearHistory,
    this.onMarkAsRead,
    this.onMarkAsUnread,
    this.customActions = const [],
    required this.config,
  });

  @override
  State<StatefulWidget> createState() => _ConversationItemState();
}

class _ConversationItemState extends State<ConversationItem> {
  late AppLocalizedText atomicLocale;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final colorsTheme = SemanticColorScheme.of(context);
    atomicLocale = AppLocalization.of(context);
    final backgroundColor =
        widget.backgroundColor ?? colorsTheme.listColorDefault;

    return SwipeActionCell(
      key: ObjectKey(widget.conversation.conversationID),
      trailingActions: _buildSwipeActions(colorsTheme),
      backgroundColor: backgroundColor,
      child: _buildConversationContent(context, backgroundColor),
    );
  }

  List<SwipeAction> _buildSwipeActions(SemanticColorScheme colorsTheme) {
    final actions = <SwipeAction>[];

    if (widget.config.isSupportPin) {
      actions.add(SwipeAction(
        title: widget.conversation.isPinned
            ? atomicLocale.unpin
            : atomicLocale.pin,
        onTap: (CompletionHandler handler) async {
          widget.onPinToggle?.call();
          handler(false);
        },
        color: colorsTheme.buttonColorPrimaryDefault,
        icon: Icon(
          Icons.push_pin_outlined,
          color: colorsTheme.textColorButton,
        ),
        style: FontScheme.caption3Regular.copyWith(
          color: colorsTheme.textColorButton,
        ),
      ));
    }

    if (widget.config.isSupportDelete) {
      actions.add(SwipeAction(
        title: atomicLocale.delete,
        onTap: (CompletionHandler handler) async {
          widget.onDelete?.call();
          handler(false);
        },
        color: colorsTheme.textColorError,
        icon: Icon(
          Icons.delete_outline,
          color: colorsTheme.textColorButton,
        ),
        style: FontScheme.caption3Regular.copyWith(
          color: colorsTheme.textColorButton,
        ),
      ));
    }

    return actions;
  }

  Widget _buildConversationContent(
      BuildContext context, Color backgroundColor) {
    final colorsTheme = SemanticColorScheme.of(context);
    String formatTime = TimeUtil.convertToFormatTime(
        widget.conversation.lastMessage?.timestamp ?? 0, context);

    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: backgroundColor,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        splashColor: primary.withValues(alpha: 0.12),
        highlightColor: primary.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            children: [
              _buildAvatar(context),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.conversation.title ?? '',
                            style: FontScheme.caption1Medium.copyWith(
                              color: colorsTheme.textColorPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _buildUnreadOrMuteIcon(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSubtitle(context, colorsTheme),
                        ),
                        const SizedBox(width: 8),
                        _buildErrorStatusIcon(colorsTheme),
                        Text(
                          formatTime,
                          style: FontScheme.caption3Regular.copyWith(
                            color: colorsTheme.textColorTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build subtitle widget with draft support
  ///
  /// 构建带有草稿支持的副标题Widget。
  Widget _buildSubtitle(BuildContext context, SemanticColorScheme colorsTheme) {
    final draft = widget.conversation.draft;

    // Build @ mention prefix
    //
    // 构建 @ 提及前缀。
    String atPrefix = _buildAtMentionPrefix();

    // If there's a draft, show draft with red label
    if (draft != null && draft.isNotEmpty) {
      // Convert emoji codes to localized names for preview
      //
      // 将表情代码转换为本地化名称以供预览。
      String localizedDraft =
          EmojiManager.getEmojiMap(context).keys.fold(draft, (previous, key) {
        return previous.replaceAll(
            key, EmojiManager.getEmojiMap(context)[key]!);
      });

      // Replace newlines with spaces for single-line display
      //
      // 将换行符替换为空格以便单行显示。
      localizedDraft = localizedDraft.replaceAll('\n', ' ');

      // Build prefix for unread count (only when muted and unreadCount >= 2)
      //
      // 构建未读数前缀（仅在已静音且 unreadCount >= 2 时）。
      String unreadPrefix = '';
      if (widget.conversation.receiveOption == ReceiveMessageOption.notNotify &&
          widget.conversation.unreadCount >= 2) {
        unreadPrefix =
            '[${_formatUnreadCount(widget.conversation.unreadCount)} ${atomicLocale.messageNum}]';
      }

      return RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            if (atPrefix.isNotEmpty)
              TextSpan(
                text: atPrefix,
                style: FontScheme.caption2Regular.copyWith(
                  color: colorsTheme.textColorError,
                ),
              ),
            if (unreadPrefix.isNotEmpty)
              TextSpan(
                text: unreadPrefix,
                style: FontScheme.caption2Regular.copyWith(
                  color: colorsTheme.textColorSecondary,
                ),
              ),
            TextSpan(
              text: atomicLocale.draft,
              style: FontScheme.caption2Regular.copyWith(
                color: colorsTheme.textColorError,
              ),
            ),
            TextSpan(
              text: ' $localizedDraft',
              style: FontScheme.caption2Regular.copyWith(
                color: colorsTheme.textColorSecondary,
              ),
            ),
          ],
        ),
      );
    }

    // No draft: show last message as before
    //
    // 无草稿：像以前一样显示最后一条消息。
    String replaceText = EmojiManager.getEmojiMap(context).keys.fold(
        MessageUtil.getMessageAbstract(
            widget.conversation.lastMessage, context), (previous, key) {
      return previous.replaceAll(key, EmojiManager.getEmojiMap(context)[key]!);
    });

    String unreadPrefix = widget.conversation.receiveOption ==
                ReceiveMessageOption.notNotify &&
            widget.conversation.unreadCount >= 2
        ? '[${_formatUnreadCount(widget.conversation.unreadCount)} ${atomicLocale.messageNum}]'
        : '';

    // If there's @ mention, show with red color
    if (atPrefix.isNotEmpty) {
      return RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            TextSpan(
              text: atPrefix,
              style: FontScheme.caption2Regular.copyWith(
                color: colorsTheme.textColorError,
              ),
            ),
            if (unreadPrefix.isNotEmpty)
              TextSpan(
                text: unreadPrefix,
                style: FontScheme.caption2Regular.copyWith(
                  color: colorsTheme.textColorSecondary,
                ),
              ),
            TextSpan(
              text: replaceText,
              style: FontScheme.caption2Regular.copyWith(
                color: colorsTheme.textColorSecondary,
              ),
            ),
          ],
        ),
      );
    }

    String displayText = '$unreadPrefix$replaceText';

    return Text(
      displayText,
      style: FontScheme.caption2Regular.copyWith(
        color: colorsTheme.textColorSecondary,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Build @ mention prefix based on groupAtInfoList
  ///
  /// 根据 groupAtInfoList 构建 @ 提及前缀。
  String _buildAtMentionPrefix() {
    // Only show @ tag when unreadCount > 0 and is group chat
    //
    // 仅当 unreadCount > 0 且为群聊时显示 @ 标签。
    if (widget.conversation.unreadCount <= 0) {
      return '';
    }

    // Check if it's a group chat
    //
    // 检查是否是群聊
    if (!widget.conversation.conversationID.startsWith('group_')) {
      return '';
    }

    final atInfoList = widget.conversation.groupAtInfoList;
    if (atInfoList == null || atInfoList.isEmpty) {
      return '';
    }

    // Check for different @ types
    //
    // 检查不同类型的@提醒
    bool hasAtAll = false;
    bool hasAtMe = false;

    for (final atInfo in atInfoList) {
      switch (atInfo.atType) {
        case GroupAtType.atAll:
          hasAtAll = true;
          break;
        case GroupAtType.atMe:
          hasAtMe = true;
          break;
        case GroupAtType.atAllAtMe:
          hasAtAll = true;
          hasAtMe = true;
          break;
      }
    }

    // Build prefix based on @ types
    // Priority: @All + @Me shows both tags, @Me shows [@Me], @All shows [@All]
    //
    // 根据@类型构建前缀 优先级：@All + @Me显示两个标签，@Me显示[@Me]，@All显示[@All]
    if (hasAtAll && hasAtMe) {
      return '${atomicLocale.conversationListAtAll} ${atomicLocale.conversationListAtMe} ';
    } else if (hasAtMe) {
      return '${atomicLocale.conversationListAtMe} ';
    } else if (hasAtAll) {
      return '${atomicLocale.conversationListAtAll} ';
    }

    return '';
  }

  Widget _buildAvatar(BuildContext context) {
    // Show red dot for muted conversations with unread status
    //
    // 对已静音但有未读状态的对话显示红点
    bool hasDot = false;
    if (widget.conversation.receiveOption == ReceiveMessageOption.notNotify) {
      // Check both unreadCount and markList for unread status
      //
      // 检查unreadCount和markList是否有未读状态
      hasDot = widget.conversation.unreadCount > 0 ||
          widget.conversation.conversationMarkList
              .any((mark) => mark == ConversationMarkType.unread);
    }

    return Avatar.image(
      name: _getAvatarText(),
      url: widget.conversation.avatarURL!,
      badge: hasDot ? DotBadge() : NoBadge(),
      size: AvatarSize.l,
    );
  }

  String _getAvatarText() {
    if (widget.conversation.title == null ||
        widget.conversation.title!.isEmpty) {
      return '?';
    }

    return widget.conversation.title!.substring(0, 1).toUpperCase();
  }

  String _formatUnreadCount(int count) {
    if (count > 99) {
      return '99+';
    }
    return count.toString();
  }

  Widget _buildUnreadOrMuteIcon() {
    final colorsTheme = SemanticColorScheme.of(context);

    // For muted conversations (except meeting groups), show mute icon
    if (widget.conversation.receiveOption == ReceiveMessageOption.notNotify &&
        widget.conversation.groupType != GroupType.meeting) {
      return Padding(
        padding: const EdgeInsets.only(left: 8.0),
        child: SvgPicture.asset(
          'chat_assets/icon/ic_mute.svg',
          width: 18,
          height: 18,
          colorFilter:
              ColorFilter.mode(colorsTheme.textColorTertiary, BlendMode.srcIn),
          package: 'tencent_chat_uikit',
        ),
      );
    }

    // Check for unread status: unreadCount > 0 OR marked as unread
    //
    // 检查未读状态：unreadCount > 0 或标记为未读
    final bool hasUnreadMark = widget.conversation.conversationMarkList
        .any((mark) => mark == ConversationMarkType.unread);

    if (widget.conversation.unreadCount > 0) {
      // Show real unread count
      //
      // 显示真实未读数
      return _buildUnreadBadge(
        _formatUnreadCount(widget.conversation.unreadCount),
        colorsTheme,
      );
    } else if (hasUnreadMark) {
      // Show virtual badge with "1" when marked as unread but unreadCount is 0
      //
      // 当标记为未读但unreadCount为0时显示虚拟徽章“1”
      return _buildUnreadBadge('1', colorsTheme);
    } else {
      return const SizedBox.shrink();
    }
  }

  Widget _buildUnreadBadge(String text, SemanticColorScheme colorsTheme) {
    final bool isSingleDigit = text.length == 1;
    return Container(
      alignment: Alignment.center,
      padding: isSingleDigit
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      constraints: isSingleDigit
          ? const BoxConstraints.tightFor(width: 18, height: 18)
          : const BoxConstraints(minWidth: 16, minHeight: 16),
      decoration: BoxDecoration(
        color: colorsTheme.textColorError,
        shape: isSingleDigit ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isSingleDigit ? null : BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: FontScheme.caption3Medium.copyWith(
          color: colorsTheme.textColorButton,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// Build error status icon (sendFail or violation) - shown to the left of time
  ///
  /// 构建错误状态图标（发送失败或违规）- 显示在时间的左边
  Widget _buildErrorStatusIcon(SemanticColorScheme colorsTheme) {
    final lastMessage = widget.conversation.lastMessage;
    if (lastMessage != null &&
        (lastMessage.status == MessageStatus.sendFail ||
            lastMessage.status == MessageStatus.violation)) {
      return Padding(
        padding: const EdgeInsets.only(right: 4.0),
        child: Icon(
          Icons.error,
          size: 16,
          color: colorsTheme.textColorError,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
