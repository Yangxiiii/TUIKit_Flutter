import 'dart:convert';

import 'message_input_config.dart';
import 'message_text.dart';
import '../message_list/utils/rich_content_message.dart';
import '../message_list/utils/rich_content_markdown_format.dart';
import 'package:flutter/services.dart';

/// 与消息展示共用标记优先级，避免输入状态与渲染边界不一致。
const _markdownFormatOrder = richContentMarkdownFormatOrder;
const _richContentDraftPrefix = 'oa-rich-content-draft-v1:';

/// 富文本附件在编辑和上传过程中的状态。
enum RichContentAttachmentStatus {
  pending,
  uploading,
  uploaded,
  failed,

  /// 相册仍在导出、压缩或读取尺寸，只能展示本地占位，不能发送。
  preparing,

  /// 本地处理失败或恢复了中断的处理，占位须删除后重新选择。
  preparationFailed,
}

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

  /// 已上传视频首帧封面地址；收起、草稿恢复和再次发送均保留。
  final String? thumbnailUrl;

  /// 当前上传状态；仅 uploaded 状态可编码进消息，本地待上传附件仍可提交发送。
  final RichContentAttachmentStatus status;

  const RichContentDraftAttachmentBlock(
    super.id, {
    required this.attachment,
    this.remoteUrl,
    this.thumbnailUrl,
    this.status = RichContentAttachmentStatus.pending,
  });

  /// 远端资源及视频封面均已就绪，可以直接编码进消息而不再上传。
  bool get isReadyToSend => _isReadyAttachment(this);

  RichContentDraftAttachmentBlock copyWith({
    String? remoteUrl,
    String? thumbnailUrl,
    RichContentAttachmentStatus? status,
  }) {
    return RichContentDraftAttachmentBlock(
      id,
      attachment: attachment,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
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

  /// 撤回后恢复已发送的完整图文；远端附件保持已上传状态，避免重复上传。
  factory RichContentDraft.fromMessage(RichContentMessage message) {
    final blocks = <RichContentDraftBlock>[];
    // 按已发送消息的顺序恢复文字和远端附件，块ID仅在当前草稿内重新编号。
    for (var i = 0; i < message.blocks.length; i++) {
      final block = message.blocks[i];
      if (block is RichTextBlock) {
        blocks.add(RichContentDraftTextBlock(i, block.text));
        continue;
      }
      final image = block is RichImageBlock ? block : null;
      final file = block is RichFileBlock ? block : null;
      final url = image?.url ?? file!.url;
      blocks.add(
        RichContentDraftAttachmentBlock(
          i,
          attachment: RichContentLocalAttachment(
            type: image == null
                ? RichContentAttachmentType.file
                : RichContentAttachmentType.image,
            localPath: '',
            fileName: file?.name ?? 'image',
            fileSize: file?.size ?? 0,
            mimeType: file?.mimeType ?? 'image/*',
            width: image?.width ?? file?.width,
            height: image?.height ?? file?.height,
          ),
          remoteUrl: url,
          thumbnailUrl: file?.thumbnailUrl,
          status: RichContentAttachmentStatus.uploaded,
        ),
      );
    }
    return RichContentDraft(blocks: List.unmodifiable(blocks));
  }

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

  /// 草稿是否包含可展示的文字或附件；仅有格式状态不算草稿内容。
  bool get hasContent =>
      title.trim().isNotEmpty ||
      blocks.any(
        (block) => switch (block) {
          RichContentDraftTextBlock block =>
            richContentMarkdownToPlainText(block.text).trim().isNotEmpty,
          RichContentDraftAttachmentBlock _ => true,
        },
      );

  /// 返回会话列表使用的单行草稿摘要，避免展示内部持久化 JSON。
  String get plainTextPreview {
    final values = <String>[if (title.isNotEmpty) title];
    for (final block in blocks) {
      switch (block) {
        case RichContentDraftTextBlock block:
          values.add(richContentMarkdownToPlainText(block.text));
        case RichContentDraftAttachmentBlock block:
          values.add(
            block.attachment.type == RichContentAttachmentType.image
                ? '[图片]'
                : block.attachment.mimeType.startsWith('video/')
                    ? '[视频]'
                    : block.attachment.fileName,
          );
      }
    }
    return values.join(' ');
  }

  /// 标题及文字块的可见字符总数；隐藏格式标记和附件不计，输入的换行计数。
  int get characterCount =>
      messageTextCharacterCount(title) +
      blocks.whereType<RichContentDraftTextBlock>().fold<int>(
            0,
            (count, block) =>
                count +
                messageTextCharacterCount(
                  richContentMarkdownToPlainText(block.text),
                ),
          );

  /// 草稿有有效内容、未超过文字上限且全部附件取得合法远端URL时可发送。
  bool get canSend {
    return hasContent &&
        characterCount <= messageTextCharacterLimit &&
        blocks.whereType<RichContentDraftAttachmentBlock>().every(
              (block) => _isReadyAttachment(block),
            );
  }

  /// 内容须符合字数限制，媒体须有正整数宽高；附件须有远端资源或已完成本地处理。
  bool get canSubmit =>
      hasContent &&
      characterCount <= messageTextCharacterLimit &&
      blocks.whereType<RichContentDraftAttachmentBlock>().every((block) =>
          block.status != RichContentAttachmentStatus.preparing &&
          block.status != RichContentAttachmentStatus.preparationFailed &&
          block.attachment.hasRequiredDimensions &&
          (block.isReadyToSend || block.attachment.localPath.isNotEmpty));

  /// 比较用户编辑的内容与附件身份，忽略上传状态和远端地址的变化。
  bool hasSameContentAs(RichContentDraft other) {
    if (title != other.title || blocks.length != other.blocks.length) {
      return false;
    }
    // 上传只替换附件元数据，不能因此被误判为用户继续编辑，也不能忽略附件的删除或替换。
    for (var i = 0; i < blocks.length; i++) {
      switch ((blocks[i], other.blocks[i])) {
        case (RichContentDraftTextBlock a, RichContentDraftTextBlock b):
          if (a.text != b.text) return false;
        case (
            RichContentDraftAttachmentBlock a,
            RichContentDraftAttachmentBlock b
          ):
          if (a.id != b.id || !identical(a.attachment, b.attachment)) {
            return false;
          }
        default:
          return false;
      }
    }
    return true;
  }

  /// 把可发送草稿转换成现有 oa_rich_content v1 消息。
  RichContentMessage? toMessage() {
    if (!canSend) return null;
    return _buildContent();
  }

  /// 仅本地发送气泡使用本地媒体预览；该结果不能交给 SDK，发送仍须经过 toMessage 校验。
  RichContentMessage get localPreview => _buildContent(localPreview: true);

  /// 发送和预览保持同一排版，只有本地预览可使用文件路径代替远端地址。
  RichContentMessage _buildContent({bool localPreview = false}) {
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
          final url = localPreview && attachment.localPath.isNotEmpty
              ? Uri.file(attachment.localPath).toString()
              : block.remoteUrl!;
          if (attachment.type == RichContentAttachmentType.image) {
            messageBlocks.add(
              RichImageBlock(url, attachment.width, attachment.height),
            );
          } else {
            messageBlocks.add(
              RichFileBlock(
                url,
                attachment.fileName,
                attachment.fileSize,
                attachment.mimeType,
                width: attachment.width,
                height: attachment.height,
                thumbnailUrl: localPreview && attachment.thumbnailPath != null
                    ? Uri.file(attachment.thumbnailPath!).toString()
                    : block.thumbnailUrl,
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
        'thumbnailPath': block.attachment.thumbnailPath,
        'durationMs': block.attachment.durationMs,
        'thumbnailUrl': block.thumbnailUrl,
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
  final thumbnailPath = json['thumbnailPath'];
  final durationMs = json['durationMs'];
  final thumbnailUrl = json['thumbnailUrl'];
  final width = json['width'];
  final height = json['height'];
  final remoteUrl = json['remoteUrl'];
  final rawStatus = json['status'];
  final status = RichContentAttachmentStatus.values
      .where((candidate) => candidate.name == rawStatus)
      .firstOrNull;
  if (attachmentType == null ||
      localPath is! String ||
      // 相册处理中还没有沙盒路径；远端回填则必须已有合法地址。
      (localPath.isEmpty &&
          status != RichContentAttachmentStatus.preparing &&
          status != RichContentAttachmentStatus.preparationFailed &&
          !(status == RichContentAttachmentStatus.uploaded &&
              isValidRichContentUrl(remoteUrl))) ||
      fileName is! String ||
      fileName.isEmpty ||
      fileSize is! int ||
      fileSize < 0 ||
      mimeType is! String ||
      mimeType.isEmpty ||
      thumbnailPath is! String? ||
      (durationMs != null && (durationMs is! int || durationMs < 0)) ||
      (thumbnailUrl != null &&
          !isValidRichContentUrl(
              thumbnailUrl is String ? thumbnailUrl : null)) ||
      width is! int? ||
      height is! int? ||
      remoteUrl is! String? ||
      status == null) {
    return null;
  }
  if ((attachmentType == RichContentAttachmentType.image ||
          mimeType.startsWith('video/')) &&
      ((width != null && width <= 0) || (height != null && height <= 0))) {
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
      thumbnailPath: thumbnailPath,
      durationMs: durationMs as int?,
      width: width,
      height: height,
    ),
    remoteUrl: remoteUrl,
    thumbnailUrl: thumbnailUrl as String?,
    // 本地处理不能跨进程恢复；保留失败占位供删除，避免一直转圈或误发原始路径。
    status: switch (status) {
      RichContentAttachmentStatus.preparing =>
        RichContentAttachmentStatus.preparationFailed,
      RichContentAttachmentStatus.uploading =>
        RichContentAttachmentStatus.pending,
      _ => status,
    },
  );
}

/// 附件须已上传且元数据有效，图片和视频发送前必须具有正整数宽高。
bool _isReadyAttachment(RichContentDraftAttachmentBlock block) {
  if (block.status != RichContentAttachmentStatus.uploaded ||
      !isValidRichContentUrl(block.remoteUrl)) {
    return false;
  }
  final attachment = block.attachment;
  // 新选择的视频须同时完成首帧封面上传；没有封面字段的旧远端消息保持兼容。
  if (attachment.isVideo &&
      attachment.thumbnailPath != null &&
      !isValidRichContentUrl(block.thumbnailUrl)) {
    return false;
  }
  if (attachment.fileName.isEmpty ||
      attachment.fileSize < 0 ||
      attachment.mimeType.isEmpty ||
      !attachment.hasRequiredDimensions) {
    return false;
  }
  return true;
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
    // 删除先维护隐藏标签边界，避免后续格式补齐把已删除的内容恢复出来。
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
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }

    // 候选词提交和直接输入统一定位实际变更范围，光标偏移始终基于原始Markdown。
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
    if (inserted.contains('\n') || inserted.contains('\r')) {
      final parts = RegExp(r'\r\n|\r|\n|[^\r\n]+')
          .allMatches(inserted)
          .map((match) => match.group(0)!)
          .toList();
      // 粘贴及输入法可一次提交多行；逐段复用单行规则，不能生成跨行的行内标签。
      if (parts.length > 1) {
        return _formatMultilineInsertion(
            oldValue, newValue, start, insertedEnd, parts);
      }
      // 已有格式必须拆行，即使工具条已关闭或草稿回填后没有选中任何格式。
      return _splitMarkdownRangeAtNewline(newValue, start, inserted) ??
          newValue;
    }
    if (markers.isEmpty) return newValue;
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

  /// 将一次多行提交依次应用到当前选区，保留每次拆行后重新映射的正文光标。
  TextEditingValue _formatMultilineInsertion(
    TextEditingValue oldValue,
    TextEditingValue newValue,
    int start,
    int insertedEnd,
    List<String> parts,
  ) {
    var value = oldValue;
    var replaceStart = start;
    var replaceEnd =
        oldValue.text.length - (newValue.text.length - insertedEnd);
    // 首段替换原选区，后续段落插入上一步的视觉光标位置，避免闭合标签被拆坏。
    for (final part in parts) {
      value = formatEditUpdate(
          value,
          value.copyWith(
            text: value.text.replaceRange(replaceStart, replaceEnd, part),
            selection:
                TextSelection.collapsed(offset: replaceStart + part.length),
            composing: TextRange.empty,
          ));
      replaceStart = replaceEnd = value.selection.extentOffset;
    }
    return value;
  }
}

/// 按换行前后实际保留的正文拆分格式，替换选区时不能重新插回被删除的文字。
TextEditingValue? _splitMarkdownRangeAtNewline(
  TextEditingValue newValue,
  int offset,
  String lineBreak,
) {
  final text =
      newValue.text.replaceRange(offset, offset + lineBreak.length, '');
  final split = _splitMarkdownTextAt(text, offset);
  if (split == null) return null;
  return newValue.copyWith(
    text: '${split.before}$lineBreak${split.after}',
    selection: TextSelection.collapsed(
        offset: split.before.length + lineBreak.length + split.openingLength),
    composing: TextRange.empty,
  );
}

/// 递归关闭光标左侧的各层格式并在右侧恢复，紧邻标签和空行不生成空格式段。
({String before, String after, int openingLength})? _splitMarkdownTextAt(
    String text, int offset) {
  for (var start = 0; start < text.length; start++) {
    final format = parseRichContentMarkdownFormatAt(text, start);
    if (format == null) continue;
    if (offset < format.contentStart || offset > format.contentEnd) {
      start = format.closeEnd - 1;
      continue;
    }
    // 内层先拆，再分别包回外层标签，防止只关闭最外层而留下断开的斜体或下划线。
    final content = text.substring(format.contentStart, format.contentEnd);
    final relativeOffset = offset - format.contentStart;
    final inner = _splitMarkdownTextAt(content, relativeOffset);
    final opening = text.substring(start, format.contentStart);
    final closing = text.substring(format.contentEnd, format.closeEnd);
    final before = inner?.before ?? content.substring(0, relativeOffset);
    final after = inner?.after ?? content.substring(relativeOffset);
    final left = before.isEmpty ? '' : '$opening$before$closing';
    final right = after.isEmpty ? '' : '$opening$after$closing';
    return (
      before: text.substring(0, start) + left,
      after: right + text.substring(format.closeEnd),
      openingLength:
          after.isEmpty ? 0 : opening.length + (inner?.openingLength ?? 0),
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
_MarkdownMarkerRange? _markerRangeAt(String text, int offset, String marker,
    {int sourceStart = 0}) {
  // 读取共用格式边界，光标移动、删除和发送后的展示不能各自配对相邻标签。
  for (var start = 0; start < text.length; start++) {
    final format = parseRichContentMarkdownFormatAt(text, start);
    if (format == null) continue;
    if (format.markers.contains(marker) &&
        offset >= format.contentStart &&
        offset <= format.contentEnd) {
      return _MarkdownMarkerRange(
        openStart: sourceStart + start,
        contentStart: sourceStart + format.contentStart,
        contentEnd: sourceStart + format.contentEnd,
        closeEnd: sourceStart + format.closeEnd,
      );
    }
    // 局部嵌套必须继续查找内层，光标自动选中的格式不能在下一次输入时被重复套用。
    if (offset >= format.contentStart && offset <= format.contentEnd) {
      final inner = _markerRangeAt(
          text.substring(format.contentStart, format.contentEnd),
          offset - format.contentStart,
          marker,
          sourceStart: sourceStart + format.contentStart);
      if (inner != null) return inner;
    }
    start = format.closeEnd - 1;
  }
  return null;
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
