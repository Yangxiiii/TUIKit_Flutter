import '../../../emoji_picker/emoji_manager.dart';
import '../../../message_input/mention/mention_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../utils/rich_content_markdown_parser.dart';
import '../../utils/rich_content_markdown_span.dart';
import 'chat_mention_span.dart';

/// 在聊天气泡的文字块中展示 Markdown，不创建独立滚动区域。
class RichContentMarkdown extends StatelessWidget {
  /// 原始 Markdown 文本，由富文本消息的文字块提供。
  final String data;

  /// 继承当前气泡的字号与前景色。
  final TextStyle textStyle;

  /// 已按当前块原文验证的提及定位。
  final List<MentionInfo> mentions;

  /// 仅接收端群聊传入当前账号，用于标出匹配该账号的个人提及。
  final String? highlightedMentionUserId;

  /// 成员点击交还宿主复核权限。
  final void Function(BuildContext, String)? onMentionTap;

  /// 按已校验的提及成员 ID 生成行内回执，普通 Markdown 无需提供。
  final Widget? Function(String)? buildMentionReceipt;

  const RichContentMarkdown({
    super.key,
    required this.data,
    required this.textStyle,
    this.mentions = const [],
    this.highlightedMentionUserId,
    this.onMentionTap,
    this.buildMentionReceipt,
  });

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
    // 仅在 Markdown 的展示副本置入无语法标记的令牌；原文与消息位置始终保留。
    var prefix = '\uE510';
    while (data.contains(prefix)) {
      prefix += '\uE512';
    }
    final mentionsByToken = <String, MentionInfo>{};
    var display = data;
    for (final (index, mention) in mentions.indexed.toList().reversed) {
      final token = '$prefix$index\uE511';
      mentionsByToken[token] = mention;
      display =
          display.replaceRange(mention.startIndex, mention.endIndex - 1, token);
    }
    final inlineBuilder = _InlineFormatBuilder(
      textStyle,
      mentionsByToken,
      highlightedMentionUserId,
      onMentionTap,
      buildMentionReceipt,
    );
    final hasEmoji = EmojiManager.tokenPattern.hasMatch(display);
    // 富文本保留消息原始字号，仅跟随平台无障碍缩放，不叠加宿主的普通文字档位。
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQueryData.fromView(View.of(context)).textScaler,
      ),
      child: MarkdownBody(
        // 正文相同时 Markdown 会复用行内节点。接收者变化时重新生成提及样式。
        key:
            mentionsByToken.isEmpty ? null : ValueKey(highlightedMentionUserId),
        data: display,
        styleSheet: style,
        softLineBreak: true,
        extensionSet: richContentMarkdownExtensionSet,
        inlineSyntaxes: [
          if (mentionsByToken.isNotEmpty) _MentionSyntax(prefix),
          if (hasEmoji) _EmojiSyntax(),
        ],
        // 与会话列表共用行内样式转换，块级排版继续使用 MarkdownBody。
        builders: {
          for (final tag in ['strong', 'em', 'u', 'del', 'a', 'code'])
            if (tag != 'code' || mentionsByToken.isNotEmpty) tag: inlineBuilder,
          if (mentionsByToken.isNotEmpty) 'zd-mention': inlineBuilder,
          if (hasEmoji) _EmojiSyntax.tag: inlineBuilder,
        },
        // 消息文字中的 Markdown 图片不是附件块，不允许借此读取本地资源。
        imageBuilder: (uri, title, alt) => Text(alt ?? '', style: textStyle),
      ),
    );
  }
}

/// 把已注册表情交给行内渲染器，普通段落也能和加粗等格式共用表情展示。
final class _EmojiSyntax extends md.InlineSyntax {
  // 方括号后紧跟链接地址时，保留 Markdown 对链接标签的解释。
  _EmojiSyntax()
      : super('(?:${EmojiManager.tokenPattern.pattern})(?!\\()',
            startCharacter: 0x5b);

  /// 仅供气泡展示用的节点，原始消息正文及表情编码不变。
  static const tag = 'zd-emoji';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(tag, match[0]!));
    return true;
  }
}

/// 仅识别当前展示副本注入的令牌，避免手打姓名成为链接。
final class _MentionSyntax extends md.InlineSyntax {
  _MentionSyntax(String prefix) : super('${RegExp.escape(prefix)}[0-9]+\uE511');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('zd-mention', match[0]!));
    return true;
  }
}

/// 将聊天窗口的行内节点交给共用样式转换，保留 MarkdownBody 提供的段落上下文。
class _InlineFormatBuilder extends MarkdownElementBuilder {
  _InlineFormatBuilder(
      this.baseStyle,
      this.mentions,
      this.highlightedMentionUserId,
      this.onMentionTap,
      this.buildMentionReceipt);

  /// 当前文字块从展示令牌到已校验身份的映射。
  final Map<String, MentionInfo> mentions;

  /// 当前接收者 ID。段落拆分或嵌套格式不会改变提及对象。
  final String? highlightedMentionUserId;

  /// 仅用户提及会触发宿主名片入口。
  final void Function(BuildContext, String)? onMentionTap;

  /// 提及正文和回执共享同一份令牌定位。
  final Widget? Function(String)? buildMentionReceipt;

  /// 段落未提供父级样式时沿用聊天正文样式。
  final TextStyle baseStyle;

  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element,
          TextStyle? preferredStyle, TextStyle? parentStyle) =>
      _InlineFormattedText(
        element: element,
        style: parentStyle ?? baseStyle,
        mentions: mentions,
        highlightedMentionUserId: highlightedMentionUserId,
        onMentionTap: onMentionTap,
        buildMentionReceipt: buildMentionReceipt,
      );
}

/// 渲染共享的行内样式，并负责聊天链接识别器的创建与释放。
class _InlineFormattedText extends StatefulWidget {
  const _InlineFormattedText({
    required this.element,
    required this.style,
    required this.mentions,
    required this.highlightedMentionUserId,
    required this.onMentionTap,
    required this.buildMentionReceipt,
  });

  /// 当前消息块中的定位令牌及成员 ID。
  final Map<String, MentionInfo> mentions;

  /// 当前接收者 ID，按令牌绑定的成员身份匹配。
  final String? highlightedMentionUserId;

  /// 宿主按真实成员 ID 处理点击。
  final void Function(BuildContext, String)? onMentionTap;

  /// 为个人提及附加回执，不参与 Markdown 源文本解析。
  final Widget? Function(String)? buildMentionReceipt;

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
      mentionSpan: widget.mentions.isEmpty ? null : _mentionSpan,
    ));
  }

  /// 将当前节点内的令牌恢复成原名；提及点击优先于父链接。
  TextSpan? _mentionSpan(
      String text, TextStyle style, GestureRecognizer? inherited) {
    final pattern = RegExp(widget.mentions.keys.map(RegExp.escape).join('|'));
    if (!pattern.hasMatch(text)) return null;
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in pattern.allMatches(text)) {
      if (offset < match.start) {
        spans.add(_ordinarySpan(
            text.substring(offset, match.start), style, inherited));
      }
      final mention = widget.mentions[match[0]!]!;
      final open = widget.onMentionTap;
      final tap = !mention.isAtAll && open != null
          ? (TapGestureRecognizer()
            ..onTap = () => open(context, mention.userID))
          : null;
      if (tap != null) _linkRecognizers.add(tap);
      spans.add(buildChatMentionSpan(
        context,
        mention,
        style: style,
        highlightedUserId: widget.highlightedMentionUserId,
        recognizer: tap,
      ));
      // 无论提及处于何种嵌套格式，全体提及都没有个人回执。
      final receipt = mention.isAtAll
          ? null
          : widget.buildMentionReceipt?.call(mention.userID);
      if (receipt != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: receipt,
        ));
      }
      offset = match.end;
    }
    if (offset < text.length) {
      spans.add(_ordinarySpan(text.substring(offset), style, inherited));
    }
    return TextSpan(style: style, children: spans);
  }

  /// 与其余富文本节点使用相同的业务表情资源和父链接。
  TextSpan _ordinarySpan(
          String text, TextStyle style, GestureRecognizer? tap) =>
      EmojiManager.tokenPattern.hasMatch(text)
          ? TextSpan(
              children: EmojiManager.buildInlineSpans(text,
                  size: style.fontSize ?? 16),
              recognizer: tap)
          : TextSpan(text: text, recognizer: tap);

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
