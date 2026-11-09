import '../fixtures/emoji_fixture.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_input/message_text.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';

void main() {
  setUp(configureEmojiFixture);
  test('可见字素、SDK表情和换行使用同一计数口径', () {
    expect(messageTextCharacterCount('汉😀👍🏽👨‍👩‍👧‍👦'), 4);
    expect(messageTextCharacterCount('[ZDEmoji_Smile]\r\n好\n'), 4);
    expect(messageTextCharacterCount('[ZDEmoji_unknown]'), 17);
  });

  test('普通文本按UTF-8计数，富文本按实际JSON计入标题和转义', () {
    expect(messageTextByteCount('${'字' * 3412}😀'), 10240);
    final template = RichContentDraft(
      title: '标题',
      blocks: const [RichContentDraftTextBlock(1, '**正文**\n"')],
    );
    final overhead = messageTextByteCount(template.toMessage()!.toCustomData());
    final body = '**正文**\n"${'a' * (10240 - overhead)}';
    final draft = RichContentDraft(
      title: '标题',
      blocks: [RichContentDraftTextBlock(1, body)],
    );
    expect(messageTextByteCount(draft.toMessage()!.toCustomData()), 10240);
    expect(draft.byteCount, 10240);
    final tooLong = RichContentDraft(
      title: draft.title,
      blocks: [RichContentDraftTextBlock(1, '${body}a')],
    );
    expect(tooLong.byteCount, 10241);
    expect(tooLong.toMessage(), isNull);
  });

  test('有格式的纯空白仍不可发送', () {
    expect(
      const RichContentDraft(
        blocks: [RichContentDraftTextBlock(1, '** **\n\r\n')],
      ).canSend,
      isFalse,
    );
  });

  test('退格完整删除原生组合表情和SDK令牌并正确放置光标', () {
    for (final character in ['😀', '👍🏽', '👨‍👩‍👧‍👦', '[ZDEmoji_Smile]']) {
      final value = TextEditingValue(
        text: '甲$character乙',
        selection: TextSelection.collapsed(offset: 1 + character.length),
      );
      final result = deleteMessageCharacterBefore(value);
      expect(result.text, '甲乙');
      expect(result.selection.baseOffset, 1);
    }
    final inside = deleteMessageCharacterBefore(
      const TextEditingValue(
        text: '甲😀乙',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    expect(inside.text, '甲乙');
    expect(inside.selection.baseOffset, 1);
  });
}
