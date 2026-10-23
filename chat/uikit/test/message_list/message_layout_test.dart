import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_message_manager.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_conversation_manager.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_friendship_manager.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_reaction_result.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/third_party/scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/text_message_widget.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text/extended_text.dart';

void main() {
  for (final type in [TongueType.newMessages, TongueType.unreadMessages]) {
    testWidgets('新消息提示保持44高与同源箭头：${type.name}', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppThemeFactory.create(
            const AppNormalColorScheme(), Brightness.light),
        home: Scaffold(
            body: Align(
          alignment: Alignment.topLeft,
          child: MessageTongueWidget(
            tongueState:
                TongueState(type: type, newMessageCount: 100, unreadCount: 100),
            onTap: () {},
            backToLatestText: '返回最新',
            newMessageCountText: (count) => '$count',
          ),
        )),
      ));
      final size = tester.getSize(find.byType(MessageTongueWidget));
      expect(size.height, 44);
      expect(size.width, greaterThanOrEqualTo(132));
      expect(
          find.byIcon(type == TongueType.unreadMessages
              ? AppIcons.directionIcon2
              : AppIcons.directionIcon),
          findsOneWidget);
      expect(find.text('100'), findsOneWidget);
    });
  }

  testWidgets('文字气泡没有内部时间时不留空槽，有时间时保留分隔', (tester) async {
    final message = MessageInfo(
      msgID: 'text-layout',
      messageType: MessageType.text,
      messagePayload: TextMessagePayload(text: '单行消息'),
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      status: MessageStatus.sendSuccess,
    );
    Future<void> mount(bool showTime) => tester.pumpWidget(MaterialApp(
          theme: AppThemeFactory.create(
              const AppNormalColorScheme(), Brightness.light),
          home: Scaffold(
              body: Align(
            alignment: Alignment.topLeft,
            child: TextMessageWidget(
                message: message,
                isSelf: false,
                maxWidth: 390,
                config: ChatMessageListConfig(isShowTimeInBubble: showTime)),
          )),
        ));
    await mount(false);
    final text = tester.getRect(find.byType(ExtendedText));
    final bubble = tester.getRect(find.byType(TextMessageWidget));
    expect(bubble.width - text.width, closeTo(28, .01));
    expect(bubble.height, closeTo(40, .01));
    await mount(true);
    final visibleText = tester.getRect(find.byType(ExtendedText));
    final time = tester.getRect(find.byType(Text).last);
    expect(time.left - visibleText.right, closeTo(8, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('时间组24间隔、组内16间隔，宿主覆盖只改变组内间距', (tester) async {
    final original = TencentImSDKPlugin.v2TIMManager;
    TencentImSDKPlugin.v2TIMManager = _Sdk('/layout');
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    Future<void> mount(double spacing) => tester.pumpWidget(MaterialApp(
          theme: AppThemeFactory.create(
              const AppNormalColorScheme(), Brightness.light),
          home: Scaffold(
              body: Column(children: [
            MessageList(
              conversationID: 'c2c_visual',
              config: ChatMessageListConfig(
                  cellSpacing: spacing, isShowRightAvatar: true),
            )
          ])),
        ));
    Rect bubble(String id) => tester.getRect(find.byWidgetPredicate(
          (widget) => widget is TextMessageWidget && widget.message.msgID == id,
        ));
    await mount(const ChatMessageListConfig().cellSpacing);
    await tester.pumpAndSettle();
    final first = bubble('first');
    final second = bubble('second');
    final third = bubble('third');
    expect(first.top, closeTo(16 + 21 + 16, .01));
    expect(second.top - first.bottom, closeTo(24 + 21 + 16, .01));
    expect(third.top - second.bottom, closeTo(16, .01));
    await mount(32);
    await tester.pumpAndSettle();
    expect(bubble('second').top - bubble('first').bottom, closeTo(61, .01));
    expect(bubble('third').top - bubble('second').bottom, closeTo(32, .01));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  testWidgets('长会话滚离最新位置后收到新消息保留数量提示', (tester) async {
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/history');
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeFactory.create(
          const AppNormalColorScheme(), Brightness.light),
      home: const Scaffold(
          body: Column(children: [
        MessageList(
          conversationID: 'c2c_history_visual',
          config: ChatMessageListConfig(isShowRightAvatar: true),
        )
      ])),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    final list = find.byType(ScrollablePositionedList);
    await tester.drag(list, const Offset(0, 400));
    await tester.pumpAndSettle();
    final positions = tester
        .widget<ScrollablePositionedList>(list)
        .itemPositionsNotifier!
        .itemPositions
        .value;
    expect(positions.any((p) => p.index <= 1), isFalse);
    final visibleAnchor = positions.where((p) => p.itemLeadingEdge >= 0).reduce(
          (a, b) => a.itemLeadingEdge < b.itemLeadingEdge ? a : b,
        );
    final anchorID = 'history-${20 - visibleAnchor.index}';
    final anchorFinder = find.byWidgetPredicate((widget) =>
        widget is TextMessageWidget && widget.message.msgID == anchorID);
    final anchorTop = tester.getTopLeft(anchorFinder).dy;

    sdk.messages.listener!.onRecvNewMessage(_Message('new-21'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageTongueWidget), findsOneWidget);
    expect(find.text('1 条新消息'), findsOneWidget);
    for (var index = 22; index <= 120; index++) {
      sdk.messages.listener!.onRecvNewMessage(_Message('new-$index'));
    }
    await tester.pumpAndSettle();
    expect(find.text('100 条新消息'), findsOneWidget);
    expect(tester.getTopLeft(anchorFinder).dy, closeTo(anchorTop, .01));
    // 新一批消息尚未完成布局就退出，旧回调也不能访问已销毁的列表。
    sdk.messages.listener!.onRecvNewMessage(_Message('new-121'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

final class _Sdk implements V2TIMManager {
  _Sdk(String scene)
      : conversations = _Conversations(scene),
        messages = _Messages(scene);
  final _Conversations conversations;
  final _Messages messages;
  final friends = _Friends();
  @override
  dynamic noSuchMethod(Invocation call) => switch (call.memberName) {
        #getConversationManager => conversations,
        #getMessageManager => messages,
        #getFriendshipManager => friends,
        #callExperimentalAPI => Future.value(
            V2TimValueCallback<String>(code: 0, desc: '', data: ''),
          ),
        _ => throw StateError('夹具未覆盖SDK入口: ${call.memberName}'),
      };
}

final class _Conversations implements V2TIMConversationManager {
  _Conversations(this.scene);
  final String scene;
  @override
  dynamic noSuchMethod(Invocation call) => switch (call.memberName) {
        #getConversation => Future.value(
            V2TimValueCallback<V2TimConversation>(
              code: 0,
              desc: '',
              data: V2TimConversation(
                conversationID: 'c2c_visual',
                userID: 'visual',
                type: 1,
                showName: '杨洋阳 (一只羊)',
                draftText: scene == '/single'
                    ? '你好，很高兴认识你'
                    : scene == '/multi'
                        ? '你好，很高兴认识你。你好，很高兴认识你。你好，很高兴认识你。你好，很高兴认识你。你好，很高兴认识你。你好，很高兴认识你。'
                        : '',
              ),
            ),
          ),
        #getTotalUnreadMessageCount => Future.value(
            V2TimValueCallback<int>(code: 0, desc: '', data: 0),
          ),
        #getConversationListByFilter => Future.value(
            V2TimValueCallback<V2TimConversationResult>(
              code: 0,
              desc: '',
              data: V2TimConversationResult(
                  isFinished: true, conversationList: []),
            ),
          ),
        #cleanConversationUnreadMessageCount ||
        #setConversationDraft ||
        #markC2CMessageAsRead ||
        #markGroupMessageAsRead =>
          Future.value(V2TimCallback(code: 0, desc: '')),
        #addConversationListener ||
        #removeConversationListener =>
          Future<void>.value(),
        _ => throw StateError('夹具未覆盖会话入口: ${call.memberName}'),
      };
}

final class _Messages implements V2TIMMessageManager {
  _Messages(this.scene);
  final String scene;
  V2TimAdvancedMsgListener? listener;
  bool _historyLoaded = false;
  List<V2TimMessage> _history() {
    if (scene != '/history') {
      return [_Message('third'), _Message('second'), _Message('first')];
    }
    if (_historyLoaded) return [];
    _historyLoaded = true;
    return List.generate(20, (index) => _Message('history-${20 - index}'));
  }

  @override
  dynamic noSuchMethod(Invocation call) => switch (call.memberName) {
        #getHistoryMessageList => Future.value(
            V2TimValueCallback<List<V2TimMessage>>(
              code: 0,
              desc: '',
              data: _history(),
            ),
          ),
        #addAdvancedMsgListener => Future<void>.sync(() {
            listener =
                call.namedArguments[#listener] as V2TimAdvancedMsgListener;
          }),
        #removeAdvancedMsgListener => Future<void>.value(),
        #getMessageReactions => Future.value(
            V2TimValueCallback<List<V2TimMessageReactionResult>>(
              code: 0,
              desc: '',
              data: [],
            ),
          ),
        #markC2CMessageAsRead ||
        #markGroupMessageAsRead =>
          Future.value(V2TimCallback(code: 0, desc: '')),
        _ => throw StateError('夹具未覆盖消息入口: ${call.memberName}'),
      };
}

final class _Friends implements V2TIMFriendshipManager {
  @override
  dynamic noSuchMethod(Invocation call) => switch (call.memberName) {
        #addFriendListener || #removeFriendListener => Future<void>.value(),
        _ => throw StateError('夹具未覆盖好友入口: ${call.memberName}'),
      };
}

/// SDK消息替身使用稳定时间与正文，避免原生构造器访问服务时间。
final class _Message implements V2TimMessage {
  _Message(this.msgID);
  @override
  final String msgID;
  @override
  dynamic noSuchMethod(Invocation call) => switch (call.memberName) {
        #seq => msgID.contains('-') ? msgID.split('-').last : null,
        #status => 2,
        #timestamp => DateTime.now()
                .copyWith(
                  day: DateTime.now().day - (msgID == 'first' ? 1 : 0),
                  hour: 18,
                  minute: msgID == 'third' ? 1 : 0,
                  second: 0,
                )
                .millisecondsSinceEpoch ~/
            1000,
        #elemType => 1,
        #sender || #userID => msgID.contains('-') ? 'history_visual' : 'visual',
        #isSelf ||
        #isRead ||
        #isPeerRead ||
        #needReadReceipt ||
        #isSupportMessageExtension =>
          false,
        #textElem => V2TimTextElem(text: msgID),
        #toJson => <String, dynamic>{'msgID': msgID},
        _ => null,
      };
}
