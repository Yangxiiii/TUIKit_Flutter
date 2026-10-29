import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:atomic_x_core/impl/message/message_input_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_list_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_action_store_impl.dart';

import 'chat_media_sender.dart';
import 'message_input_config.dart';
import 'rich_content_draft.dart';

/// 本地气泡持有完整发送任务，上传与 SDK 发送共用发送态；收起或销毁输入框不丢失任务。
/// 本地路径只保存在内存草稿，继承的 customData 始终为空，不能作为远端消息发送。
/// shortcut: 任务与现有文件上传一样只在内存中保存，需要跨应用重启恢复时接入持久化队列。
final class PendingRichContentMessage extends CustomMessagePayload {
  PendingRichContentMessage({
    required RichContentDraft draft,
    required String conversationID,
    required SendMessageOption option,
    required ActionGuard guard,
    required MessageInputStore store,
    RichContentAttachmentUploader? uploader,
    ChatMediaSender? mediaSender,
  })  : _draft = draft,
        _conversationID = conversationID,
        _option = option,
        _guard = guard,
        _store = store,
        _uploader = uploader,
        _mediaSender = mediaSender {
    final user = LoginStore.shared.loginState.loginUserInfo;
    _accountID = user?.userID ?? '';
    message = MessageInfo(
      msgID:
          'oa_rich_${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(this)}',
      status: MessageStatus.sending,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      isSentBySelf: true,
      from: MessageSenderInfo(
        userID: _accountID,
        nickname: user?.nickname ?? '',
        avatarURL: user?.avatarURL ?? '',
      ),
      messageType: MessageType.custom,
      messagePayload: this,
      atUserList: option.atUserList ?? const [],
      needReadReceipt: option.needReadReceipt,
      quoteInfo: option.quotedMessage == null
          ? null
          : MessageQuoteInfo(
              msgID: option.quotedMessage!.msgID,
              timestamp: option.quotedMessage!.timestamp ?? 0,
              sequence: option.quotedMessage!.sequence ?? 0,
              sender: option.quotedMessage!.from,
              messageType: option.quotedMessage!.messageType,
              messagePayload: option.quotedMessage!.messagePayload,
            ),
    );
  }

  /// 最新上传结果保留在任务中，失败重试不重复上传已成功的媒体或封面。
  RichContentDraft _draft;

  /// 本地展示数据；只有上传后的 toMessage 结果可以进入 SDK。
  RichContentDraft get draft => _draft;

  /// 占位与重试共用同一消息 ID，SDK 创建真实消息后才删除这一行。
  late final MessageInfo message;

  /// 发送绑定创建任务时的账号，切换账号后禁止继续发送旧草稿。
  late final String _accountID;
  final String _conversationID;

  /// 引用、回执、提及及推送均固定为点击发送时的选项。
  final SendMessageOption _option;
  final ActionGuard _guard;
  final MessageInputStore _store;
  final RichContentAttachmentUploader? _uploader;
  final ChatMediaSender? _mediaSender;

  /// 立即发布本地气泡，后台执行上传与发送；失败保留气泡供用户重试。
  void start() {
    unawaited(send());
  }

  /// 气泡重试合并到同一任务；上传全部完成后只发送一份远端自定义消息。
  Future<CompletionHandler> send() => _guard.singleFlight(
        'tim.rich-send:${message.msgID}',
        () async {
          MessageInfo? actualMessage;
          try {
            _checkAccount();
            message.status = MessageStatus.sending;
            _notify(MessageSendNotifyKey.messageSendBegin, message);
            // 按正文顺序上传，阶段结果立即写回任务，后续失败仍能复用成功资源。
            for (var i = 0; i < _draft.blocks.length; i++) {
              final block = _draft.blocks[i];
              if (block is! RichContentDraftAttachmentBlock ||
                  block.isReadyToSend) {
                continue;
              }
              await _upload(i, block);
              _checkAccount();
            }
            final content = _draft.toMessage();
            if (content == null) throw StateError('消息内容尚未就绪');
            final payload = CustomSendMessagePayload(
              customData: content.toCustomData(),
              description: _option.offlinePushInfo?.description,
              extensionInfo: message.msgID,
            );
            // SDK 发出真实气泡的开始通知后交接占位，上传与实际发送之间不出现空窗或重复行。
            final result = await sendChatMedia(
              message: MessageInfo(
                  messageType: MessageType.custom,
                  messagePayload:
                      CustomMessagePayload(customData: payload.customData)),
              payload: payload,
              option: _option,
              conversationID: _conversationID,
              store: _store,
              sender: _mediaSender,
              onMessageCreated: (actual) {
                actualMessage = actual;
                _removePlaceholder();
              },
            );
            if (!result.isSuccess) {
              // SDK 已接管的普通失败已发布通知，不能重复发布同一次失败。
              if (actualMessage != null) return result;
              throw StateError(result.errorMessage ?? '消息发送失败');
            }
            _removePlaceholder();
            return result;
          } on Object catch (error) {
            // SDK 尚未接管时，保留本地内容和上传进度；接管后由真实失败消息走原有重发流程。
            final failed = actualMessage ?? message;
            failed.status = MessageStatus.sendFail;
            _notify(MessageSendNotifyKey.messageSendFailed, failed);
            return CompletionHandler()
              ..errorCode = -1
              ..errorMessage = error.toString();
          }
        },
      );

  /// 视频先传封面再传本体；每次成功都更新快照，重试只处理缺少的远端地址。
  Future<void> _upload(int index, RichContentDraftAttachmentBlock block) async {
    final uploader = _uploader;
    if (uploader == null) throw StateError('媒体上传服务不可用');
    final attachment = block.attachment;
    // 封面先就绪并单独保留，视频本体失败后无需再次上传同一封面。
    if (attachment.isVideo &&
        attachment.thumbnailPath != null &&
        !isValidRichContentUrl(block.thumbnailUrl)) {
      final file = File(attachment.thumbnailPath!);
      final url = await uploader(RichContentLocalAttachment(
        type: RichContentAttachmentType.image,
        localPath: file.path,
        fileName: file.uri.pathSegments.last,
        fileSize: await file.length(),
        mimeType: 'image/*',
        width: attachment.width,
        height: attachment.height,
      ));
      if (!isValidRichContentUrl(url)) throw StateError('视频封面上传失败');
      block = block.copyWith(thumbnailUrl: url);
      _replaceBlock(index, block);
    }
    _checkAccount();
    // 上传返回合法远端 URL 后才标记附件可编码，原始本地路径始终留在任务内。
    final url = await uploader(attachment);
    if (!isValidRichContentUrl(url)) throw StateError('媒体上传失败');
    _replaceBlock(
        index,
        block.copyWith(
            remoteUrl: url, status: RichContentAttachmentStatus.uploaded));
  }

  /// 每个成功阶段替换不可变草稿，失败重试继续使用同一份进度。
  void _replaceBlock(int index, RichContentDraftAttachmentBlock block) {
    final blocks = [..._draft.blocks];
    blocks[index] = block;
    _draft = RichContentDraft(
        title: _draft.title, blocks: List.unmodifiable(blocks));
  }

  /// 异步边界重新校验账号，禁止切换账号后继续发送之前选中的附件。
  void _checkAccount() {
    if ((LoginStore.shared.loginState.loginUserInfo?.userID ?? '') !=
        _accountID) {
      throw StateError('发送账号已变更');
    }
  }

  void _notify(String key, MessageInfo value) => notificationCenter.post(key,
      MessageSendEventData(conversationID: _conversationID, message: value));

  /// 仅删除本地占位行，SDK 消息仍由原有消息列表状态维护。
  void _removePlaceholder() => notificationCenter.post(
      MessageActionNotifyKey.messageDelete,
      MessageDeleteEventData(messageIDList: [message.msgID]));
}
