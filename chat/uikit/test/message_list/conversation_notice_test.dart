import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_selection_policy.dart';
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
  testWidgets('旧建群通知从历史和摘要过滤，直接构建也不占位', (tester) async {
    final legacy = _custom(
      'legacy-create',
      '{"businessID":"group_create","opUser":"张三","cmd":0}',
    );
    final message = MessageInfo(
      msgID: 'ordinary',
      messageType: MessageType.text,
      messagePayload: TextMessagePayload(text: '普通消息'),
    );
    expect(ConversationNotice.visibleMessages([legacy, message]), [message]);
    expect(ConversationNotice.hidesMessage(legacy), isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: MessageItem(
            message: legacy,
            conversationID: 'group_test',
            isGroup: true,
            maxWidth: 360,
            config: const ChatMessageListConfig(),
            messageListStore: _NoticeListStore(),
            isHighlighted: false,
          ),
        ),
      ),
    ));
    expect(find.textContaining('创建群组'), findsNothing);
    expect(tester.getSize(find.byType(MessageItem)).height, 0);
    expect(
        MessageUtil.getMessageAbstract(
          legacy,
          tester.element(find.byType(MessageItem)),
        ),
        isEmpty);
  });

  testWidgets('邀请与踢人共用通知构建器，关闭离群提示时仍显示邀请', (tester) async {
    final invite = _custom(
      'invite',
      _encode(
          'group.members_invited',
          {
            'operator': _operator,
            'members': [_member, _member],
          },
          eventId: 'invite'),
    );
    final removal = _custom(
      'removal',
      _encode(
          'group.members_removed',
          {
            'operator': _operator,
            'members': [_member],
          },
          eventId: 'removal'),
    );
    Widget view({required bool showDeparture}) => MaterialApp(
          home: Scaffold(
            body: Column(children: [
              for (final message in [invite, removal])
                MessageItem(
                  message: message,
                  conversationID: 'group_test',
                  isGroup: true,
                  maxWidth: 360,
                  config: ChatMessageListConfig(
                    showGroupDepartureNotices: showDeparture,
                    groupMemberNoticeBuilder: (_, notice) => Text(
                      notice.groupMemberParts().map((part) => part.text).join(),
                      key: ValueKey(notice.eventId),
                    ),
                  ),
                  messageListStore: _NoticeListStore(),
                  isHighlighted: false,
                ),
            ]),
          ),
        );
    await tester.pumpWidget(view(showDeparture: true));
    expect(find.text('张三 邀请 李四 加入了群组'), findsOneWidget);
    expect(find.text('张三 将 李四 移出了群组'), findsOneWidget);
    expect(
      ConversationNotice.fromMessage(invite)!
          .groupMemberParts()
          .map((part) => part.userId)
          .whereType<String>(),
      ['u001', 'u002'],
    );
    await tester.pumpWidget(view(showDeparture: false));
    expect(find.byKey(const ValueKey('invite')), findsOneWidget);
    expect(find.byKey(const ValueKey('removal')), findsNothing);
  });

  testWidgets('建群通知居中换行，发起人和每个受邀人按各自 ID 打开名片', (tester) async {
    const longName = '这是一个超过一行的较长姓名(昵称也会显示在同行并且自然跨行显示)';
    const invitee = {'userId': 'u003', 'nameSnapshot': longName};
    final message = _custom(
      'creation',
      _encode('group.created', {
        'operator': _operator,
        'group': {'groupId': 'test', 'nameSnapshot': '测试群'},
        'initialMembers': [_operator, _member, _member, invitee],
      }),
    );
    final tapped = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            child: MessageItem(
              message: message,
              conversationID: 'group_test',
              isGroup: true,
              maxWidth: 240,
              config: ChatMessageListConfig(
                onGroupInfoOperatorTap: (_, id) => tapped.add(id),
              ),
              messageListStore: _NoticeListStore(),
              isHighlighted: false,
            ),
          ),
        ),
      ),
    ));

    const text = '张三 发起群聊，并邀请 李四、$longName 加入此群';
    final notification = find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == text,
    );
    expect(tester.widget<RichText>(notification).textAlign, TextAlign.center);
    final paragraph = tester.renderObject<RenderParagraph>(notification);
    final semanticsNodes = tester
        .getSemantics(notification)
        .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder);
    for (final (name, id) in [
      ('张三', 'u001'),
      ('李四', 'u002'),
      (longName, 'u003'),
    ]) {
      expect(
        semanticsNodes
            .singleWhere(
              (node) => node.identifier == 'tim.groupCreation.notice-001.$id',
            )
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      final offset = text.indexOf(name);
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + name.length),
      );
      if (id == 'u003') expect(boxes.length, greaterThan(1));
      // 点最后一段，确保跨行姓名的后半段也能触发名片。
      await tester.tapAt(paragraph.localToGlobal(boxes.last.toRect().center));
    }
    expect(tapped, ['u001', 'u002', 'u003']);
    expect(
      ConversationNotice.fromMessage(message)?.textFor('u001'),
      '你 发起群聊，并邀请 李四、$longName 加入此群',
    );
  });

  testWidgets('设置和撤销管理员走自定义成员通知，普通成员仍可见', (tester) async {
    final operator = GroupMember(userID: 'u001', nickname: '张三');
    final member = GroupMember(userID: 'u002', nickname: '李四');
    for (final (type, tip, ending) in [
      (
        'group.add_manager',
        SetGroupAdmin(opUser: operator, setAdminMembers: [member]),
        '添加为群管理员',
      ),
      (
        'group.remove_manager',
        CancelGroupAdmin(opUser: operator, cancelAdminMembers: [member]),
        '从群管理员中移除',
      ),
    ]) {
      final expected = '张三 将 李四 $ending';
      final data = _encode(
          type,
          {
            'operator': _operator,
            'members': [_member, _member],
          },
          eventId: type);
      final message = _custom(type, data);
      final native = MessageInfo(
        msgID: 'native-$type',
        messageType: MessageType.tips,
        messagePayload: TipsMessagePayload(groupTips: [tip]),
      );
      final people = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageItem(
            message: message,
            conversationID: 'group_test',
            isGroup: true,
            maxWidth: 360,
            config: ChatMessageListConfig(
              showGroupDepartureNotices: false,
              groupMemberNoticeBuilder: (_, notice) {
                final parts = notice.groupMemberParts();
                people.addAll(
                    parts.map((part) => part.userId).whereType<String>());
                return Text(parts.map((part) => part.text).join());
              },
            ),
            messageListStore: _NoticeListStore(),
            isHighlighted: false,
          ),
        ),
      ));
      expect(find.text(expected), findsOneWidget);
      expect(people, ['u001', 'u002']);
      expect(
        MessageUtil.getMessageAbstract(
            message, tester.element(find.text(expected))),
        expected,
      );
      expect(ConversationNotice.fromMessage(message)?.textFor('u002'),
          '张三 将 你 $ending');
      expect(ConversationNotice.hidesMessage(native), isTrue);
      expect(
        ConversationNotice.visibleMessages([
          _custom('retry-$type', data),
          native,
          message,
        ]),
        [message],
      );
      expect(
        ConversationNotice.tryParse(_encode(type, {
          'operator': _operator,
          'members': [],
        })),
        isNull,
      );
    }
  });

  test('退群通知保留成员名片标识，移出通知保留所有成员且去重', () {
    final left = ConversationNotice.tryParse(
      _encode('group.member_left', {'member': _member}),
    )!;
    expect(left.groupMemberParts().map((part) => part.userId), ['u002', null]);
    final removed =
        ConversationNotice.tryParse(_encode('group.members_removed', {
      'operator': _operator,
      'members': [
        _member,
        _member,
        {'userId': 'u003', 'nameSnapshot': '王五'}
      ],
    }))!;
    expect(
        removed
            .groupMemberParts()
            .map((part) => part.userId)
            .whereType<String>(),
        ['u001', 'u002', 'u003']);
    expect(removed.groupMemberParts().map((part) => part.text).join(),
        '张三 将 李四、王五 移出了群组');
  });

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

  testWidgets('头像变更只在会话摘要展示，混合事件仍可在群聊改名提示打开名片', (tester) async {
    final operator = GroupMember(userID: 'u001', nickname: '张三');
    final avatar =
        ChangeGroupAvatar(opUser: operator, groupAvatar: 'avatar.png');
    final avatarOnly = MessageInfo(
      msgID: 'avatar',
      messageType: MessageType.tips,
      messagePayload: TipsMessagePayload(groupTips: [avatar]),
    );
    final mixed = MessageInfo(
      msgID: 'mixed',
      messageType: MessageType.tips,
      messagePayload: TipsMessagePayload(groupTips: [
        avatar,
        ChangeGroupName(opUser: operator, groupName: '产品群'),
      ]),
    );

    expect(ConversationNotice.hidesNativeMessage(avatarOnly), isFalse);
    expect(
      ConversationNotice.hidesNativeMessage(avatarOnly, inChatWindow: true),
      isTrue,
    );
    expect(ConversationNotice.visibleMessages([avatarOnly, mixed]), [mixed]);

    final tapped = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          SystemMessageWidget(message: avatarOnly),
          SystemMessageWidget(
            message: mixed,
            onOperatorTap: (_, id) => tapped.add(id),
          ),
        ]),
      ),
    ));

    expect(find.textContaining('修改了群头像', findRichText: true), findsNothing);
    expect(find.textContaining('产品群', findRichText: true), findsOneWidget);
    await tester.tap(find.text('张三'));
    expect(tapped, ['u001']);
    final context = tester.element(find.byType(Scaffold));
    expect(MessageUtil.getMessageAbstract(avatarOnly, context), '张三 修改了群头像');
  });

  testWidgets('原生描述提示可见，同一事件的后端副本只展示一次', (tester) async {
    final operator = GroupMember(userID: 'u001', nickname: '张三');
    final timestamp = DateTime.parse(_time).millisecondsSinceEpoch ~/ 1000;
    final avatar =
        ChangeGroupAvatar(opUser: operator, groupAvatar: 'avatar.png');
    final change = ChangeGroupIntroduction(
      opUser: operator,
      groupIntroduction: '产品讨论',
    );
    final native = MessageInfo(
      msgID: 'native-description',
      timestamp: timestamp,
      messageType: MessageType.tips,
      messagePayload: TipsMessagePayload(groupTips: [change]),
    );
    final mixed = MessageInfo(
      msgID: 'mixed-description',
      timestamp: timestamp,
      messageType: MessageType.tips,
      messagePayload: TipsMessagePayload(groupTips: [avatar, change]),
    );
    final backend = _custom(
      'server-description',
      _encode('group.description_changed', {
        'operator': _operator,
        'newDescription': '产品讨论',
      }),
    );
    final earlier = _custom(
      'earlier-description',
      _encode(
        'group.description_changed',
        {'operator': _operator, 'newDescription': '产品讨论'},
        eventId: 'earlier',
        time: '2026-11-13T17:59:59+08:00',
      ),
    );

    expect(ConversationNotice.hidesNativeMessage(native), isFalse);
    expect(
      ConversationNotice.hidesNativeMessage(native, inChatWindow: true),
      isFalse,
    );
    expect(ConversationNotice.visibleMessages([native]), [native]);
    expect(ConversationNotice.visibleMessages([backend]), [backend]);
    expect(ConversationNotice.visibleMessages([backend, native]), [native]);
    expect(ConversationNotice.visibleMessages([mixed, backend]), [mixed]);
    expect(
      ConversationNotice.visibleMessages([native, earlier]),
      [native, earlier],
    );
    expect(
      ConversationNotice.fromMessage(backend)
          ?.matchesNativeDescriptionIn([mixed]),
      isTrue,
    );

    final tapped = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SystemMessageWidget(
          message: mixed,
          onOperatorTap: (_, id) => tapped.add(id),
        ),
      ),
    ));

    expect(
      find.textContaining('更新了群描述：产品讨论', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('修改了群头像', findRichText: true), findsNothing);
    await tester.tap(find.text('张三'));
    expect(tapped, ['u001']);
    final context = tester.element(find.byType(Scaffold));
    expect(
      MessageUtil.getMessageAbstract(native, context),
      '张三 更新了群描述：产品讨论',
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

  testWidgets('群名称和描述提示的操作人打开同一名片', (tester) async {
    final rename = MessageInfo(
      msgID: 'rename',
      messageType: MessageType.tips,
      messagePayload: TipsMessagePayload(groupTips: [
        ChangeGroupName(
          opUser: GroupMember(userID: 'u001', nickname: '张三'),
          groupName: '产品群',
        ),
      ]),
    );
    final nativeDescription = MessageInfo(
      msgID: 'native-description',
      messageType: MessageType.tips,
      messagePayload: TipsMessagePayload(groupTips: [
        ChangeGroupIntroduction(
          opUser: GroupMember(userID: 'u001', nickname: '张三'),
          groupIntroduction: '产品讨论',
        ),
      ]),
    );
    final description = _custom(
      'description',
      _encode('group.description_changed', {
        'operator': _operator,
        'newDescription': '产品讨论',
      }),
    );
    final tapped = <String>[];
    final store = _NoticeListStore();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          for (final message in [rename, nativeDescription, description])
            MessageItem(
              message: message,
              conversationID: 'group_test',
              isGroup: true,
              maxWidth: 360,
              config: ChatMessageListConfig(
                onGroupInfoOperatorTap: (_, id) => tapped.add(id),
              ),
              messageListStore: store,
              isHighlighted: false,
            ),
        ]),
      ),
    ));

    final names = find.text('张三');
    expect(names, findsNWidgets(3));
    for (final index in [0, 1, 2]) {
      await tester.tap(names.at(index));
    }
    expect(tapped, ['u001', 'u001', 'u001']);
    expect(
      ConversationNotice.fromMessage(description)?.textFor('u001'),
      '张三 更新了群描述：产品讨论',
    );
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

final class _NoticeListStore extends Fake implements MessageListStore {}
