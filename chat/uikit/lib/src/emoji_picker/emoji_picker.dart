import '../message_list/utils/recent_emoji_manager.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_manager.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import 'package:tuikit_atomic_x/base_component/theme/color_scheme.dart';
import 'emoji_picker_config.dart';
import 'emoji_picker_model.dart';

/// 展示常用表情与完整目录，选择后将令牌交给活动输入框。
class EmojiPicker extends StatefulWidget {
  /// 选择后返回完整文字令牌，由输入框决定插入和发送时机。
  final Function(Map<String, dynamic> data)? onEmojiClick;

  /// 语音预览的退格交由预览文字输入框处理。
  final VoidCallback? onDeleteClick;

  /// 语音编辑采用带分区标题的目录，确认发送仍由浮层提供，不在面板另放发送按钮。
  final bool voicePreview;

  const EmojiPicker({
    super.key,
    this.onEmojiClick,
    this.onDeleteClick,
    this.voicePreview = false,
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
      if (widget.voicePreview) {
        final recent = await RecentEmojiManager.getRecentEmojiIds();
        return {...recent, ...EmojiManager.emojis.map((item) => item.name)}
            .take(7)
            .map((id) => EmojiManager.getEmoji(id)!)
            .toList();
      }
      return await RecentEmojiManager.getQuickEmojis(context);
    } on Object {
      // 近期缓存只决定排序，不能阻断面板展示或已经触发的文字插入。
      return EmojiManager.emojis.take(widget.voicePreview ? 7 : 6).toList();
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
          : widget.voicePreview
              ? _voicePanel(context)
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
                  ),
                ]),
    );
  }

  /// 常用行、完整目录与底部退格分别定位，目录只滚动自身，不挤压语音确认操作。
  Widget _voicePanel(BuildContext context) {
    final colors = context.appColors;
    // 面板独立遮住聊天底图，网格空白和底部安全区也不能透出原会话。
    return ColoredBox(
        color: colors.groupedPageBackground,
        child: Stack(children: [
          Positioned.fill(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 64),
                children: [
                  Text('最常使用',
                      style: TextStyle(
                          fontSize: 12,
                          height: 17 / 12,
                          color: colors.textTertiary)),
                  const SizedBox(height: 12),
                  FutureBuilder<List<EmojiPickerModelItem>>(
                    future: _quickEmojis,
                    initialData: EmojiManager.emojis.take(7).toList(),
                    builder: (_, snapshot) =>
                        _voiceGrid(snapshot.data!, 'recent'),
                  ),
                  const SizedBox(height: 20),
                  Text('默认表情',
                      style: TextStyle(
                          fontSize: 12,
                          height: 17 / 12,
                          color: colors.textTertiary)),
                  const SizedBox(height: 12),
                  _voiceGrid(EmojiManager.emojis.toList(), 'default'),
                ]),
          ),
          Positioned(
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 8,
            child: Semantics(
              identifier: 'chat.voice.emoji_delete',
              button: true,
              enabled: widget.onDeleteClick != null,
              label: '删除表情或文字',
              child: GestureDetector(
                onTap: widget.onDeleteClick,
                child: Container(
                    width: 48,
                    height: 40,
                    decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(8)),
                    // 项目字体暂无退格字形，保留既有表情键盘图标，待字体补齐后统一替换。
                    child: Icon(Icons.backspace_outlined,
                        size: 24,
                        color: widget.onDeleteClick == null
                            ? colors.textTertiary
                            : colors.textPrimary)),
              ),
            ),
          ),
        ]));
  }

  /// 两个分区使用独立语义命名空间，近期表情同时出现在完整目录时仍可唯一定位。
  Widget _voiceGrid(List<EmojiPickerModelItem> emojis, String section) =>
      GridView.builder(
        // 安全区已由面板统一承载，内嵌网格不能再次自动添加状态栏及底部留白。
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 32,
            mainAxisSpacing: 20,
            crossAxisSpacing: 20),
        itemCount: emojis.length,
        itemBuilder: (_, index) {
          final emoji = emojis[index];
          return Semantics(
              identifier: 'chat.voice.emoji.$section.${emoji.name}',
              label: emoji.label,
              button: true,
              child: GestureDetector(
                  onTap: () => _onEmojiClick(emoji),
                  child: Image.asset(emoji.path,
                      package: EmojiManager.assetPackage,
                      width: 32,
                      height: 32)));
        },
      );
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

/// 按业务顺序显示可滚动表情网格，常用行由面板单独承载。
class EmojiPickerContent extends StatelessWidget {
  /// 当前显示的分组编号，不作为表情的业务编号。
  final int activeTabIndex;

  /// 选择当前目录项，令牌事件由外层面板统一构造。
  final ValueChanged<EmojiPickerModelItem>? onEmojiClick;

  const EmojiPickerContent({
    super.key,
    required this.activeTabIndex,
    this.onEmojiClick,
  });

  @override
  Widget build(BuildContext context) {
    final group =
        EmojiPickerConfig.customStickerLists.elementAtOrNull(activeTabIndex);
    return Expanded(
      child: SafeArea(
        // 输入工具栏承担操作入口，表情网格填满面板可用高度。
        child: GridView(
          padding: const EdgeInsets.all(10),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: group?.rowNum ?? 7,
            childAspectRatio: 1,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          children: [
            for (final emoji
                in group?.stickers ?? const <EmojiPickerModelItem>[])
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onEmojiClick?.call(emoji),
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
    );
  }
}
