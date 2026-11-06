import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 展示直接回复数。仅聊天列表提供点击操作，详情页作为内容标题复用。
final class MessageReplyCount extends StatelessWidget {
  const MessageReplyCount({
    super.key,
    required this.count,
    this.onTap,
    this.identifier,
  });

  /// 已去重的直接回复消息数量。
  final int count;

  /// 仅有可打开的回复详情时提供动作。
  final VoidCallback? onTap;

  /// 聊天列表按源消息区分自动化入口。
  final String? identifier;

  @override
  Widget build(BuildContext context) {
    final color = context.appColors.primary;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.messageBlack, color: color, size: 14),
        const SizedBox(width: 4),
        Text('$count条回复', style: TextStyle(color: color, fontSize: 12)),
      ],
    );
    if (onTap == null) return content;
    return Semantics(
      identifier: identifier,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: content,
        ),
      ),
    );
  }
}
