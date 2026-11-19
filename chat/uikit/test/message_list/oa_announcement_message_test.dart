import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_actions_scope.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/oa_announcement_message_card.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';

const _id = '9007199254740993';
const _title = '公告标题';
const _summary = '明天下午三点召开项目会议，请准时参加。';
const _payload = {
  'id': _id,
  'title': _title,
  'summary': _summary,
  'realName': '杨洋阳',
  'nickname': '一只羊',
};

String _wire({
  Object? payload = _payload,
  Object? version = 1,
  String businessID = 'oa_announcement',
}) =>
    jsonEncode({
      'businessID': businessID,
      'version': version,
      'payload': payload,
    });

MessageInfo _message(
  String data, {
  MessageStatus status = MessageStatus.sendSuccess,
  ConversationType type = ConversationType.c2c,
  String sender = 'backend-user',
  String messageId = 'oa-announcement-message',
}) =>
    MessageInfo(
      msgID: messageId,
      timestamp: 1794880800,
      messageType: MessageType.custom,
      conversationType: type,
      status: status,
      from: MessageSenderInfo(userID: sender, nickname: '公告'),
      messagePayload: CustomMessagePayload(customData: data),
    );

void main() {
  test('公告标题与摘要独立，长 ID 原样保留且不限制后台账号', () {
    final notification = OaAnnouncementMessage.fromConversation(
      _message(_wire(), sender: 'another-backend'),
      'c2c_another-backend',
    );
    expect(notification?.id, _id);
    expect(notification?.title, _title);
    expect(notification?.summary, _summary);
    expect(notification?.preview, _title);
    expect(notification?.publisherName, '杨洋阳(一只羊)');
    expect(
      OaAnnouncementMessage.tryParse(
        _wire(payload: {..._payload, 'id': '00$_id'}),
      )?.id,
      '00$_id',
    );
  });

  test('坏 JSON、未知业务和版本以及错误字段不产生公告入口', () {
    for (final raw in [
      null,
      '',
      '{',
      '[]',
      '{}',
      _wire(businessID: 'oa_group_announcement'),
      _wire(version: '1'),
      _wire(version: 1.0),
      _wire(version: 2),
      _wire(payload: []),
      _wire(payload: {..._payload, 'id': 9007199254740993}),
      _wire(payload: {..._payload, 'id': ' '}),
      _wire(payload: {..._payload, 'title': null}),
      _wire(payload: {..._payload, 'title': ' '}),
      _wire(payload: {..._payload, 'summary': 1}),
      _wire(payload: {..._payload, 'realName': []}),
      _wire(payload: {..._payload, 'nickname': false}),
    ]) {
      expect(OaAnnouncementMessage.tryParse(raw), isNull, reason: '$raw');
    }
  });

  test('发布人快照缺失或重复时不显示空括号，不查询其他资料', () {
    for (final values in [
      ('杨洋阳', null, '杨洋阳'),
      (null, '一只羊', '一只羊'),
      ('杨洋阳', '杨洋阳', '杨洋阳'),
      (null, null, ''),
    ]) {
      final message = OaAnnouncementMessage.tryParse(_wire(payload: {
        ..._payload,
        'realName': values.$1,
        'nickname': values.$2,
      }));
      expect(message?.publisherName, values.$3);
    }
    final withoutNames = {..._payload}
      ..remove('realName')
      ..remove('nickname');
    expect(
      OaAnnouncementMessage.tryParse(_wire(payload: withoutNames))
          ?.publisherName,
      '',
    );
  });

  test('群聊、空会话、撤回、删除和违规消息不使用单聊公告展示', () {
    for (final conversation in ['', 'c2c_', 'group_backend-user']) {
      expect(
        OaAnnouncementMessage.fromConversation(_message(_wire()), conversation),
        isNull,
      );
    }
    for (final type in [ConversationType.group, ConversationType.unknown]) {
      expect(
        OaAnnouncementMessage.fromMessage(_message(_wire(), type: type)),
        isNull,
      );
    }
    for (final status in [
      MessageStatus.revoked,
      MessageStatus.deleted,
      MessageStatus.violation,
    ]) {
      expect(
        OaAnnouncementMessage.fromMessage(_message(_wire(), status: status)),
        isNull,
      );
    }
    expect(OaAnnouncementMessage.fromMessage(null), isNull);
  });

  testWidgets('通用消息摘要和会话列表均显示独立公告标题', (tester) async {
    String? preview;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            preview =
                MessageUtil.getMessageAbstract(_message(_wire()), context);
            return ConversationItem(
              conversation: ConversationInfo(
                conversationID: 'c2c_backend-user',
                type: ConversationType.c2c,
                title: '公告',
                avatarURL: '',
                lastMessage: _message(_wire()),
              ),
              contentBuilder: (_, subtitle) => subtitle,
              config: const ChatConversationActionConfig(),
            );
          }),
        ),
      ),
    );
    expect(preview, _title);
    expect(tester.widget<Text>(find.text(_title)).maxLines, 1);
    expect(find.text(_summary), findsNothing);
  });

  testWidgets('通知卡独立显示字段，详情保留长 ID 且不把点击写为已读', (tester) async {
    final semantics = tester.ensureSemantics();
    String? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: _message(_wire()),
          conversationID: 'c2c_backend-user',
          isSelf: false,
          maxWidth: 350,
          messageListStore: null,
          config: ChatMessageListConfig(
            onOaAnnouncementTap: (_, id) => opened = id,
          ),
        ),
      ),
    ));
    expect(find.text(_title), findsOneWidget);
    expect(tester.widget<Text>(find.text(_summary)).maxLines, isNull);
    expect(find.text('杨洋阳(一只羊) 发布'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.bySemanticsLabel('阅读状态未知'), findsOneWidget);
    expect(find.text('未读'), findsNothing);
    expect(find.text('已读'), findsNothing);
    expect(tester.getSize(find.byType(OaAnnouncementMessageCard)).width, 310);

    // 只有详情按钮响应，不把卡片正文误设为另一个导航或已读入口。
    await tester.tap(find.text(_summary));
    expect(opened, isNull);
    final detail = find
        .bySemanticsIdentifier('tim.assistant.detail.oa-announcement-message');
    expect(
      tester
          .getSemantics(detail)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(detail);
    expect(opened, _id);
    expect(find.text('—'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: _message(_wire(), messageId: ''),
          conversationID: 'c2c_backend-user',
          isSelf: false,
          maxWidth: 310,
          messageListStore: null,
          config: const ChatMessageListConfig(),
        ),
      ),
    ));
    expect(find.bySemanticsIdentifier('tim.assistant.detail.$_id'),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets('通知阅读状态只读取业务入口，缺失或失败保持未知', (tester) async {
    for (final read in [false, true, null]) {
      String? queried;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: _message(_wire()),
            conversationID: 'c2c_backend-user',
            isSelf: false,
            maxWidth: 310,
            messageListStore: null,
            config: ChatMessageListConfig(
              oaAnnouncementReadStatus: (id) {
                queried = id;
                return read;
              },
            ),
          ),
        ),
      ));
      expect(queried, _id);
      expect(
          find.text(read == null ? '—' : (read ? '已读' : '未读')), findsOneWidget);
    }
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: _message(_wire()),
          conversationID: 'c2c_backend-user',
          isSelf: false,
          maxWidth: 310,
          messageListStore: null,
          config: ChatMessageListConfig(
            oaAnnouncementReadStatus: (_) => throw StateError('状态不可用'),
          ),
        ),
      ),
    ));
    expect(find.text('—'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('查看详情'));
    await tester.pump();
    expect(find.text('公告详情暂未开放'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('公告消息行保持通知头像和类型名，窄屏不溢出', (tester) async {
    final longSummary = List.filled(6, _summary).join();
    for (final width in [358.0, 288.0]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: MessageItem(
                message: _message(
                    _wire(payload: {..._payload, 'summary': longSummary})),
                conversationID: 'c2c_backend-user',
                maxWidth: width,
                messageListStore: null,
                isHighlighted: false,
                config: const ChatMessageListConfig(),
              ),
            ),
          ),
        ),
      ));
      expect(find.text('公告'), findsOneWidget);
      final avatar = find.byType(OaAnnouncementAvatar);
      final card = find.byType(OaAnnouncementMessageCard);
      expect(tester.getSize(avatar), const Size(40, 40));
      expect(tester.getSize(card).width, width - 48);
      expect(tester.getTopLeft(card).dx - tester.getTopLeft(avatar).dx, 48);
      expect(tester.widget<Text>(find.text(longSummary)).maxLines, isNull);
      expect(tester.getSize(find.text(longSummary)).height, greaterThan(48));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('通知消息长按不展示普通消息写操作', (tester) async {
    var openedMenu = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageActionsScope(
          config: null,
          onMessagesChanged: (_) {},
          showActions: (_, __, ___, ____, _____) => openedMenu = true,
          child: MessageBubble(
            message: _message(_wire()),
            conversationID: 'c2c_backend-user',
            isSelf: false,
            maxWidth: 310,
            messageListStore:
                MessageListStore.create(conversationID: 'c2c_backend-user'),
            config: const ChatMessageListConfig(),
          ),
        ),
      ),
    ));
    await tester.longPress(find.text(_summary));
    expect(openedMenu, isFalse);
  });
}
