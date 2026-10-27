import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

import 'rich_content_markdown_format.dart';

/// 三处展示共用编辑器格式规则；Markdown 扩展只补充分块、代码、链接等排版。
final richContentMarkdownExtensionSet = md.ExtensionSet([
  _RichContentNestedTildeBlockSyntax(),
  ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
], [
  _RichContentEditorFormatSyntax(),
  _RichContentUnderlineSyntax(),
  ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
]);

/// 按聊天气泡的 Markdown 语法提取可见文字，供单行摘要使用。
String richContentMarkdownPlainText(String source) {
  return parseRichContentMarkdown(source)
      .map(_nodePlainText)
      .where((text) => text.isNotEmpty)
      .join('\n')
      .trim();
}

/// 使用与聊天气泡一致的语法解析节点，供摘要保留文字及行内样式。
List<md.Node> parseRichContentMarkdown(String source) {
  // 与 MarkdownBody 共用扩展和下划线语法；保留转义字符及代码中的字面标记。
  final document = md.Document(
    extensionSet: richContentMarkdownExtensionSet,
    encodeHtml: false,
  );
  return document.parseLines(const LineSplitter().convert(source));
}

/// 将同一行完整闭合的三波浪号组合按正文解析，避免与多行代码围栏混淆。
class _RichContentNestedTildeBlockSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^ {0,3}~~~(?!~)\S.*(?<!~)~~~[ \t]*$');

  @override
  bool canParse(md.BlockParser parser) {
    if (!super.canParse(parser)) return false;
    final source = parser.current.content.trim();
    final format = parseRichContentMarkdownFormatAt(source, 0);
    return format != null && format.closeEnd == source.length;
  }

  @override
  md.Node? parse(md.BlockParser parser) {
    // 编辑器叠加单、双波浪号会得到三波浪号；未在同一行闭合的代码围栏不命中此规则。
    return const md.ParagraphSyntax().parse(parser);
  }
}

/// 去除节点的排版信息，保留链接文字、图片替代文字及块之间的分隔。
String _nodePlainText(md.Node node) {
  if (node is! md.Element) return node.textContent;
  if (node.tag == 'img') return node.attributes['alt'] ?? '';
  if (node.tag == 'br') return '\n';

  // 列表、引用和表格的子块必须分隔，行内加粗等节点则不能插入额外空格。
  final separator = switch (node.tag) {
    'ul' ||
    'ol' ||
    'li' ||
    'blockquote' ||
    'table' ||
    'thead' ||
    'tbody' ||
    'tr' =>
      '\n',
    _ => '',
  };
  return node.children?.map(_nodePlainText).join(separator) ?? '';
}

/// 使用 Markdown 的成对分隔符处理嵌套，单波浪号为下划线、双波浪号为删除线。
class _RichContentUnderlineSyntax extends md.DelimiterSyntax {
  _RichContentUnderlineSyntax()
      : super('~+',
            requiresDelimiterRun: true,
            allowIntraWord: true,
            startCharacter: 0x7e,
            tags: [md.DelimiterTag('u', 1), md.DelimiterTag('del', 2)]);
}

/// 把编辑器识别的格式片段转换为 Markdown 节点，不再单独推测紧邻标签的配对方式。
class _RichContentEditorFormatSyntax extends md.InlineSyntax {
  _RichContentEditorFormatSyntax() : super(r'[*~]');

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final start = startMatchPos ?? parser.pos;
    if (parseRichContentMarkdownFormatAt(parser.source, start) == null) {
      return false;
    }
    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final format =
        parseRichContentMarkdownFormatAt(parser.source, match.start)!;
    // 仅递归解析正文，格式范围和闭合边界使用编辑器已经确认的同一结果。
    var children = md.InlineParser(
      parser.source.substring(format.contentStart, format.contentEnd),
      parser.document,
    ).parse();
    for (final marker in format.markers.reversed) {
      final tag = switch (marker) {
        '**' => 'strong',
        '~~' => 'del',
        '*' => 'em',
        _ => 'u',
      };
      children = [md.Element(tag, children)];
    }
    parser.addNode(children.single);
    // 当前匹配只探测一个起始字符，必须一次消费整个格式片段，不能再由基类重复前进。
    parser.consume(format.closeEnd - parser.pos);
    return false;
  }
}
