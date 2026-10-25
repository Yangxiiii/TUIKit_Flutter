import 'dart:ui';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart'
    show SemanticColorScheme;
import '../../emoji_picker/emoji_picker.dart';
import '../../third_party/extended_text_field/extended_text_field.dart';
import '../src/chat_special_text_span_builder.dart';

/// 编辑原文本消息的独立输入区；普通草稿保持挂载，取消及失败不会清空草稿。
class MessageEditComposer extends StatefulWidget {
  const MessageEditComposer(
      {super.key,
      required this.text,
      required this.onCancel,
      required this.onSave,
      required this.onBounds});

  /// SDK查询取得的最新原文，仅在本次编辑开始时回填。
  final String text;

  /// 取消后由聊天页恢复普通输入模式，不调用SDK。
  final VoidCallback onCancel;

  /// 返回null表示保存成功；失败文案交给页面提示，当前输入继续保留。
  final Future<String?> Function(String text) onSave;

  /// 整个编辑区域的实测边界，包含展开或表情面板时增加的高度。
  final ValueChanged<Rect> onBounds;

  @override
  State<MessageEditComposer> createState() => _MessageEditComposerState();
}

/// 管理本次编辑的输入连接与可见面板，保存忙碌态仅限制当前组件的提交交互。
class _MessageEditComposerState extends State<MessageEditComposer> {
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode();
  final GlobalKey _bounds = GlobalKey();
  bool _saving = false;
  bool _emojis = false;
  bool _expanded = false;
  bool _formats = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.text)
      ..selection = TextSelection.collapsed(offset: widget.text.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 插入普通文本或TUIKit表情令牌，保持选区和正文偏移一致。
  void _insert(String value) {
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : start;
    _text.value = TextEditingValue(
      text: _text.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    setState(() {});
  }

  /// 忙碌态只限制当前编辑器交互，真正的重复请求合并由宿主统一保存入口负责。
  Future<void> _save() async {
    if (_saving || _text.text.trim().isEmpty || _text.text == widget.text) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(_text.text);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// 为编辑工具、取消和确认提供稳定语义标识，禁用态不触发业务回调。
  Widget _button(String id, IconData icon, VoidCallback? action,
      {bool filled = false,
      bool cancel = false,
      double width = 50,
      double height = 32}) {
    final colors = context.appColors;
    return Semantics(
        identifier: 'tim.message.$id',
        button: true,
        enabled: action != null,
        child: SizedBox(
            width: filled || cancel ? 40 : width,
            height: height,
            child: Material(
                color: filled
                    ? colors.primary
                    : cancel
                        ? colors.outline
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                    onTap: action,
                    borderRadius: BorderRadius.circular(8),
                    child: Center(
                        child: Icon(icon,
                            size: 24,
                            color: filled
                                ? colors.onPrimary
                                : cancel
                                    ? colors.textSecondary
                                    : colors.textPrimary))))));
  }

  /// 输入行独立测量换行高度，展开仅改变本次编辑视图。
  Widget _buildInputRow() {
    final colors = context.appColors;
    return Padding(
        padding: const EdgeInsets.all(8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _button('editVoice', AppIcons.voice1, null, width: 40, height: 44),
          // 展开入口覆盖输入区右上角，正文右侧预留空间，避免文字被遮挡。
          Expanded(
              child: Stack(children: [
            Semantics(
                identifier: 'tim.message.editInput',
                child: ExtendedTextField(
                  controller: _text,
                  focusNode: _focus,
                  readOnly: _saving,
                  minLines: _expanded ? 6 : 1,
                  maxLines: _expanded ? 10 : 6,
                  style: TextStyle(
                      fontSize: 16, height: 1.5, color: colors.textPrimary),
                  specialTextSpanBuilder: ChatSpecialTextSpanBuilder(
                      onTapUrl: (_) {},
                      colorScheme: SemanticColorScheme.of(context)),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      filled: true,
                      isDense: true,
                      fillColor: colors.surface,
                      contentPadding: const EdgeInsets.fromLTRB(12, 10, 40, 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none)),
                )),
            Positioned(
              top: 8,
              right: 8,
              child: Semantics(
                  identifier: 'tim.message.editExpand',
                  button: true,
                  child: GestureDetector(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                              _expanded ? AppIcons.narrow : AppIcons.expand,
                              size: 20,
                              color: colors.textSecondary)))),
            ),
          ])),
        ]));
  }

  /// 工具栏保持普通发送入口隐藏，取消与确认固定在右侧。
  Widget _buildToolbar(bool canSave) => SizedBox(
      height: 44,
      child: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Row(children: [
            _button(
                'editEmoji',
                AppIcons.emoji,
                _saving
                    ? null
                    : () {
                        setState(() => _emojis = !_emojis);
                        if (_emojis) {
                          _focus.unfocus();
                        } else {
                          _focus.requestFocus();
                        }
                      }),
            _button(
                'editMention', AppIcons.a, _saving ? null : () => _insert('@')),
            _button('editFormat', AppIcons.format,
                _saving ? null : () => setState(() => _formats = !_formats)),
            const Spacer(),
            _button('editCancel', AppIcons.close, widget.onCancel,
                cancel: true),
            const SizedBox(width: 12),
            _button('editSave', AppIcons.check, canSave ? _save : null,
                filled: true),
          ])));

  @override
  Widget build(BuildContext context) {
    // 键盘、表情和展开高度均以布局后的屏幕边界通知列表，不能用固定高度猜测。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final box = _bounds.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        widget.onBounds(box.localToGlobal(Offset.zero) & box.size);
      }
    });
    final colors = context.appColors;
    final canSave =
        !_saving && _text.text.trim().isNotEmpty && _text.text != widget.text;
    return ClipRect(
        child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Material(
                key: _bounds,
                color: colors.chatInputBackground.withValues(alpha: 0.85),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _buildInputRow(),
                  _buildToolbar(canSave),
                  // 格式与表情只展开当前编辑视图，不改动普通输入区的面板状态。
                  if (_formats)
                    SizedBox(
                        height: 44,
                        child: Row(children: [
                          _button(
                              'editBold', AppIcons.bold, () => _insert('**')),
                          _button(
                              'editItalic', AppIcons.tilt, () => _insert('*')),
                          _button('editStrike', AppIcons.strikethrough,
                              () => _insert('~~')),
                        ])),
                  if (_emojis)
                    SizedBox(
                        height: 280,
                        child: EmojiPicker(onEmojiClick: (data) {
                          final value = data['name'];
                          if (value is String) {
                            _insert(value);
                          }
                        })),
                ]))));
  }
}
