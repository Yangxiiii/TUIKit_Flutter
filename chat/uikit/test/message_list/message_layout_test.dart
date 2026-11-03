import 'dart:async';
import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_action_sheet.dart';
import 'package:tencent_chat_uikit/src/message_input/widget/message_edit_composer.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_overlay_avoider.dart';
import 'package:tencent_chat_uikit/src/third_party/scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/text_message_widget.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text/extended_text.dart';

void main() {
  for (final sameId in [true, false]) {
    testWidgets('HTTP搜索${sameId ? '相同ID' : '不同ID'}定位挂载后高亮一次并恢复',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final original = TencentImSDKPlugin.v2TIMManager;
      final sdk = _Sdk('/single');
      TencentImSDKPlugin.v2TIMManager = sdk;
      addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
      MessageList.clearViewportSnapshots();
      addTearDown(MessageList.clearViewportSnapshots);
      final gate = sdk.messages.historyGate =
          Completer<V2TimValueCallback<List<V2TimMessage>>>();
      final stamp = DateTime(2026, 11, 3, 12).millisecondsSinceEpoch ~/ 1000;
      // HTTP命中没有rawMessage，只保留后端提供的原消息ID、时间和序列号。
      final target = MessageInfo(
        msgID: sameId ? 'search-9' : 'server-key',
        timestamp: stamp + 9,
        sequence: 9,
        from: MessageSenderInfo(userID: 'history_visual'),
        conversationType: ConversationType.c2c,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
          MessageList(conversationID: 'c2c_visual', locateMessage: target),
        ])),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      gate.complete(V2TimValueCallback(code: 0, desc: '', data: [
        for (var i = 18; i >= 0; i--)
          _Message('search-$i', timestampOverride: stamp + i),
      ]));
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final row = find.byWidgetPredicate((widget) =>
          widget is MessageItem && widget.message.msgID == 'search-9');
      expect(row, findsOneWidget);
      expect(tester.widget<MessageItem>(row).isHighlighted, isTrue);
      final list = tester.widget<ScrollablePositionedList>(
          find.byType(ScrollablePositionedList));
      expect(
          list.itemPositionsNotifier!.itemPositions.value.any((position) =>
              position.index == 9 &&
              position.itemLeadingEdge >= 0 &&
              position.itemLeadingEdge < 1),
          isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<MessageItem>(row).isHighlighted, isTrue);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(tester.widget<MessageItem>(row).isHighlighted, isFalse);
      sdk.messages.listener!.onRecvMessageModified(
        _Message('search-9', timestampOverride: stamp + 9),
      );
      await tester.pump();
      expect(tester.widget<MessageItem>(row).isHighlighted, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final reason in ['重复候选', '缺少序列号', '发送者不匹配']) {
    testWidgets('HTTP搜索$reason时不误高亮其他消息', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final original = TencentImSDKPlugin.v2TIMManager;
      final sdk = _Sdk('/single');
      TencentImSDKPlugin.v2TIMManager = sdk;
      addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
      MessageList.clearViewportSnapshots();
      addTearDown(MessageList.clearViewportSnapshots);
      final stamp = DateTime(2026, 11, 3, 12).millisecondsSinceEpoch ~/ 1000;
      sdk.messages.historyGate =
          Completer<V2TimValueCallback<List<V2TimMessage>>>()
            ..complete(V2TimValueCallback(code: 0, desc: '', data: [
              for (var i = 17; i >= 0; i--)
                _Message('search-$i', timestampOverride: stamp + i),
              if (reason == '重复候选')
                _Message('duplicate-9', timestampOverride: stamp + 9),
            ]));
      final target = MessageInfo(
        msgID: 'server-key',
        timestamp: stamp + 9,
        sequence: reason == '缺少序列号' ? 0 : 9,
        from: MessageSenderInfo(
            userID: reason == '发送者不匹配' ? 'other' : 'history_visual'),
        conversationType: ConversationType.c2c,
      );
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Column(children: [
        MessageList(conversationID: 'c2c_visual', locateMessage: target),
      ]))));
      await tester.pumpAndSettle();
      expect(
          find.byWidgetPredicate(
              (widget) => widget is MessageItem && widget.isHighlighted),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('基类导航展示全局实时未读与统一姓名，0隐藏且超过99封顶', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    TencentImSDKPlugin.v2TIMManager = _Sdk('/single');
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    final unread = ValueNotifier<int>(0);
    addTearDown(unread.dispose);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      home: ChatPage(
          conversation: ConversationInfo(
              conversationID: 'c2c_visual',
              type: ConversationType.c2c,
              title: '旧标题'),
          displayName: '姓名 (昵称)',
          totalUnreadCount: unread),
    )));
    await tester.pumpAndSettle();
    expect(find.text('姓名 (昵称)'), findsOneWidget);
    expect(find.text('旧标题'), findsNothing);
    expect(
        find.byWidgetPredicate((w) =>
            w is Semantics && w.properties.identifier == 'tim.chat.unread'),
        findsNothing);
    for (final count in [1, 9, 10, 99, 100]) {
      unread.value = count;
      await tester.pump();
      final label = find.text(count > 99 ? '99+' : '$count');
      expect(label, findsOneWidget);
      final badge = find.descendant(
        of: find.byWidgetPredicate((w) =>
            w is Semantics && w.properties.identifier == 'tim.chat.unread'),
        matching: find.byType(Container),
      );
      final badgeSize = tester.getSize(badge);
      final textSize = tester.getSize(label);
      expect(tester.widget<Text>(label).style!.color,
          tester.element(label).appColors.textPrimary);
      expect(badgeSize.height, textSize.height);
      expect(
          badgeSize.width,
          closeTo(
              textSize.width <= textSize.height
                  ? textSize.height
                  : textSize.width + 8,
              .01));
      expect(
          (tester.widget<Container>(badge).decoration as BoxDecoration)
              .borderRadius,
          BorderRadius.circular(badgeSize.height / 2));
    }
    expect(tester.getCenter(find.text('姓名 (昵称)')).dx,
        closeTo(tester.getCenter(find.byType(AppBaseNavigationBar)).dx, .01));
    unread.value = 0;
    await tester.pump();
    expect(find.text('99+'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    unread.value = 3;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('本机窗口在云端完成前显示，实时消息和云端合并后无重复且不清空本地', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/single');
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    final cloud = sdk.messages.historyGate =
        Completer<V2TimValueCallback<List<V2TimMessage>>>();
    var readCalls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      MessageList(
        conversationID: 'c2c_visual',
        localMessagesLoader: () async =>
            [ChatUtil.convertToUIMessage(_Message('second'))],
        onInitialMessagesLoaded: () => readCalls++,
      )
    ])));
    await tester.pumpAndSettle();
    expect(find.byType(TextMessageWidget), findsOneWidget);
    expect(readCalls, 0);
    expect(sdk.messages.historyCalls, 1);
    for (final listener in [...sdk.messages.listeners]) {
      listener.onRecvNewMessage(_Message('third'));
    }
    await tester.pumpAndSettle();
    cloud.complete(
        V2TimValueCallback(code: 0, desc: '', data: [_Message('second')]));
    await tester.pumpAndSettle();
    final ids = tester
        .widgetList<MessageItem>(find.byType(MessageItem))
        .map((w) => w.message.msgID)
        .toList();
    expect(ids.toSet(), {'second', 'third'});
    expect(ids.length, 2);
    expect(readCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('本地窗口已滚到历史时，云端补到己方历史也保持当前消息锚点', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/single');
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    final cloud = sdk.messages.historyGate =
        Completer<V2TimValueCallback<List<V2TimMessage>>>();
    final stamp = DateTime(2026, 10, 30, 12).millisecondsSinceEpoch ~/ 1000;
    final raw = List.generate(
        20, (i) => _Message('local-${i + 1}', timestampOverride: stamp + i));
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      MessageList(
          conversationID: 'c2c_visual',
          localMessagesLoader: () async =>
              raw.reversed.map(ChatUtil.convertToUIMessage).toList())
    ])));
    await tester.pumpAndSettle();
    final list = tester.widget<ScrollablePositionedList>(
        find.byType(ScrollablePositionedList));
    list.itemScrollController!.jumpTo(index: 10, alignment: .1);
    await tester.pumpAndSettle();
    final target = find.byWidgetPredicate(
        (w) => w is MessageItem && w.message.msgID == 'local-10');
    final top = tester.getTopLeft(target).dy;
    cloud.complete(V2TimValueCallback(code: 0, desc: '', data: [
      _Message('synced-self',
          timestampOverride: stamp + 30, isSelfOverride: true),
      ...raw.reversed.take(18)
    ]));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(target).dy, closeTo(top, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('本地消息在云端失败后保留，显式定位不调用最新本地加载器', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    var localCalls = 0;
    for (final locate in [false, true]) {
      final sdk = _Sdk('/single');
      TencentImSDKPlugin.v2TIMManager = sdk;
      MessageList.clearViewportSnapshots();
      final cloud = sdk.messages.historyGate =
          Completer<V2TimValueCallback<List<V2TimMessage>>>();
      await tester.pumpWidget(MaterialApp(
          home: Column(children: [
        MessageList(
            conversationID: 'c2c_visual',
            locateMessage:
                locate ? ChatUtil.convertToUIMessage(_Message('first')) : null,
            localMessagesLoader: () async {
              localCalls++;
              return [ChatUtil.convertToUIMessage(_Message('second'))];
            })
      ])));
      await tester.pumpAndSettle();
      expect(localCalls, 1);
      cloud.complete(V2TimValueCallback(code: 1, desc: '离线'));
      await tester.pumpAndSettle();
      if (!locate) expect(find.byType(TextMessageWidget), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('双向头像聚合保留列宽和8像素间距，每条气泡保持独立', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/single');
    final stamp = DateTime(2026, 10, 30, 12).millisecondsSinceEpoch ~/ 1000;
    sdk.messages.chronologicalHistory = [
      _Message('incomingA', timestampOverride: stamp),
      _Message('incomingB', timestampOverride: stamp + 30),
      _Message('outgoingA',
          timestampOverride: stamp + 40, isSelfOverride: true),
      _Message('outgoingB',
          timestampOverride: stamp + 60, isSelfOverride: true),
    ];
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      MessageList(
          conversationID: 'c2c_visual',
          aggregateMessages: true,
          config: const ChatMessageListConfig(isShowRightAvatar: true))
    ])));
    await tester.pumpAndSettle();
    Finder item(String id) => find
        .byWidgetPredicate((w) => w is MessageItem && w.message.msgID == id);
    Finder bubble(String id) =>
        find.descendant(of: item(id), matching: find.byType(TextMessageWidget));
    for (final prefix in ['incoming', 'outgoing']) {
      expect(tester.widget<MessageItem>(item('${prefix}A')).isContinuation,
          isFalse);
      expect(tester.widget<MessageItem>(item('${prefix}B')).isContinuation,
          isTrue);
      final hidden = find.descendant(
          of: item('${prefix}B'), matching: find.byType(Visibility));
      expect(
          tester
              .widgetList<Visibility>(hidden)
              .any((w) => !w.visible && w.maintainSize),
          isTrue);
      final first = tester.getRect(bubble('${prefix}A'));
      final next = tester.getRect(bubble('${prefix}B'));
      expect(prefix == 'incoming' ? next.left : next.right,
          closeTo(prefix == 'incoming' ? first.left : first.right, .01));
      expect(next.top - first.bottom, closeTo(8, .01));
    }
    expect(find.byType(TextMessageWidget), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('仅成功消息可删除，二次确认取消零调用且删除成功通知宿主', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    final deleted = <String>[];
    Finder control(String id) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.identifier == id);
    for (final status in [1, 3, 2]) {
      Future<void> settle() async {
        if (status == 1) {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump();
        } else {
          await tester.pumpAndSettle();
        }
      }

      final sdk = _Sdk('/single');
      sdk.messages.chronologicalHistory = [
        _Message('target', statusOverride: status, isSelfOverride: true)
      ];
      TencentImSDKPlugin.v2TIMManager = sdk;
      MessageList.clearViewportSnapshots();
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
        navigatorObservers: [AppDialog.observer],
        builder: AppDialog.init(),
        home: ChatPage(
            conversation: ConversationInfo(
                conversationID: 'c2c_visual', type: ConversationType.c2c),
            enableSuccessfulDelete: true,
            messageListConfig:
                const ChatMessageListConfig(isSupportDelete: false),
            messageInputConfig:
                ChatMessageInputConfig(actionGuard: ActionGuard()),
            messageStickyConfig: ChatMessageStickyConfig(
                pin: (_) async => null,
                bannerBuilder: (_, locate) => const SizedBox.shrink(),
                onMessagesChanged: (_) {},
                onMessagesDeleted: deleted.addAll,
                onInitialLoadFinished: () {})),
      )));
      await settle();
      await tester.longPress(find.byType(TextMessageWidget));
      await settle();
      final entry = control('tim.message.action.delete');
      expect(tester.widget<Semantics>(entry).properties.enabled, status == 2);
      if (status == 2) {
        await tester.tap(entry);
        await settle();
        expect(sdk.messages.deleteCalls, 0);
        expect(deleted, isEmpty);
        await tester.tap(control('tim.message.delete.confirm.cancel'));
        await settle();
        expect(sdk.messages.deleteCalls, 0);
        expect(find.byType(TextMessageWidget), findsOneWidget);
        await tester.longPress(find.byType(TextMessageWidget));
        await settle();
        await tester.tap(control('tim.message.action.delete'));
        await settle();
        await tester.tap(control('tim.message.delete.confirm.confirm'));
        await settle();
        expect(sdk.messages.deleteCalls, 1);
        expect(deleted, ['target']);
        expect(find.byType(TextMessageWidget), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await settle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('失败图标打开精确重发确认，取消不重试，确认恢复原上传任务', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/single');
    sdk.messages.chronologicalHistory = [
      _Message('failed', statusOverride: 3, isSelfOverride: true)
    ];
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    var retries = 0;
    Finder control(String id) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.identifier == id);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      navigatorObservers: [AppDialog.observer],
      builder: AppDialog.init(),
      home: ChatPage(
          conversation: ConversationInfo(
              conversationID: 'c2c_visual', type: ConversationType.c2c),
          enableSuccessfulDelete: true,
          messageInputConfig:
              ChatMessageInputConfig(actionGuard: ActionGuard()),
          messageListConfig:
              ChatMessageListConfig(isSupportDelete: false, fileTransfers: {
            'failed': ChatFileTransferView(
                failed: true,
                retry: () async {
                  retries++;
                  return CompletionHandler();
                })
          })),
    )));
    await tester.pumpAndSettle();
    await tester.tap(control('tim.message.retry.failed'));
    await tester.pumpAndSettle();
    expect(find.text('发送失败，重发该消息？', findRichText: true), findsOneWidget);
    await tester.tap(control('tim.message.retry.confirm.cancel'));
    await tester.pumpAndSettle();
    expect(retries, 0);
    expect(sdk.messages.deleteCalls, 0);
    await tester.tap(control('tim.message.retry.failed'));
    await tester.pumpAndSettle();
    await tester.tap(control('tim.message.retry.confirm.confirm'));
    await tester.pumpAndSettle();
    expect(retries, 1);
    expect(sdk.messages.deleteCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('聊天复用基类导航且列表紧贴导航和输入，编辑期间返回只退出编辑', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/single');
    sdk.messages.chronologicalHistory = [
      _Message('third',
          timestampOverride: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1)
    ];
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    final navigator = GlobalKey<NavigatorState>();
    var settingsCalls = 0;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('会话列表')),
      ),
    ));
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => ChatPage(
        conversation: ConversationInfo(
          conversationID: 'c2c_visual',
          type: ConversationType.c2c,
          title: '测试会话',
        ),
        onOpenSettings: () async {
          settingsCalls++;
          return null;
        },
        messageEditConfig: ChatMessageEditConfig(
          canEdit: (_) => true,
          prepare: (_) async => (text: 'original', error: null),
          save: (_, __) async => null,
          onMessageWindowChanged: (_) {},
        ),
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(AppBaseNavigationBar), findsOneWidget);
    expect(
      tester
          .widget<AppBaseNavigationBar>(find.byType(AppBaseNavigationBar))
          .showBottomDivider,
      isTrue,
    );
    expect(find.text('测试会话'), findsOneWidget);
    expect(find.byIcon(AppIcons.back), findsOneWidget);
    expect(
      tester.getCenter(find.text('测试会话')).dx,
      closeTo(tester.getCenter(find.byType(AppBaseNavigationBar)).dx, .01),
    );
    final list = tester.getRect(find.byType(MessageOverlayAvoider));
    expect(
        list.top,
        closeTo(
            tester.getBottomLeft(find.byType(AppBaseNavigationBar)).dy, .01));
    expect(list.bottom,
        closeTo(tester.getTopLeft(find.byType(MessageInput)).dy, .01));
    final viewport = find.byType(ScrollablePositionedList);
    final outerPadding = tester.widget<Padding>(
        find.ancestor(of: viewport, matching: find.byType(Padding)).first);
    expect(outerPadding.padding.vertical, 0);
    // 设置入口仍由原聊天状态处理，不因导航栏迁移丢失回调。
    Finder control(String id) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.identifier == id);
    await tester.tap(control('tim.chat.settings'));
    await tester.pumpAndSettle();
    expect(settingsCalls, 1);
    await tester.longPress(find.byType(TextMessageWidget).first);
    await tester.pumpAndSettle();
    await tester.tap(control('tim.message.action.edit'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageEditComposer), findsOneWidget);
    await tester.tap(control('tim.chat.back'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageEditComposer), findsNothing);
    expect(find.byType(ChatPage), findsOneWidget);
    await tester.tap(control('tim.chat.back'));
    await tester.pumpAndSettle();
    expect(find.text('会话列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('退出短会话后收到新消息，再进入时消息仍连续排列', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/layout');
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    addTearDown(MessageList.clearViewportSnapshots);
    sdk.messages.chronologicalHistory = [_Message('first'), _Message('second')];
    Widget page() => MaterialApp(
          theme: AppThemeFactory.create(
              const AppNormalColorScheme(), Brightness.light),
          home: const Scaffold(
            body: Column(children: [MessageList(conversationID: 'c2c_visual')]),
          ),
        );
    Rect bubble(String id) => tester.getRect(find.byWidgetPredicate(
        (widget) => widget is TextMessageWidget && widget.message.msgID == id));

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    final previousTop = bubble('second').top;
    // 销毁页面保存阅读快照，再在 SDK 历史中补入新消息，走实际重新入场流程。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    sdk.messages.chronologicalHistory!.add(_Message('third'));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(bubble('third').top - bubble('second').bottom, closeTo(16, .01));
    expect(bubble('second').top, closeTo(previousTop, .01));

    // 相同消息首次进入与恢复快照的间距必须一致。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    MessageList.clearViewportSnapshots();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(bubble('third').top - bubble('second').bottom, closeTo(16, .01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('首屏消息先加载，置顶辅助请求挂起或失败不影响消息显示', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/single');
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    final history = sdk.messages.historyGate =
        Completer<V2TimValueCallback<List<V2TimMessage>>>();
    final sticky = Completer<void>();
    var stickyCalls = 0, stickyErrors = 0, loadedCalls = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeFactory.create(
          const AppNormalColorScheme(), Brightness.light),
      home: ProviderScope(
          child: ChatPage(
        conversation: ConversationInfo(
            conversationID: 'c2c_visual', type: ConversationType.c2c),
        onInitialMessagesLoaded: () => loadedCalls++,
        messageStickyConfig: ChatMessageStickyConfig(
          pin: (_) async => null,
          bannerBuilder: (_, __) => const SizedBox.shrink(),
          onMessagesChanged: (_) {},
          onMessagesDeleted: (_) {},
          onInitialLoadFinished: () {
            stickyCalls++;
            unawaited(sticky.future.catchError((Object _) {
              stickyErrors++;
            }));
          },
        ),
      )),
    ));
    await tester.pump();
    expect(sdk.messages.historyCalls, 1);
    expect(stickyCalls, 0);
    history.complete(V2TimValueCallback<List<V2TimMessage>>(
      code: 0,
      desc: '',
      data: [_Message('first')],
    ));
    await tester.pumpAndSettle();
    expect(stickyCalls, 1);
    expect(loadedCalls, 1);
    expect(find.byType(TextMessageWidget), findsOneWidget);
    sticky.completeError(StateError('StickyMessage/Get 超时'));
    await tester.pumpAndSettle();
    expect(stickyErrors, 1);
    expect(find.byType(TextMessageWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首屏空结果和失败也结束辅助等待，但不能清未读', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    for (final code in [0, 1]) {
      final sdk = _Sdk('/single');
      TencentImSDKPlugin.v2TIMManager = sdk;
      MessageList.clearViewportSnapshots();
      final history = sdk.messages.historyGate =
          Completer<V2TimValueCallback<List<V2TimMessage>>>();
      var finished = 0, loaded = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppThemeFactory.create(
            const AppNormalColorScheme(), Brightness.light),
        home: Column(children: [
          MessageList(
            conversationID: 'c2c_visual',
            onInitialLoadFinished: () => finished++,
            onInitialMessagesLoaded: () => loaded++,
          )
        ]),
      ));
      history.complete(V2TimValueCallback<List<V2TimMessage>>(
          code: code, desc: '', data: []));
      await tester.pumpAndSettle();
      expect(finished, 1);
      expect(loaded, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('长按和松手只打开操作面板，点击多选才进入多选', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/single');
    sdk.messages.chronologicalHistory = [
      _Message('third',
          timestampOverride: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1)
    ];
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeFactory.create(
          const AppNormalColorScheme(), Brightness.light),
      home: ProviderScope(
          child: ChatPage(
        conversation: ConversationInfo(
            conversationID: 'c2c_visual', type: ConversationType.c2c),
        messageEditConfig: ChatMessageEditConfig(
          canEdit: (_) => true,
          prepare: (_) async => (text: 'original', error: null),
          save: (id, text) async => null,
          onMessageWindowChanged: (_) {},
        ),
      )),
    ));
    await tester.pumpAndSettle();
    final bubble = find.byType(TextMessageWidget).first;
    final bubbleState = tester.state(find.byType(MessageBubble).first);
    // 保持长按再松手，两阶段都只能展示操作面板，不能选中消息。
    final gesture = await tester.startGesture(tester.getCenter(bubble));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.byType(MessageActionSheet), findsOneWidget);
    expect(
        tester
            .widgetList<MessageItem>(find.byType(MessageItem))
            .any((w) => w.isMultiSelectMode),
        isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(MessageActionSheet), findsOneWidget);
    expect(
        tester
            .widgetList<MessageItem>(find.byType(MessageItem))
            .any((w) => w.isMultiSelectMode),
        isFalse);
    final multiSelect = find.byWidgetPredicate((w) =>
        w is Semantics &&
        w.properties.identifier == 'tim.message.action.multiSelect');
    // 明确点击面板动作后才允许进入多选，气泡实例和锚点应保持不变。
    await tester.tap(multiSelect);
    await tester.pumpAndSettle();
    expect(find.byType(MessageActionSheet), findsNothing);
    expect(
        tester
            .widgetList<MessageItem>(find.byType(MessageItem))
            .every((w) => w.isMultiSelectMode),
        isTrue);
    expect(find.byType(MessageEditComposer), findsNothing);
    expect(
        tester
            .widgetList<MessageItem>(find.byType(MessageItem))
            .where((w) => w.isSelected),
        isEmpty);
    // 初始零条，只有手动点击复选框才增减选择，不能沿用长按目标。
    await tester.tap(find.byType(MessageCheckbox).first);
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<MessageItem>(find.byType(MessageItem))
            .where((w) => w.isSelected),
        hasLength(1));
    await tester.tap(find.byType(MessageCheckbox).first);
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<MessageItem>(find.byType(MessageItem))
            .where((w) => w.isSelected),
        isEmpty);
    expect(tester.state(find.byType(MessageBubble).first), same(bubbleState));
    // 已有多选状态不能跟随下一次长按进入操作面板，编辑和多选互斥。
    await tester.longPress(find.byType(TextMessageWidget).first);
    await tester.pumpAndSettle();
    expect(find.byType(MessageActionSheet), findsOneWidget);
    expect(
        tester
            .widgetList<MessageItem>(find.byType(MessageItem))
            .any((w) => w.isMultiSelectMode),
        isFalse);
    await tester.tap(find.byWidgetPredicate((w) =>
        w is Semantics &&
        w.properties.identifier == 'tim.message.action.edit'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageEditComposer), findsOneWidget);
    expect(tester.state(find.byType(MessageBubble).first), same(bubbleState));
    expect(
        tester
            .widgetList<MessageItem>(find.byType(MessageItem))
            .any((w) => w.isMultiSelectMode),
        isFalse);
    await tester.tap(find.byWidgetPredicate((w) =>
        w is Semantics && w.properties.identifier == 'tim.message.editCancel'));
    // 编辑取消后再用菜单，验证保留的气泡没有继续使用上一模式的旧回调。
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(TextMessageWidget).first);
    await tester.pumpAndSettle();
    await tester.tap(multiSelect);
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<MessageItem>(find.byType(MessageItem))
            .every((w) => w.isMultiSelectMode),
        isTrue);
    expect(
        tester
            .widgetList<MessageItem>(find.byType(MessageItem))
            .where((w) => w.isSelected),
        isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

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
  Completer<V2TimValueCallback<List<V2TimMessage>>>? historyGate;
  int historyCalls = 0;
  int deleteCalls = 0;

  /// 按时间正序排列的可变历史，用于模拟页面关闭期间收到新消息。
  List<V2TimMessage>? chronologicalHistory;

  /// 可变历史按 SDK 游标分页，其他场景继续使用原有挂起或固定响应。
  Future<V2TimValueCallback<List<V2TimMessage>>> _loadHistory(Invocation call) {
    historyCalls++;
    final history = chronologicalHistory;
    if (history != null) {
      // SDK 旧消息页倒序、新消息页正序，且两页均不重复返回游标自身。
      final cursor = (call.namedArguments[#lastMsg] as V2TimMessage?)?.msgID;
      final index = history.indexWhere((message) => message.msgID == cursor);
      assert(cursor == null || index >= 0);
      final newer = call.namedArguments[#getType] ==
          HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG;
      final messages = cursor == null
          ? history.reversed.toList()
          : newer
              ? history.skip(index + 1).toList()
              : history.take(index).toList().reversed.toList();
      return Future.value(
          V2TimValueCallback(code: 0, desc: '', data: messages));
    }
    return historyGate?.future ??
        Future.value(
          V2TimValueCallback<List<V2TimMessage>>(
              code: 0, desc: '', data: _history()),
        );
  }

  final listeners = <V2TimAdvancedMsgListener>[];
  V2TimAdvancedMsgListener? get listener =>
      listeners.isEmpty ? null : listeners.first;
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
        #deleteMessages => Future<V2TimCallback>.sync(() {
            deleteCalls++;
            return V2TimCallback(code: 0, desc: '');
          }),
        #getHistoryMessageList => _loadHistory(call),
        #addAdvancedMsgListener => Future<void>.sync(() {
            listeners.add(
                call.namedArguments[#listener] as V2TimAdvancedMsgListener);
          }),
        #removeAdvancedMsgListener => Future<void>.sync(() {
            listeners.remove(call.namedArguments[#listener]);
          }),
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
  _Message(this.msgID,
      {this.timestampOverride,
      this.statusOverride = 2,
      this.isSelfOverride = false});
  final int? timestampOverride;
  final int statusOverride;
  final bool isSelfOverride;
  @override
  final String msgID;
  @override
  dynamic noSuchMethod(Invocation call) => switch (call.memberName) {
        #seq => msgID.contains('-') ? msgID.split('-').last : null,
        #status => statusOverride,
        #timestamp => timestampOverride ??
            DateTime.now()
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
        #isSelf => isSelfOverride,
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
