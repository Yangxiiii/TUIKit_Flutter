import 'dart:convert';

import 'package:app_api/app_api_models.dart'
    show GroupCallRecordData, GroupCallRecordOutcome;
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

void main() {
  late V2TIMManager original;
  late _Sdk sdk;
  UserProfile? originalProfile;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    original = TencentImSDKPlugin.v2TIMManager;
    originalProfile = LoginStore.shared.loginState.loginUserInfo;
    sdk = _Sdk();
    TencentImSDKPlugin.v2TIMManager = sdk;
    // 使用公开资料入口给展示层提供当前账号，所有 SDK 调用由替身接管。
    await LoginStore.shared
        .setSelfInfo(userInfo: UserProfile(userID: 'callee'));
  });
  tearDown(() async {
    // 仅恢复测试前展示账号；logout 的版本日志会初始化真实 TRTC，不属于 Widget 回归。
    await LoginStore.shared
        .setSelfInfo(userInfo: originalProfile ?? UserProfile(userID: ''));
    TencentImSDKPlugin.v2TIMManager = original;
  });

  Future<void> mount(WidgetTester tester, MessageInfo message,
          {String alignment = 'two-sided', bool merged = false}) =>
      tester.pumpWidget(MaterialApp(
        builder: AppDialog.init(),
        navigatorObservers: [AppDialog.observer],
        theme: AppThemeFactory.create(
            const AppNormalColorScheme(), Brightness.light),
        home: Scaffold(
          body: MessageItem(
            message: message,
            conversationID: 'c2c_caller',
            messageListStore: _ListStore(),
            isHighlighted: false,
            isInMergedDetailView: merged,
            config: ChatMessageListConfig(
                alignment: alignment, enableReadReceipt: false),
          ),
        ),
      ));

  testWidgets('被叫本人失败报告保留来电方向与发起人头像，三个布局都有重发入口', (tester) async {
    final message = _report();
    for (final alignment in ['two-sided', 'left', 'right']) {
      await mount(tester, message, alignment: alignment);
      expect(tester.widget<MessageBubble>(find.byType(MessageBubble)).isSelf,
          isFalse);
      expect(tester.widget<Avatar>(find.byType(Avatar)).userID, 'caller');
      expect(find.bySemanticsIdentifier('tim.message.retry.record'),
          findsOneWidget);
      expect(message.from.userID, 'callee');
      expect(message.isSentBySelf, isTrue);
    }
    await tester.tap(find.bySemanticsIdentifier('tim.message.retry.record'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('tim.message.retry.confirm.confirm'),
        findsOneWidget);
    await tester
        .tap(find.bySemanticsIdentifier('tim.message.retry.confirm.cancel'));
    await tester.pumpAndSettle();
    expect(sdk.unexpectedCalls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('确认期间失去真实发送所有权不能删除或重发，远端报告不获得重发入口', (tester) async {
    final message = _report();
    await mount(tester, message);
    await tester.tap(find.bySemanticsIdentifier('tim.message.retry.record'));
    await tester.pumpAndSettle();
    message.isSentBySelf = false;
    await tester
        .tap(find.bySemanticsIdentifier('tim.message.retry.confirm.confirm'));
    await tester.pumpAndSettle();
    expect(sdk.unexpectedCalls, isEmpty);
    for (final alignment in ['two-sided', 'left', 'right']) {
      await mount(tester, _report(own: false), alignment: alignment);
      expect(
          find.bySemanticsIdentifier('tim.message.retry.record'), findsNothing);
    }
    // 主叫查看被叫报告时气泡在右侧，右侧不能被误认为拥有发送权限。
    await LoginStore.shared
        .setSelfInfo(userInfo: UserProfile(userID: 'caller'));
    final fromCallee = _report()..isSentBySelf = false;
    await mount(tester, fromCallee);
    expect(tester.widget<MessageBubble>(find.byType(MessageBubble)).isSelf,
        isTrue);
    expect(
        find.bySemanticsIdentifier('tim.message.retry.record'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('被叫本人发送中显示进度，合并只读记录和普通远端消息不显示发送操作', (tester) async {
    await mount(tester, _report(status: MessageStatus.sending));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await mount(tester, _report(), merged: true);
    expect(
        find.bySemanticsIdentifier('tim.message.retry.record'), findsNothing);
    for (final own in [true, false]) {
      final text = MessageInfo(
          msgID: 'text',
          isSentBySelf: own,
          from: MessageSenderInfo(userID: own ? 'callee' : 'caller'),
          to: own ? 'caller' : 'callee',
          messageType: MessageType.text,
          status: MessageStatus.sendFail,
          messagePayload: TextMessagePayload(text: '普通消息'));
      await mount(tester, text);
      expect(find.bySemanticsIdentifier('tim.message.retry.text'),
          own ? findsOneWidget : findsNothing);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

MessageInfo _report(
    {bool own = true, MessageStatus status = MessageStatus.sendFail}) {
  final record = GroupCallRecordData(
      callId: 'call',
      groupId: '',
      callerId: 'caller',
      callerName: '发起人',
      calleeId: 'callee',
      reporterId: own ? 'callee' : 'caller',
      participantIds: const ['caller', 'callee'],
      mediaType: 'audio',
      outcome: GroupCallRecordOutcome.completed,
      durationSeconds: 12,
      endedAtMs: 1000,
      revision: 1);
  return MessageInfo(
      msgID: 'record',
      status: status,
      from: MessageSenderInfo(userID: record.reporterId),
      to: own ? 'caller' : 'callee',
      isSentBySelf: own,
      conversationType: ConversationType.c2c,
      messageType: MessageType.custom,
      messagePayload:
          CustomMessagePayload(customData: jsonEncode(record.toJson())));
}

class _ListStore extends Fake implements MessageListStore {}

/// 仅提供显示账号；任何消息删除或发送调用都会被记录，不接触真实 IM。
class _Sdk extends Fake implements V2TIMManager {
  final List<Symbol> unexpectedCalls = [];
  @override
  Future<V2TimCallback> setSelfInfo(
          {required V2TimUserFullInfo userFullInfo}) async =>
      V2TimCallback(code: 0, desc: '');
  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls.add(invocation.memberName);
    return super.noSuchMethod(invocation);
  }
}
