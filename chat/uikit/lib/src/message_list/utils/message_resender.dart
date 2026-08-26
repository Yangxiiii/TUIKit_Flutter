import 'package:atomic_x_core/atomicxcore.dart';

/// Resend a previously-failed message.
///
/// MessageInputStore's public API only accepts a [SendMessagePayload], so a
/// naive "send the original payload again" approach mints a brand-new
/// V2TimMessage with a fresh msgID — leaving the failed row stranded next
/// to the new sending row, since MessageListStore keys reconciliation off
/// msgID. The agreed cross-platform fix (aligned with the Kotlin team) is
/// therefore:
///
/// 1. Delete the failed row first via [MessageActionStore.delete] so the
///    stale entry disappears from the local IM SDK store and the message
///    list.
/// 2. Then send a fresh message constructed from the original payload.
///
/// This restores the desired UX (failed row replaced by a new sending row)
/// without touching the [MessageInputStore] interface.
///
/// Note: fields that don't round-trip through [SendMessagePayload] /
/// [SendMessageOption] are necessarily lost on resend (quote pointer is
/// the main one — we only have [MessageQuoteInfo], not the original
/// quoted [MessageInfo]). This matches Kotlin behaviour for the
/// payload-based resend path.
class MessageResender {
  static Future<void> resend({
    required MessageInfo message,
    required String conversationID,
  }) async {
    final payload = _convertToSendPayload(message.messagePayload);
    if (payload == null) return;

    await MessageActionStore.create(message).delete();

    final option = SendMessageOption(
      atUserList: message.atUserList,
      needReadReceipt: message.needReadReceipt,
      isExtensionEnabled: message.isExtensionEnabled,
      offlinePushInfo: message.offlinePushInfo,
    );

    await MessageInputStore.create(conversationID: conversationID)
        .sendMessage(payload: payload, option: option);
  }

  static SendMessagePayload? _convertToSendPayload(MessagePayload? payload) {
    if (payload == null) return null;
    switch (payload) {
      case TextMessagePayload p:
        return TextSendMessagePayload(text: p.text);
      case ImageMessagePayload p:
        final path = p.originalImagePath;
        if (path == null || path.isEmpty) return null;
        return ImageSendMessagePayload(
          imagePath: path,
          imageWidth: p.originalImageWidth,
          imageHeight: p.originalImageHeight,
        );
      case VideoMessagePayload p:
        final path = p.videoPath;
        final snapshot = p.videoSnapshotPath;
        final type = p.videoType;
        if (path == null ||
            path.isEmpty ||
            snapshot == null ||
            snapshot.isEmpty ||
            type == null ||
            type.isEmpty) {
          return null;
        }
        return VideoSendMessagePayload(
          videoFilePath: path,
          videoType: type,
          duration: p.videoDuration,
          snapshotPath: snapshot,
          snapshotWidth: p.videoSnapshotWidth,
          snapshotHeight: p.videoSnapshotHeight,
        );
      case AudioMessagePayload p:
        final path = p.audioPath;
        if (path == null || path.isEmpty) return null;
        return AudioSendMessagePayload(
          audioFilePath: path,
          duration: p.audioDuration,
        );
      case FileMessagePayload p:
        final path = p.filePath;
        final name = p.fileName;
        if (path == null || path.isEmpty || name == null || name.isEmpty)
          return null;
        return FileSendMessagePayload(
          filePath: path,
          fileName: name,
          fileSize: p.fileSize,
        );
      case FaceMessagePayload p:
        final data = p.faceData;
        if (data == null || data.isEmpty) return null;
        return FaceSendMessagePayload(index: p.faceIndex, data: data);
      case CustomMessagePayload p:
        return CustomSendMessagePayload(
          customData: p.customData,
          description: p.description,
          extensionInfo: p.extensionInfo,
        );
      default:
        return null;
    }
  }
}
