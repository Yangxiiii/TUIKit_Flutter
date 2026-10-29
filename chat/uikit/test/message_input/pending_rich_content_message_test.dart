import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:atomic_x_core/impl/message/message_input_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_list_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_action_store_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_chat_uikit/src/message_input/message_input_config.dart';
import 'package:tencent_chat_uikit/src/message_input/pending_rich_content_message.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_resender.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_status_mixin.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/custom_message_widget.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('上传前即有本地媒体气泡，上传和 SDK 发送全程复用转圈，交接后只有一行', (tester) async {
    late Directory directory;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('pending_rich_');
      await File('${directory.path}/preview.png').writeAsBytes(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOQcHnxHwAEAAJEfJjuTwAAAABJRU5ErkJggg=='));
    });
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/preview.png';
    final input = _Input();
    final upload = Completer<String>();
    final rows = _LocalRows();
    addTearDown(rows.dispose);
    final option = SendMessageOption(
        atUserList: ['peer'],
        needReadReceipt: true,
        quotedMessage: MessageInfo(msgID: 'quoted'),
        offlinePushInfo: OfflinePushInfo(description: '发送正文'));
    final task = PendingRichContentMessage(
      draft: RichContentDraft(title: '标题', blocks: [
        const RichContentDraftTextBlock(0, '发送正文'),
        RichContentDraftAttachmentBlock(1,
            attachment: RichContentLocalAttachment(
              type: RichContentAttachmentType.image,
              localPath: path,
              fileName: 'preview.png',
              fileSize: 1,
              mimeType: 'image/png',
              width: 120,
              height: 60,
            )),
      ]),
      conversationID: 'c2c_peer',
      option: option,
      guard: ActionGuard(),
      store: input,
      uploader: (_) => upload.future,
    );
    final first = task.send();
    expect(identical(first, task.send()), isTrue);
    await tester.pump();
    expect(rows.messages.values.single, same(task.message));
    expect(input.payloads, isEmpty);
    expect(task.customData, isEmpty);
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeFactory.create(
          const AppNormalColorScheme(), Brightness.light),
      home: Scaffold(body: _Bubble(task.message)),
    ));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('发送正文'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);

    upload.complete('https://example.com/image.png');
    await tester.pump();
    expect(rows.messages, hasLength(1));
    expect(rows.messages.values.single, same(input.actual));
    expect(input.actual!.status, MessageStatus.sending);
    expect(input.options.single, same(option));
    expect(input.payloads.single.customData, isNot(contains(path)));
    expect(RichContentMessage.tryParse(input.payloads.single.customData),
        isNotNull);
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: _Bubble(input.actual!))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    input.complete();
    await tester.pump();
    expect((await tester.runAsync(() => first))!.isSuccess, isTrue);
    await tester.pump();
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: _Bubble(input.actual!))));
    expect(rows.messages, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(input.actual!.status, MessageStatus.sendSuccess);
  });

  test('视频上传失败保留原气泡，重复重试合并且复用已上传封面', () async {
    final directory = await Directory.systemTemp.createTemp('pending_cover_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final cover = await File('${directory.path}/cover.png').writeAsBytes([1]);
    final input = _Input();
    final rows = _LocalRows();
    addTearDown(rows.dispose);
    var covers = 0;
    var videos = 0;
    final retryUpload = Completer<String>();
    final task = PendingRichContentMessage(
      draft: RichContentDraft(blocks: [
        RichContentDraftAttachmentBlock(1,
            attachment: RichContentLocalAttachment(
              type: RichContentAttachmentType.file,
              localPath: '/tmp/video.mp4',
              fileName: 'video.mp4',
              fileSize: 1,
              mimeType: 'video/mp4',
              thumbnailPath: cover.path,
            ))
      ]),
      conversationID: 'c2c_peer',
      option: SendMessageOption(),
      guard: ActionGuard(),
      store: input,
      uploader: (attachment) async {
        if (!attachment.isVideo) {
          covers++;
          return 'https://example.com/cover.png';
        }
        videos++;
        if (videos == 1) throw StateError('模拟上传失败');
        return retryUpload.future;
      },
    );
    expect((await task.send()).isSuccess, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(rows.messages.values.single, same(task.message));
    expect(task.message.status, MessageStatus.sendFail);
    expect(input.payloads, isEmpty);
    final retry = MessageResender.resend(
        message: task.message, conversationID: 'c2c_peer');
    final duplicate = MessageResender.resend(
        message: task.message, conversationID: 'c2c_peer');
    await Future<void>.delayed(Duration.zero);
    expect(task.message.status, MessageStatus.sending);
    expect(covers, 1);
    expect(videos, 2);
    retryUpload.complete('https://example.com/video.mp4');
    await Future<void>.delayed(Duration.zero);
    expect(input.payloads, hasLength(1));
    expect(rows.messages, hasLength(1));
    final video = RichContentMessage.tryParse(input.payloads.single.customData)!
        .blocks
        .whereType<RichFileBlock>()
        .single;
    expect(video.thumbnailUrl, 'https://example.com/cover.png');
    input.complete();
    await Future.wait([retry, duplicate]);
    expect(rows.messages.values.single.status, MessageStatus.sendSuccess);
  });

  test('上传完成后 SDK 创建失败保留本地气泡，重试不重传资源，SDK 发送失败交给真实失败行', () async {
    final input = _Input()..failCreation = true;
    final rows = _LocalRows();
    addTearDown(rows.dispose);
    var uploads = 0;
    final task = PendingRichContentMessage(
      draft: const RichContentDraft(blocks: [
        RichContentDraftAttachmentBlock(1,
            attachment: RichContentLocalAttachment(
                type: RichContentAttachmentType.image,
                localPath: '/tmp/image.png',
                fileName: 'image.png',
                fileSize: 1,
                mimeType: 'image/png'))
      ]),
      conversationID: 'c2c_peer',
      option: SendMessageOption(),
      guard: ActionGuard(),
      store: input,
      uploader: (_) async {
        uploads++;
        return 'https://example.com/image.png';
      },
    );
    expect((await task.send()).isSuccess, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(rows.messages.values.single, same(task.message));
    expect(task.message.status, MessageStatus.sendFail);
    input.failCreation = false;
    final retry = task.send();
    await Future<void>.delayed(Duration.zero);
    expect(uploads, 1);
    expect(rows.messages.values.single, same(input.actual));
    input.complete(code: 1);
    expect((await retry).isSuccess, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(rows.messages, hasLength(1));
    expect(rows.messages.values.single, same(input.actual));
    expect(input.actual!.status, MessageStatus.sendFail);
    expect(rows.messages.containsKey(task.message.msgID), isFalse);
  });
}

/// 以真实通知协议模拟 SDK 产生真实消息及异步完成，上传前不接受本地负载。
class _Input implements MessageInputStore {
  final payloads = <CustomSendMessagePayload>[];
  final options = <SendMessageOption?>[];
  Completer<CompletionHandler>? result;
  MessageInfo? actual;
  bool failCreation = false;

  @override
  Future<CompletionHandler> sendMessage(
      {required SendMessagePayload payload, SendMessageOption? option}) {
    payloads.add(payload as CustomSendMessagePayload);
    options.add(option);
    if (failCreation) return Future.value(CompletionHandler()..errorCode = 1);
    actual = MessageInfo(
        msgID: 'sdk_${payloads.length}',
        status: MessageStatus.sending,
        isSentBySelf: true,
        messageType: MessageType.custom,
        messagePayload: CustomMessagePayload(
            customData: payload.customData,
            extensionInfo: payload.extensionInfo));
    notificationCenter.post(MessageSendNotifyKey.messageSendBegin,
        MessageSendEventData(conversationID: 'c2c_peer', message: actual));
    result = Completer<CompletionHandler>();
    return result!.future;
  }

  void complete({int code = 0}) {
    actual!.status =
        code == 0 ? MessageStatus.sendSuccess : MessageStatus.sendFail;
    notificationCenter.post(
        code == 0
            ? MessageSendNotifyKey.messageSendSuccess
            : MessageSendNotifyKey.messageSendFailed,
        MessageSendEventData(conversationID: 'c2c_peer', message: actual));
    result!.complete(CompletionHandler()..errorCode = code);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 复用消息列表的通知增删规则，断言占位和真实消息交接后始终只有一行。
class _LocalRows {
  final messages = <String, MessageInfo>{};
  final subscriptions = <StreamSubscription>[];
  _LocalRows() {
    for (final key in [
      MessageSendNotifyKey.messageSendBegin,
      MessageSendNotifyKey.messageSendSuccess,
      MessageSendNotifyKey.messageSendFailed
    ]) {
      subscriptions.add(
          notificationCenter.addListener<MessageSendEventData>(key, (event) {
        if (event.conversationID == 'c2c_peer') {
          final message = event.message as MessageInfo;
          messages[message.msgID] = message;
        }
      }));
    }
    subscriptions.add(notificationCenter.addListener<MessageDeleteEventData>(
        MessageActionNotifyKey.messageDelete, (event) {
      for (final id in event.messageIDList) {
        messages.remove(id);
      }
    }));
  }
  void dispose() {
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}

/// 使用现有消息状态组件验证本地媒体预览与转圈，远端消息只检查状态以避免真实网络。
class _Bubble extends StatelessWidget with MessageStatusMixin {
  const _Bubble(this.message);
  final MessageInfo message;
  @override
  Widget build(BuildContext context) => Column(children: [
        if (message.messagePayload is PendingRichContentMessage)
          CustomMessageWidget(message: message, isSelf: true, maxWidth: 400),
        if (buildOutsideBubbleStatusIndicator(
                message: message, colorsTheme: SemanticColorScheme.of(context))
            case final Widget status)
          status,
      ]);
}
