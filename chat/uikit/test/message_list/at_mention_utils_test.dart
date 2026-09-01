import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_input/mention/mention_info.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/at_mention_utils.dart';

void main() {
  test('实时消息能区分 @我、@所有人和两者同时出现', () {
    const currentUserID = 'user-1';

    expect(
      resolveGroupAtType([currentUserID], currentUserID),
      GroupAtType.atMe,
    );
    expect(
      resolveGroupAtType([MentionInfo.atAllUserID], currentUserID),
      GroupAtType.atAll,
    );
    expect(
      resolveGroupAtType(
        [currentUserID, MentionInfo.atAllUserID],
        currentUserID,
      ),
      GroupAtType.atAllAtMe,
    );
    expect(resolveGroupAtType(['user-2'], currentUserID), isNull);
  });

  test('跳转到 @ 消息后只保留序号更大的新消息', () {
    expect(isMessageAfterSequence(MessageInfo(sequence: 9), 10), isFalse);
    expect(isMessageAfterSequence(MessageInfo(sequence: 10), 10), isFalse);
    expect(isMessageAfterSequence(MessageInfo(sequence: 11), 10), isTrue);
    expect(isMessageAfterSequence(MessageInfo(), 10), isTrue);
  });
}
