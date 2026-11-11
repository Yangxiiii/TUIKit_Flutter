import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';

import '../message_list/utils/rich_content_markdown_format.dart';
import 'rich_content_draft.dart';
import 'src/chat_special_text_span_builder.dart' show EmojiText, HttpText;

typedef _Piece = ({
  int start,
  int end,
  List<String> formats,
  bool selected,
  bool editable,
});

/// 只识别格式边界及不能拆开的附件、业务表情和链接令牌。
final _pieceBoundary = RegExp(
  '${richContentAttachmentTokenPattern.pattern}|${RegExp.escape(EmojiText.flag)}[^\\]\\r\\n]*\\]|'
  '${RegExp.escape(HttpText.flag)}[^\\r\\n]+?${RegExp.escape(HttpText.flag)}|'
  r'\r\n|[\r\n]|\\[^\r\n]|[*~\[`@]',
);

/// 光标沿用左侧样式；范围选区只有每段正文都带同一样式时才点亮按钮。
Set<String> richContentSelectionFormats(TextEditingValue value,
    {Map<int, int> mentionEnds = const {}}) {
  final selection = value.selection;
  if (!selection.isValid || selection.end > value.text.length) return {};
  if (selection.isCollapsed) {
    return richContentMarkdownFormatsAt(value.text, selection.extentOffset);
  }
  return _commonFormats(_selectionPieces(value.text, selection, mentionEnds));
}

/// 将格式应用到选中正文，返回新选区及需要一并更新的提及起点。
({TextEditingValue value, Map<int, int> mentionOffsets})
    toggleSelectedMarkdownFormat(
  TextEditingValue value,
  String marker, {
  Map<int, int> mentionEnds = const {},
}) {
  final selection = value.selection;
  final source = value.text;
  if (!selection.isValid ||
      selection.isCollapsed ||
      selection.end > source.length ||
      !richContentMarkdownFormatOrder.contains(marker)) {
    return (value: value, mentionOffsets: const {});
  }

  // 混合选区统一添加样式，整段已经带该样式时才取消。
  final pieces = _selectionPieces(source, selection, mentionEnds);
  if (!pieces.any((piece) => piece.selected && piece.editable)) {
    return (value: value, mentionOffsets: const {});
  }
  final remove = _commonFormats(pieces).contains(marker);
  final output = StringBuffer();
  final mentionOffsets = <int, int>{};
  var open = <String>[];
  int? selectionStart;
  int? selectionEnd;

  // 相同样式连成一段。样式变化时先闭合整段，避免混用单星号与双星号时跨片段配对。
  for (final piece in pieces) {
    final formats = [...piece.formats];
    if (piece.selected && piece.editable) {
      if (remove) {
        formats.remove(marker);
      } else if (!formats.contains(marker)) {
        formats.add(marker);
      }
    }
    if (!listEquals(open, formats)) {
      output.writeAll(open.reversed);
      output.writeAll(formats);
      open = formats;
    }
    if (piece.selected) selectionStart ??= output.length;
    for (final mention in mentionEnds.entries) {
      if (mention.key >= piece.start && mention.value <= piece.end) {
        mentionOffsets[mention.key] = output.length + mention.key - piece.start;
      }
    }
    output.write(source.substring(piece.start, piece.end));
    if (piece.selected) selectionEnd = output.length;
  }
  output.writeAll(open.reversed);

  // 继续保留从左或从右开始的选择方向，便于连续切换多个样式。
  final reversed = selection.baseOffset > selection.extentOffset;
  return (
    value: value.copyWith(
      text: output.toString(),
      selection: selection.copyWith(
        baseOffset: reversed ? selectionEnd : selectionStart,
        extentOffset: reversed ? selectionStart : selectionEnd,
      ),
      composing: TextRange.empty,
    ),
    mentionOffsets: mentionOffsets,
  );
}

/// 只比较可编辑正文的格式，选区内的换行和附件不影响按钮状态。
Set<String> _commonFormats(List<_Piece> pieces) {
  Set<String>? common;
  for (final piece in pieces) {
    if (!piece.selected || !piece.editable) continue;
    common =
        common?.intersection(piece.formats.toSet()) ?? piece.formats.toSet();
    if (common.isEmpty) break;
  }
  return common ?? {};
}

/// 将 Markdown 拆成带原文偏移的正文片段和原样保留的结构边界。
List<_Piece> _selectionPieces(
    String source, TextSelection selection, Map<int, int> mentionEnds) {
  final pieces = <_Piece>[];

  void add(int start, int end, List<String> formats, {bool editable = true}) {
    if (start >= end) return;
    if (end <= selection.start || start >= selection.end) {
      pieces.add((
        start: start,
        end: end,
        formats: formats,
        selected: false,
        editable: editable
      ));
      return;
    }
    // 不拆结构令牌；只有正文需要在选区端点精确分割。
    final selectedStart =
        !editable || start >= selection.start ? start : selection.start;
    final selectedEnd = !editable || end <= selection.end ? end : selection.end;
    add(start, selectedStart, formats);
    pieces.add((
      start: selectedStart,
      end: selectedEnd,
      formats: formats,
      selected: true,
      editable: editable,
    ));
    add(selectedEnd, end, formats);
  }

  void scan(String text, int offset, List<String> formats) {
    var cursor = 0;
    for (final boundary in _pieceBoundary.allMatches(text)) {
      final start = boundary.start;
      if (start < cursor) continue;
      // 只保护已选成员的提及范围，普通正文中的 @ 继续作为文字处理。
      if (boundary[0] == '@') {
        final end = mentionEnds[offset + start];
        if (end == null || end > offset + text.length) continue;
        add(offset + cursor, offset + start, formats);
        add(offset + start, end, formats, editable: false);
        cursor = end - offset;
        continue;
      }
      final format = parseRichContentMarkdownFormatAt(text, start);
      final linkOrCode = richContentMarkdownPattern.matchAsPrefix(text, start);
      // 未配对的分隔符保留为字面字符，避免新标记把它误读成格式边界。
      add(offset + cursor, offset + start, formats);
      if (format != null) {
        cursor = format.closeEnd;
        if (offset + start >= selection.end ||
            offset + cursor <= selection.start) {
          add(offset + start, offset + cursor, formats, editable: false);
        } else {
          scan(
            text.substring(format.contentStart, format.contentEnd),
            offset + format.contentStart,
            [...formats, ...format.markers.where((m) => !formats.contains(m))],
          );
        }
      } else if (linkOrCode?.group(10) case final label?) {
        final labelStart = offset + start + 1;
        final labelEnd = labelStart + label.length;
        add(offset + start, labelStart, formats, editable: false);
        scan(label, labelStart, formats);
        cursor = linkOrCode!.end;
        add(labelEnd, offset + cursor, formats, editable: false);
      } else {
        cursor = linkOrCode?.group(13) == null ? boundary.end : linkOrCode!.end;
        add(offset + start, offset + cursor, formats, editable: false);
      }
    }
    add(offset + cursor, offset + text.length, formats);
  }

  scan(source, 0, const []);
  return pieces;
}
