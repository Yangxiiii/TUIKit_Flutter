import 'dart:io';

import 'package:flutter/material.dart';
import 'package:app_ui/app_ui.dart' show AppIcons;
import 'package:tencent_chat_uikit/src/file_picker/file_picker.dart';
import 'package:tencent_chat_uikit/src/message_input/message_input_config.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';
import 'package:tencent_chat_uikit/src/message_input/src/chat_special_text_span_builder.dart';
import 'package:tencent_chat_uikit/src/message_input/utils/image_size_reader.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_markdown_format.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/rich_content_video_preview.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text_field/extended_text_field.dart';
import 'package:tuikit_atomic_x/album_picker/album_picker.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart'
    hide IconButton;

const _editorBodyTopPadding = 12.0;
const _editorBodyBottomPadding = 20.0;

const _editorImageVerticalMargin = 4.0;

/// 附件令牌的起始字符。
const richContentAttachmentTokenStart = '\uFFF9';

/// 附件令牌的结束字符。
const richContentAttachmentTokenEnd = '\uFFFA';

/// 匹配附件稳定 ID 的编辑态令牌。
final richContentAttachmentTokenPattern = RegExp(
  '$richContentAttachmentTokenStart(\\d+)$richContentAttachmentTokenEnd',
);

/// 返回编辑态附件的可逆令牌，普通输入框和展开编辑器共用。
String richContentAttachmentToken(int id) =>
    '$richContentAttachmentTokenStart$id$richContentAttachmentTokenEnd';

/// 按当前行内最高图片或视频封面计算光标高度，普通文字行返回 null。
double? richContentAttachmentCursorHeight({
  required BuildContext context,
  required TextEditingController controller,
  required Map<int, RichContentDraftAttachmentBlock> attachments,
  required double maxImageWidth,
  required TextStyle textStyle,
}) {
  final text = controller.text;
  final selection = controller.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;
  final caret = selection.extentOffset.clamp(0, text.length);
  final lineStart = caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
  final separator = text.indexOf('\n', caret);
  final lineEnd = separator < 0 ? text.length : separator;
  final line = text.substring(lineStart, lineEnd);
  double? imageLineHeight;
  for (final match in richContentAttachmentTokenPattern.allMatches(line)) {
    final block = attachments[int.parse(match.group(1)!)];
    if (block == null || !block.attachment.isInlineMedia) continue;
    final height = richContentEditorImageSize(
      block.attachment,
      maxImageWidth,
    ).height;
    if (imageLineHeight == null || height > imageLineHeight) {
      imageLineHeight = height;
    }
  }
  if (imageLineHeight == null) return null;
  final textLineHeight = TextPainter(
    text: TextSpan(text: ' ', style: textStyle),
    textDirection: Directionality.of(context),
  ).preferredLineHeight;
  return imageLineHeight > textLineHeight ? imageLineHeight : textLineHeight;
}

/// 富文本编辑器关闭时返回的草稿和发送结果。
final class RichContentEditorResult {
  /// 关闭时的最新草稿。
  final RichContentDraft draft;

  /// 是否已经成功发送；成功时调用方应清空普通输入框草稿。
  final bool sent;

  const RichContentEditorResult({required this.draft, required this.sent});
}

/// 将编辑器绘制在普通输入区之上，并让共享工具条保持在编辑器之上。
final class RichContentEditorOverlayLayout extends StatelessWidget {
  /// 编辑器区域从页面顶部延伸到共享工具条上沿。
  final double editorBottom;

  /// 共享工具条在根 Overlay 中的位置和尺寸。
  final Rect toolbarRect;

  /// 包含遮罩和上升动画的编辑器。
  final Widget editor;

  /// 与普通输入区共用状态和回调的顶层工具条视图。
  final Widget toolbar;

  const RichContentEditorOverlayLayout({
    super.key,
    required this.editorBottom,
    required this.toolbarRect,
    required this.editor,
    required this.toolbar,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          key: const Key('rich_content_editor_layer'),
          top: 0,
          left: 0,
          right: 0,
          height: editorBottom,
          child: editor,
        ),
        Positioned.fromRect(
          key: const Key('rich_content_toolbar_layer'),
          rect: toolbarRect,
          child: toolbar,
        ),
      ],
    );
  }
}

/// 为普通输入和展开编辑器提供同一套快捷操作与文字格式工具条。
final class RichContentInputToolbar extends StatelessWidget {
  /// 工具条切换动画的稳定身份，普通输入与展开态分别持有。
  final Key _switcherKey;

  /// 当前工具条的键与无障碍标识前缀。
  final String _keyPrefix;

  /// 为真时展示格式操作，为假时展示默认七个快捷入口。
  final bool _showFormatting;

  /// 当前草稿已启用的格式标记，组件不维护第二份格式状态。
  final Set<String> _activeFormats;

  /// 调用方已校验内容上限及发送状态，禁用时不触发发送回调。
  final bool _canSend;

  /// 表情面板展开时，原表情入口显示键盘字形。
  final bool _showKeyboard;
  final String _emojiTooltip;
  final String _imageTooltip;
  final String _fileTooltip;
  final String _sendTooltip;
  final VoidCallback? _onEmoji;
  final VoidCallback? _onMention;
  final VoidCallback? _onVideo;
  final VoidCallback? _onImage;
  final VoidCallback? _onFile;
  final VoidCallback _onShowFormatting;
  final VoidCallback _onCloseFormatting;
  final ValueChanged<String> _onToggleFormat;
  final VoidCallback? _onSend;

  /// 根据调用方的编辑状态构建统一工具条，事件仍由各自输入区处理。
  const RichContentInputToolbar({
    super.key,
    required Key switcherKey,
    required String keyPrefix,
    required bool showFormatting,
    required Set<String> activeFormats,
    required bool canSend,
    bool showKeyboard = false,
    required String emojiTooltip,
    required String imageTooltip,
    required String fileTooltip,
    required String sendTooltip,
    required VoidCallback? onEmoji,
    required VoidCallback? onMention,
    required VoidCallback? onVideo,
    required VoidCallback? onImage,
    required VoidCallback? onFile,
    required VoidCallback onShowFormatting,
    required VoidCallback onCloseFormatting,
    required ValueChanged<String> onToggleFormat,
    required VoidCallback? onSend,
  })  : _switcherKey = switcherKey,
        _keyPrefix = keyPrefix,
        _showFormatting = showFormatting,
        _activeFormats = activeFormats,
        _canSend = canSend,
        _showKeyboard = showKeyboard,
        _emojiTooltip = emojiTooltip,
        _imageTooltip = imageTooltip,
        _fileTooltip = fileTooltip,
        _sendTooltip = sendTooltip,
        _onEmoji = onEmoji,
        _onMention = onMention,
        _onVideo = onVideo,
        _onImage = onImage,
        _onFile = onFile,
        _onShowFormatting = onShowFormatting,
        _onCloseFormatting = onCloseFormatting,
        _onToggleFormat = onToggleFormat,
        _onSend = onSend;

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    return ClipRect(
      child: AnimatedSwitcher(
        key: _switcherKey,
        duration: const Duration(milliseconds: 180),
        reverseDuration: const Duration(milliseconds: 180),
        transitionBuilder: (child, animation) {
          final isFormatting =
              child.key == ValueKey('${_keyPrefix}_formatting');
          // 切换动画的旧工具条仍在绘制，但不能保留可操作的重复语义入口。
          return ExcludeSemantics(
            excluding: child.key !=
                ValueKey(
                  _showFormatting
                      ? '${_keyPrefix}_formatting'
                      : '${_keyPrefix}_main',
                ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, isFormatting ? 1 : -1),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(
            _showFormatting ? '${_keyPrefix}_formatting' : '${_keyPrefix}_main',
          ),
          child: _showFormatting
              ? _buildFormattingToolbar(colors)
              : _buildMainToolbar(colors),
        ),
      ),
    );
  }

  /// 快捷栏使用同源字体字形，保留六个入口和独立的发送区域。
  Widget _buildMainToolbar(SemanticColorScheme colors) => _buildActionRow(
        [
          _iconButton(_showKeyboard ? AppIcons.inputKeyboard : AppIcons.emoji,
              _emojiTooltip, _onEmoji, colors),
          _iconButton(AppIcons.a, '提及成员', _onMention, colors),
          _iconButton(AppIcons.startVideoConference, '视频通话', _onVideo, colors),
          MergeSemantics(
            child: Semantics(
              identifier: 'tim.$_keyPrefix.album',
              child:
                  _iconButton(AppIcons.photo, _imageTooltip, _onImage, colors),
            ),
          ),
          MergeSemantics(
            child: Semantics(
              identifier: 'tim.$_keyPrefix.file',
              child: _iconButton(AppIcons.flile, _fileTooltip, _onFile, colors),
            ),
          ),
          _iconButton(AppIcons.format, '文字格式', _onShowFormatting, colors),
        ],
        _buildSendButton(colors, _sendTooltip),
      );

  /// 格式切换只改变工具条内容，发送仍使用同一个字形和可用状态。
  Widget _buildFormattingToolbar(SemanticColorScheme colors) => _buildActionRow(
        [
          _iconButton(AppIcons.expand, '关闭文字格式', _onCloseFormatting, colors),
          for (final format in [
            (AppIcons.bold, '粗体', '**'),
            (AppIcons.strikethrough, '删除线', '~~'),
            (AppIcons.tilt, '斜体', '*'),
            (AppIcons.underline, '下划线', '~'),
          ])
            _iconButton(
                format.$1, format.$2, () => _onToggleFormat(format.$3), colors,
                selected: _activeFormats.contains(format.$3)),
        ],
        _buildSendButton(colors, '发送富文本消息'),
      );

  /// 对照390宽设计：44高触控区，前六项等距，发送前留34的独立间隔。
  Widget _buildActionRow(List<Widget> actions, Widget send) => SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: LayoutBuilder(builder: (context, constraints) {
            // 窄屏只收缩操作触控区，避免七个入口与发送间隔挤出可用宽度。
            final actionWidth =
                ((constraints.maxWidth - 78) / actions.length).clamp(0.0, 44.0);
            return Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final action in actions)
                        SizedBox(width: actionWidth, child: action),
                    ],
                  ),
                ),
                const SizedBox(width: 34),
                send,
              ],
            );
          }),
        ),
      );

  /// 合并按钮语义，禁用时保留实心发送字形并关闭点击动作。
  Widget _buildSendButton(SemanticColorScheme colors, String tooltip) =>
      MergeSemantics(
        child: Semantics(
          identifier: 'tim.$_keyPrefix.send',
          child: _iconButton(
              AppIcons.send1, tooltip, _canSend ? _onSend : null, colors,
              highlight: true),
        ),
      );

  Widget _iconButton(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed,
    SemanticColorScheme colors, {
    bool highlight = false,
    bool selected = false,
  }) =>
      SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          isSelected: selected,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: selected
                ? colors.buttonColorPrimaryDefault.withValues(alpha: 0.12)
                : null,
          ),
          icon: Icon(
            icon,
            size: 24,
            color: onPressed == null
                ? colors.textColorTertiary
                : highlight || selected
                    ? colors.buttonColorPrimaryDefault
                    : colors.textColorPrimary,
          ),
        ),
      );
}

/// 按 MasterGo 展开态展示标题、有序正文块和格式工具栏。
final class RichContentEditorSheet extends StatefulWidget {
  /// 当前会话名称，用于正文空态提示。
  final String conversationName;

  /// 上次收起时保存的富文本草稿。
  final RichContentDraft initialDraft;

  /// 业务附件上传入口；未配置时附件保持待上传并禁用发送。
  final RichContentAttachmentUploader? attachmentUploader;

  /// 宿主提供的原色播放图标，同时用于展开编辑器和普通输入区。
  final ImageProvider? videoPlayIcon;

  /// 把完整自定义消息交回 MessageInput 发送，成功时返回 true。
  final Future<bool> Function(RichContentDraft draft) onSend;

  /// 关闭时把最新草稿和发送结果交回输入区。
  final ValueChanged<RichContentEditorResult>? onClose;

  /// 编辑状态变化时通知外部共享工具条刷新。
  final VoidCallback? onToolbarChanged;

  /// 编辑内容变化时把完整草稿交给输入区执行防抖持久化。
  final ValueChanged<RichContentDraft>? onDraftChanged;

  /// 是否在编辑器内嵌工具条；生产聊天页使用外部共享工具条。
  final bool showToolbar;

  /// 打开前共享工具条是否已切换到 Markdown 格式模式。
  final bool initialShowFormatting;

  /// 打开前共享工具条已选中的 Markdown 标记。
  final Set<String> initialActiveFormats;

  const RichContentEditorSheet({
    super.key,
    required this.conversationName,
    required this.initialDraft,
    required this.onSend,
    this.attachmentUploader,
    this.videoPlayIcon,
    this.onClose,
    this.onToolbarChanged,
    this.onDraftChanged,
    this.showToolbar = true,
    this.initialShowFormatting = false,
    this.initialActiveFormats = const {},
  });

  @override
  State<RichContentEditorSheet> createState() => RichContentEditorSheetState();
}

/// 管理编辑器打开期间的输入、焦点和附件上传状态。
final class RichContentEditorSheetState extends State<RichContentEditorSheet> {
  late final TextEditingController _titleController;
  final List<_EditorBlock> _blocks = [];

  /// 正文图片和视频令牌对应的草稿块；令牌被删除时同步移除，避免已删媒体参与发送。
  final Map<int, RichContentDraftAttachmentBlock> _inlineMedia = {};
  final Set<int> _insertedAlbumMediaIds = {};
  int _nextBlockId = 1;
  int? _activeTextBlockId;
  late bool _showFormatting;

  /// 仅限制本编辑器的提交交互；跨入口业务防重仍由宿主发送入口处理。
  bool _isSending = false;

  /// 当前格式栏中处于选中状态的 Markdown 标记。
  final Set<String> _activeFormats = {};
  late final _formatInputFormatter = activeMarkdownFormatInputFormatter(
    () => _activeFormats,
  );

  /// 外部共享工具条当前是否显示文字格式操作。
  bool get showFormatting => _showFormatting;

  /// 外部共享工具条当前的格式选中集合。
  Set<String> get activeFormats => Set.unmodifiable(_activeFormats);

  /// 当前草稿是否满足富文本发送条件。
  bool get canSend => !_isSending && _buildDraft().canSend;

  /// 应用编辑状态后同步最新草稿和共享工具条，保证持久化读取更新后的内容。
  void _setEditorState(VoidCallback change) {
    setState(change);
    widget.onDraftChanged?.call(_buildDraft());
    widget.onToolbarChanged?.call();
  }

  @override
  void initState() {
    super.initState();
    _showFormatting = widget.initialShowFormatting;
    _activeFormats.addAll(widget.initialActiveFormats);
    _titleController = TextEditingController(text: widget.initialDraft.title)
      ..addListener(_refresh);
    _restoreDraft(widget.initialDraft);
    if (_blocks.isEmpty) _blocks.add(_newTextBlock());
    for (final block in _blocks.whereType<_TextEditorBlock>()) {
      block.lastValue = block.controller.value;
      block.controller.addListener(_refresh);
      block.focusNode.addListener(_refresh);
    }
    final initialBlock = _blocks.whereType<_TextEditorBlock>().first;
    _activeTextBlockId = initialBlock.id;
    // 在弹层首帧建立输入连接后接管焦点，键盘已展开时不会先收起再弹出。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      initialBlock.focusNode.requestFocus();
      widget.onToolbarChanged?.call();
    });
  }

  @override
  void dispose() {
    _titleController
      ..removeListener(_refresh)
      ..dispose();
    for (final block in _blocks.whereType<_TextEditorBlock>()) {
      block.controller
        ..removeListener(_refresh)
        ..dispose();
      block.focusNode
        ..removeListener(_refresh)
        ..dispose();
    }
    super.dispose();
  }

  /// 同步当前正文块的光标样式并清理已删除附件，再刷新编辑器及外部工具栏。
  void _refresh() {
    if (!mounted) return;
    // 只在实际移动光标或切换正文块时派生格式；文字提交不能覆盖用户刚选择的输入样式。
    for (final block in _blocks.whereType<_TextEditorBlock>()) {
      final value = block.controller.value;
      final previous = block.lastValue;
      block.lastValue = value;
      final moved = value.text == previous.text &&
          previous.selection.isValid &&
          value.selection != previous.selection;
      final activated =
          block.focusNode.hasFocus && block.id != _activeTextBlockId;
      if ((moved || activated) &&
          value.selection.isValid &&
          value.selection.isCollapsed) {
        _activeTextBlockId = block.id;
        _activeFormats
          ..clear()
          ..addAll(richContentMarkdownFormatsAt(
              value.text, value.selection.extentOffset));
      }
    }
    final source = _blocks
        .whereType<_TextEditorBlock>()
        .map((block) => block.controller.text)
        .join();
    // ExtendedTextField 会整体删除图片令牌，此处以控制器原文为准回收图片状态。
    _inlineMedia.removeWhere(
      (id, _) => !source.contains(richContentAttachmentToken(id)),
    );
    _setEditorState(() {});
  }

  _TextEditorBlock _newTextBlock([String text = '']) {
    return _TextEditorBlock(
      _nextBlockId++,
      TextEditingController(text: text),
      FocusNode(),
    );
  }

  /// 把已保存图片和视频还原为同一文本控制器中的原子占位元素。
  void _restoreDraft(RichContentDraft draft) {
    for (final block in draft.blocks) {
      _nextBlockId = _nextBlockId > block.id ? _nextBlockId : block.id + 1;
    }
    _TextEditorBlock? currentText;
    for (final block in draft.blocks) {
      switch (block) {
        case RichContentDraftTextBlock block:
          currentText ??= _TextEditorBlock(
            block.id,
            TextEditingController(),
            FocusNode(),
          );
          if (!_blocks.contains(currentText)) _blocks.add(currentText);
          currentText.controller.text += block.text;
        case RichContentDraftAttachmentBlock block
            when block.attachment.isInlineMedia:
          currentText ??= _newTextBlock();
          if (!_blocks.contains(currentText)) _blocks.add(currentText);
          _inlineMedia[block.id] = block;
          currentText.controller.text += richContentAttachmentToken(block.id);
        case RichContentDraftAttachmentBlock block:
          currentText = null;
          _blocks.add(_AttachmentEditorBlock(block));
      }
    }
  }

  /// 按正文中的文字和媒体令牌顺序还原发送草稿。
  RichContentDraft _buildDraft() {
    final draftBlocks = <RichContentDraftBlock>[];
    var nextDraftId = _nextBlockId;
    // 媒体令牌只用于编辑态；发送前拆回有序文字块及各自的媒体协议。
    for (final block in _blocks) {
      if (block is _AttachmentEditorBlock) {
        draftBlocks.add(block.block);
        continue;
      }
      final textBlock = block as _TextEditorBlock;
      var offset = 0;
      for (final match in richContentAttachmentTokenPattern.allMatches(
        textBlock.controller.text,
      )) {
        final text = textBlock.controller.text.substring(offset, match.start);
        if (text.isNotEmpty) {
          draftBlocks.add(RichContentDraftTextBlock(nextDraftId++, text));
        }
        final image = _inlineMedia[int.parse(match.group(1)!)];
        if (image != null) draftBlocks.add(image);
        offset = match.end;
      }
      final trailing = textBlock.controller.text.substring(offset);
      if (trailing.isNotEmpty) {
        draftBlocks.add(RichContentDraftTextBlock(nextDraftId++, trailing));
      }
    }
    return RichContentDraft(
      title: _titleController.text,
      blocks: draftBlocks,
    );
  }

  void _close() {
    final result = RichContentEditorResult(draft: _buildDraft(), sent: false);
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }

  /// 发送当前快照；成功只关闭未继续编辑的草稿，失败或异常均释放忙碌态。
  Future<void> send() async {
    final draft = _buildDraft();
    if (_isSending || !draft.canSend) return;
    final sentSnapshot = draft.toPersistedString();
    _setEditorState(() => _isSending = true);
    var closed = false;
    try {
      final sent = await widget.onSend(draft);
      // 发送期间允许继续编辑，旧消息成功不能带走用户新增的内容。
      if (!mounted ||
          !sent ||
          _buildDraft().toPersistedString() != sentSnapshot) {
        return;
      }
      const result = RichContentEditorResult(
        draft: RichContentDraft(),
        sent: true,
      );
      final onClose = widget.onClose;
      if (onClose != null) {
        onClose(result);
      } else {
        Navigator.of(context).pop(result);
      }
      closed = true;
    } finally {
      // 已关闭的编辑器不能再回传旧草稿，未关闭时保证失败后可以重试。
      if (mounted && !closed) _setEditorState(() => _isSending = false);
    }
  }

  /// 在当前正文光标处插入表情。
  void insertEmoji() => _insertText('😀');

  /// 在当前正文光标处插入提及符号。
  void insertMention() => _insertText('@');

  void _insertText(String value) {
    final block =
        _activeTextBlock ?? _blocks.whereType<_TextEditorBlock>().last;
    final current = block.controller.value;
    final selection = current.selection.isValid
        ? current.selection
        : TextSelection.collapsed(offset: current.text.length);
    block.controller.value = TextEditingValue(
      text: current.text.replaceRange(selection.start, selection.end, value),
      selection: TextSelection.collapsed(
        offset: selection.start + value.length,
      ),
    );
    block.focusNode.requestFocus();
  }

  _TextEditorBlock? get _activeTextBlock {
    for (final block in _blocks.whereType<_TextEditorBlock>()) {
      if (block.id == _activeTextBlockId) return block;
    }
    return null;
  }

  /// 点击正文时同步当前块的光标格式；空正文保留已手动选择、尚待输入的样式。
  void _activateTextBlock(_TextEditorBlock block) {
    if (_activeTextBlockId == block.id) return;
    _setEditorState(() {
      _activeTextBlockId = block.id;
      final value = block.controller.value;
      if (value.text.isNotEmpty &&
          value.selection.isValid &&
          value.selection.isCollapsed) {
        _activeFormats
          ..clear()
          ..addAll(richContentMarkdownFormatsAt(
              value.text, value.selection.extentOffset));
      }
    });
  }

  /// 切换外部共享工具条指定的 Markdown 格式。
  void toggleFormat(String marker) {
    final block =
        _activeTextBlock ?? _blocks.whereType<_TextEditorBlock>().last;
    if (block.controller.selection.isCollapsed) {
      final value = exitActiveMarkdownFormats(
        block.controller.value,
        _activeFormats,
      );
      block.lastValue = value;
      block.controller.value = value;
    }
    if (!_activeFormats.remove(marker)) {
      _activeFormats.add(marker);
    }
    _setEditorState(() {});
    block.focusNode.requestFocus();
  }

  /// 返回快捷工具条，并结束当前格式范围。
  void closeFormattingToolbar() {
    final block =
        _activeTextBlock ?? _blocks.whereType<_TextEditorBlock>().last;
    final value = exitActiveMarkdownFormats(
      block.controller.value,
      _activeFormats,
    );
    block.lastValue = value;
    block.controller.value = value;
    _setEditorState(() {
      _activeFormats.clear();
      _showFormatting = false;
    });
  }

  /// 选择相册图片或视频，处理完成后按当前光标位置插入草稿。
  Future<void> pickAlbumMedia() async {
    _insertedAlbumMediaIds.clear();
    final locale = Localizations.localeOf(context);
    await AlbumPicker.pickMedia(
      config: AlbumPickerConfig(
        mediaFilter: AlbumPickerMediaFilter.imageAndVideo,
        maxSelectionCount: 9,
        itemsPerRow: 3,
        showsCameraItem: false,
        style: AlbumPickerStyle.likeWeChat,
        language: locale.languageCode == 'zh'
            ? AlbumPickerLanguage.zhHans
            : AlbumPickerLanguage.en,
      ),
      theme: AlbumPickerTheme(
        primaryColor: Theme.of(context).colorScheme.primary,
      ),
      // 确认事件只代表用户完成选择；统一等待处理完成，避免读取尚未生成的沙盒路径。
      onMediaProcessing: (media, progress, error) async {
        if (error || progress < 1) return;
        await insertProcessedMedia(media);
      },
    );
  }

  /// 将处理完成的媒体插入草稿；同一选择会话中的重复完成事件只消费一次。
  @visibleForTesting
  Future<bool> insertProcessedMedia(
    AlbumMedia media, {
    Future<ImageSize?> Function(String path)? readSize,
  }) async {
    if (!mounted ||
        media.mediaPath.isEmpty ||
        !_insertedAlbumMediaIds.add(media.id)) {
      return false;
    }
    final isImage = media.mediaType == AlbumMediaType.image;
    // 相册返回视频首帧，图片和视频均用实际预览尺寸维护正文行高与光标。
    final previewPath = isImage ? media.mediaPath : media.videoThumbnailPath;
    final size = previewPath == null || previewPath.isEmpty
        ? null
        : await (readSize ?? ImageSizeReader.read)(previewPath);
    if (size == null || !mounted) {
      _insertedAlbumMediaIds.remove(media.id);
      return false;
    }
    await _insertAttachment(
      RichContentLocalAttachment(
        type: isImage
            ? RichContentAttachmentType.image
            : RichContentAttachmentType.file,
        localPath: media.mediaPath,
        fileName: _fileName(media.mediaPath),
        fileSize: media.fileSize,
        mimeType: isImage
            ? _mimeType(media.fileExtension, image: true)
            : _videoMimeType(media.fileExtension),
        width: size.width,
        height: size.height,
        thumbnailPath: isImage ? null : previewPath,
      ),
    );
    return true;
  }

  /// 选择文件并插入当前正文位置。
  Future<void> pickFiles() async {
    final files = await FilePicker.pickFiles(
      context: context,
      config: FilePickerConfig(maxCount: 9),
    );
    for (final file in files) {
      if (!mounted) return;
      await _insertAttachment(
        RichContentLocalAttachment(
          type: RichContentAttachmentType.file,
          localPath: file.filePath,
          fileName: file.fileName,
          fileSize: file.fileSize,
          mimeType: _mimeType(file.extension),
        ),
      );
    }
  }

  /// 把附件插入当前光标位置，并用稳定块 ID 防止已删除附件被异步结果复活。
  Future<void> _insertAttachment(RichContentLocalAttachment attachment) async {
    final active =
        _activeTextBlock ?? _blocks.whereType<_TextEditorBlock>().last;
    final selection = active.controller.selection.isValid
        ? active.controller.selection
        : TextSelection.collapsed(offset: active.controller.text.length);
    final before = active.controller.text.substring(0, selection.start);
    final after = active.controller.text.substring(selection.end);
    final attachmentBlock = RichContentDraftAttachmentBlock(
      _nextBlockId++,
      attachment: attachment,
      status: widget.attachmentUploader == null
          ? RichContentAttachmentStatus.pending
          : RichContentAttachmentStatus.uploading,
    );
    // 图片和视频共用原子令牌、换行、选区替换和删除；旧文件草稿仍保留独立块。
    if (attachment.isInlineMedia) {
      final token = richContentAttachmentToken(attachmentBlock.id);
      final leadingBreak = before.isEmpty || before.endsWith('\n') ? '' : '\n';
      final inserted = '$leadingBreak$token';
      _inlineMedia[attachmentBlock.id] = attachmentBlock;
      active.controller.value = TextEditingValue(
        text: '$before$inserted$after',
        selection: TextSelection.collapsed(
          offset: before.length + inserted.length,
        ),
      );
      active.focusNode.requestFocus();
    } else {
      final index = _blocks.indexOf(active);
      final trailing = _newTextBlock(after);
      trailing.controller.addListener(_refresh);
      trailing.focusNode.addListener(_refresh);
      active.controller.text = before;
      _setEditorState(() {
        _blocks.insert(index + 1, _AttachmentEditorBlock(attachmentBlock));
        _blocks.insert(index + 2, trailing);
        _activeTextBlockId = trailing.id;
      });
      trailing.focusNode.requestFocus();
    }

    final uploader = widget.attachmentUploader;
    if (uploader == null) return;
    // 上传结果仅按稳定 ID 更新仍存在的元素，用户已删除时不会重新插回。
    try {
      String? thumbnailUrl;
      // 封面也需可被接收端访问；两份资源都成功后才把视频标为可发送。
      if (attachment.isVideo && attachment.thumbnailPath != null) {
        final thumbnail = File(attachment.thumbnailPath!);
        thumbnailUrl = await uploader(RichContentLocalAttachment(
          type: RichContentAttachmentType.image,
          localPath: thumbnail.path,
          fileName: _fileName(thumbnail.path),
          fileSize: thumbnail.lengthSync(),
          mimeType: _mimeType(thumbnail.path.split('.').last, image: true),
          width: attachment.width,
          height: attachment.height,
        ));
        if (!isValidRichContentUrl(thumbnailUrl)) throw StateError('视频封面上传失败');
      }
      final url = await uploader(attachment);
      _finishUpload(
        attachmentBlock.id,
        url,
        isValidRichContentUrl(url)
            ? RichContentAttachmentStatus.uploaded
            : RichContentAttachmentStatus.failed,
        thumbnailUrl: thumbnailUrl,
      );
    } catch (_) {
      _finishUpload(
        attachmentBlock.id,
        null,
        RichContentAttachmentStatus.failed,
      );
    }
  }

  /// 仅更新仍存在的原子媒体或旧附件块，上传结果不能复活已删除的正文。
  void _finishUpload(int id, String? url, RichContentAttachmentStatus status,
      {String? thumbnailUrl}) {
    if (!mounted) return;
    final inlineImage = _inlineMedia[id];
    if (inlineImage != null) {
      _setEditorState(() {
        _inlineMedia[id] = inlineImage.copyWith(
          remoteUrl: url,
          thumbnailUrl: thumbnailUrl,
          status: status,
        );
      });
      return;
    }
    final index = _blocks.indexWhere((block) => block.id == id);
    if (index < 0) return;
    final old = (_blocks[index] as _AttachmentEditorBlock).block;
    _setEditorState(() {
      _blocks[index] = _AttachmentEditorBlock(
        old.copyWith(remoteUrl: url, status: status),
      );
    });
  }

  void _removeAttachment(int id) {
    _setEditorState(() => _blocks.removeWhere((block) => block.id == id));
  }

  /// 显示文字格式工具条。
  void showFormattingToolbar() {
    _setEditorState(() => _showFormatting = true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final panel = Material(
      color: colors.bgColorOperate,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildTitle(colors),
          Expanded(child: _buildBody(colors)),
          if (widget.showToolbar) ...[
            Divider(height: 1, color: colors.strokeColorModule),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: RichContentInputToolbar(
                switcherKey: const Key('rich_content_toolbar_switcher'),
                keyPrefix: 'rich_content_toolbar',
                showFormatting: _showFormatting,
                activeFormats: _activeFormats,
                canSend: canSend,
                emojiTooltip: '插入表情',
                imageTooltip: '插入图片/视频',
                fileTooltip: '插入文件',
                sendTooltip: '发送富文本消息',
                onEmoji: insertEmoji,
                onMention: insertMention,
                onVideo: null,
                onImage: pickAlbumMedia,
                // 展开编辑器不提供文件插入，保留按钮位置并使用统一禁用样式。
                onFile: null,
                onShowFormatting: showFormattingToolbar,
                onCloseFormatting: closeFormattingToolbar,
                onToggleFormat: toggleFormat,
                onSend: send,
              ),
            ),
          ],
        ],
      ),
    );
    final editor = widget.showToolbar
        ? panel
        : TweenAnimationBuilder<double>(
            key: const Key('rich_content_editor_entrance'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            builder: (context, progress, child) {
              // 遮罩覆盖工具条上方全部区域，面板从下边界进入，确保共享工具条始终露出。
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    key: const Key('rich_content_editor_backdrop'),
                    child: Opacity(
                      key: const Key('rich_content_editor_backdrop_opacity'),
                      opacity: progress,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {},
                        child: ColoredBox(color: colors.bgColorMask),
                      ),
                    ),
                  ),
                  Positioned(
                    key: const Key('rich_content_editor_panel_position'),
                    top: 57,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: FractionalTranslation(
                      translation: Offset(0, 1 - progress),
                      child: child,
                    ),
                  ),
                ],
              );
            },
            child: panel,
          );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: widget.showToolbar
          ? Padding(
              padding: EdgeInsets.only(bottom: keyboardInset),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height - keyboardInset - 57,
                child: editor,
              ),
            )
          : editor,
    );
  }

  Widget _buildTitle(SemanticColorScheme colors) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              identifier: 'tim.rich.title',
              child: TextField(
                key: const Key('rich_content_title'),
                controller: _titleController,
                maxLines: 1,
                style: TextStyle(
                  color: colors.textColorPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: '无标题',
                  hintStyle: TextStyle(color: colors.textColorTertiary),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '收起富文本编辑器',
            onPressed: _close,
            icon: Icon(AppIcons.narrow, color: colors.textColorPrimary),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildBody(SemanticColorScheme colors) {
    return ListView.builder(
      key: const Key('rich_content_body'),
      padding: const EdgeInsets.fromLTRB(
        16,
        _editorBodyTopPadding,
        16,
        _editorBodyBottomPadding,
      ),
      itemCount: _blocks.length,
      itemBuilder: (context, index) {
        final block = _blocks[index];
        return switch (block) {
          _TextEditorBlock block => LayoutBuilder(
              builder: (context, constraints) {
                final style = TextStyle(
                  color: colors.textColorPrimary,
                  fontSize: 16,
                );
                final maxImageWidth = constraints.maxWidth / 2;
                final defaultMinLines =
                    _blocks.length == 1 && index == 0 ? 5 : 1;
                return Semantics(
                  identifier: 'tim.rich.text.${block.id}',
                  child: ExtendedTextField(
                    key: Key('rich_content_text_${block.id}'),
                    controller: block.controller,
                    focusNode: block.focusNode,
                    inputFormatters: [_formatInputFormatter],
                    onTap: () => _activateTextBlock(block),
                    keyboardType: TextInputType.multiline,
                    minLines: defaultMinLines,
                    maxLines: null,
                    style: style,
                    // 图片需要参与真实行高，固定 strut 会把图片绘制到上一行之上。
                    strutStyle: StrutStyle.disabled,
                    cursorHeight: richContentAttachmentCursorHeight(
                      context: context,
                      controller: block.controller,
                      attachments: _inlineMedia,
                      maxImageWidth: maxImageWidth,
                      textStyle: style,
                    ),
                    // 正文只由外层列表滚动，避免图片撑高后内外滚动手势互相抢占。
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    decoration: InputDecoration(
                      hintText:
                          index == 0 ? '发送给 ${widget.conversationName}' : null,
                      hintStyle: TextStyle(color: colors.textColorTertiary),
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                    specialTextSpanBuilder: RichContentAttachmentSpanBuilder(
                      videoPlayIcon: widget.videoPlayIcon,
                      attachments: _inlineMedia,
                      maxImageWidth: maxImageWidth,
                      onTapUrl: (_) {},
                      colorScheme: colors,
                      mapMarkdownMarkers: true,
                    ),
                  ),
                );
              },
            ),
          _AttachmentEditorBlock block => _buildAttachment(block.block, colors),
        };
      },
    );
  }

  /// 展示旧文件草稿的名称和上传状态，图片和视频统一由行内预览处理。
  Widget _buildAttachment(
    RichContentDraftAttachmentBlock block,
    SemanticColorScheme colors,
  ) {
    final attachment = block.attachment;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Stack(
        children: [
          // 旧文件保留附件卡片，图片和视频不进入此布局。
          Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.bgColorInput,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.insert_drive_file,
                  color: colors.textColorSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    attachment.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textColorPrimary),
                  ),
                ),
              ],
            ),
          ),
          // 删除按稳定块ID操作，迟到的上传结果找不到旧块时直接丢弃。
          Positioned(
            top: 0,
            right: 0,
            child: Semantics(
              identifier: 'tim.rich.remove_attachment.${block.id}',
              child: IconButton(
                tooltip: '删除附件',
                onPressed: () => _removeAttachment(block.id),
                icon: Icon(Icons.close, color: colors.textColorSecondary),
              ),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: Text(
              _uploadStatusText(block.status),
              style: TextStyle(fontSize: 12, color: colors.textColorSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

sealed class _EditorBlock {
  final int id;
  const _EditorBlock(this.id);
}

/// 保存正文块的输入与光标状态，由编辑器统一注册监听并释放资源。
final class _TextEditorBlock extends _EditorBlock {
  /// 当前块的原文及选区，偏移包含隐藏的格式标签。
  final TextEditingController controller;

  /// 当前块的输入焦点，用于切换共享工具条所对应的正文。
  final FocusNode focusNode;

  /// 上次原文与选区，用于区分光标移动和文字提交，并保护工具条的主动格式切换。
  TextEditingValue lastValue;
  _TextEditorBlock(super.id, this.controller, this.focusNode)
      : lastValue = controller.value;
}

final class _AttachmentEditorBlock extends _EditorBlock {
  final RichContentDraftAttachmentBlock block;
  _AttachmentEditorBlock(this.block) : super(block.id);
}

/// 把附件令牌渲染为可由 ExtendedTextField 整体选择和删除的元素。
final class RichContentAttachmentSpanBuilder
    extends ChatSpecialTextSpanBuilder {
  /// 视频封面中央的原色播放图标；为空时沿用字体图标。
  final ImageProvider? videoPlayIcon;

  /// 按稳定 ID 索引的附件草稿块。
  final Map<int, RichContentDraftAttachmentBlock> attachments;

  /// 图片及视频封面在当前输入区可使用的最大宽度。
  final double maxImageWidth;

  RichContentAttachmentSpanBuilder({
    this.videoPlayIcon,
    required this.attachments,
    required this.maxImageWidth,
    required super.onTapUrl,
    required super.colorScheme,
    required super.mapMarkdownMarkers,
  });

  @override
  SpecialText? createSpecialText(
    String flag, {
    TextStyle? textStyle,
    SpecialTextGestureTapCallback? onTap,
    int? index,
  }) {
    if (isStart(flag, richContentAttachmentTokenStart)) {
      return _EditorAttachmentText(
        videoPlayIcon: videoPlayIcon,
        attachments: attachments,
        maxImageWidth: maxImageWidth,
        start: index!,
        textStyle: textStyle,
      );
    }
    return super.createSpecialText(
      flag,
      textStyle: textStyle,
      onTap: onTap,
      index: index,
    );
  }
}

/// 将附件令牌转换成单个可编辑元素，actualText 保持控制器偏移可逆。
final class _EditorAttachmentText extends SpecialText {
  /// 从宿主配置透传的播放图标，不随文本颜色变化。
  final ImageProvider? videoPlayIcon;
  final Map<int, RichContentDraftAttachmentBlock> attachments;
  final double maxImageWidth;

  final int start;

  _EditorAttachmentText({
    this.videoPlayIcon,
    required this.attachments,
    required this.maxImageWidth,
    required this.start,
    required TextStyle? textStyle,
  }) : super(
          richContentAttachmentTokenStart,
          richContentAttachmentTokenEnd,
          textStyle,
        );

  @override
  InlineSpan finishText() {
    final id = int.tryParse(getContent());
    final block = id == null ? null : attachments[id];
    if (block == null) return TextSpan(text: toString(), style: textStyle);
    final attachment = block.attachment;
    if (!attachment.isInlineMedia) {
      return SpecialTextSpan(
        text: attachment.fileName,
        actualText: toString(),
        start: start,
        deleteAll: true,
        style: textStyle,
      );
    }
    final size = richContentEditorImageSize(
      attachment,
      maxImageWidth,
    );
    if (attachment.isVideo) {
      final path = attachment.thumbnailPath;
      final ImageProvider? image = path != null && path.isNotEmpty
          ? FileImage(File(path))
          : block.thumbnailUrl != null
              ? NetworkImage(block.thumbnailUrl!)
              : null;
      return ExtendedWidgetSpan(
        actualText: toString(),
        start: start,
        deleteAll: true,
        alignment: PlaceholderAlignment.bottom,
        child: Padding(
          key: Key('rich_content_inline_video_$id'),
          padding:
              const EdgeInsets.symmetric(vertical: _editorImageVerticalMargin),
          child: RichContentVideoPreview(
              image: image, size: size, playIcon: videoPlayIcon),
        ),
      );
    }
    return ImageSpan(
      attachment.localPath.isNotEmpty || block.remoteUrl == null
          ? FileImage(File(attachment.localPath))
          : NetworkImage(block.remoteUrl!),
      key: Key('rich_content_inline_image_$id'),
      imageWidth: size.width,
      imageHeight: size.height,
      actualText: toString(),
      start: start,
      alignment: PlaceholderAlignment.bottom,
      fit: BoxFit.cover,
      margin: const EdgeInsets.symmetric(vertical: _editorImageVerticalMargin),
    );
  }
}

/// 按图片或视频封面的比例计算编辑尺寸，只限制宽度以免随编辑器高度变化。
Size richContentEditorImageSize(
  RichContentLocalAttachment attachment,
  double maxWidth,
) {
  final sourceWidth = attachment.width ?? 0;
  final sourceHeight = attachment.height ?? 0;
  if (sourceWidth <= 0 || sourceHeight <= 0) {
    return Size.square(maxWidth);
  }
  var scale = 1.0;
  if (sourceWidth * scale > maxWidth) scale = maxWidth / sourceWidth;
  return Size(sourceWidth * scale, sourceHeight * scale);
}

String _fileName(String path) => path.split(Platform.pathSeparator).last;

/// 视频媒体类型已由相册确认，扩展名只决定 MIME 子类型，不改变附件业务类型。
String _videoMimeType(String extension) =>
    switch (extension.toLowerCase().replaceFirst('.', '')) {
      'mov' => 'video/quicktime',
      'm4v' => 'video/x-m4v',
      'avi' => 'video/x-msvideo',
      'mkv' => 'video/x-matroska',
      '3gp' => 'video/3gpp',
      '' => 'video/*',
      final value => 'video/$value',
    };

String _mimeType(String extension, {bool image = false}) {
  final normalized = extension.toLowerCase().replaceFirst('.', '');
  if (image) return 'image/${normalized == 'jpg' ? 'jpeg' : normalized}';
  return switch (normalized) {
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _ => 'application/octet-stream',
  };
}

String _uploadStatusText(RichContentAttachmentStatus status) {
  return switch (status) {
    RichContentAttachmentStatus.pending => '等待上传',
    RichContentAttachmentStatus.uploading => '上传中',
    RichContentAttachmentStatus.uploaded => '已上传',
    RichContentAttachmentStatus.failed => '上传失败',
  };
}
