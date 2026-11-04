import 'package:flutter_test/flutter_test.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_selection_policy.dart';

MessageInfo _message(String id,
        {MessageStatus status = MessageStatus.sendSuccess,
        MessageType type = MessageType.text}) =>
    MessageInfo(msgID: id, status: status, messageType: type);

void main() {
  test('100条允许，第101条拒绝，满选仍可反选后再选', () {
    var ids = <String>{};
    for (var i = 0; i < 100; i++)
      ids = toggleChatMessageSelection(ids, _message('$i')).ids;
    final rejected = toggleChatMessageSelection(ids, _message('extra'));
    expect(rejected.limited, isTrue);
    expect(rejected.ids, hasLength(100));
    ids = toggleChatMessageSelection(ids, _message('0')).ids;
    final accepted = toggleChatMessageSelection(ids, _message('extra'));
    expect(accepted.limited, isFalse);
    expect(accepted.ids, hasLength(100));
    expect(accepted.ids.contains('0'), isFalse);
  });

  test('撤回、删除、系统提示和空标识不能选；语音仍可进入多选后统一确认资格', () {
    for (final message in [
      _message('revoked', status: MessageStatus.revoked),
      _message('deleted', status: MessageStatus.deleted),
      _message('tips', type: MessageType.tips),
      _message('')
    ]) {
      expect(toggleChatMessageSelection({}, message).ids, isEmpty);
    }
    expect(
        toggleChatMessageSelection(
                {}, _message('audio', type: MessageType.audio))
            .ids,
        {'audio'});
  });

  test('选择以下按传入显示边界补选并去重，最多100条', () {
    final selected = selectChatMessagesBelow({'old'},
        [for (var i = 0; i < 105; i++) _message('$i'), _message('old')]);
    expect(selected.limited, isTrue);
    expect(selected.ids, hasLength(100));
    expect(selected.ids.contains('old'), isTrue);
    expect(selected.ids.contains('98'), isTrue);
    expect(selected.ids.contains('99'), isFalse);
  });

  test('窗口更新自动移除撤回、删除和已离开窗口的选择', () {
    final next = retainSelectableChatMessages({
      'valid',
      'revoked',
      'deleted',
      'missing'
    }, [
      _message('valid'),
      _message('revoked', status: MessageStatus.revoked),
      _message('deleted', status: MessageStatus.deleted)
    ]);
    expect(next, {'valid'});
  });
}
