import '../message_list/utils/recent_emoji_manager.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_manager.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import 'package:tuikit_atomic_x/base_component/theme/color_scheme.dart';
import 'emoji_picker_config.dart';
import 'emoji_picker_model.dart';

/// 展示当前业务唯一表情目录，插入令牌、删除与发送交给输入框回调。
class EmojiPicker extends StatefulWidget {
  /// 选择后返回完整文字令牌，由输入框决定插入和发送时机。
  final Function(Map<String, dynamic> data)? onEmojiClick;

  /// 复用输入框已有发送动作，面板不直接创建SDK消息。
  final VoidCallback? onSendClick;

  /// 交由输入框按完整表情和字素执行退格。
  final VoidCallback? onDeleteClick;

  const EmojiPicker({
    super.key,
    this.onEmojiClick,
    this.onSendClick,
    this.onDeleteClick,
  });

  @override
  State<StatefulWidget> createState() => EmojiPickerState();
}

/// 显示常用表情和完整目录，近期记录只影响顶部排序，不改变原始目录顺序。
class EmojiPickerState extends State<EmojiPicker> {
  /// 缓存本次面板的近期读取结果，父级重建时不重新异步加载或清空面板。
  late Future<List<EmojiPickerModelItem>> _quickEmojis;

  @override
  void initState() {
    super.initState();
    _quickEmojis = _loadQuickEmojis();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    EmojiPickerConfig.loadData(context);
  }

  /// 选择后更新共用近期记录；存储失败时仍按目录顺序提供可点击表情。
  Future<List<EmojiPickerModelItem>> _loadQuickEmojis(
      [String? selected]) async {
    try {
      if (selected != null) await RecentEmojiManager.addRecentEmoji(selected);
      if (!mounted) return const [];
      return await RecentEmojiManager.getQuickEmojis(context);
    } on Object {
      // 近期缓存只决定排序，不能阻断面板展示或已经触发的文字插入。
      return EmojiManager.emojis.take(6).toList();
    }
  }

  /// 顶部常用项与网格共用完整令牌回调，点击后保持表情面板展开。
  void _onEmojiClick(EmojiPickerModelItem emoji) {
    widget.onEmojiClick?.call({
      'type': 0,
      'name': emoji.name,
      'stickerIndex': 0,
      'eventType': 'stickClick',
    });
    if (mounted) {
      final recent = _loadQuickEmojis(emoji.name);
      setState(() {
        _quickEmojis = recent;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 整个面板接收空白处点击，阻止聊天页祖先的收起手势；子级表情和按钮仍优先响应。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: () {},
      child: EmojiPickerConfig.customStickerLists.isEmpty
          ? const EmojiPickerError()
          : Column(children: [
              FutureBuilder<List<EmojiPickerModelItem>>(
                future: _quickEmojis,
                initialData: EmojiManager.emojis.take(6).toList(),
                builder: (context, snapshot) => _QuickEmojiRow(
                  emojis: snapshot.data!,
                  onEmojiClick: _onEmojiClick,
                ),
              ),
              EmojiPickerContent(
                activeTabIndex: 0,
                onEmojiClick: _onEmojiClick,
                onSendClick: widget.onSendClick,
                onDeleteClick: widget.onDeleteClick,
              ),
            ]),
    );
  }
}

/// 目录为空时展示配置错误，不回退到已经弃用的腾讯表情。
class EmojiPickerError extends StatelessWidget {
  const EmojiPickerError({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Padding(
        padding: EdgeInsets.only(right: 10),
        child: Icon(Icons.error_outline),
      ),
    ]);
  }
}

/// 顶部六项常用表情直接插入文字，与下方网格使用同一点击回调。
class _QuickEmojiRow extends StatelessWidget {
  const _QuickEmojiRow({required this.emojis, required this.onEmojiClick});

  /// 近期项优先，不足六项时由原始目录顺序补足。
  final List<EmojiPickerModelItem> emojis;

  /// 点击后插入完整令牌，不执行分类切换或关闭面板。
  final ValueChanged<EmojiPickerModelItem> onEmojiClick;

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.strokeColorPrimary)),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        for (final emoji in emojis)
          Expanded(
            child: Semantics(
              identifier: 'tim.emoji.quick.${emoji.name}',
              label: emoji.label,
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onEmojiClick(emoji),
                child: SizedBox(
                  height: 40,
                  child: Center(
                      child: Image.asset(emoji.path,
                          package: EmojiManager.assetPackage,
                          width: 32,
                          height: 32)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// 按业务顺序展示表情网格，并保留输入框的发送和退格操作。
class EmojiPickerContent extends StatefulWidget {
  /// 当前显示的分组编号，不作为表情的业务编号。
  final int activeTabIndex;

  /// 选择当前目录项，令牌事件由外层面板统一构造。
  final ValueChanged<EmojiPickerModelItem>? onEmojiClick;

  /// 复用输入框已有发送动作，面板不直接创建SDK消息。
  final VoidCallback? onSendClick;

  /// 交由输入框按完整表情和字素执行退格。
  final VoidCallback? onDeleteClick;

  const EmojiPickerContent({
    super.key,
    required this.activeTabIndex,
    this.onEmojiClick,
    this.onSendClick,
    this.onDeleteClick,
  });

  @override
  State<StatefulWidget> createState() => EmojiPickerContentState();
}

/// 将当前目录令牌交给输入框，滚动网格独立于底部操作按钮。
class EmojiPickerContentState extends State<EmojiPickerContent> {
  /// 面板依赖变化时读取当前语言，底部发送按钮沿用输入区文案。
  late AppLocalizedText atomicLocale;

  /// 网格与底部操作区域使用当前主题，不缓存跨主题颜色。
  late SemanticColorScheme colorsTheme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    atomicLocale = AppLocalization.of(context);
    colorsTheme = SemanticColorScheme.of(context);
  }

  @override
  Widget build(BuildContext context) {
    List<EmojiPickerModelItem> currentStickerList = [];
    int crossAxisCount = 7;
    if (EmojiPickerConfig.customStickerLists
            .elementAtOrNull(widget.activeTabIndex) !=
        null) {
      currentStickerList =
          EmojiPickerConfig.customStickerLists[widget.activeTabIndex].stickers;
      crossAxisCount =
          EmojiPickerConfig.customStickerLists[widget.activeTabIndex].rowNum;
    }

    return Expanded(
      child: SafeArea(
        child: Stack(
          children: [
            // 网格填满实际键盘区域，底部留出操作按钮的位置，不再嵌套固定高度滚动区。
            Positioned.fill(
              child: GridView(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 70),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 1,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                children: [
                  for (final emoji in currentStickerList)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onEmojiClick?.call(emoji),
                      child: Semantics(
                        identifier: 'tim.emoji.insert.${emoji.name}',
                        label: emoji.label,
                        button: true,
                        child: Image.asset(emoji.path,
                            package: EmojiManager.assetPackage),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildActionButtons(colorsTheme, atomicLocale),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部操作固定在网格上层，发送和退格仍由输入框处理。
  Widget _buildActionButtons(
      SemanticColorScheme colorsTheme, AppLocalizedText atomicLocale) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorsTheme.textColorButton.withAlpha(0),
            colorsTheme.textColorButton.withAlpha(200),
            colorsTheme.textColorButton,
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (widget.onDeleteClick != null)
            Container(
              margin: const EdgeInsets.only(right: 12),
              child: Semantics(
                identifier: 'tim.emoji.delete',
                label: '删除表情',
                button: true,
                child: InkWell(
                  onTap: widget.onDeleteClick,
                  child: Icon(
                    Icons.backspace_outlined,
                    size: 24,
                    color: colorsTheme.buttonColorOff,
                  ),
                ),
              ),
            ),
          if (widget.onSendClick != null)
            Semantics(
              identifier: 'tim.emoji.send',
              label: atomicLocale.send,
              button: true,
              child: InkWell(
                onTap: widget.onSendClick,
                child: Container(
                  width: 60,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colorsTheme.buttonColorPrimaryDefault,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      atomicLocale.send,
                      style: TextStyle(
                        color: colorsTheme.textColorButton,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
