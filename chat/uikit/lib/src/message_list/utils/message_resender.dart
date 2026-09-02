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
///
/// 重新发送之前发送失败的消息。
///
/// MessageInputStore 的公开 API 只接受 [SendMessagePayload]，所以简单地“再次发送原始负载”会生成一个全新的 V2TimMessage 并带上一个新的
/// msgID——导致失败的那行保留在新发送行旁边，因为 MessageListStore 是根据 msgID 来进行键的对比。双方同意的跨平台解决方案（与 Kotlin 团队一致）是
///
/// 1. 先通过 [MessageActionStore.delete] 删除失败行，这样本地 IM SDK 存储里就不会再有旧条目，消息也消失了。
///
/// 2. 然后用原始负载构建一个新的消息进行发送。
///
/// 这样就能恢复想要的用户体验（失败行被新的发送行替代），同时不需要修改 [MessageInputStore] 接口。
///
/// 注意：那些无法通过 [SendMessagePayload] / [SendMessageOption] 完整传递的字段，在重发时肯定会丢失（引用指针是主要的——我们只有
/// [MessageQuoteInfo]，没有原始引用的 [MessageInfo]）。这和 Kotlin 的基于 payload 的重发路径行为一致。
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
