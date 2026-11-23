import 'dart:convert';

import 'package:app_api/app_api_models.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:app_ui/app_ui.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/call_message_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/system_message_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/text_message_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/calling_message_data_provider.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/group_call_record_message.dart';

MessageInfo _message(String id, String reporter,
    {int revision = 1,
    int seconds = 12,
    String group = '',
    String? sender,
    String? attemptId,
    GroupCallRecordOutcome outcome = GroupCallRecordOutcome.completed,
    Map<String, GroupCallRecordOutcome> outcomes = const {}}) {
  final data = GroupCallRecordData(
      callId: 'call',
      groupId: group,
      callerId: 'caller',
      calleeId: group.isEmpty ? 'peer' : '',
      reporterId: reporter,
      participantIds: const ['caller', 'peer', 'third'],
      mediaType: 'video',
      outcome: outcome,
      attemptId: attemptId,
      outcomesByUserId: outcomes,
      durationSeconds: seconds,
      endedAtMs: 1000 + revision,
      revision: revision);
  return MessageInfo(
      msgID: id,
      from: MessageSenderInfo(userID: sender ?? reporter),
      to: group.isEmpty ? 'peer' : group,
      status: MessageStatus.sendSuccess,
      conversationType:
          group.isEmpty ? ConversationType.c2c : ConversationType.group,
      messageType: MessageType.custom,
      messagePayload:
          CustomMessagePayload(customData: jsonEncode(data.toJson())));
}

void main() {
  test('同场优先本人最高版本，乱序回放和远端时长不覆盖个人累计时长', () {
    final own1 = _message('own-1', 'peer');
    final own2 = _message('own-2', 'peer', revision: 2, seconds: 20);
    final remote = _message('remote', 'caller', revision: 9, seconds: 60);
    for (final list in [
      [own1, remote, own2],
      [own2, own1, remote],
      [remote, own1, own2]
    ]) {
      expect(GroupCallRecordMessage.visibleMessages(list, 'peer').single.msgID,
          'own-2');
    }
    final remoteData = GroupCallRecordMessage.fromMessage(remote, 'peer')!;
    expect(GroupCallRecordMessage.content(remoteData, 'peer'), '对方已结束通话');
    final ownData = GroupCallRecordMessage.fromMessage(own2, 'peer')!;
    expect(GroupCallRecordMessage.content(ownData, 'peer'), '通话时长 00:20');
    final capped = GroupCallRecordMessage.fromMessage(
        _message('capped', 'peer', group: 'group', seconds: 3601), 'peer')!;
    expect(GroupCallRecordMessage.content(capped, 'peer'), '通话时长 1:00:00');
    final text = MessageInfo(msgID: 'text', messageType: MessageType.text);
    expect(
        GroupCallRecordMessage.visibleMessages([own1, text, own2], 'peer')
            .map((message) => message.msgID),
        ['text', 'own-2']);
  });

  test('真实sender、群归属和单聊主被叫边界不可由自定义载荷绕过', () {
    expect(
        GroupCallRecordMessage.fromMessage(
            _message('spoof', 'caller', sender: 'third'), 'peer'),
        isNull);
    expect(
        GroupCallRecordMessage.visibleMessages(
            [_message('pair', 'caller')], 'third'),
        isEmpty);
    final group = _message('group', 'peer', group: 'group');
    expect(GroupCallRecordMessage.fromMessage(group, 'peer'), isNotNull);
    expect(GroupCallRecordMessage.fromMessage(group, 'third'), isNull);
    expect(GroupCallRecordMessage.fromMessage(group, 'outsider'), isNull);
    group.to = 'different-group';
    expect(GroupCallRecordMessage.fromMessage(group, 'peer'), isNull);
    final ordinary = MessageInfo(msgID: 'text', messageType: MessageType.text);
    expect(
        GroupCallRecordMessage.visibleMessages([ordinary], 'peer'), [ordinary]);
  });

  testWidgets('两人临时多人记录仍禁止单聊回拨，旧群广播不向未邀请者显示', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    })));
    final record = CallingMessageDataProvider(_message('own', 'peer'), context,
        viewerId: 'peer');
    expect(record.isTemporaryMultiParty, isTrue);
    expect(record.content, '通话时长 00:12');
    final invalid = CallingMessageDataProvider(_message('own', 'peer'), context,
        viewerId: 'third');
    expect(invalid.excludeFromHistory, isTrue);
    final legacy = MessageInfo(
        from: MessageSenderInfo(userID: 'caller'),
        messageType: MessageType.custom,
        messagePayload: CustomMessagePayload(
            customData: jsonEncode({
          'groupID': 'group',
          'inviteeList': ['peer'],
          'actionType': 1,
          'data': jsonEncode({'businessID': 'av_call', 'call_type': 1}),
        })));
    final hidden =
        CallingMessageDataProvider(legacy, context, viewerId: 'third');
    expect(hidden.excludeFromHistory, isTrue);
    expect(hidden.content, isEmpty);
  });
  test('主叫先挂断仅说明其个人退出，未接被叫使用自身邀请结果', () {
    final caller =
        _message('caller-record', 'caller', group: 'group', outcomes: {
      'peer': GroupCallRecordOutcome.completed,
      'third': GroupCallRecordOutcome.unanswered,
    });
    final peer = GroupCallRecordMessage.fromMessage(caller, 'peer')!;
    expect(GroupCallRecordMessage.content(peer, 'peer'), '发起人已结束通话');
    final third = GroupCallRecordMessage.fromMessage(caller, 'third')!;
    expect(GroupCallRecordMessage.content(third, 'third'), '未接听');
  });

  test('同次呼叫保留发起气泡与最新结果，双端文案按角色展示', () {
    MessageInfo start(String id) => MessageInfo(
        msgID: id,
        from: MessageSenderInfo(userID: 'caller'),
        to: 'group',
        conversationType: ConversationType.group,
        status: MessageStatus.sendSuccess,
        messageType: MessageType.custom,
        messagePayload: CustomMessagePayload(
            customData: jsonEncode(GroupCallStartData(
          groupId: 'group',
          callerId: 'caller',
          mediaType: 'video',
          inviteeIds: ['peer', 'third'],
          attemptId: id,
        ).toJson())));
    for (final (outcome, callerText, calleeText) in [
      (GroupCallRecordOutcome.cancelled, '已取消', '对方已取消'),
      (GroupCallRecordOutcome.unanswered, '无人接听', '未接听'),
      (GroupCallRecordOutcome.rejected, '对方已拒接', '已拒绝'),
      (GroupCallRecordOutcome.interrupted, '通话中断 00:12', '通话中断 00:12'),
    ]) {
      final caller = _message('caller-result', 'caller',
          group: 'group', attemptId: 'current', outcome: outcome);
      final peer = _message('peer-result', 'peer',
          group: 'group', attemptId: 'current', outcome: outcome);
      expect(GroupCallRecordMessage.content(
          GroupCallRecordMessage.fromMessage(caller, 'caller')!, 'caller'), callerText);
      expect(GroupCallRecordMessage.content(
          GroupCallRecordMessage.fromMessage(peer, 'peer')!, 'peer'), calleeText);
      final previousPeer = _message('old-result', 'peer', group: 'group',
          attemptId: 'current', outcome: outcome, revision: 1);
      final latestPeer = _message('latest-result', 'peer', group: 'group',
          attemptId: 'current', outcome: outcome, revision: 2);
      expect(GroupCallRecordMessage.visibleMessages(
          [start('previous'), start('current'), previousPeer, latestPeer], 'peer')
          .map((message) => message.msgID),
          ['previous', 'current', 'latest-result']);
    }
    final elsewhere = _message('elsewhere', 'peer',
        group: 'group', attemptId: 'current',
        outcome: GroupCallRecordOutcome.otherDeviceAccepted, seconds: 0, revision: 9);
    final complete = _message('complete', 'peer',
        group: 'group', attemptId: 'current');
    expect(GroupCallRecordMessage.content(
        GroupCallRecordMessage.fromMessage(elsewhere, 'peer')!, 'peer'), '已在其它设备接听');
    expect(GroupCallRecordMessage.visibleMessages(
        [elsewhere, complete], 'peer').single, complete);
  });

  testWidgets('群个人结果复用左右气泡，不变成系统提示也不误拨单人', (tester) async {
    var dialed = 0;
    final accepted = ValueNotifier<String?>('current');
    addTearDown(accepted.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeFactory.create(
          const AppNormalColorScheme(), Brightness.light),
      home: Scaffold(
          body: CallMessageWidget(
        message: _message('group-own', 'peer',
            group: 'group', attemptId: 'current'),
        viewerId: 'peer',
        isSelf: false,
        maxWidth: 390,
        config: ChatMessageListConfig(acceptedCallAttempt: accepted),
        onCallMessageClick: (_, __) {
          dialed++;
        },
      )),
    ));
    expect(find.text('通话时长 00:12'), findsOneWidget);
    expect(find.byType(TextMessageWidget), findsOneWidget);
    expect(find.byType(SystemMessageWidget), findsNothing);
    await tester.tap(find.bySemanticsIdentifier('tim.message.call.group-own'));
    expect(dialed, 0);
  });
}
