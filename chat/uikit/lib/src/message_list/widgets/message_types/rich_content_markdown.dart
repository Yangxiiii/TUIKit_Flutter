import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// 在聊天气泡的文字块中展示 Markdown，不创建独立滚动区域。
class RichContentMarkdown extends StatelessWidget {
  /// 原始 Markdown 文本，由富文本消息的文字块提供。
  final String data;

  /// 继承当前气泡的字号与前景色。
  final TextStyle textStyle;

  const RichContentMarkdown(
      {super.key, required this.data, required this.textStyle});

  @override
  Widget build(BuildContext context) {
    final style = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: textStyle,
      pPadding: EdgeInsets.zero,
      blockquote: textStyle,
      code: textStyle.copyWith(fontFamily: 'monospace'),
      a: textStyle.copyWith(decoration: TextDecoration.underline),
      blockSpacing: 4,
    );
    return MarkdownBody(
      data: data,
      styleSheet: style,
      softLineBreak: true,
      inlineSyntaxes: [_UnderlineSyntax()],
      builders: {'u': _UnderlineBuilder()},
      // 消息文字中的 Markdown 图片不是附件块，不允许借此读取本地资源。
      imageBuilder: (uri, title, alt) => Text(alt ?? '', style: textStyle),
      onTapLink: (_, href, __) {
        // 链接来自聊天消息，只允许打开无账号信息的网页地址。
        final uri = href == null ? null : Uri.tryParse(href);
        if (uri != null &&
            (uri.scheme == 'http' || uri.scheme == 'https') &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty) {
          launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }
}

/// 将单波浪号解析为下划线；双波浪号仍交给标准删除线语法处理。
class _UnderlineSyntax extends md.InlineSyntax {
  _UnderlineSyntax()
      : super(r'(?<!~)~(?!~)([^~\n]+)(?<!~)~(?!~)', startCharacter: 0x7e);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('u', match[1]!));
    return true;
  }
}

/// 将自定义下划线节点渲染成沿用气泡文字样式的行内文字。
class _UnderlineBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Text(
      element.textContent,
      style: parentStyle?.copyWith(decoration: TextDecoration.underline),
    );
  }
}
