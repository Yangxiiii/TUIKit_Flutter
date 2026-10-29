import 'package:atomic_x_core/atomicxcore.dart';
import '../../message_input/chat_media_sender.dart';
import '../../message_input/pending_rich_content_message.dart';

/// 校验失败消息后重新发送；实际调用SDK前才删除旧行，避免校验失败丢失记录。
/// 引用信息无法由历史负载完整恢复，其余发送选项沿用原消息。
class MessageResender {
  /// 旧消息只在新发送具备执行条件后移除，媒体复用统一分流边界。
  static Future<void> resend({
    required MessageInfo message,
    required String conversationID,
    ChatMediaSender? mediaSender,
  }) async {
    // 本地富文本尚未取得远端资源，只能重试原任务，不能把空 customData 发给 SDK。
    if (message.messagePayload case final PendingRichContentMessage pending) {
      await pending.send();
      return;
    }
    final payload = _convertToSendPayload(message.messagePayload);
    if (payload == null) return;

    final option = SendMessageOption(
      atUserList: message.atUserList,
      needReadReceipt: message.needReadReceipt,
      isExtensionEnabled: message.isExtensionEnabled,
      offlinePushInfo: message.offlinePushInfo,
    );

    await sendChatMedia(
        message: message,
        payload: payload,
        option: option,
        conversationID: conversationID,
        sender: mediaSender,
        beforeSend: () async {
          final result = await MessageActionStore.create(message).delete();
          if (!result.isSuccess) throw StateError('重发前删除失败消息失败');
        });
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
        if (path == null || path.isEmpty || name == null || name.isEmpty) {
          return null;
        }
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
