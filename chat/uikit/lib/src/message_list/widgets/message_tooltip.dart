import 'dart:math' as math;

import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_picker_model.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/reaction_emoji_picker.dart';

class MessageMenuItem {
  final String title;
  final IconData? icon;
  final String? assetName;
  final String? package;
  final VoidCallback onTap;
  final bool isDestructive;

  const MessageMenuItem({
    required this.title,
    this.icon,
    this.assetName,
    this.package,
    required this.onTap,
    this.isDestructive = false,
  });
}

abstract class MessageMenuCallbacks {
  void onCopyMessage(MessageInfo message);

  void onDeleteMessage(MessageInfo message);

  void onRecallMessage(MessageInfo message);

  void onForwardMessage(MessageInfo message);

  void onQuoteMessage(MessageInfo message);

  void onMultiSelectMessage(MessageInfo message);

  void onResendMessage(MessageInfo message);
}

class MessageTooltip extends StatefulWidget {
  final List<MessageMenuItem> menuItems;
  final MessageInfo message;
  final VoidCallback onCloseTooltip;
  final bool isSelf;
  final bool showReactionPicker;
  final void Function(EmojiPickerModelItem emoji)? onReactionSelected;

  const MessageTooltip({
    super.key,
    required this.menuItems,
    required this.message,
    required this.onCloseTooltip,
    required this.isSelf,
    this.showReactionPicker = false,
    this.onReactionSelected,
  });

  @override
  State<StatefulWidget> createState() => MessageTooltipState();
}

class MessageTooltipState extends State<MessageTooltip> {
  @override
  Widget build(BuildContext context) {
    final colorTheme = SemanticColorScheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colorTheme.bgColorOperate,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(MediaQuery.of(context).size.width * 0.75, 350),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reaction emoji picker
            //
            // 表情反应选择器
            if (widget.showReactionPicker && widget.onReactionSelected != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ReactionEmojiPicker(
                  onEmojiClick: (emoji) {
                    widget.onCloseTooltip();
                    widget.onReactionSelected!(emoji);
                  },
                  onExpandClick: () async {
                    widget.onCloseTooltip();
                    final selectedEmoji =
                        await ReactionEmojiPickerSheet.show(context);
                    if (selectedEmoji != null &&
                        widget.onReactionSelected != null) {
                      widget.onReactionSelected!(selectedEmoji);
                    }
                  },
                ),
              ),
            // Menu items
            //
            // 菜单项
            Wrap(
              alignment: WrapAlignment.start,
              spacing: 4,
              runSpacing: 4,
              children: widget.menuItems
                  .map((item) => _buildMenuItem(item, colorTheme))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(MessageMenuItem item, SemanticColorScheme colorTheme) {
    return Material(
      color: colorTheme.bgColorOperate,
      child: InkWell(
        onTap: () {
          widget.onCloseTooltip();
          item.onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(
            minWidth: 44,
            maxWidth: 72,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMenuIcon(item, colorTheme),
              const SizedBox(height: 4),
              Text(
                item.title,
                style: FontScheme.caption3Regular.copyWith(
                  decoration: TextDecoration.none,
                  color: item.isDestructive
                      ? colorTheme.textColorError
                      : colorTheme.textColorPrimary,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuIcon(MessageMenuItem item, SemanticColorScheme colorTheme) {
    // 图标色跟随当前 app_ui 主题，确保在不同背景上保持可见。
    // both light and dark modes; destructive actions (e.g. delete) use the
    // error color to match their label.
    //
    // 支持灯光和暗黑模式；破坏性操作（如删除）使用错误颜色以匹配其标签。
    final color = item.isDestructive
        ? colorTheme.textColorError
        : colorTheme.textColorPrimary;

    if (item.assetName != null && item.assetName!.isNotEmpty) {
      final isSvg = item.assetName!.toLowerCase().endsWith('.svg');

      if (isSvg) {
        return SvgPicture.asset(
          item.assetName!,
          package: item.package,
          width: 18,
          height: 18,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          placeholderBuilder: (context) => Icon(
            item.icon,
            size: 18,
            color: color,
          ),
        );
      } else {
        return Image.asset(
          item.assetName!,
          package: item.package,
          width: 18,
          height: 18,
          color: color,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              item.icon,
              size: 18,
              color: color,
            );
          },
        );
      }
    }

    return Icon(
      item.icon,
      size: 18,
      color: color,
    );
  }
}
