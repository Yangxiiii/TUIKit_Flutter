import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_input/message_text.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';

void main() {
  test('可见字素、SDK表情和换行使用同一计数口径', () {
    expect(messageTextCharacterCount('汉😀👍🏽👨‍👩‍👧‍👦'), 4);
    expect(messageTextCharacterCount('[TUIEmoji_Smile]\r\n好\n'), 4);
    expect(messageTextCharacterCount('[TUIEmoji_unknown]'), 18);
  });

  test('普通与富文本的4000边界一致且隐藏格式不计数', () {
    final text = '${'字' * 3999}😀';
    expect(messageTextCharacterCount(text), 4000);
    final draft = RichContentDraft(
      blocks: [RichContentDraftTextBlock(1, '**$text**')],
    );
    expect(draft.characterCount, 4000);
    expect(draft.canSend, isTrue);
    expect(
      RichContentDraft(
        title: '再',
        blocks: draft.blocks,
      ).canSend,
      isFalse,
    );
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
    for (final character in ['😀', '👍🏽', '👨‍👩‍👧‍👦', '[TUIEmoji_Smile]']) {
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
