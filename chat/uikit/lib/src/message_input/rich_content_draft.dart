import 'dart:convert';

import 'message_input_config.dart';
import '../message_list/utils/rich_content_message.dart';
import 'package:flutter/services.dart';

const _markdownFormatOrder = ['**', '~~', '*', '~'];
const _richContentDraftPrefix = 'oa-rich-content-draft-v1:';

/// 从指定位置识别任意顺序的多层 Markdown 格式标签。
///
/// 打开标签不能重复，关闭标签必须与打开顺序相反，正文不能跨行。
({
  List<String> markers,
  int contentStart,
  int contentEnd,
  int closeEnd,
})? parseNestedMarkdownFormat(String text, int start) {
  var contentStart = start;
  final markers = <String>[];
  while (true) {
    String? matched;
    for (final marker in _markdownFormatOrder) {
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

/// 富文本附件在编辑和上传过程中的状态。
enum RichContentAttachmentStatus { pending, uploading, uploaded, failed }

/// 富文本编辑器内按顺序排列的草稿块。
sealed class RichContentDraftBlock {
  /// 当前编辑器实例内用于识别异步上传结果的稳定标识。
  final int id;

  const RichContentDraftBlock(this.id);
}

/// 保留 Markdown 原文的草稿文字块。
final class RichContentDraftTextBlock extends RichContentDraftBlock {
  /// 当前文字块内容。
  final String text;

  const RichContentDraftTextBlock(super.id, this.text);
}

/// 包含本地文件和上传结果的草稿附件块。
final class RichContentDraftAttachmentBlock extends RichContentDraftBlock {
  /// 交给宿主上传器的本地附件信息。
  final RichContentLocalAttachment attachment;

  /// 上传完成后的远端 URL；只有 uploaded 状态允许非空。
  final String? remoteUrl;

  /// 当前上传状态，决定发送按钮是否可用。
  final RichContentAttachmentStatus status;

  const RichContentDraftAttachmentBlock(
    super.id, {
    required this.attachment,
    this.remoteUrl,
    this.status = RichContentAttachmentStatus.pending,
  });

  RichContentDraftAttachmentBlock copyWith({
    String? remoteUrl,
    RichContentAttachmentStatus? status,
  }) {
    return RichContentDraftAttachmentBlock(
      id,
      attachment: attachment,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      status: status ?? this.status,
    );
  }
}

/// 保存编辑器标题与有序正文块，并在发送前生成自定义消息协议。
final class RichContentDraft {
  /// 标题按纯文本处理，发送时编码为加粗 Markdown 首段。
  final String title;

  /// 正文中的文字和附件块，顺序即接收端展示顺序。
  final List<RichContentDraftBlock> blocks;

  const RichContentDraft({this.title = '', this.blocks = const []});

  /// 将编辑草稿编码为 IM SDK 可持久化的字符串，保留本地附件路径和块顺序。
  String toPersistedString() {
    return '$_richContentDraftPrefix${jsonEncode({
          'title': title,
          'blocks': blocks.map(_draftBlockToJson).toList(growable: false),
        })}';
  }

  /// 解析 text/image/file 多态草稿块；普通文本或任一字段损坏时返回 null。
  static RichContentDraft? tryParsePersisted(String source) {
    if (!source.startsWith(_richContentDraftPrefix)) return null;
    try {
      final root = jsonDecode(source.substring(_richContentDraftPrefix.length));
      if (root is! Map<String, dynamic> || root['title'] is! String) {
        return null;
      }
      final rawBlocks = root['blocks'];
      if (rawBlocks is! List) return null;
      final blocks = <RichContentDraftBlock>[];
      final ids = <int>{};
      for (final rawBlock in rawBlocks) {
        if (rawBlock is! Map<String, dynamic>) return null;
        final block = _draftBlockFromJson(rawBlock);
        if (block == null || !ids.add(block.id)) return null;
        blocks.add(block);
      }
      return RichContentDraft(
        title: root['title'] as String,
        blocks: List.unmodifiable(blocks),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// 判断字符串是否属于本组件的内部草稿格式。
  static bool isPersistedString(String source) =>
      source.startsWith(_richContentDraftPrefix);

  /// 返回会话列表使用的单行草稿摘要，避免展示内部持久化 JSON。
  String get plainTextPreview {
    final values = <String>[if (title.isNotEmpty) title];
    for (final block in blocks) {
      switch (block) {
        case RichContentDraftTextBlock block:
          values.add(block.text);
        case RichContentDraftAttachmentBlock block:
          values.add(block.attachment.fileName);
      }
    }
    return values.join(' ');
  }

  /// 草稿至少有一段有效内容，且所有附件都已取得合法远端 URL 时可发送。
  bool get canSend {
    final hasContent = title.trim().isNotEmpty ||
        blocks.any(
          (block) => switch (block) {
            RichContentDraftTextBlock block => block.text.trim().isNotEmpty,
            RichContentDraftAttachmentBlock _ => true,
          },
        );
    return hasContent &&
        blocks.whereType<RichContentDraftAttachmentBlock>().every(
              (block) => _isReadyAttachment(block),
            );
  }

  /// 把可发送草稿转换成现有 oa_rich_content v1 消息。
  RichContentMessage? toMessage() {
    if (!canSend) return null;
    final messageBlocks = <RichContentBlock>[];
    for (final block in blocks) {
      switch (block) {
        case RichContentDraftTextBlock block:
          if (block.text.isNotEmpty) {
            messageBlocks.add(RichTextBlock(block.text));
          }
          break;
        case RichContentDraftAttachmentBlock block:
          final attachment = block.attachment;
          final url = block.remoteUrl!;
          if (attachment.type == RichContentAttachmentType.image) {
            messageBlocks.add(
              RichImageBlock(url, attachment.width!, attachment.height!),
            );
          } else {
            messageBlocks.add(
              RichFileBlock(
                url,
                attachment.fileName,
                attachment.fileSize,
                attachment.mimeType,
              ),
            );
          }
          break;
      }
    }
    final heading = title.trim();
    if (heading.isNotEmpty) {
      final encodedHeading = '**${escapeMarkdown(heading)}**';
      if (messageBlocks.firstOrNull case final RichTextBlock first) {
        messageBlocks[0] = RichTextBlock('$encodedHeading\n\n${first.text}');
      } else {
        messageBlocks.insert(0, RichTextBlock(encodedHeading));
      }
    }
    return RichContentMessage(List.unmodifiable(messageBlocks));
  }
}

/// 将单个编辑块编码为内部草稿 JSON，不改变消息发送协议。
Map<String, Object?> _draftBlockToJson(RichContentDraftBlock block) {
  return switch (block) {
    RichContentDraftTextBlock block => {
        'type': 'text',
        'id': block.id,
        'text': block.text,
      },
    RichContentDraftAttachmentBlock block => {
        'type': block.attachment.type.name,
        'id': block.id,
        'localPath': block.attachment.localPath,
        'fileName': block.attachment.fileName,
        'fileSize': block.attachment.fileSize,
        'mimeType': block.attachment.mimeType,
        'width': block.attachment.width,
        'height': block.attachment.height,
        'remoteUrl': block.remoteUrl,
        'status': block.status.name,
      },
  };
}

/// 校验并恢复单个内部草稿块，任何字段越界都拒绝整份富文本草稿。
RichContentDraftBlock? _draftBlockFromJson(Map<String, dynamic> json) {
  final id = json['id'];
  final type = json['type'];
  if (id is! int || id < 0 || type is! String) return null;
  if (type == 'text') {
    final text = json['text'];
    return text is String ? RichContentDraftTextBlock(id, text) : null;
  }
  final attachmentType = RichContentAttachmentType.values
      .where((candidate) => candidate.name == type)
      .firstOrNull;
  final localPath = json['localPath'];
  final fileName = json['fileName'];
  final fileSize = json['fileSize'];
  final mimeType = json['mimeType'];
  final width = json['width'];
  final height = json['height'];
  final remoteUrl = json['remoteUrl'];
  final rawStatus = json['status'];
  final status = RichContentAttachmentStatus.values
      .where((candidate) => candidate.name == rawStatus)
      .firstOrNull;
  if (attachmentType == null ||
      localPath is! String ||
      localPath.isEmpty ||
      fileName is! String ||
      fileName.isEmpty ||
      fileSize is! int ||
      fileSize < 0 ||
      mimeType is! String ||
      mimeType.isEmpty ||
      width is! int? ||
      height is! int? ||
      remoteUrl is! String? ||
      status == null) {
    return null;
  }
  if (attachmentType == RichContentAttachmentType.image &&
      ((width ?? 0) <= 0 || (height ?? 0) <= 0)) {
    return null;
  }
  return RichContentDraftAttachmentBlock(
    id,
    attachment: RichContentLocalAttachment(
      type: attachmentType,
      localPath: localPath,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      width: width,
      height: height,
    ),
    remoteUrl: remoteUrl,
    // 进程退出后没有仍在执行的上传任务，恢复为待上传避免永久卡住。
    status: status == RichContentAttachmentStatus.uploading
        ? RichContentAttachmentStatus.pending
        : status,
  );
}

bool _isReadyAttachment(RichContentDraftAttachmentBlock block) {
  if (block.status != RichContentAttachmentStatus.uploaded ||
      !isValidRichContentUrl(block.remoteUrl)) {
    return false;
  }
  final attachment = block.attachment;
  if (attachment.fileName.isEmpty ||
      attachment.fileSize < 0 ||
      attachment.mimeType.isEmpty) {
    return false;
  }
  return attachment.type != RichContentAttachmentType.image ||
      ((attachment.width ?? 0) > 0 && (attachment.height ?? 0) > 0);
}

/// 只接受不含凭证信息的 HTTP(S) 附件地址。
bool isValidRichContentUrl(String? value) {
  if (value == null || value.isEmpty) return false;
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

/// 转义标题中的 Markdown 控制字符，避免标题改变正文结构。
String escapeMarkdown(String value) {
  return value.replaceAllMapped(
    RegExp(r'([\\`*_{}\[\]()#+\-.!~>])'),
    (match) => '\\${match.group(1)}',
  );
}

/// 创建按当前选中格式写入 Markdown 的输入格式器。
///
/// 输入法组合文字期间不改写内容，只在文字提交后补齐标记，避免破坏候选词状态。
TextInputFormatter activeMarkdownFormatInputFormatter(
  Set<String> Function() activeMarkers,
) {
  return _ActiveMarkdownFormatInputFormatter(activeMarkers);
}

/// 把光标移到指定格式范围之外，后续输入不再继承已关闭的格式。
TextEditingValue exitActiveMarkdownFormats(
  TextEditingValue value,
  Iterable<String> markers,
) {
  final selection = value.selection;
  if (!selection.isValid) return value;
  var target = selection.end;
  var foundRange = false;
  for (final marker in markers) {
    final range = _markerRangeAt(value.text, selection.end, marker);
    if (range != null) {
      foundRange = true;
      if (range.closeEnd > target) target = range.closeEnd;
    }
  }
  if (!foundRange) return value;
  return value.copyWith(selection: TextSelection.collapsed(offset: target));
}

/// 在输入和删除时维护当前 Markdown 格式范围及隐藏标签边界。
final class _ActiveMarkdownFormatInputFormatter extends TextInputFormatter {
  final Set<String> Function() _activeMarkers;

  _ActiveMarkdownFormatInputFormatter(this._activeMarkers);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final valueWithoutMarkerDeletion = _replaceMarkerDeletionWithContent(
      oldValue,
      newValue,
    );
    if (valueWithoutMarkerDeletion != null) {
      return _removeEmptyMarkdownRange(oldValue, valueWithoutMarkerDeletion) ??
          valueWithoutMarkerDeletion;
    }
    final valueWithoutEmptyFormat = _removeEmptyMarkdownRange(
      oldValue,
      newValue,
    );
    if (valueWithoutEmptyFormat != null) return valueWithoutEmptyFormat;

    final markers = _activeMarkers();
    if (markers.isEmpty) return newValue;
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }

    var start = 0;
    var insertedEnd = 0;
    if (oldValue.composing.isValid &&
        !oldValue.composing.isCollapsed &&
        newValue.composing.isCollapsed &&
        oldValue.text == newValue.text) {
      start = oldValue.composing.start;
      insertedEnd = oldValue.composing.end;
    } else {
      final changedRange = _insertedRange(oldValue.text, newValue.text);
      if (changedRange == null) return newValue;
      start = changedRange.start;
      insertedEnd = changedRange.end;
    }

    final inserted = newValue.text.substring(start, insertedEnd);
    if (inserted.isEmpty) return newValue;
    if (inserted == '\n') {
      return _splitMarkdownRangeAtNewline(oldValue, newValue, start) ??
          newValue;
    }
    final missingMarkers = _markdownFormatOrder
        .where(
          (marker) =>
              markers.contains(marker) &&
              _markerRangeAt(oldValue.text, start, marker) == null,
        )
        .toList(growable: false);
    if (missingMarkers.isEmpty) return newValue;

    final opening = missingMarkers.join();
    final closing = missingMarkers.reversed.join();
    return newValue.copyWith(
      text: newValue.text.replaceRange(
        start,
        insertedEnd,
        '$opening$inserted$closing',
      ),
      selection: TextSelection.collapsed(
        offset: start + opening.length + inserted.length,
      ),
      composing: TextRange.empty,
    );
  }
}

/// 换行时结束当前行内格式；若光标位于段落中间，则在下一行恢复剩余正文格式。
TextEditingValue? _splitMarkdownRangeAtNewline(
  TextEditingValue oldValue,
  TextEditingValue newValue,
  int offset,
) {
  for (final marker in _markdownFormatOrder) {
    final range = _markerRangeAt(oldValue.text, offset, marker);
    if (range == null) continue;
    final opening =
        oldValue.text.substring(range.openStart, range.contentStart);
    final closing = oldValue.text.substring(range.contentEnd, range.closeEnd);
    final before = oldValue.text.substring(range.contentStart, offset);
    final after = oldValue.text.substring(offset, range.contentEnd);
    final left = before.isEmpty ? '' : '$opening$before$closing';
    final right = after.isEmpty ? '' : '$opening$after$closing';
    final replacement = '$left\n$right';
    final text = oldValue.text.replaceRange(
      range.openStart,
      range.closeEnd,
      replacement,
    );
    return newValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(
        offset: range.openStart +
            left.length +
            1 +
            (after.isEmpty ? 0 : opening.length),
      ),
      composing: TextRange.empty,
    );
  }
  return null;
}

/// 把针对隐藏标签的删除转换为同方向的正文删除。
TextEditingValue? _replaceMarkerDeletionWithContent(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  final deleted = _deletedRange(oldValue.text, newValue.text);
  if (deleted == null) return null;
  final range = _findMarkdownRangeNear(
        oldValue.text,
        deleted.start,
        (range) => _deletionTouchesMarker(deleted, range),
      ) ??
      _findMarkdownRangeNear(
        oldValue.text,
        deleted.end,
        (range) => _deletionTouchesMarker(deleted, range),
      );
  if (range == null || range.contentStart == range.contentEnd) return null;

  final touchesOpening = deleted.start < range.contentStart;
  final touchesClosing = deleted.end > range.contentEnd;
  // 同时覆盖两侧标签表示整段删除，保留系统提交的结果，不重建格式范围。
  if (touchesOpening && touchesClosing) return null;
  var contentDeleteStart = touchesClosing
      ? deleted.start.clamp(range.contentStart, range.contentEnd).toInt()
      : range.contentStart;
  var contentDeleteEnd = touchesOpening
      ? deleted.end.clamp(range.contentStart, range.contentEnd).toInt()
      : range.contentEnd;
  if (contentDeleteStart == contentDeleteEnd) {
    if (touchesClosing) {
      contentDeleteStart = _previousCodePointStart(
        oldValue.text,
        range.contentEnd,
      );
    } else {
      contentDeleteEnd = _nextCodePointEnd(oldValue.text, range.contentStart);
    }
  }
  return TextEditingValue(
    text: oldValue.text.replaceRange(contentDeleteStart, contentDeleteEnd, ''),
    selection: TextSelection.collapsed(offset: contentDeleteStart),
  );
}

/// 判断系统提交的删除范围是否与格式范围任一侧标签相交。
bool _deletionTouchesMarker(TextRange deleted, _MarkdownMarkerRange range) {
  final touchesOpening =
      deleted.start < range.contentStart && deleted.end > range.openStart;
  final touchesClosing =
      deleted.start < range.closeEnd && deleted.end > range.contentEnd;
  return touchesOpening || touchesClosing;
}

/// 删除格式范围内的全部正文时，一并移除已失去作用的 Markdown 标记。
TextEditingValue? _removeEmptyMarkdownRange(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  final deleted = _deletedRange(oldValue.text, newValue.text);
  if (deleted == null) return null;
  for (final marker in _markdownFormatOrder) {
    final range = _markerRangeAt(oldValue.text, deleted.start, marker);
    if (range == null ||
        deleted.start != range.contentStart ||
        deleted.end != range.contentEnd) {
      continue;
    }
    final emptyRangeEnd = range.closeEnd - (deleted.end - deleted.start);
    final cleanedText = newValue.text.replaceRange(
      range.openStart,
      emptyRangeEnd,
      '',
    );
    // 删除隐藏闭合标签时，旧光标位于实际正文删除范围之后，仍按退格方向回落。
    final deletingBackward = oldValue.selection.isValid &&
        oldValue.selection.isCollapsed &&
        oldValue.selection.end >= deleted.end;
    return newValue.copyWith(
      text: cleanedText,
      selection: TextSelection.collapsed(
        offset: _adjacentMarkdownContentOffset(
          cleanedText,
          range.openStart,
          preferPrevious: deletingBackward,
        ),
      ),
      composing: TextRange.empty,
    );
  }
  return null;
}

/// 返回一次纯删除操作在旧文本中移除的范围。
TextRange? _deletedRange(String oldText, String newText) {
  if (newText.length >= oldText.length) return null;
  final inserted = _insertedRange(oldText, newText);
  if (inserted == null || !inserted.isCollapsed) return null;
  return TextRange(
    start: inserted.start,
    end: oldText.length - (newText.length - inserted.end),
  );
}

/// 把标签边界上的光标移回相邻正文，避免下一次删除先破坏隐藏标签。
int _adjacentMarkdownContentOffset(
  String text,
  int boundary, {
  required bool preferPrevious,
}) {
  final markerWidth = _markdownFormatOrder.fold<int>(
    0,
    (width, marker) => width + marker.length,
  );
  for (var distance = 0; distance <= markerWidth; distance++) {
    final offset = boundary + (preferPrevious ? -distance : distance);
    if (offset < 0 || offset > text.length) break;
    for (final marker in _markdownFormatOrder) {
      final range = _markerRangeAt(text, offset, marker);
      if (range == null) continue;
      if (preferPrevious && range.closeEnd == boundary) {
        return range.contentEnd;
      }
      if (!preferPrevious && range.openStart == boundary) {
        return range.contentStart;
      }
    }
  }
  if (preferPrevious) {
    return _adjacentMarkdownContentOffset(
      text,
      boundary,
      preferPrevious: false,
    );
  }
  return boundary;
}

/// 在标签最大宽度内查找满足条件的相邻格式范围。
_MarkdownMarkerRange? _findMarkdownRangeNear(
  String text,
  int anchor,
  bool Function(_MarkdownMarkerRange range) matches,
) {
  final markerWidth = _markdownFormatOrder.fold<int>(
    0,
    (width, marker) => width + marker.length,
  );
  for (var distance = 0; distance <= markerWidth; distance++) {
    for (final offset in {anchor - distance, anchor + distance}) {
      if (offset < 0 || offset > text.length) continue;
      for (final marker in _markdownFormatOrder) {
        final range = _markerRangeAt(text, offset, marker);
        if (range != null && matches(range)) return range;
      }
    }
  }
  return null;
}

/// 返回前一个 Unicode 码点的起始偏移，避免拆开代理对。
int _previousCodePointStart(String text, int offset) {
  if (offset < 2) return offset - 1;
  final last = text.codeUnitAt(offset - 1);
  final previous = text.codeUnitAt(offset - 2);
  return last >= 0xDC00 &&
          last <= 0xDFFF &&
          previous >= 0xD800 &&
          previous <= 0xDBFF
      ? offset - 2
      : offset - 1;
}

/// 返回下一个 Unicode 码点的结束偏移，避免拆开代理对。
int _nextCodePointEnd(String text, int offset) {
  if (offset + 1 >= text.length) return offset + 1;
  final first = text.codeUnitAt(offset);
  final next = text.codeUnitAt(offset + 1);
  return first >= 0xD800 && first <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF
      ? offset + 2
      : offset + 1;
}

/// 定位单次编辑中新写入或替换的文本范围，删除操作返回空范围。
TextRange? _insertedRange(String oldText, String newText) {
  if (newText == oldText) return null;
  var start = 0;
  while (start < oldText.length &&
      start < newText.length &&
      oldText.codeUnitAt(start) == newText.codeUnitAt(start)) {
    start++;
  }
  var oldEnd = oldText.length;
  var newEnd = newText.length;
  while (oldEnd > start &&
      newEnd > start &&
      oldText.codeUnitAt(oldEnd - 1) == newText.codeUnitAt(newEnd - 1)) {
    oldEnd--;
    newEnd--;
  }
  return TextRange(start: start, end: newEnd);
}

/// 按原文顺序定位格式范围，支持单层、多层嵌套及紧密相邻的格式段。
_MarkdownMarkerRange? _markerRangeAt(String text, int offset, String marker) {
  for (var start = 0; start < text.length; start++) {
    final nested = parseNestedMarkdownFormat(text, start);
    if (nested != null) {
      final range = _MarkdownMarkerRange(
        openStart: start,
        contentStart: nested.contentStart,
        contentEnd: nested.contentEnd,
        closeEnd: nested.closeEnd,
      );
      if (nested.markers.contains(marker) &&
          offset >= range.contentStart &&
          offset <= range.contentEnd) {
        return range;
      }
      start = range.closeEnd - 1;
      continue;
    }
    _MarkdownMarkerRange? range;
    String? matchedMarker;
    for (final candidate in _markdownFormatOrder) {
      range = _singleMarkdownMarkerRangeAt(text, start, candidate);
      if (range != null) {
        matchedMarker = candidate;
        break;
      }
    }
    if (range == null) continue;
    if (matchedMarker == marker &&
        offset >= range.contentStart &&
        offset <= range.contentEnd) {
      return range;
    }
    start = range.closeEnd - 1;
  }
  return null;
}

/// 按文本顺序识别单层格式，使相邻段的连续标记仍按前后两段分割。
_MarkdownMarkerRange? _singleMarkdownMarkerRangeAt(
  String text,
  int start,
  String marker,
) {
  if (!text.startsWith(marker, start)) return null;
  final contentStart = start + marker.length;
  final contentEnd = text.indexOf(marker, contentStart);
  if (contentEnd <= contentStart) return null;
  final content = text.substring(contentStart, contentEnd);
  if (content.contains('\n') || content.contains(marker[0])) return null;
  return _MarkdownMarkerRange(
    openStart: start,
    contentStart: contentStart,
    contentEnd: contentEnd,
    closeEnd: contentEnd + marker.length,
  );
}

final class _MarkdownMarkerRange {
  final int openStart;
  final int contentStart;
  final int contentEnd;
  final int closeEnd;

  const _MarkdownMarkerRange({
    required this.openStart,
    required this.contentStart,
    required this.contentEnd,
    required this.closeEnd,
  });
}
