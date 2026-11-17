import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_input/mention/mention_info.dart';
import 'package:tencent_chat_uikit/src/message_input/mention/mention_text_editing_controller.dart';
import 'package:tencent_chat_uikit/src/message_input/mention/message_mentions.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';

void main() {
  test('位置按 UTF-16 计算，重复身份按首次出现生成提醒', () {
    final items = MessageMentions.encode(
      '😀 @同名 @同名 @同名',
      [
        MentionInfo(userID: 'first', displayName: '同名', startIndex: 3),
        MentionInfo(userID: 'second', displayName: '同名', startIndex: 7),
        MentionInfo(userID: 'first', displayName: '同名', startIndex: 11),
      ],
      0,
    );
    expect(items.map((item) => item['start']), [3, 7, 11]);
    expect(items.map((item) => item['length']), [3, 3, 3]);
    expect(MessageMentions.targets(items), ['first', 'second']);
  });

  test('标题与格式标记计入位置，草稿刷新保留成员标识', () {
    final draft = RichContentDraft(
      title: '题',
      blocks: [
        RichContentDraftTextBlock(1, '😀 **@成员**', mentions: [
          MentionInfo(userID: '42', displayName: '成员', startIndex: 5),
        ]),
      ],
    );
    final restored =
        RichContentDraft.tryParsePersisted(draft.toPersistedString())!;
    expect(restored.nativeMentionText, isNull);
    expect(restored.messageMentions.single['start'], 12);
    expect(restored.messageMentions.single['userID'], '42');
    expect(restored.hasSameContentAs(draft), isTrue);
  });

  test('覆盖选中的同名提及撤销身份，其余成员仍可提醒', () {
    final controller = MentionTextEditingController();
    addTearDown(controller.dispose);
    controller.insertMentions(const TextSelection.collapsed(offset: 0), [
      MentionInfo(userID: 'first', displayName: '同名', startIndex: 0),
      MentionInfo(userID: 'second', displayName: '同名', startIndex: 0),
    ]);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    controller.value = const TextEditingValue(
      text: '你好！ @同名 ',
      selection: TextSelection.collapsed(offset: 4),
    );
    expect(controller.mentionList.single.userID, 'second');
    expect(controller.mentionList.single.startIndex, 4);
  });

  test('非法范围和重叠定位回退为普通文本', () {
    const text = '@同名';
    final item = {
      'kind': 'user',
      'userID': '42',
      'displayName': '同名',
      'blockIndex': 0,
      'start': 0,
      'length': 3,
    };
    expect(
        MessageMentions.decodeItems([
          item,
          {...item, 'userID': '43'}
        ], text, 0),
        isEmpty);
    expect(
        MessageMentions.decodeItems([
          {...item, 'start': -1}
        ], text, 0),
        isEmpty);
    expect(
        MessageMentions.decodeItems([
          {...item, 'userID': 42}
        ], text, 0),
        isEmpty);
  });
}
