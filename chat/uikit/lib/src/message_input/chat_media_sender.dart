import 'dart:io';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:atomic_x_core/impl/message/message_action_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_input_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_list_store_impl.dart';
import 'package:flutter/widgets.dart';
import '../message_list/utils/big_file_message.dart';

/// 由宿主统一处理媒体分流，SDK原生发送能力通过请求对象提供。
typedef ChatMediaSender = Future<CompletionHandler> Function(
    ChatMediaSendRequest request);

/// 选择器交还独立文件消息，不包含富文本草稿。
typedef ChatFileSelector = Future<List<MessageInfo>> Function(
    BuildContext context);

/// 文件类型图片由宿主提供，UIKit不反向依赖业务资源包。
typedef ChatFileIconBuilder = Widget Function(
    BuildContext context, String fileName);

/// 宿主把业务文件下载到当前账号的托管目录，再交还可打开的本地路径。
typedef ChatFileDownloader = Future<String> Function(BigFileMessage file);

/// 仅可靠的404/410资源失效结果使用此错误，权限失败和断网不进入失效终态。
final class ChatFileExpiredException implements Exception {
  const ChatFileExpiredException();
}

/// 用消息类型确定传输通道，扩展名只参与图标和MIME展示。
enum ChatMediaKind {
  image('IMAGE', 28 * 1024 * 1024),
  audio('SOUND', 28 * 1024 * 1024),
  video('VIDEO', 100 * 1024 * 1024),
  file('FILE', 100 * 1024 * 1024);

  const ChatMediaKind(this.fileType, this.nativeLimitBytes);

  /// 后端直传接口的文件类型值。
  final String fileType;

  /// 腾讯原生消息允许的字节上限，等于上限仍走原生API。
  final int nativeLimitBytes;
}

/// 校验后的本地上传源，只在发送边界从实际文件读取大小。
final class ChatLocalMedia {
  const ChatLocalMedia(
      {required this.kind,
      required this.path,
      required this.name,
      required this.size});

  /// 按待发送消息确定的类型，不能由文件扩展名改写。
  final ChatMediaKind kind;

  /// 当前账号可读的本地文件路径，不进入自定义消息。
  final String path;

  /// 原始文件名，优先使用普通文件负载提供的名称。
  final String name;

  /// 发送前stat得到的实际字节数。
  final int size;

  /// 后端直传统一业务上限；服务端仍保留最终校验。
  static const maxBytes = 10 * 1024 * 1024 * 1024;
  bool get needsDirectUpload => size > kind.nativeLimitBytes;

  /// 文本和其他自定义消息不参与媒体分流；媒体必须是可读的普通文件。
  static Future<ChatLocalMedia?> read(MessagePayload? payload) async {
    final (kind, path, name) = switch (payload) {
      ImageMessagePayload p => (ChatMediaKind.image, p.originalImagePath, null),
      AudioMessagePayload p => (ChatMediaKind.audio, p.audioPath, null),
      VideoMessagePayload p => (ChatMediaKind.video, p.videoPath, null),
      FileMessagePayload p => (ChatMediaKind.file, p.filePath, p.fileName),
      _ => (null, null, null),
    };
    if (kind == null) return null;
    if (path == null || path.isEmpty) throw const FileSystemException('文件不可用');
    final stat = await FileStat.stat(path);
    if (stat.type == FileSystemEntityType.directory) {
      throw const FileSystemException('不支持发送文件夹，请先压缩。');
    }
    if (stat.type != FileSystemEntityType.file) {
      throw const FileSystemException('文件不可用');
    }
    if (stat.size > maxBytes) throw const FileSystemException('文件超过10G，无法发送。');
    return ChatLocalMedia(
        kind: kind,
        path: path,
        name: name?.trim().isNotEmpty == true
            ? name!
            : File(path).uri.pathSegments.last,
        size: stat.size);
  }
}

/// 实际发给SDK时可观察生成的真实消息，用于原子替换本地上传占位。
typedef ChatPayloadSender = Future<CompletionHandler> Function(
    SendMessagePayload payload,
    {void Function(MessageInfo message)? onCreated});

/// 保存发送参数与列表通知回调，宿主无需引用AtomicX内部通知实现。
final class ChatMediaSendRequest {
  const ChatMediaSendRequest(
      {required this.message,
      required this.payload,
      required this.option,
      required this.send,
      required this.showLocalMessage,
      required this.removeLocalMessage,
      this.onRetryFailure});

  /// 原始待发消息，用于区分图片、语音、视频与普通文件。
  final MessageInfo message;

  /// 未超限时原样交还腾讯SDK的负载。
  final SendMessagePayload payload;

  /// 引用、回执与推送配置，上传完成后仍须保留。
  final SendMessageOption option;

  /// 使用相同会话和选项发送实际负载。
  final ChatPayloadSender send;

  /// 重试失败后的单次UI反馈，由当前输入页检查mounted后执行。
  final VoidCallback? onRetryFailure;

  /// 插入或更新仅本地可见的上传占位消息。
  final void Function(MessageInfo message) showLocalMessage;

  /// 上传消息交接给SDK真实消息时删除占位，避免重复行。
  final void Function(String messageId) removeLocalMessage;
}

/// 会话Controller提供的不可变上传视图，进度与重试不由消息Widget单独保存。
final class ChatFileTransferView {
  const ChatFileTransferView(
      {this.progress,
      this.failed = false,
      this.interrupted = false,
      this.retry});

  /// 上传进度，0到1；申请凭证或登记时为null。
  final double? progress;

  /// 失败卡片可通过retry恢复原任务。
  final bool failed;

  /// 会话清理等主动中断区别于普通失败。
  final bool interrupted;

  /// 重试同一上传任务，已登记对象不会重复上传。
  final Future<CompletionHandler> Function()? retry;
}

/// 普通发送与失败重发共用宿主分流入口，原生通知只在 UIKit 边界使用。
/// onMessageCreated 在 SDK 发布真实消息时回调，用于交接上传阶段的本地气泡。
Future<CompletionHandler> sendChatMedia(
    {required MessageInfo message,
    required SendMessagePayload payload,
    required SendMessageOption option,
    required String conversationID,
    ChatMediaSender? sender,
    MessageInputStore? store,
    Future<void> Function()? beforeSend,
    void Function(MessageInfo message)? onMessageCreated,
    VoidCallback? onRetryFailure}) {
  final input =
      store ?? MessageInputStore.create(conversationID: conversationID);

  /// 仅上传占位交接或失败重发需要监听真实消息，其余发送沿用SDK路径。
  Future<CompletionHandler> observedSend(SendMessagePayload next,
      void Function(MessageInfo message)? onCreated) async {
    // 失败旧行仅在校验与上传均通过后删除，不能因本地源不可读丢失失败记录。
    if (beforeSend != null) await beforeSend();
    final subscription = notificationCenter.addListener<MessageSendEventData>(
        MessageSendNotifyKey.messageSendBegin, (event) {
      final actual = event.message.messagePayload;
      if (event.conversationID == conversationID &&
          next is CustomSendMessagePayload &&
          actual is CustomMessagePayload &&
          actual.customData == next.customData &&
          actual.extensionInfo == next.extensionInfo) {
        onCreated?.call(event.message);
      }
    });
    try {
      return await input.sendMessage(payload: next, option: option);
    } finally {
      await subscription.cancel();
    }
  }

  Future<CompletionHandler> send(SendMessagePayload next,
      {void Function(MessageInfo message)? onCreated}) {
    if (next is CustomSendMessagePayload &&
        BigFileMessage.tryParse(next.customData) != null) {
      option.offlinePushInfo?.description = '[文件]';
    }
    // 普通发送不注册观察者，也不增加异步阶段，保留SDK原有完成与错误回调时序。
    if (beforeSend == null && onCreated == null && onMessageCreated == null) {
      return input.sendMessage(payload: next, option: option);
    }
    return observedSend(next, (message) {
      onMessageCreated?.call(message);
      onCreated?.call(message);
    });
  }

  if (sender == null) return send(payload);
  return sender(ChatMediaSendRequest(
    message: message,
    payload: payload,
    option: option,
    send: send,
    onRetryFailure: onRetryFailure,
    showLocalMessage: (local) => notificationCenter.post(
        MessageSendNotifyKey.messageSendBegin,
        MessageSendEventData(conversationID: conversationID, message: local)),
    removeLocalMessage: (id) => notificationCenter.post(
        MessageActionNotifyKey.messageDelete,
        MessageDeleteEventData(messageIDList: [id])),
  ));
}
