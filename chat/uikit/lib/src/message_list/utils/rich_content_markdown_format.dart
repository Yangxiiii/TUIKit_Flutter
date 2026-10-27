/// 编辑器写入和读取格式标签时的固定优先级，也是消息展示的格式识别顺序。
const richContentMarkdownFormatOrder = ['**', '~~', '*', '~'];

/// 按原文光标返回显式格式；正文起点不选中、末尾沿用左侧样式，嵌套叠加，忽略代码及链接地址。
Set<String> richContentMarkdownFormatsAt(String text, int offset) {
  if (offset < 0 || offset > text.length) return const {};
  var cursor = 0;
  while (cursor < text.length) {
    // 转义和代码中的字面标记不代表编辑格式，不能点入这些内容后误选工具条。
    if (text[cursor] == '\\') {
      cursor += 2;
      continue;
    }
    if (text[cursor] == '`') {
      final run = RegExp(r'`+').matchAsPrefix(text, cursor)!.group(0)!;
      final end = text.indexOf(run, cursor + run.length);
      cursor = end < 0 ? text.length : end + run.length;
      continue;
    }
    final link = richContentMarkdownPattern.matchAsPrefix(text, cursor);
    final label = link?.group(10);
    if (link != null && label != null) {
      final labelStart = cursor + 1;
      if (offset >= labelStart && offset <= labelStart + label.length) {
        return richContentMarkdownFormatsAt(label, offset - labelStart);
      }
      if (offset == link.end) {
        return richContentMarkdownFormatsAt(label, label.length);
      }
      cursor = link.end;
      continue;
    }
    final format = parseRichContentMarkdownFormatAt(text, cursor);
    if (format == null) {
      cursor++;
      continue;
    }
    // 左开右闭：正文前不继承右侧格式，末尾及隐藏闭合标签后仍沿用左侧样式。
    if (offset > format.contentStart && offset <= format.closeEnd) {
      final innerOffset =
          offset.clamp(format.contentStart, format.contentEnd).toInt() -
              format.contentStart;
      return {
        ...format.markers,
        ...richContentMarkdownFormatsAt(
            text.substring(format.contentStart, format.contentEnd),
            innerOffset),
      };
    }
    cursor = format.closeEnd;
  }
  return const {};
}

/// 编辑器和消息展示共用的单段格式规则；匹配结果保留原文边界。
final richContentMarkdownPattern = RegExp(
  r'(\*\*([^*\n]+)\*\*)|(~~([^~\n]+)~~)|(\*([^*\n]+)\*)|(~([^~\n]+)~)|(\[([^\]\n]+)\]\((https?://[^)\s]+)\))|(```([\s\S]*?)```)',
);

/// 从指定位置识别任意顺序的多层 Markdown 格式标签。
///
/// 打开标签不能重复，关闭标签必须与打开顺序相反，正文不能跨行。
({
  List<String> markers,
  int contentStart,
  int contentEnd,
  int closeEnd,
})? parseNestedMarkdownFormat(String text, int start) {
  // 按编辑器的标记优先级识别连续的打开标签，保证三处得到相同的嵌套边界。
  var contentStart = start;
  final markers = <String>[];
  while (true) {
    String? matched;
    for (final marker in richContentMarkdownFormatOrder) {
      if (!markers.contains(marker) && text.startsWith(marker, contentStart)) {
        matched = marker;
        break;
      }
    }
    if (matched == null) break;
    markers.add(matched);
    contentStart += matched.length;
  }
  if (markers.length < 2) return null;

  // 关闭标签必须逆序且位于同一行，未完成的输入继续作为普通文字保留。
  final closing = markers.reversed.join();
  final contentEnd = text.indexOf(closing, contentStart);
  if (contentEnd <= contentStart ||
      text.substring(contentStart, contentEnd).contains('\n')) {
    return null;
  }
  return (
    markers: List.unmodifiable(markers),
    contentStart: contentStart,
    contentEnd: contentEnd,
    closeEnd: contentEnd + closing.length,
  );
}

/// 移除富文本格式标签，只保留会话摘要需要展示的可见文字。
String richContentMarkdownToPlainText(String text) {
  final output = StringBuffer();
  var offset = 0;
  // 按原始偏移依次消费片段，不改变编辑器计数与光标所依赖的原文。
  while (offset < text.length) {
    final nested = parseRichContentMarkdownFormatAt(text, offset);
    final match = richContentMarkdownPattern.matchAsPrefix(text, offset);
    if (nested != null) {
      output.write(richContentMarkdownToPlainText(
        text.substring(nested.contentStart, nested.contentEnd),
      ));
      offset = nested.closeEnd;
    } else if (match != null) {
      output.write(
        match.group(2) ??
            match.group(4) ??
            match.group(6) ??
            match.group(8) ??
            match.group(10) ??
            match.group(13) ??
            '',
      );
      offset = match.end;
    } else {
      output.writeCharCode(text.codeUnitAt(offset));
      offset++;
    }
  }
  return output.toString();
}

/// 识别编辑器可生成的单层或完整嵌套格式，原文偏移同时供光标映射和消息解析使用。
({List<String> markers, int contentStart, int contentEnd, int closeEnd})?
    parseRichContentMarkdownFormatAt(String text, int start) {
  final nested = parseNestedMarkdownFormat(text, start);
  if (nested != null) return nested;
  // 匹配顺序与编辑器写入顺序一致，紧邻片段只消费第一段。
  final marker = richContentMarkdownFormatOrder
      .where((candidate) => text.startsWith(candidate, start))
      .firstOrNull;
  if (marker == null) return null;
  final contentStart = start + marker.length;
  var cursor = contentStart;
  while (cursor < text.length && text[cursor] != '\n') {
    // 转义字符和代码中的字面标记不能参与外层格式配对。
    if (text[cursor] == '\\') {
      cursor += 2;
      continue;
    }
    if (text[cursor] == '`') {
      final run = RegExp(r'`+').matchAsPrefix(text, cursor)!.group(0)!;
      final end = text.indexOf(run, cursor + run.length);
      if (end >= 0 && !text.substring(cursor, end).contains('\n')) {
        cursor = end + run.length;
        continue;
      }
    }
    final candidate = richContentMarkdownFormatOrder
        .where((value) => text.startsWith(value, cursor))
        .firstOrNull;
    // 不同格式可以嵌在正文中；例如斜体内部的双星号优先识别为加粗，识别失败才关闭斜体。
    if (candidate != null && candidate != marker) {
      final inner = parseRichContentMarkdownFormatAt(text, cursor);
      if (inner != null) {
        cursor = inner.closeEnd;
        continue;
      }
    }
    if (text.startsWith(marker, cursor)) {
      if (cursor == contentStart) return null;
      return (
        markers: List.unmodifiable([marker]),
        contentStart: contentStart,
        contentEnd: cursor,
        closeEnd: cursor + marker.length,
      );
    }
    cursor++;
  }
  return null;
}
