import 'dart:io';

import 'message_input_config.dart';
import 'rich_content_draft.dart';

/// 上传单个富文本附件；视频封面先写回，重试时可复用已取得的远端地址。
Future<void> uploadRichContentAttachment(
  RichContentDraftAttachmentBlock block,
  RichContentAttachmentUploader uploader, {
  required void Function(RichContentDraftAttachmentBlock) onProgress,
  required void Function() checkCurrent,
}) async {
  checkCurrent();
  final attachment = block.attachment;
  // 封面先就绪并单独保留，视频本体失败后无需再次上传同一封面。
  if (attachment.isVideo &&
      attachment.thumbnailPath != null &&
      !isValidRichContentUrl(block.thumbnailUrl)) {
    final file = File(attachment.thumbnailPath!);
    final size = await file.length();
    checkCurrent();
    final url = await uploader(RichContentLocalAttachment(
      type: RichContentAttachmentType.image,
      localPath: file.path,
      fileName: file.uri.pathSegments.last,
      fileSize: size,
      mimeType: 'image/*',
      width: attachment.width,
      height: attachment.height,
    ));
    checkCurrent();
    if (!isValidRichContentUrl(url)) throw StateError('视频封面上传失败');
    block = block.copyWith(thumbnailUrl: url);
    onProgress(block);
  }
  checkCurrent();
  // 上传返回合法远端 URL 后才标记附件可编码，原始本地路径始终留在任务内。
  final url = await uploader(attachment);
  if (!isValidRichContentUrl(url)) throw StateError('媒体上传失败');
  checkCurrent();
  onProgress(block.copyWith(
      remoteUrl: url, status: RichContentAttachmentStatus.uploaded));
}
