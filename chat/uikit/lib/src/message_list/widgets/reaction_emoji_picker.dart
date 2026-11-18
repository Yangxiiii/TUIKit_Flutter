import 'package:app_ui/app_ui.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_manager.dart';
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

/// 在面板生命周期内加载近期回应，资源始终来自当前目录。
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

/// 展示单个业务回应入口，点击后交由消息层处理。
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
          child: Semantics(
            identifier: 'tim.reaction.quick.${emoji.name}',
            label: emoji.label,
            button: true,
            child: Image.asset(
              emoji.path,
              package: EmojiManager.assetPackage,
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
      ),
    );
  }
}

/// 展示常用和默认回应表情，面板高度由外层拖拽容器管理。
class ReactionEmojiPickerSheet extends StatelessWidget {
  /// 选择任一表情后由外层关闭面板并提交回应。
  final void Function(EmojiPickerModelItem emoji) onEmojiClick;

  /// 两组表情共用拖拽容器提供的滚动控制器。
  final ScrollController? scrollController;

  /// 打开面板时读取的常用项，避免拖动期间因缓存回调改变布局。
  final List<EmojiPickerModelItem> quickEmojis;

  const ReactionEmojiPickerSheet({
    super.key,
    required this.onEmojiClick,
    this.scrollController,
    this.quickEmojis = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final allEmojis = RecentEmojiManager.getAllEmojis(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
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
              color: colors.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 两组网格和标题属于同一滚动区，上滑先展开面板再翻阅其内容。
          Expanded(
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverMainAxisGroup(slivers: [
                    if (quickEmojis.isNotEmpty) ...[
                      _heading('最常使用'),
                      _grid(quickEmojis, 'recent'),
                      const SliverToBoxAdapter(child: SizedBox(height: 20)),
                    ],
                    _heading('默认表情'),
                    _grid(allEmojis, 'select'),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  SliverToBoxAdapter _heading(String title) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(title),
        ),
      );

  /// 同一表情可能在两组出现，使用分区标识区分实际点击节点。
  SliverGrid _grid(List<EmojiPickerModelItem> emojis, String section) =>
      SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: emojis.length,
        itemBuilder: (context, index) {
          final emoji = emojis[index];
          return GestureDetector(
            onTap: () => onEmojiClick(emoji),
            child: Semantics(
              identifier: 'tim.reaction.$section.${emoji.name}',
              label: emoji.label,
              button: true,
              child: Center(
                  child: Image.asset(
                emoji.path,
                package: EmojiManager.assetPackage,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.sentiment_satisfied_alt,
                    color: context.appColors.textSecondary,
                  );
                },
              )),
            ),
          );
        },
      );

  /// 以底部面板展示常用表情和完整目录，近期缓存失效时以默认顺序补足。
  static Future<EmojiPickerModelItem?> show(BuildContext context) async {
    final recent = await RecentEmojiManager.getRecentEmojiIds()
        .onError<Object>((_, __) => const <String>[]);
    if (!context.mounted) return null;
    final quickEmojis = {...recent, ...EmojiManager.emojis.map((e) => e.name)}
        .take(14)
        .map((id) => EmojiManager.getEmoji(id)!)
        .toList(growable: false);
    // 清除主焦点，以防面板关闭时恢复上一层的输入键盘。
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
      barrierColor: context.appColors.scrim.withValues(alpha: .6),
      useSafeArea: true,
      // 空白区域交给路由遮罩处理，拖拽容器只占实际面板高度。
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        shouldCloseOnMinExtent: false,
        snap: true,
        builder: (context, scrollController) => ReactionEmojiPickerSheet(
          scrollController: scrollController,
          quickEmojis: quickEmojis,
          onEmojiClick: (emoji) {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.of(sheetContext).pop(emoji);
          },
        ),
      ),
    );
  }
}
