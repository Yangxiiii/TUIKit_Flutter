import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_actions_scope.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';

const _group = 'group_group-001';
const _id = '9007199254740993';
const _summary = '明天下午三点召开项目会议，请准时参加。';
const _richBody = '[{"type":"text","text":"**会议通知**","title":false},'
    '{"type":"image","url":"https://example.com/notice.png","name":"image.png"}]';
const _wire = '''
{
  "businessID": "oa_group_announcement",
  "version": 1,
  "payload": {
    "announcementId": "$_id",
    "groupId": "group-001",
    "summary": "$_summary"
  }
}
''';

String _wireWithContent(Map<String, String> fields) => jsonEncode({
      'businessID': 'oa_group_announcement',
      'version': 1,
      'payload': {
        'announcementId': _id,
        'groupId': 'group-001',
        ...fields,
      },
    });

MessageInfo _message(String data,
        {MessageStatus status = MessageStatus.sendSuccess}) =>
    MessageInfo(
      msgID: 'announcement-message',
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      messageType: MessageType.custom,
      status: status,
      from: MessageSenderInfo(userID: 'author', nickname: '发布者'),
      messagePayload: CustomMessagePayload(customData: data),
    );

void main() {
  test('识别群公告 v1，远端长 ID 保持为字符串，跨群和无效消息不识别', () {
    final card =
        GroupAnnouncementMessage.fromConversation(_message(_wire), _group);
    expect(card?.announcementId, _id);
    expect(card?.preview, '[群公告]$_summary');
    for (final invalid in [
      '{',
      _wire.replaceFirst('"version": 1', '"version": 2'),
      _wire.replaceFirst('"$_id"', _id),
      _wire.replaceFirst('"$_summary"', 'null'),
    ]) {
      expect(
          GroupAnnouncementMessage.fromConversation(_message(invalid), _group),
          isNull);
    }
    expect(
        GroupAnnouncementMessage.fromConversation(
            _message(_wire), 'group_other'),
        isNull);
    expect(
        GroupAnnouncementMessage.fromConversation(
            _message(_wire), 'c2c_author'),
        isNull);
    expect(
      GroupAnnouncementMessage.fromConversation(
        _message(_wire, status: MessageStatus.revoked),
        _group,
      ),
      isNull,
    );
  });

  test('公告从正文或摘要读取富文本块，异常正文回退到摘要', () {
    GroupAnnouncementMessage? parse(Map<String, String> fields) =>
        GroupAnnouncementMessage.fromConversation(
            _message(_wireWithContent(fields)), _group);
    expect(parse({'content': _richBody})?.summary, '会议通知 [图片]');
    expect(
      parse({'content': _richBody, 'summary': _summary})?.summary,
      '会议通知 [图片]',
    );
    expect(parse({'summary': _richBody})?.preview, '[群公告]会议通知 [图片]');
    expect(parse({'summary': '[图片]'})?.summary, '[图片]');
    expect(
      parse({'content': '[{"type":"image"}]', 'summary': _summary})?.summary,
      _summary,
    );
    expect(
      parse({'content': '[{"type":"image"}]'})?.summary,
      '公告内容暂无法显示',
    );
  });

  testWidgets('富文本公告卡显示两行摘要，整卡把长 ID 交给宿主', (tester) async {
    GroupAnnouncementMessage? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: _message(_wireWithContent({'content': _richBody})),
            conversationID: _group,
            isSelf: false,
            maxWidth: 350,
            messageListStore: null,
            config: ChatMessageListConfig(
              onGroupAnnouncementTap: (_, card) => opened = card,
            ),
          ),
        ),
      ),
    );
    expect(find.text('群公告'), findsOneWidget);
    final preview = find.text('会议通知 [图片]');
    expect(tester.widget<Text>(preview).maxLines, 2);
    await tester.tap(preview);
    expect(opened?.announcementId, _id);
  });

  testWidgets('会话首页显示发送者和单行群公告摘要', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationItem(
            conversation: ConversationInfo(
              conversationID: _group,
              type: ConversationType.group,
              title: '项目群',
              avatarURL: '',
              lastMessage: _message(_wire),
            ),
            contentBuilder: (_, subtitle) => subtitle,
            config: const ChatConversationActionConfig(),
          ),
        ),
      ),
    );
    final preview = find.text('发布者：[群公告]$_summary');
    expect(tester.widget<Text>(preview).maxLines, 1);
  });

  testWidgets('公告菜单保留本地删除，移除复制、撤回和转发', (tester) async {
    List<String>? actions;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageActionsScope(
            config: null,
            onMessagesChanged: (_) {},
            showActions: (message, anchor, row, items, react) => actions =
                items.map((item) => item.id).whereType<String>().toList(),
            child: MessageBubble(
              message: _message(_wire),
              conversationID: _group,
              isSelf: true,
              maxWidth: 350,
              messageListStore: MessageListStore.create(conversationID: _group),
              config: const ChatMessageListConfig(
                isSupportCopy: true,
                isSupportRecall: true,
                isSupportForward: true,
                isSupportDelete: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.text(_summary));
    expect(actions, contains('delete'));
    expect(actions, isNot(contains('copy')));
    expect(actions, isNot(contains('recall')));
    expect(actions, isNot(contains('forward')));
  });
}
