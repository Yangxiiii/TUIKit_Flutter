import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';

/// Type of tongue display
///
/// 小舌头显示类型
enum TongueType {
  none,
  backToLatest,
  newMessages,
  atMention,

  /// Unread messages tongue shown at the top-right when entering a chat with unread messages
  ///
  /// 未读消息小舌头在进入有未读消息的聊天时显示在右上角
  unreadMessages,

  /// Back to quote position tongue shown after navigating to a quoted message
  ///
  /// 返回引用位置小舌头在导航到引用消息后显示
  backToQuote,
}

/// State data for the tongue widget
///
/// 小舌头控件状态数据
class TongueState {
  final TongueType type;
  final int newMessageCount;
  final String? atMentionText;
  final int? atMessageSeq;
  final int unreadCount;
  final bool isLoading;

  const TongueState({
    this.type = TongueType.none,
    this.newMessageCount = 0,
    this.atMentionText,
    this.atMessageSeq,
    this.unreadCount = 0,
    this.isLoading = false,
  });

  TongueState copyWith({
    TongueType? type,
    int? newMessageCount,
    String? atMentionText,
    int? atMessageSeq,
    int? unreadCount,
    bool? isLoading,
  }) {
    return TongueState(
      type: type ?? this.type,
      newMessageCount: newMessageCount ?? this.newMessageCount,
      atMentionText: atMentionText ?? this.atMentionText,
      atMessageSeq: atMessageSeq ?? this.atMessageSeq,
      unreadCount: unreadCount ?? this.unreadCount,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// A floating tongue widget displayed in the message list.
/// Supports multiple display modes:
/// 1. "Back to latest" - scroll back to bottom (bottom-right, double down arrow)
/// 2. "x new messages" - new message count indicator (bottom-right, double down arrow)
/// 3. "@mention" - at-mention navigation (bottom-right, double down arrow)
/// 4. "x unread messages" - unread messages on enter (top-right, double up arrow)
///
/// 消息列表中显示的浮动小舌头控件。支持多种显示模式：1. “返回最新” - 滚动到底部（右下角，双下箭头） 2. “x 条新消息” - 新消息数量提示（右下角，双下箭头） 3. “@提到” -
/// @提到导航（右下角，双下箭头） 4. “x 条未读消息” - 进入时未读消息（右上角，双上箭头）
class MessageTongueWidget extends StatelessWidget {
  final TongueState tongueState;
  final VoidCallback onTap;
  final String backToLatestText;
  final String Function(int count)? newMessageCountText;
  final String? backToQuoteText;

  const MessageTongueWidget({
    super.key,
    required this.tongueState,
    required this.onTap,
    required this.backToLatestText,
    this.newMessageCountText,
    this.backToQuoteText,
  });

  /// Whether the arrow should point upward (for unread messages tongue at top)
  ///
  /// 箭头是否应指向上方（用于顶部未读消息小舌头）
  bool get _isUpDirection => tongueState.type == TongueType.unreadMessages;

  @override
  Widget build(BuildContext context) {
    if (tongueState.type == TongueType.none) {
      return const SizedBox.shrink();
    }

    final colorsTheme = SemanticColorScheme.of(context);
    final text = _getDisplayText();

    return GestureDetector(
      onTap: tongueState.isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorsTheme.bgColorDefault,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLeadingIcon(colorsTheme),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                style: FontScheme.caption2Medium.copyWith(
                  color: colorsTheme.buttonColorPrimaryDefault,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build leading icon: loading spinner or double arrow
  ///
  /// 构建前导图标：加载旋转图标或双箭头
  Widget _buildLeadingIcon(SemanticColorScheme colorsTheme) {
    if (tongueState.isLoading) {
      return const CupertinoActivityIndicator(radius: 8);
    }
    return _buildDoubleArrow(colorsTheme);
  }

  /// Build double arrow icon (chevron) pointing up or down
  ///
  /// 构建双箭头图标（箭头符号），指向上或下
  Widget _buildDoubleArrow(SemanticColorScheme colorsTheme) {
    final color = colorsTheme.buttonColorPrimaryDefault;
    final icon = _isUpDirection
        ? Icons.keyboard_double_arrow_up
        : Icons.keyboard_double_arrow_down;
    return Icon(
      icon,
      size: 18,
      color: color,
    );
  }

  String _getDisplayText() {
    switch (tongueState.type) {
      case TongueType.backToLatest:
        return backToLatestText;
      case TongueType.newMessages:
        if (newMessageCountText != null) {
          return newMessageCountText!(tongueState.newMessageCount);
        }
        return '${tongueState.newMessageCount}';
      case TongueType.atMention:
        return tongueState.atMentionText ?? '';
      case TongueType.unreadMessages:
        if (newMessageCountText != null) {
          return newMessageCountText!(tongueState.unreadCount);
        }
        return '${tongueState.unreadCount}';
      case TongueType.backToQuote:
        return backToQuoteText ?? '';
      case TongueType.none:
        return '';
    }
  }
}
