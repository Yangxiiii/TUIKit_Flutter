import 'dart:convert';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_selection_policy.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_item.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/system_message_widget.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';

const _operator = {'userId': 'u001', 'nameSnapshot': '张三'};
const _member = {'userId': 'u002', 'nameSnapshot': '李四'};
const _time = '2026-11-13T18:00:00+08:00';

String _encode(
  String type,
  Map<String, Object> data, {
  String eventId = 'notice-001',
  int version = 1,
  String time = _time,
}) =>
    jsonEncode({
      'businessID': 'oa_system_notice',
      'version': version,
      'eventId': eventId,
      'type': type,
      'occurredAt': time,
      'data': data,
    });

MessageInfo _custom(String id, String data) => MessageInfo(
      msgID: id,
      messageType: MessageType.custom,
      messagePayload: CustomMessagePayload(customData: data),
    );

void main() {
  testWidgets('后端接管的原生提示不显示，混合提示保留改名', (tester) async {
    final invite = InviteToGroup(
      inviter: GroupMember(userID: 'u001', nickname: '张三'),
      invitees: [GroupMember(userID: 'u002', nickname: '李四')],
    );
    final member = GroupMember(userID: 'u002', nickname: '李四');
    final operator = GroupMember(userID: 'u001', nickname: '张三');
    final tips = [
      invite,
      JoinGroup(joinMember: member),
      QuitGroup(quitMember: member),
      KickedFromGroup(opUser: operator, kickedMembers: [member]),
      ChangeGroupIntroduction(opUser: operator, groupIntroduction: '群描述'),
      PinGroupMessage(opUser: operator),
      UnpinGroupMessage(opUser: operator),
    ];
    final native = [
      for (final (index, tip) in tips.indexed)
        MessageInfo(
          msgID: 'native-$index',
          timestamp: 1,
          messageType: MessageType.tips,
          messagePayload: TipsMessagePayload(groupTips: [tip]),
        ),
    ];
    final rename = ChangeGroupName(opUser: operator, groupName: '产品群');
    final mixed = MessageInfo(
      msgID: 'mixed',
      messageType: MessageType.tips,
      messagePayload: TipsMessagePayload(groupTips: [
        invite,
        rename,
      ]),
    );
    final backend = _custom(
      'backend',
      _encode('group.members_invited', {
        'operator': _operator,
        'members': [_member],
      }),
    );
    expect(ConversationNotice.visibleMessages(native), isEmpty);
    expect(
      ConversationNotice.visibleMessages([backend, ...native, mixed]),
      [backend, mixed],
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final context = tester.element(find.byType(Scaffold));
    for (final message in native) {
      expect(MessageUtil.getMessageAbstract(message, context), isEmpty);
    }
    expect(
      MessageUtil.getMessageAbstract(mixed, context),
      MessageUtil.getSingleSystemInfoDisplayString(rename, context),
    );
    expect(
      MessageUtil.getMessageAbstract(backend, context),
      '张三 邀请 李四 加入了群组',
    );
  });

  testWidgets('聊天和摘要使用同一提示文案，系统行不响应多选', (tester) async {
    final message = _custom(
      'welcome',
      _encode('group.welcome', {
        'group': {'groupId': 'group-a', 'nameSnapshot': '测试群'},
        'member': _member,
      }),
    );
    String? preview;
    var selections = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          preview = MessageUtil.getMessageAbstract(message, context);
          return MessageItem(
            message: message,
            conversationID: 'group_test',
            maxWidth: 360,
            config: ChatMessageListConfig(),
            messageListStore: null,
            isHighlighted: false,
            isMultiSelectMode: true,
            onToggleSelection: () => selections++,
          );
        },
      ),
    ));
    final notice = find.byType(SystemMessageWidget);
    expect(preview, '欢迎加入 测试群 群组');
    expect(
      find.descendant(of: notice, matching: find.text(preview!)),
      findsOneWidget,
    );
    await tester.tap(find.text(preview!), warnIfMissed: false);
    expect(selections, 0);
  });

  test('按成员 ID 替换本人并保留去重后的顺序', () {
    final raw = _encode('group.members_removed', {
      'operator': _operator,
      'members': [
        _member,
        {'userId': 'u003', 'nameSnapshot': '李四'},
        {'userId': 'u002', 'nameSnapshot': '重复姓名'},
      ],
    });
    final notice = ConversationNotice.tryParse(raw)!;
    expect(notice.textFor('u001'), '你 将 李四、李四 移出了群组');
    expect(notice.textFor('u002'), '张三 将 你、李四 移出了群组');
    expect(canSelectChatMessage(_custom('notice', raw)), isFalse);
  });

  test('仅接受当前版本和必填字段完整的提示', () {
    final emptyDescription = {'operator': _operator, 'newDescription': ''};
    expect(
      ConversationNotice.tryParse(
        _encode('group.description_changed', emptyDescription),
      )?.textFor(null),
      '张三 清空了群描述',
    );
    for (final raw in [
      '{',
      _encode('group.description_changed', {'operator': _operator}),
      _encode('group.members_joined', {'members': []}),
      _encode('group.unknown', emptyDescription),
      _encode('group.description_changed', emptyDescription, version: 2),
      _encode('group.description_changed', emptyDescription,
          time: '2026-11-13T18:00:00'),
    ]) {
      expect(ConversationNotice.tryParse(raw), isNull);
    }
  });

  test('重复事件保留原行，独立撤回记录不生成提示行', () {
    final raw = _encode('group.members_joined', {
      'members': [_operator, _member],
    });
    final recall = _custom(
      'recall',
      _encode(
          'message.recalled', {'operator': _operator, 'messageId': 'original'},
          eventId: 'recall'),
    );
    final old = _custom('original-event', raw);
    final original =
        MessageInfo(msgID: 'original', status: MessageStatus.revoked);
    expect(
      ConversationNotice.visibleMessages([
        _custom('retry', raw),
        recall,
        old,
        original,
      ]),
      [old, original],
    );
  });
}
