import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_input/message_clipboard.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('复制图文只写可见文字，保留原文、媒体顺序及封面', () async {
    final source = RichContentMessage(const [
      RichTextBlock('**文字** [官网](https://example.com)'),
      RichImageBlock('https://example.com/image.png', 200, 100),
      RichFileBlock(
        'https://example.com/video.mp4',
        'video.mp4',
        10,
        'video/mp4',
        thumbnailUrl: 'https://example.com/cover.png',
        width: 200,
        height: 100,
        videoDuration: 232,
      ),
    ]);
    final copied = CopiedChatMessage.fromMessage(MessageInfo(
      messagePayload: CustomMessagePayload(customData: source.toCustomData()),
    ))!;
    expect(copied.preview, '文字 官网\n[图片]\n[视频]');
    final attachments = <int, RichContentDraftAttachmentBlock>{};
    var id = 5;
    final fragment = richContentClipboardFragment(
        copied.richDraft!, () => ++id, attachments);
    expect(
        fragment,
        '**文字** [官网](https://example.com)'
        '${richContentAttachmentToken(6)}${richContentAttachmentToken(7)}');
    expect(attachments[6]!.remoteUrl, 'https://example.com/image.png');
    expect(attachments[7]!.thumbnailUrl, 'https://example.com/cover.png');
    expect(attachments[7]!.attachment.durationMs, 232000);
    expect(copied.richDraft!.canSend, isTrue);
  });

  test('腾讯历史媒体缺少尺寸时保留附件，系统预览使用媒体占位', () {
    final photo = CopiedChatMessage.fromMessage(MessageInfo(
      messagePayload:
          ImageMessagePayload(originalImageURL: 'https://example.com/a.png'),
    ))!;
    final video = CopiedChatMessage.fromMessage(MessageInfo(
      messagePayload: VideoMessagePayload(
        videoURL: 'https://example.com/v.mp4',
        videoDuration: 232,
      ),
    ))!;
    expect(photo.preview, '[图片]');
    expect(video.preview, '[视频]');
    expect(photo.richDraft!.toMessage()!.blocks.single, isA<RichImageBlock>());
    final restored = RichContentDraft.tryParsePersisted(
        photo.richDraft!.toPersistedString());
    expect(restored?.canSend, isTrue);
    final copiedVideo =
        video.richDraft!.toMessage()!.blocks.single as RichFileBlock;
    expect(copiedVideo.videoDuration, 232);
  });

  test('只匹配完整的纯富文本预览，并替换格式工具条新增的标签', () async {
    const channel = MethodChannel('tencent_chat_uikit');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final message = CopiedChatMessage.fromMessage(MessageInfo(
      messagePayload: TextMessagePayload(text: '*斜体*'),
    ))!;
    await MessageClipboard.copy(message, 'c2c_test');

    const before = TextEditingValue(
      text: '前删后',
      selection: TextSelection(baseOffset: 1, extentOffset: 2),
    );
    const submitted = TextEditingValue(
      text: '前斜体后',
      selection: TextSelection.collapsed(offset: 3),
    );
    const applied = TextEditingValue(
      text: '前**斜体**后',
      selection: TextSelection.collapsed(offset: 5),
    );
    final range =
        MessageClipboard.richPreviewSelection(before, submitted, applied);
    expect(range?.textInside(applied.text), '**斜体**');
    expect(
      MessageClipboard.richPreviewSelection(
        before,
        submitted.copyWith(composing: const TextRange(start: 1, end: 3)),
        applied,
      ),
      isNull,
    );
  });

  test('同名外部剪贴板条目无法还原先前复制的附件', () async {
    const channel = MethodChannel('tencent_chat_uikit');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    String? token;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'writeMessageClipboard') {
        expect(call.arguments['text'], '[图片]');
        expect(
            (call.arguments as Map).keys, unorderedEquals(['text', 'token']));
        token = call.arguments['token'] as String;
        return null;
      }
      return token;
    });

    final copied = CopiedChatMessage.fromMessage(MessageInfo(
      messagePayload:
          ImageMessagePayload(originalImageURL: 'https://example.com/a.png'),
    ))!;
    await MessageClipboard.copy(copied, 'group_example');
    expect((await MessageClipboard.read('group_example'))!.sameConversation,
        isTrue);
    expect((await MessageClipboard.read('group_other'))!.sameConversation,
        isFalse);
    token = null;
    expect(await MessageClipboard.read('group_example'), isNull);
  });

  test('成员匹配支持空格昵称和末尾提及，同名成员降级为普通文本', () {
    expect(
        matchCopiedMentions('请找 @Alex Chen', {
          'alex': {'Alex Chen'},
        }).single.startIndex,
        3);
    expect(
        matchCopiedMentions('@小明 ', {
          'a': {'小明'},
          'b': {'小明'},
        }),
        isEmpty);
  });
}
