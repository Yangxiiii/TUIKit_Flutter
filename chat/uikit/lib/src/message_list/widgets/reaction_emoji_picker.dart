import 'package:flutter/material.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_picker_model.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/recent_emoji_manager.dart';

/// Quick emoji picker for message reactions (6 emojis + expand button)
///
/// 消息反应的快捷表情选择器（6 个表情 + 展开按钮）
class ReactionEmojiPicker extends StatefulWidget {
  final void Function(EmojiPickerModelItem emoji) onEmojiClick;
  final VoidCallback onExpandClick;

  const ReactionEmojiPicker({
    super.key,
    required this.onEmojiClick,
    required this.onExpandClick,
  });

  @override
  State<ReactionEmojiPicker> createState() => _ReactionEmojiPickerState();
}

class _ReactionEmojiPickerState extends State<ReactionEmojiPicker> {
  List<EmojiPickerModelItem> _quickEmojis = [];
  bool _isLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isLoaded) {
      _isLoaded = true;
      _loadQuickEmojis();
    }
  }

  Future<void> _loadQuickEmojis() async {
    final emojis = await RecentEmojiManager.getQuickEmojis(context);
    if (mounted) {
      setState(() {
        _quickEmojis = emojis;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colors.bgColorOperate,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._quickEmojis.map((emoji) => _ReactionEmojiItem(
                emoji: emoji,
                onTap: () => widget.onEmojiClick(emoji),
              )),
          GestureDetector(
            onTap: widget.onExpandClick,
            child: Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(left: 2),
              decoration: BoxDecoration(
                color: colors.dropdownColorDefault,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.add,
                size: 18,
                color: colors.textColorSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionEmojiItem extends StatelessWidget {
  final EmojiPickerModelItem emoji;
  final VoidCallback onTap;

  const _ReactionEmojiItem({
    required this.emoji,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: colors.dropdownColorDefault,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Image.asset(
            emoji.path,
            package: 'tencent_chat_uikit',
            width: 26,
            height: 26,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.sentiment_satisfied_alt,
                size: 26,
                color: colors.textColorSecondary,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Full emoji picker sheet for reactions
///
/// 消息反应的完整表情选择面板
class ReactionEmojiPickerSheet extends StatelessWidget {
  final void Function(EmojiPickerModelItem emoji) onEmojiClick;

  const ReactionEmojiPickerSheet({
    super.key,
    required this.onEmojiClick,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    final allEmojis = RecentEmojiManager.getAllEmojis(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.bgColorOperate,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          //
          // 拖拽手柄
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.strokeColorPrimary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Emoji grid
          //
          // 表情网格
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: allEmojis.length,
              itemBuilder: (context, index) {
                final emoji = allEmojis[index];
                return GestureDetector(
                  onTap: () => onEmojiClick(emoji),
                  child: Image.asset(
                    emoji.path,
                    package: 'tencent_chat_uikit',
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.sentiment_satisfied_alt,
                        color: colors.textColorSecondary,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Show the full emoji picker as a bottom sheet
  ///
  /// 以底部面板显示完整表情选择器
  static Future<EmojiPickerModelItem?> show(BuildContext context) {
    // Unfocus and clear primary focus to prevent keyboard from popping up when sheet closes
    //
    // 取消焦点并清除主焦点，以防面板关闭时键盘弹出
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
      FocusManager.instance.primaryFocus?.unfocus();
    }

    return showModalBottomSheet<EmojiPickerModelItem>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => GestureDetector(
        onTap: () {
          // Ensure focus is cleared before closing
          //
          // 在关闭前确保焦点已清除
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(sheetContext).pop();
        },
        behavior: HitTestBehavior.opaque,
        child: GestureDetector(
          onTap: () {},
          child: DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.3,
            maxChildSize: 0.6,
            builder: (context, scrollController) => ReactionEmojiPickerSheet(
              onEmojiClick: (emoji) {
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.of(sheetContext).pop(emoji);
              },
            ),
          ),
        ),
      ),
    );
  }
}
