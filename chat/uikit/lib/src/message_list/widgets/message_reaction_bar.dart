import 'package:app_ui/app_ui.dart' show AppColorBuildContext;
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_manager.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/recent_emoji_manager.dart';

/// 原生回应最多在气泡内展示五种，更多条目继续通过明细查看。
const int _maxDisplayReactions = 5;

/// 在没有业务回应组件时逐行展示原生表情，保留成员明细入口。
class MessageReactionBar extends StatelessWidget {
  /// 与表情编码共同标识当前消息的回应入口。
  final String messageId;

  /// 当前消息的原生回应快照。
  final List<MessageReaction> reactionList;

  /// 回应底色使用消息归属，不受列表对齐模式影响。
  final bool isSelf;

  /// 打开完整回应成员名单。
  final VoidCallback onClick;

  /// 宿主可单独处理某个表情的点击。
  final void Function(MessageReaction reaction)? onReactionTap;

  const MessageReactionBar({
    super.key,
    required this.messageId,
    required this.reactionList,
    required this.isSelf,
    required this.onClick,
    this.onReactionTap,
  });

  @override
  Widget build(BuildContext context) {
    if (reactionList.isEmpty) return const SizedBox.shrink();

    final colors = context.appColors;
    final background = colors.chatMessageReactionBackground(isSelf: isSelf);
    final tapReaction = onReactionTap;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          // 每种表情保留自己的计数和点击动作，宽屏也只占一行。
          for (final reaction in reactionList.take(_maxDisplayReactions))
            _buildChip(
              background: background,
              identifier: 'emoji.${Uri.encodeComponent(reaction.reactionID)}',
              onTap:
                  tapReaction == null ? onClick : () => tapReaction(reaction),
              child: _ReactionItem(reaction: reaction),
            ),
          // 超出气泡展示上限的条目可从明细完整查看。
          if (reactionList.length > _maxDisplayReactions)
            _buildChip(
              background: background,
              identifier: 'more',
              onTap: onClick,
              child: Text('…',
                  style: TextStyle(color: colors.chatMessageSecondary)),
            ),
        ],
      ),
    );
  }

  /// 原生胶囊沿用与业务回应一致的边距，语义节点保留点击入口。
  Widget _buildChip({
    required Color background,
    required String identifier,
    required VoidCallback onTap,
    required Widget child,
  }) {
    const radius = BorderRadius.all(Radius.circular(11));
    return Material(
      color: background,
      borderRadius: radius,
      child: Semantics(
        identifier: messageId.isEmpty
            ? null
            : 'tim.reaction.native.${Uri.encodeComponent(messageId)}.$identifier',
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 展示一个原生表情及其人数，条目的点击由外层胶囊接管。
class _ReactionItem extends StatelessWidget {
  /// SDK 提供的表情编码和对应人数。
  final MessageReaction reaction;

  const _ReactionItem({required this.reaction});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final emoji =
        RecentEmojiManager.getEmojiByReactionID(context, reaction.reactionID);

    final fallback = Icon(Icons.sentiment_satisfied_alt,
        size: 16, color: colors.chatMessageSecondary);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 历史编码没有对应图片时仍保留回应计数和点击入口。
        if (emoji == null)
          fallback
        else
          Image.asset(
            emoji.path,
            package: EmojiManager.assetPackage,
            width: 16,
            height: 16,
            errorBuilder: (_, __, ___) => fallback,
          ),
        if (reaction.totalUserCount > 0) ...[
          Container(
            width: 1,
            height: 10,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: colors.chatMessageReactionDivider,
          ),
          Text(
            '${reaction.totalUserCount}',
            style: TextStyle(
              color: colors.chatMessageSecondary,
              fontSize: 12,
              height: 1.25,
            ),
          ),
        ],
      ],
    );
  }
}
