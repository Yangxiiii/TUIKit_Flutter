import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart' hide IconButton;
import 'package:tencent_chat_uikit/src/third_party/extended_text_field/extended_text_field.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';
import 'package:tencent_chat_uikit/src/message_input/widget/rich_content_editor_sheet.dart';
import 'package:tencent_chat_uikit/src/message_input/utils/image_size_reader.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_conversation_manager.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_friendship_manager.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_message_manager.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/enum/offlinePushInfo.dart' as sdk_model;
import 'package:tencent_cloud_chat_sdk/models/v2_tim_msg_create_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

void main() {
  late V2TIMManager original;
  late _Sdk sdk;
  setUp(() {
    original = TencentImSDKPlugin.v2TIMManager;
    sdk = _Sdk();
    TencentImSDKPlugin.v2TIMManager = sdk;
  });
  tearDown(() => TencentImSDKPlugin.v2TIMManager = original);

  Future<void> mount(WidgetTester tester,
          {RichContentAttachmentUploader? uploader,
          ChatMessageReplyConfig? replyConfig,
          bool voicePreview = false}) =>
      tester.pumpWidget(
        MaterialApp(
          builder: AppDialog.init(),
          theme: AppThemeFactory.create(
            const AppNormalColorScheme(),
            Brightness.light,
          ),
          home: Scaffold(
            body: Column(children: [
              const Spacer(),
              MessageInput(
                conversationID: 'c2c_test',
                replyConfig: replyConfig,
                config: ChatMessageInputConfig(
                    actionGuard: ActionGuard(),
                    previewVoiceBeforeSend: voicePreview,
                    enableReadReceipt: false,
                    richContentAttachmentUploader: uploader),
              )
            ]),
          ),
        ),
      );

  Future<void> enter(WidgetTester tester, String text) async {
    if (find.byType(ExtendedTextField).evaluate().isEmpty) {
      await tester.tap(find.textContaining('发送给 '));
      await tester.pump();
    }
    final input =
        tester.widget<ExtendedTextField>(find.byType(ExtendedTextField).first);
    input.controller!.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    await tester.pump();
  }

  Future<String> createPreview(WidgetTester tester) async {
    late Directory directory;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('send_media_');
      await File('${directory.path}/preview.png').writeAsBytes(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOQcHnxHwAEAAJEfJjuTwAAAABJRU5ErkJggg=='));
    });
    addTearDown(() => directory.deleteSync(recursive: true));
    return '${directory.path}/preview.png';
  }

  IconButton sendButton(WidgetTester tester) =>
      tester.widget<IconButton>(find.ancestor(
        of: find.descendant(
            of: find.byKey(const Key('message_input_shared_toolbar')),
            matching: find.byIcon(AppIcons.send1)),
        matching: find.byType(IconButton),
      ));

  testWidgets('单个及多个纯表情调用SDK表情消息，混合正文仍调用文本消息', (tester) async {
    EmojiManager.configure(assetPackage: 'tuikit_atomic_x', emojis: const [
      EmojiPickerModelItem(
          name: '[ZDEmoji_Like]',
          label: '点赞',
          path: 'call_assets/handsfree_on.png'),
      EmojiPickerModelItem(
          name: '[ZDEmoji_Smile]',
          label: '微笑',
          path: 'call_assets/handsfree_on.png'),
    ]);
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    for (final source in [
      '[ZDEmoji_Like]',
      '[ZDEmoji_Like][ZDEmoji_Smile]',
      '你好[ZDEmoji_Like]',
      '[ZDEmoji_Unknown]',
    ]) {
      final faces = sdk.messages.faceMessages.length;
      await enter(tester, source);
      await tester
          .tap(find.bySemanticsIdentifier('tim.message_input_toolbar.send'));
      await tester.pump();
      if (EmojiManager.isOnlyEmojis(source)) {
        expect(sdk.messages.faceMessages.length, faces + 1);
        expect(sdk.messages.faceMessages.last, (index: 0, data: source));
      } else {
        expect(sdk.messages.faceMessages.length, faces);
        expect(sdk.messages.textMessages.last, source);
      }
      sdk.messages.completeSend();
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('纯表情富文本草稿不再编码成自定义富文本消息', (tester) async {
    EmojiManager.configure(assetPackage: 'tuikit_atomic_x', emojis: const [
      EmojiPickerModelItem(
          name: '[ZDEmoji_Like]',
          label: '点赞',
          path: 'call_assets/handsfree_on.png'),
    ]);
    await mount(tester);
    sdk.conversations.completeDraft(const RichContentDraft(
      blocks: [RichContentDraftTextBlock(1, '[ZDEmoji_Like]')],
    ).toPersistedString());
    await tester.pump();
    await tester
        .tap(find.bySemanticsIdentifier('tim.message_input_toolbar.send'));
    await tester.pump();
    expect(sdk.messages.faceMessages, [(index: 0, data: '[ZDEmoji_Like]')]);
    expect(sdk.messages.customData, isEmpty);
    sdk.messages.completeSend();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('权限等待期间松手或离开后，不补启动原生采音', (tester) async {
    // 共享硬件队列属于同一应用会话，两个场景在同一测试Zone中逐次释放。
    for (final leavePage in [false, true]) {
      sdk = _Sdk();
      TencentImSDKPlugin.v2TIMManager = sdk;
      const permissionChannel = MethodChannel('atomic_x/permission');
      const playerChannel = MethodChannel('tencent_chat_uikit/audio_player');
      const recorderChannel =
          MethodChannel('tencent_chat_uikit/audio_recorder');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final permission = Completer<String>();
      var checks = 0;
      var playerCalls = 0;
      var starts = 0;
      messenger.setMockMethodCallHandler(permissionChannel, (_) async {
        checks++;
        return permission.future;
      });
      messenger.setMockMethodCallHandler(playerChannel, (_) async {
        playerCalls++;
        return null;
      });
      messenger.setMockMethodCallHandler(recorderChannel, (call) async {
        if (call.method == 'startRecord') starts++;
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(permissionChannel, null);
        messenger.setMockMethodCallHandler(playerChannel, null);
        messenger.setMockMethodCallHandler(recorderChannel, null);
      });
      await mount(tester, voicePreview: true);
      sdk.conversations.completeDraft('');
      await tester.pump();
      await tester.tap(find.byTooltip('切换语音输入'));
      await tester.pump();
      final gesture = await tester.startGesture(
          tester.getCenter(find.bySemanticsIdentifier('chat.voice.hold')));
      await tester.pumpAndSettle();
      expect(checks, 1, reason: '共享播放器停止调用数：$playerCalls');
      if (leavePage) await tester.pumpWidget(const SizedBox());
      await gesture.up();
      permission.complete('granted');
      await tester.pump(const Duration(seconds: 3));
      expect(starts, 0);
      expect(
          find.bySemanticsIdentifier('chat.voice.preview_text'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('表情与系统键盘在同一区域切换，焦点选区和输入连接持续保留', (tester) async {
    EmojiManager.configure(assetPackage: 'tuikit_atomic_x', emojis: const [
      EmojiPickerModelItem(
          name: '[ZDEmoji_Like]',
          label: '点赞',
          path: 'call_assets/handsfree_on.png'),
    ]);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    await enter(tester, '前中后');
    final field = tester.widget<ExtendedTextField>(
        find.byKey(const Key('message_input_text_field')));
    field.controller!.selection =
        const TextSelection(baseOffset: 1, extentOffset: 2);
    final focus = field.focusNode!;
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    final toolbar = find.byKey(const Key('message_input_shared_toolbar'));
    final top = tester.getRect(toolbar).bottom;
    tester.testTextInput.log.clear();
    await tester.tap(find.byTooltip('表情'));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(field.controller!.selection,
        const TextSelection(baseOffset: 1, extentOffset: 2));
    for (final inset in [200.0, 80.0, 0.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pumpAndSettle();
      expect(tester.getRect(toolbar).bottom, closeTo(top, .01));
    }
    expect(tester.getSize(find.byType(EmojiPicker)).height, 320);
    // 模拟隐藏IME会关闭原生连接的平台，焦点与选区仍须保留，切回时重新建立客户端。
    tester
        .state<ExtendedEditableTextState>(find.byType(ExtendedEditableText))
        .connectionClosed();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(field.controller!.selection,
        const TextSelection(baseOffset: 1, extentOffset: 2));
    final emoji = find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.identifier == 'tim.emoji.insert.[ZDEmoji_Like]');
    await tester.tap(emoji);
    await tester.pumpAndSettle();
    expect(field.controller!.text, '前[ZDEmoji_Like]后');
    expect(field.controller!.selection.baseOffset, 15);
    expect(focus.hasFocus, isTrue);
    expect(
        tester.testTextInput.log.any((call) => call.method == 'TextInput.hide'),
        isTrue);
    expect(
        tester.testTextInput.log.any((call) => call.method == 'TextInput.show'),
        isFalse);
    expect(
        tester.testTextInput.log
            .any((call) => call.method == 'TextInput.clearClient'),
        isFalse);
    await tester.tap(find.byTooltip('显示键盘'));
    await tester.pumpAndSettle();
    for (final inset in [100.0, 200.0, 320.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getRect(toolbar).bottom, closeTo(top, .01));
    }
    expect(find.byType(EmojiPicker), findsNothing);
    expect(
        tester.testTextInput.log.any((call) => call.method == 'TextInput.show'),
        isTrue);
    expect(
        tester.testTextInput.log
            .any((call) => call.method == 'TextInput.clearClient'),
        isFalse);
    expect(focus.hasFocus, isTrue);
    expect(field.controller!.selection.baseOffset, 15);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('空闲区直接打开表情不闪现系统键盘，首次输入没有额外空格', (tester) async {
    EmojiManager.configure(assetPackage: 'tuikit_atomic_x', emojis: const [
      EmojiPickerModelItem(
          name: '[ZDEmoji_Like]',
          label: '点赞',
          path: 'call_assets/handsfree_on.png'),
    ]);
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    tester.testTextInput.log.clear();
    await tester.tap(find.byTooltip('表情'));
    await tester.pumpAndSettle();
    final field = tester.widget<ExtendedTextField>(
        find.byKey(const Key('message_input_text_field')));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(
        tester.testTextInput.log.any((call) => call.method == 'TextInput.show'),
        isFalse);
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.identifier == 'tim.emoji.quick.[ZDEmoji_Like]'));
    await tester.pumpAndSettle();
    expect(field.controller!.text, '[ZDEmoji_Like]');
    expect(field.controller!.selection.baseOffset, 14);
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('媒体加载时收起或重开仍可完成预览，普通输入区删除占位后不被迟到结果复活', (tester) async {
    final path = await createPreview(tester);
    for (final mode in ['normal', 'reopen', 'delete']) {
      var uploads = 0;
      await mount(tester, uploader: (_) async {
        uploads++;
        return 'https://example.com/resource-$uploads';
      });
      if (mode == 'normal') sdk.conversations.completeDraft('');
      await tester.pump();
      await tester.tap(find.byKey(const Key('open_rich_content_editor')));
      await tester.pumpAndSettle();
      final editor = tester.state<RichContentEditorSheetState>(
          find.byType(RichContentEditorSheet));
      final placeholder = editor.beginMediaPreparation(
          AlbumMedia(id: 1, mediaType: AlbumMediaType.video))!;
      final dimensions = Completer<ImageSize?>();
      final preparing = editor.completeMediaPreparation(
          placeholder,
          AlbumMedia(
              id: 1,
              mediaType: AlbumMediaType.video,
              mediaPath: '/tmp/video.mp4',
              videoThumbnailPath: path),
          readSize: (_) => dimensions.future);
      await tester.pump();
      expect(sendButton(tester).onPressed, isNull);
      await tester.tap(find.byTooltip('收起富文本编辑器'));
      await tester.pump();
      final loading = find.bySemanticsIdentifier(
          'tim.rich_content.media_loading.${placeholder.id}');
      expect(loading, findsOneWidget);
      if (mode == 'reopen') {
        await tester.tap(find.byKey(const Key('open_rich_content_editor')));
        await tester.pump();
      } else if (mode == 'delete') {
        final input = tester.widget<ExtendedTextField>(
            find.byKey(const Key('message_input_text_field')));
        final token = richContentAttachmentTokenPattern
            .firstMatch(input.controller!.text)!;
        input.controller!.value = TextEditingValue(
            text:
                input.controller!.text.replaceRange(token.start, token.end, ''),
            selection: TextSelection.collapsed(offset: token.start));
        await tester.pump();
      }
      dimensions.complete(const ImageSize(120, 60));
      await tester.pump();
      await preparing;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(loading, findsNothing);
      expect(uploads, mode == 'delete' ? 0 : 2);
      if (mode == 'delete') {
        expect(find.byIcon(AppIcons.cameraOn), findsNothing);
        expect(sendButton(tester).onPressed, isNull);
      } else {
        expect(find.byIcon(AppIcons.cameraOn), findsOneWidget);
        expect(sendButton(tester).onPressed, isNotNull);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('提前上传图和视频，返回的远端地址超限时保留草稿并禁发', (tester) async {
    final path = await createPreview(tester);
    final imageUrl = 'https://example.com/${'x' * 550}.png';
    final coverUrl = Completer<String>();
    final imageUpload = Completer<String>();
    final videoUrl = Completer<String>();
    final uploads = <RichContentLocalAttachment>[];
    await mount(tester, uploader: (attachment) {
      uploads.add(attachment);
      if (attachment.isVideo) return videoUrl.future;
      if (attachment.mimeType == 'image/*') return coverUrl.future;
      return imageUpload.future;
    });
    sdk.conversations.completeDraft('a' * 9750);
    await tester.pump();
    await tester.tap(find.byKey(const Key('open_rich_content_editor')));
    await tester.pumpAndSettle();
    final editor = tester.state<RichContentEditorSheetState>(
        find.byType(RichContentEditorSheet));
    await editor.insertProcessedMedia(
        AlbumMedia(id: 1, mediaType: AlbumMediaType.image, mediaPath: path),
        readSize: (_) async => const ImageSize(120, 60));
    await editor.insertProcessedMedia(
        AlbumMedia(
            id: 2,
            mediaType: AlbumMediaType.video,
            mediaPath: '/tmp/video.mp4',
            videoThumbnailPath: path),
        readSize: (_) async => const ImageSize(120, 60));
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(uploads, hasLength(2));
    expect(editor.canSend, isFalse);
    expect(find.text('输入内容过长'), findsNothing);

    coverUrl.complete('https://example.com/cover.png');
    await tester.pump();
    expect(uploads.last.isVideo, isTrue);
    videoUrl.complete('https://example.com/video.mp4');
    await tester.pump();
    expect(sdk.messages.created, 0);
    expect(find.text('输入内容过长'), findsNothing);

    // 上传结果跨展开、收起边界后仍更新当前输入，不发布未校验的气泡。
    await tester.tap(find.byTooltip('收起富文本编辑器'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(sendButton(tester).onPressed, isNull);
    imageUpload.complete(imageUrl);
    await tester.pump();
    await tester.pump();
    expect(find.text('输入内容过长'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);
    expect(sdk.messages.created, 0);
    final field = tester.widget<ExtendedTextField>(
        find.byKey(const Key('message_input_text_field')));
    expect(field.controller!.text, contains('a' * 9750));
    await enter(tester, field.controller!.text.replaceFirst('a' * 9750, ''));
    expect(sendButton(tester).onPressed, isNotNull);
    sendButton(tester).onPressed!();
    await tester.pump();
    expect(sdk.messages.created, 1);
    expect(uploads, hasLength(3));
    expect(sdk.messages.customDescriptions.single, 'oarichimage oarichvideo');
    expect(sdk.messages.pushDescriptions.single, isNotEmpty);
    expect(sdk.messages.pushDescriptions.single, isNot(contains('oarich')));
    final message =
        RichContentMessage.tryParse(sdk.messages.customData.single)!;
    final image = message.blocks.whereType<RichImageBlock>().single;
    final video = message.blocks.whereType<RichFileBlock>().single;
    expect(image.url, imageUrl);
    expect(video.url, 'https://example.com/video.mp4');
    expect(video.thumbnailUrl, 'https://example.com/cover.png');
    expect((image.width, image.height), (120, 60));
    expect((video.width, video.height), (120, 60));
    sdk.messages.completeSend();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('上传失败保留富文本，重试取得地址后才允许发送', (tester) async {
    final path = await createPreview(tester);
    var attempts = 0;
    final retry = Completer<String>();
    await mount(tester, uploader: (_) async {
      if (++attempts == 1) throw StateError('模拟上传失败');
      return retry.future;
    });
    sdk.conversations.completeDraft('');
    await tester.pump();
    await tester.tap(find.byKey(const Key('open_rich_content_editor')));
    await tester.pumpAndSettle();
    final editor = tester.state<RichContentEditorSheetState>(
        find.byType(RichContentEditorSheet));
    await editor.insertProcessedMedia(
        AlbumMedia(id: 1, mediaType: AlbumMediaType.image, mediaPath: path),
        readSize: (_) async => const ImageSize(120, 60));
    await tester.pump();
    expect(attempts, 1);
    expect(editor.canSend, isTrue);
    await editor.send();
    await tester.pump();
    expect(attempts, 2);
    expect(editor.canSend, isFalse);
    expect(sdk.messages.created, 0);
    retry.complete('https://example.com/image.png');
    await tester.pump();
    expect(editor.canSend, isTrue);
    expect(sdk.messages.created, 0);
    unawaited(editor.send());
    await tester.pump();
    expect(sdk.messages.created, 1);
    sdk.messages.completeSend();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('撤回文本回填保留已有草稿，迟到加载不能覆盖回填内容', (tester) async {
    await mount(tester);
    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    state.restoreRecalledDraft(const ChatMessageRecallDraft(text: '撤回原文'));
    sdk.conversations.completeDraft('迟到的旧草稿');
    await tester.pump();
    var input =
        tester.widget<ExtendedTextField>(find.byType(ExtendedTextField).first);
    expect(input.controller!.text, '撤回原文');
    input.controller!.text = '正在输入';
    state.restoreRecalledDraft(const ChatMessageRecallDraft(text: '再次回填'));
    await tester.pump();
    input =
        tester.widget<ExtendedTextField>(find.byType(ExtendedTextField).first);
    expect(input.controller!.text, '正在输入\n再次回填');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(sdk.conversations.saved.last, '正在输入\n再次回填');
  });

  testWidgets('富文本撤回回填后保存完整远端文件，原有文字草稿不丢失', (tester) async {
    await mount(tester);
    sdk.conversations.completeDraft('已有草稿');
    await tester.pump();
    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    state.restoreRecalledDraft(ChatMessageRecallDraft(
        richContent: const RichContentMessage([
      RichTextBlock('**原消息**'),
      RichFileBlock(
          'https://example.com/file.pdf', '文档.pdf', 123, 'application/pdf'),
    ]).toCustomData()));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    final draft =
        RichContentDraft.tryParsePersisted(sdk.conversations.saved.last!);
    expect(draft, isNotNull);
    expect(draft!.canSend, isTrue);
    final message = draft.toMessage()!;
    expect(message.plainTextPreview, contains('已有草稿'));
    expect(message.plainTextPreview, contains('**原消息**'));
    expect(message.blocks.whereType<RichFileBlock>().single.url,
        'https://example.com/file.pdf');
    expect(sdk.messages.created, 0);
  });

  testWidgets('撤回原消息后清理输入区引用，不能继续显示原文', (tester) async {
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    final message = MessageInfo(
        msgID: 'quoted',
        messageType: MessageType.text,
        messagePayload: TextMessagePayload(text: '应被清除的引用原文'),
        status: MessageStatus.sendSuccess);
    state.setQuotedMessage(message);
    await tester.pump();
    expect(find.textContaining('应被清除的引用原文'), findsOneWidget);
    message.status = MessageStatus.revoked;
    state.invalidateRecalledQuote([message]);
    await tester.pump();
    expect(find.textContaining('应被清除的引用原文'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('回复卡片共享摘要和输入区，超限显示回复提示且保留正文', (tester) async {
    await mount(tester,
        replyConfig: ChatMessageReplyConfig(
          project: (window, isRevoked) => (quotes: {}, replies: {}),
          openDetails: (context, message, replies, store) {},
          sendError: (_) => (message: '', reset: false),
          canStart: (context, message, count) => true,
          contentTooLongMessage: '回复内容超长',
        ));
    sdk.conversations.completeDraft('');
    await tester.pump();
    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    state.setQuotedMessage(ChatUtil.convertToUIMessage(V2TimMessage.fromJson({
      'message_msg_id': 'quoted',
      'message_conv_id': 'test',
      'message_conv_type': 1,
      'message_status': 2,
      'message_risk_type_identified': 0,
      'message_elem_array': [
        {'elem_type': 0, 'text_elem_content': '被回复的原文'},
      ],
    })
      ..nickName = '原作者'));
    await tester.pump();
    final cancel = find.bySemanticsIdentifier('tim.reply.cancel');
    final input = find.byType(ExtendedTextField);
    expect(
        tester.widget<ExtendedTextField>(input).decoration?.hintText, '发送给原作者');
    expect(
        tester.getBottomLeft(cancel).dy, lessThan(tester.getTopLeft(input).dy));
    expect(find.byKey(const Key('open_rich_content_editor')), findsNothing);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(sendButton(tester).onPressed, isNull);

    final content = '字' * 4001;
    await enter(tester, content);
    await tester.pump();
    expect(find.text('回复内容超长'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);
    await tester.tap(cancel);
    await tester.pump();
    expect(cancel, findsNothing);
    expect(find.byKey(const Key('open_rich_content_editor')), findsOneWidget);
    expect(tester.widget<ExtendedTextField>(input).controller!.text, content);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('富文本展开时文件按钮禁用，收起后恢复普通文件选择', (tester) async {
    final semantics = tester.ensureSemantics();
    var requests = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeFactory.create(
          const AppNormalColorScheme(), Brightness.light),
      home: Scaffold(
        body: Column(children: [
          const Expanded(child: SizedBox()),
          MessageInput(
            conversationID: 'c2c_test',
            config: ChatMessageInputConfig(fileSelector: (_) async {
              requests++;
              return [];
            }),
          ),
        ]),
      ),
    ));
    sdk.conversations.completeDraft('');
    await tester.pump();
    final normalFile =
        find.bySemanticsIdentifier('tim.message_input_toolbar.file');
    expect(normalFile, findsOneWidget);
    expect(
        tester
            .getSemantics(normalFile)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue);
    await tester.tap(normalFile);
    await tester.pump();
    expect(requests, 1);
    await tester.tap(find.byKey(const Key('open_rich_content_editor')));
    await tester.pumpAndSettle();
    final overlayFile =
        find.bySemanticsIdentifier('tim.rich_content_overlay_toolbar.file');
    for (final file in [normalFile, overlayFile]) {
      expect(file, findsOneWidget);
      expect(
          tester
              .getSemantics(file)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isFalse);
    }
    await tester.tap(overlayFile);
    await tester.pump();
    expect(requests, 1);
    await tester.tap(find.byTooltip('收起富文本编辑器'));
    await tester.pumpAndSettle();
    expect(overlayFile, findsNothing);
    expect(
        tester
            .getSemantics(normalFile)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue);
    await tester.tap(normalFile);
    await tester.pump();
    expect(requests, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('聊天输入框移动光标同步嵌套格式，末尾沿用且主动切换有效', (tester) async {
    const source = '**粗体** 普通 ~**~~*组合*~~**~';
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    tester
        .state<MessageInputState>(find.byType(MessageInput))
        .restoreRecalledDraft(ChatMessageRecallDraft(
            richContent: const RichContentMessage([RichTextBlock(source)])
                .toCustomData()));
    await tester.pump();
    await tester.tap(find.byTooltip('文字格式'));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<ExtendedTextField>(find.byType(ExtendedTextField).first)
        .controller!;
    bool selected(String label) =>
        tester
            .widget<IconButton>(find.ancestor(
                of: find.byTooltip(label), matching: find.byType(IconButton)))
            .isSelected ??
        false;
    for (final offset in [3, source.indexOf('体') + 1, source.indexOf(' ')]) {
      controller.selection = TextSelection.collapsed(offset: offset);
      await tester.pump();
      expect(selected('粗体'), isTrue, reason: '光标 $offset');
    }
    for (final offset in [0, source.indexOf('粗')]) {
      controller.selection = TextSelection.collapsed(offset: offset);
      await tester.pump();
      expect(selected('粗体'), isFalse, reason: '格式正文前 $offset');
    }
    controller.selection =
        TextSelection.collapsed(offset: source.indexOf('普') + 1);
    await tester.pump();
    expect(selected('粗体'), isFalse);
    controller.selection =
        TextSelection.collapsed(offset: source.indexOf('组') + 1);
    await tester.pump();
    for (final label in ['粗体', '斜体', '下划线', '删除线']) {
      expect(selected(label), isTrue);
    }
    controller.selection = TextSelection.collapsed(offset: source.indexOf('组'));
    await tester.pump();
    for (final label in ['粗体', '斜体', '下划线', '删除线']) {
      expect(selected(label), isFalse, reason: '嵌套正文前');
    }
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    await tester.tap(find.byTooltip('粗体'));
    await tester.pump();
    expect(selected('粗体'), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('320宽输入与格式工具栏保持可切换且不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('文字格式'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('粗体'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('恢复草稿显示正文但不主动弹出键盘', (tester) async {
    await mount(tester);
    sdk.conversations.completeDraft('原草稿');
    await tester.pump();
    final input =
        tester.widget<ExtendedTextField>(find.byType(ExtendedTextField).first);
    expect(input.controller!.text, '原草稿');
    expect(input.focusNode!.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('迟到的旧草稿不能覆盖新输入且新内容继续保存', (tester) async {
    await mount(tester);
    await enter(tester, '新输入');
    sdk.conversations.completeDraft('旧草稿');
    await tester.pump();
    expect(
      tester
          .widget<ExtendedTextField>(find.byType(ExtendedTextField).first)
          .controller!
          .text,
      '新输入',
    );
    await tester.pump(const Duration(milliseconds: 850));
    expect(sdk.conversations.saved.last, '新输入');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('读取未完成便退出既不清空旧草稿也不操作销毁的输入框', (tester) async {
    await mount(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(sdk.conversations.saved, isEmpty);
    sdk.conversations.completeDraft('仍应保留');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(sdk.conversations.saved, isEmpty);
  });

  testWidgets('草稿读取异常后仍能保存新输入', (tester) async {
    await mount(tester);
    sdk.conversations.pending.completeError(StateError('读取失败'));
    await tester.pump();
    await enter(tester, '读取失败后的新输入');
    await tester.pump(const Duration(milliseconds: 850));
    expect(sdk.conversations.saved.last, '读取失败后的新输入');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('草稿读取失败后直接退出不会把旧草稿清空', (tester) async {
    await mount(tester);
    sdk.conversations.pending.complete(
      V2TimValueCallback<V2TimConversation>(code: 1, desc: '读取失败'),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(sdk.conversations.saved, isEmpty);
  });

  testWidgets('普通消息按UTF-8字节校验，超限保留输入，回退后恢复', (tester) async {
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    await enter(tester, 'a' * 5000);
    expect(sendButton(tester).onPressed, isNotNull);
    final text = '${'字' * 3412}😀';
    await enter(tester, text);
    final send = find.bySemanticsIdentifier('tim.message_input_toolbar.send');
    expect(send, findsOneWidget);
    expect(
        tester
            .getSemantics(send)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue);
    expect(find.bySemanticsIdentifier('tim.input.text'), findsOneWidget);
    await enter(tester, '$text甲');
    await tester.pumpAndSettle();
    expect(
        tester
            .getSemantics(send)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse);
    expect(find.text('输入内容过长'), findsOneWidget);
    expect(
      tester
          .widget<ExtendedTextField>(find.byType(ExtendedTextField).first)
          .controller!
          .text,
      '$text甲',
    );
    final toast = find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.identifier == 'tim.input.text_limit');
    expect(toast, findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(toast, findsNothing);
    final controller = tester
        .widget<ExtendedTextField>(find.byType(ExtendedTextField).first)
        .controller!;
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    await tester.pump();
    expect(toast, findsNothing);
    await enter(tester, '$text甲乙');
    await tester.pumpAndSettle();
    expect(toast, findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await enter(tester, '$text甲');
    await tester.pumpAndSettle();
    expect(toast, findsOneWidget);
    // 表情面板的回调也是实际发送入口，禁用态不能只由按钮外观保证。
    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    await state.getEmojiPanelWidget();
    (state.stickerWidget as EmojiPicker).onSendClick!();
    await tester.pump();
    expect(sdk.messages.created, 0);
    await enter(tester, text);
    expect(
        tester
            .getSemantics(send)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('展开的富文本标题仍超限时，等长替换也再次提示', (tester) async {
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    await tester.tap(find.byKey(const Key('open_rich_content_editor')));
    await tester.pumpAndSettle();
    final editor = tester.state<RichContentEditorSheetState>(
        find.byType(RichContentEditorSheet));
    final title = tester
        .widget<ExtendedTextField>(find.byKey(const Key('rich_content_title')))
        .controller!;
    final prefix = '字' * 3414;
    final toast = find.text('输入内容过长');
    title.text = '$prefix甲';
    await tester.pump();
    await tester.pumpAndSettle();
    expect(toast, findsOneWidget);
    expect(editor.canSend, isFalse);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(toast, findsNothing);
    title.text = '$prefix乙';
    await tester.pump();
    await tester.pumpAndSettle();
    expect(toast, findsOneWidget);
    expect(editor.canSend, isFalse);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('内联富文本重复提交合并，成功不会清掉等待期间新增文字', (tester) async {
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    await enter(tester, '待发送');
    await tester.tap(find.byTooltip('文字格式'));
    await tester.pump(const Duration(milliseconds: 200));
    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    await state.getEmojiPanelWidget();
    final send = (state.stickerWidget as EmojiPicker).onSendClick!;
    send();
    send();
    await tester.pump();
    expect(sdk.messages.created, 1);
    expect(sdk.messages.pending, hasLength(1));
    await enter(tester, '等待期间新输入');
    sdk.messages.completeSend();
    await tester.pump();
    expect(
      tester
          .widget<ExtendedTextField>(find.byType(ExtendedTextField).first)
          .controller!
          .text,
      '等待期间新输入',
    );
    send();
    await tester.pump();
    expect(sdk.messages.created, 2);
    sdk.messages.completeSend();
    await tester.pump();
    expect(
      tester
          .widget<ExtendedTextField>(find.byType(ExtendedTextField).first)
          .controller!
          .text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('发送失败显示精确提示并允许重试', (tester) async {
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    await enter(tester, '失败前输入');
    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    await state.getEmojiPanelWidget();
    final send = (state.stickerWidget as EmojiPicker).onSendClick!;
    send();
    await tester.pump();
    sdk.messages.completeSend(code: 1);
    await tester.pump();
    expect(find.text('消息发送失败'), findsOneWidget);
    await enter(tester, '再次发送');
    send();
    await tester.pump();
    expect(sdk.messages.created, 2);
    sdk.messages.completeSend();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('SDK异常也会释放发送任务并保留重试能力', (tester) async {
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    await enter(tester, '异常前输入');
    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    await state.getEmojiPanelWidget();
    final send = (state.stickerWidget as EmojiPicker).onSendClick!;
    send();
    await tester.pump();
    sdk.messages.pending.removeAt(0).completeError(StateError('模拟SDK异常'));
    await tester.pump();
    expect(find.text('消息发送失败'), findsOneWidget);
    await enter(tester, '异常后重试');
    send();
    await tester.pump();
    expect(sdk.messages.created, 2);
    sdk.messages.completeSend();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class _Sdk implements V2TIMManager {
  final conversations = _Conversations();
  final messages = _Messages();
  final friends = _Friends();

  @override
  dynamic noSuchMethod(Invocation call) => switch (call.memberName) {
        #getConversationManager => conversations,
        #getMessageManager => messages,
        #getFriendshipManager => friends,
        #callExperimentalAPI => Future.value(
            V2TimValueCallback<String>(code: 0, desc: '', data: ''),
          ),
        _ => super.noSuchMethod(call),
      };
}

final class _Conversations implements V2TIMConversationManager {
  Completer<V2TimValueCallback<V2TimConversation>>? _pending;
  // 在Widget测试的异步区域内创建Future，避免结果跨测试回合才回填。
  Completer<V2TimValueCallback<V2TimConversation>> get pending =>
      _pending ??= Completer<V2TimValueCallback<V2TimConversation>>();
  final saved = <String?>[];

  void completeDraft(String draft) => pending.complete(
        V2TimValueCallback(
          code: 0,
          desc: '',
          data: V2TimConversation(
            conversationID: 'c2c_test',
            type: 1,
            userID: 'test',
            showName: '测试会话',
            draftText: draft,
          ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation call) {
    switch (call.memberName) {
      case #getConversation:
        return pending.future;
      case #setConversationDraft:
        saved.add(call.namedArguments[#draftText] as String?);
        return Future.value(V2TimCallback(code: 0, desc: ''));
      case #getTotalUnreadMessageCount:
        return Future.value(
            V2TimValueCallback<int>(code: 0, desc: '', data: 0));
      case #getConversationListByFilter:
        return Future.value(
          V2TimValueCallback<V2TimConversationResult>(
            code: 0,
            desc: '',
            data:
                V2TimConversationResult(isFinished: true, conversationList: []),
          ),
        );
      case #addConversationListener:
      case #removeConversationListener:
        return Future<void>.value();
      default:
        return super.noSuchMethod(call);
    }
  }
}

final class _Messages implements V2TIMMessageManager {
  int created = 0;
  final customData = <String>[];
  final customDescriptions = <String>[];
  final pushDescriptions = <String?>[];
  final textMessages = <String>[];
  final faceMessages = <({int index, String data})>[];
  final pending = <Completer<V2TimValueCallback<V2TimMessage>>>[];

  void completeSend({int code = 0}) => pending.removeAt(0).complete(
        V2TimValueCallback<V2TimMessage>(code: code, desc: ''),
      );

  @override
  dynamic noSuchMethod(Invocation call) {
    switch (call.memberName) {
      case #createTextMessage:
      case #createFaceMessage:
      case #createCustomMessage:
        if (call.memberName == #createTextMessage) {
          textMessages.add(call.namedArguments[#text] as String);
        } else if (call.memberName == #createFaceMessage) {
          faceMessages.add((
            index: call.namedArguments[#index] as int,
            data: call.namedArguments[#data] as String
          ));
        }
        if (call.memberName == #createCustomMessage) {
          customData.add(call.namedArguments[#data] as String);
          customDescriptions.add(call.namedArguments[#desc] as String);
        }
        created++;
        return Future.value(
          V2TimValueCallback<V2TimMsgCreateInfoResult>(
            code: 0,
            desc: '',
            data: V2TimMsgCreateInfoResult(
              messageInfo: _Message('test_$created'),
            ),
          ),
        );
      case #sendMessage:
        pushDescriptions.add((call.namedArguments[#offlinePushInfo]
                as sdk_model.OfflinePushInfo?)
            ?.desc);
        final result = Completer<V2TimValueCallback<V2TimMessage>>();
        pending.add(result);
        return result.future;
      default:
        return super.noSuchMethod(call);
    }
  }
}

final class _Friends implements V2TIMFriendshipManager {
  @override
  dynamic noSuchMethod(Invocation call) => switch (call.memberName) {
        #addFriendListener || #removeFriendListener => Future<void>.value(),
        _ => super.noSuchMethod(call),
      };
}

final class _Message implements V2TimMessage {
  _Message(this.msgID);

  @override
  String? msgID;
  @override
  int? timestamp = 1;
  @override
  bool? isSupportMessageExtension;
  @override
  bool? needReadReceipt;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
