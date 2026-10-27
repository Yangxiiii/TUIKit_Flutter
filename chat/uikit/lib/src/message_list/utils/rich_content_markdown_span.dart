import 'package:app_ui/app_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import '../../conversation_list/conversation_preview.dart';
import '../../emoji_picker/emoji_manager.dart';

/// 编辑器、聊天和列表共用的格式叠加规则，保留父级样式及全部文字装饰。
TextStyle richContentMarkdownStyle(TextStyle base, Iterable<String> markers) {
  final decorations = [
    if (base.decoration != null) base.decoration!,
    if (markers.contains('~~')) TextDecoration.lineThrough,
    if (markers.contains('~')) TextDecoration.underline,
  ];
  return base.copyWith(
    fontWeight: markers.contains('**') ? FontWeight.bold : null,
    fontStyle: markers.contains('*') ? FontStyle.italic : null,
    decoration:
        decorations.isEmpty ? null : TextDecoration.combine(decorations),
  );
}

/// 两处展示共用的行内样式转换；compact 仅压缩块布局、替换媒体和本地化摘要表情。
/// 链接识别器由聊天组件创建并释放，列表不传入以保留整行点击行为。
TextSpan richContentMarkdownSpan(
  BuildContext context,
  md.Node node,
  TextStyle style, {
  bool compact = false,
  GestureRecognizer? Function(String? href)? linkRecognizer,
  GestureRecognizer? inheritedRecognizer,
}) {
  if (node is! md.Element) {
    final text = compact
        ? EmojiManager.createLocalizedStringFromEmojiCodes(
            context, singleLineConversationPreview(node.textContent))
        : node.textContent;
    return TextSpan(text: text, style: style, recognizer: inheritedRecognizer);
  }
  if (node.tag == 'img') {
    return TextSpan(
        text: compact
            ? AppLocalization.of(context).messageTypeImage
            : node.attributes['alt'] ?? '',
        style: style);
  }
  if (node.tag == 'br') return TextSpan(text: compact ? ' ' : '\n');

  // 递归叠加样式，装饰必须合并，不能用父节点的纯文字替换已经解析的子节点。
  final nodeStyle = switch (node.tag) {
    'strong' ||
    'h1' ||
    'h2' ||
    'h3' ||
    'h4' ||
    'h5' ||
    'h6' =>
      richContentMarkdownStyle(style, const ['**']),
    'em' => richContentMarkdownStyle(style, const ['*']),
    'a' || 'u' => richContentMarkdownStyle(style, const ['~']),
    'del' => richContentMarkdownStyle(style, const ['~~']),
    'code' => style.copyWith(fontFamily: 'monospace'),
    _ => style,
  };
  final recognizer = node.tag == 'a'
      ? linkRecognizer?.call(node.attributes['href'])
      : inheritedRecognizer;
  final children = node.children ?? const <md.Node>[];
  final isList = node.tag == 'ul' || node.tag == 'ol';
  final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
  final separator = switch (node.tag) {
    'ul' ||
    'ol' ||
    'li' ||
    'blockquote' ||
    'table' ||
    'thead' ||
    'tbody' ||
    'tr' =>
      compact ? ' ' : '\n',
    _ => '',
  };

  // 列表保留条目顺序及引用标识；聊天窗口的块级排版仍由 MarkdownBody 处理。
  return TextSpan(style: nodeStyle, children: [
    if (compact && node.tag == 'blockquote') const TextSpan(text: '▎ '),
    for (final (index, child) in children.indexed) ...[
      if (index > 0 && separator.isNotEmpty) TextSpan(text: separator),
      if (compact && isList)
        TextSpan(text: node.tag == 'ul' ? '• ' : '${start + index}. '),
      richContentMarkdownSpan(context, child, nodeStyle,
          compact: compact,
          linkRecognizer: linkRecognizer,
          inheritedRecognizer: recognizer),
    ],
  ]);
}
