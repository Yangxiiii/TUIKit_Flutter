import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../utils/rich_content_markdown_parser.dart';
import '../../utils/rich_content_markdown_span.dart';

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
      // 代码块保留背景与排版，字体与消息正文一致。
      code: textStyle,
      a: textStyle.copyWith(decoration: TextDecoration.underline),
      blockSpacing: 4,
    );
    final inlineBuilder = _InlineFormatBuilder(textStyle);
    return MarkdownBody(
      data: data,
      styleSheet: style,
      softLineBreak: true,
      extensionSet: richContentMarkdownExtensionSet,
      // 与会话列表共用行内样式转换，块级排版继续使用 MarkdownBody。
      builders: {
        for (final tag in ['strong', 'em', 'u', 'del', 'a']) tag: inlineBuilder,
      },
      // 消息文字中的 Markdown 图片不是附件块，不允许借此读取本地资源。
      imageBuilder: (uri, title, alt) => Text(alt ?? '', style: textStyle),
    );
  }
}

/// 将聊天窗口的行内节点交给共用样式转换，保留 MarkdownBody 提供的段落上下文。
class _InlineFormatBuilder extends MarkdownElementBuilder {
  _InlineFormatBuilder(this.baseStyle);

  /// 段落未提供父级样式时沿用聊天正文样式。
  final TextStyle baseStyle;

  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element,
          TextStyle? preferredStyle, TextStyle? parentStyle) =>
      _InlineFormattedText(element: element, style: parentStyle ?? baseStyle);
}

/// 渲染共享的行内样式，并负责聊天链接识别器的创建与释放。
class _InlineFormattedText extends StatefulWidget {
  const _InlineFormattedText({required this.element, required this.style});

  /// MarkdownBody 已解析的完整子树，包含全部嵌套格式及链接地址。
  final md.Element element;

  /// 当前段落继承的文字样式，不缓存主题颜色。
  final TextStyle style;

  @override
  State<_InlineFormattedText> createState() => _InlineFormattedTextState();
}

/// 链接识别器只跟随当前已挂载的文字存活，避免消息重建后遗留手势资源。
class _InlineFormattedTextState extends State<_InlineFormattedText> {
  /// 当前样式树使用的识别器；重建和销毁时释放。
  final _linkRecognizers = <TapGestureRecognizer>[];

  @override
  Widget build(BuildContext context) {
    // 先释放上一棵样式树的识别器，再按当前消息子树重新建立链接。
    _clearLinkRecognizers();
    return Text.rich(richContentMarkdownSpan(
      context,
      widget.element,
      widget.style,
      linkRecognizer: _newLinkRecognizer,
    ));
  }

  /// 只为无账号信息的 HTTP(S) 地址创建聊天点击行为。
  GestureRecognizer? _newLinkRecognizer(String? href) {
    final uri = href == null ? null : Uri.tryParse(href);
    // 地址来自聊天成员，延续原聊天气泡的协议及主机校验边界。
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final recognizer = TapGestureRecognizer()
      ..onTap = () => launchUrl(uri, mode: LaunchMode.externalApplication);
    _linkRecognizers.add(recognizer);
    return recognizer;
  }

  /// 重建前及组件销毁时清理当前持有的手势资源。
  void _clearLinkRecognizers() {
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    _linkRecognizers.clear();
  }

  @override
  void dispose() {
    _clearLinkRecognizers();
    super.dispose();
  }
}
