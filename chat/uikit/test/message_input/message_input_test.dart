import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart' hide IconButton;
import 'package:tencent_chat_uikit/src/third_party/extended_text_field/extended_text_field.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';
import 'package:tencent_chat_uikit/src/message_input/pending_rich_content_message.dart';
import 'package:atomic_x_core/impl/message/message_input_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_list_store_impl.dart';
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
          {RichContentAttachmentUploader? uploader}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppThemeFactory.create(
            const AppNormalColorScheme(),
            Brightness.light,
          ),
          home: Scaffold(
            body: Column(children: [
              const Spacer(),
              MessageInput(
                conversationID: 'c2c_test',
                config: ChatMessageInputConfig(
                    actionGuard: ActionGuard(),
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

  testWidgets('媒体加载时收起或重开仍可完成预览，普通输入区删除占位后不被迟到结果复活', (tester) async {
    final path = await createPreview(tester);
    for (final mode in ['normal', 'reopen', 'delete']) {
      await mount(tester, uploader: (_) async => throw StateError('不应提前上传'));
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
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
      expect(find.byType(CircularProgressIndicator), findsNothing);
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

  testWidgets('插入媒体只预览，点击发送后才上传全部资源并发送一次消息', (tester) async {
    final path = await createPreview(tester);
    for (final mode in [
      'normal',
      'expanded',
      'dispose_during',
      'edit_during'
    ]) {
      final local = <PendingRichContentMessage>[];
      final subscription = notificationCenter.addListener<MessageSendEventData>(
          MessageSendNotifyKey.messageSendBegin, (event) {
        if ((event.message as MessageInfo).messagePayload
            case final PendingRichContentMessage pending) {
          local.add(pending);
        }
      });
      final uploads = <RichContentLocalAttachment>[];
      final results = List.generate(3, (_) => Completer<String>());
      final createdBefore = sdk.messages.created;
      await mount(tester, uploader: (attachment) {
        uploads.add(attachment);
        return results[uploads.length - 1].future;
      });
      if (mode == 'normal') sdk.conversations.completeDraft('');
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
      expect(uploads, isEmpty);
      expect(editor.canSend, isTrue);
      await tester.pump();
      if (mode == 'normal' || mode == 'edit_during') {
        await tester.tap(find.byTooltip('收起富文本编辑器'));
        await tester.pumpAndSettle();
        final submit = sendButton(tester).onPressed!;
        submit();
        submit();
      } else {
        unawaited(editor.send());
        unawaited(editor.send());
      }
      await tester.pump();
      expect(uploads, hasLength(1));
      expect(sdk.messages.created, createdBefore);
      expect(sendButton(tester).onPressed, isNull);
      expect(local, hasLength(1));
      expect(local.single.message.status, MessageStatus.sending);
      expect(find.byType(RichContentEditorSheet), findsNothing);
      if (mode == 'dispose_during') {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      String? edited;
      if (mode == 'edit_during') {
        edited = '发送期间新增';
        await enter(tester, edited);
        expect(sendButton(tester).onPressed, isNotNull);
      }
      results[0].complete('https://example.com/image.png');
      await tester.pump();
      // 封面只读取本地文件元数据，让真实文件 IO 在异步测试区完成。
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(uploads, hasLength(2));
      expect(sdk.messages.created, createdBefore);
      results[1].complete('https://example.com/cover.png');
      await tester.pump();
      expect(uploads, hasLength(3));
      expect(uploads.last.isVideo, isTrue);
      expect(sdk.messages.created, createdBefore);
      results[2].complete('https://example.com/video.mp4');
      await tester.pump();
      expect(sdk.messages.created, createdBefore + 1);
      final message =
          RichContentMessage.tryParse(sdk.messages.customData.last)!;
      expect(message.blocks.whereType<RichImageBlock>().single.url,
          'https://example.com/image.png');
      expect(message.blocks.whereType<RichFileBlock>().single.thumbnailUrl,
          'https://example.com/cover.png');
      sdk.messages.completeSend();
      await tester.pumpAndSettle();
      expect(find.byType(RichContentEditorSheet), findsNothing);
      final field = find.byKey(const Key('message_input_text_field'));
      if (field.evaluate().isNotEmpty) {
        expect(tester.widget<ExtendedTextField>(field).controller!.text,
            edited ?? '');
      } else if (mode != 'dispose_during') {
        expect(edited, isNull);
        expect(find.textContaining('发送给 '), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(subscription.cancel());
      await tester.pump();
    }
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

  testWidgets('4000字符可发、4001禁发并保留输入，回退后恢复', (tester) async {
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    final text = '${'字' * 3999}😀';
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
    expect(
      tester
          .getSemantics(find.bySemanticsIdentifier('tim.input.text'))
          .getSemanticsData()
          .hasAction(SemanticsAction.setText),
      isTrue,
    );
    await enter(tester, '$text甲');
    await tester.pump();
    expect(
        tester
            .getSemantics(send)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse);
    expect(find.text('字数超出限制无法发送'), findsOneWidget);
    expect(
      tester
          .widget<ExtendedTextField>(find.byType(ExtendedTextField).first)
          .controller!
          .text,
      '$text甲',
    );
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
  final pending = <Completer<V2TimValueCallback<V2TimMessage>>>[];

  void completeSend({int code = 0}) => pending.removeAt(0).complete(
        V2TimValueCallback<V2TimMessage>(code: code, desc: ''),
      );

  @override
  dynamic noSuchMethod(Invocation call) {
    switch (call.memberName) {
      case #createTextMessage:
      case #createCustomMessage:
        if (call.memberName == #createCustomMessage) {
          customData.add(call.namedArguments[#data] as String);
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
