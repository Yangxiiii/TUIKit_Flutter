import 'dart:async';
import 'package:atomic_x_core/impl/message/message_action_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_input_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_list_store_impl.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_bubble.dart';
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
import 'package:tencent_cloud_chat_sdk/models/v2_tim_merger_elem.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/merged_message_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/merged_message_detail_page.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_reaction_result.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_overlay_avoider.dart';
import 'package:tencent_chat_uikit/src/third_party/scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/text_message_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/file_message_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/video_message_widget.dart';
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

  testWidgets('从搜索返回已打开的聊天时使用唯一归档定位键高亮', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/single');
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    addTearDown(MessageList.clearViewportSnapshots);
    final target = ValueNotifier<MessageInfo?>(null);
    addTearDown(target.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          ValueListenableBuilder(
            valueListenable: target,
            builder: (_, message, __) => MessageList(
              conversationID: 'c2c_visual',
              locateMessage: message,
            ),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    final stamp = DateTime(2026, 11, 3, 12).millisecondsSinceEpoch ~/ 1000;
    final gate = sdk.messages.historyGate =
        Completer<V2TimValueCallback<List<V2TimMessage>>>();
    target.value = MessageInfo(
      msgID: 'archive-key',
      timestamp: stamp + 9,
      sequence: 9,
      from: MessageSenderInfo(userID: 'history_visual'),
      conversationType: ConversationType.c2c,
    );
    await tester.pump();
    gate.complete(V2TimValueCallback(code: 0, desc: '', data: [
      for (var index = 12; index >= 0; index--)
        _Message('search-$index', timestampOverride: stamp + index),
    ]));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final row = find.byWidgetPredicate((widget) =>
        widget is MessageItem && widget.message.msgID == 'search-9');
    expect(row, findsOneWidget);
    expect(tester.widget<MessageItem>(row).isHighlighted, isTrue);
    await tester.pumpAndSettle();
  });

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

  testWidgets('聊天点击合并记录后通过全局Sheet显示正文、滚动并关闭', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 24);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/single');
    sdk.messages.chronologicalHistory = [_Message('merged', isMerged: true)];
    sdk.messages.mergedContents = [
      _Message('record-0'),
      _Message('record-1'),
      _Message('record-2', isSelfOverride: true),
      _Message('nested', isMerged: true),
      for (var i = 4; i < 20; i++) _Message('record-$i'),
    ];
    var forwarded = 0;
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    addTearDown(MessageList.clearViewportSnapshots);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      navigatorObservers: [AppDialog.observer],
      builder: AppDialog.init(),
      home: ChatPage(
          messageListConfig: ChatMessageListConfig(
              isShowRightAvatar: true,
              textBubbleCornerRadius: 8,
              forwardHandler: (_, request) async {
                forwarded++;
                return false;
              }),
          conversation: ConversationInfo(
              conversationID: 'c2c_visual', type: ConversationType.c2c)),
    )));
    await tester.pumpAndSettle();
    Color currentMask() => tester
        .widgetList<Container>(find.byType(Container))
        .map((widget) => widget.color)
        .whereType<Color>()
        .singleWhere((color) =>
            color.a > 0 &&
            color.a < 1 &&
            color.r == 0 &&
            color.g == 0 &&
            color.b == 0);
    // 先读取普通弹窗实际渲染的遮罩，再对照生产合并详情入口，避免两者独立取色。
    final alert = AppDialog.showAlert(content: '遮罩对照');
    await tester.pumpAndSettle();
    final normalMask = currentMask();
    final dismissAlert = AppDialog.dismiss();
    await tester.pumpAndSettle();
    await dismissAlert;
    await alert;
    await tester.tap(find.byType(MergedMessageWidget));
    await tester.pumpAndSettle();
    expect(currentMask(), normalMask);
    expect(tester.takeException(), isNull);
    final detail = find.byType(MergedMessageDetailPage);
    expect(detail, findsOneWidget);
    // 设计保留顶部安全区及12像素留白，整张Sheet与正文都使用白色承载面。
    final sheet =
        find.ancestor(of: detail, matching: find.byType(Material)).first;
    final sheetBounds = tester.getRect(sheet);
    expect(sheetBounds.height, closeTo(844 - 44 - 12, .01));
    expect(sheetBounds.top, closeTo(44 + 12, .01));
    expect(tester.getSize(detail).height, closeTo(844 - 44 - 24 - 12, .01));
    const colors = AppNormalColorScheme();
    final detailScaffold =
        find.descendant(of: detail, matching: find.byType(Scaffold));
    final header = find.descendant(of: detail, matching: find.byType(AppBar));
    expect(tester.widget<Material>(sheet).color, colors.surface);
    expect(tester.widget<Scaffold>(detailScaffold).backgroundColor,
        colors.surface);
    expect(tester.widget<AppBar>(header).backgroundColor, colors.surface);
    expect(tester.widget<AppBar>(header).scrolledUnderElevation, 0);
    expect(tester.getSize(header).height, 48);
    expect(tester.widget<Scaffold>(detailScaffold).primary, isFalse);
    final closeButton = find.bySemanticsIdentifier('tim.forward.merged.close');
    final closeTop = tester.getTopLeft(closeButton).dy;
    final items = tester
        .widgetList<MessageItem>(
            find.descendant(of: detail, matching: find.byType(MessageItem)))
        .toList();
    final first = items.singleWhere((item) => item.message.msgID == 'record-0');
    final second =
        items.singleWhere((item) => item.message.msgID == 'record-1');
    final outgoing =
        items.singleWhere((item) => item.message.msgID == 'record-2');
    expect(first.maxWidth, 390 - 32);
    expect(second.isContinuation, isTrue);
    expect(outgoing.message.isSentBySelf, isTrue);
    expect(outgoing.isContinuation, isFalse);
    expect(
        tester.getTopLeft(find.byWidget(second)).dy -
            tester.getBottomLeft(find.byWidget(first)).dy,
        closeTo(8, .01));
    for (final item in items) {
      expect(item.isInMergedDetailView, isTrue);
      expect(item.config.forwardHandler, isNull);
      expect(item.config.isSupportForward, isFalse);
      expect(item.config.isSupportMultiSelect, isFalse);
      expect(item.config.isSupportDelete, isFalse);
      expect(item.config.enableReadReceipt, isFalse);
      expect(item.config.textBubbleCornerRadius, 8);
    }
    // 来源已配置转发，详情仍不能长按打开菜单或执行转发。
    final body = find.descendant(
        of: find.byWidget(first), matching: find.byType(TextMessageWidget));
    await tester.longPress(body);
    await tester.pumpAndSettle();
    expect(find.byType(MessageActionSheet), findsNothing);
    expect(forwarded, 0);
    final semantics = find.descendant(
        of: detail,
        matching: find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.identifier?.startsWith('tim.record.message.') ==
                true));
    expect(semantics, findsWidgets);
    expect(
        tester
            .widgetList<Semantics>(semantics)
            .every((widget) => widget.properties.onLongPress == null),
        isTrue);
    // 点击包内合并卡片仍打开只读预览，关闭后回到原详情。
    await tester.tap(find.descendant(
        of: detail, matching: find.byType(MergedMessageWidget)));
    await tester.pumpAndSettle();
    expect(find.byType(MergedMessageDetailPage), findsNWidgets(2));
    await tester
        .tap(find.bySemanticsIdentifier('tim.forward.merged.close').last);
    await tester.pumpAndSettle();
    expect(detail, findsOneWidget);
    expect(
        find.descendant(of: detail, matching: find.byType(TextMessageWidget)),
        findsWidgets);
    final list = find.descendant(
        of: detail, matching: find.byType(ScrollablePositionedList));
    // 详情位于全局浮层而非页面路由下，滚动更新也不能强制依赖PageStorage。
    expect(PageStorage.maybeOf(tester.element(list)), isNull);
    await tester.drag(list, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.getRect(sheet), sheetBounds);
    expect(tester.getTopLeft(closeButton).dy, closeTop);
    expect(tester.takeException(), isNull);
    await tester.tap(closeButton);
    await tester.pumpAndSettle();
    expect(detail, findsNothing);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宿主本地删除收到成功标识后才清理首屏候选，空回执保留原消息', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const SizedBox.shrink();
    })));
    final message = MessageInfo(
        msgID: 'local',
        status: MessageStatus.sendSuccess,
        messageType: MessageType.text,
        messagePayload: TextMessagePayload(text: '本地正文'),
        from: MessageSenderInfo(userID: 'peer'));
    for (final succeeds in [false, true]) {
      var removed = 0;
      final callbacks = DefaultMessageMenuCallbacks(
        context: context,
        messageListStore: _UnusedMenuListStore(),
        messageActionStore: _UnusedMenuActionStore(),
        conversationID: 'c2c_peer',
        config: ChatMessageListConfig(
            localDeleteHandler: (_) async => succeeds ? [message.msgID] : []),
        onDeleted: () => removed++,
      );
      callbacks.onDeleteMessage(message);
      await tester.pumpAndSettle();
      expect(removed, succeeds ? 1 : 0);
    }
  });

  testWidgets('基类导航展示全局实时未读与统一姓名，0隐藏且超过99封顶', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/single');
    // 编辑交互必须使用仍在五分钟有效期内的消息，不能依赖测试执行时的时钟。
    sdk.messages.chronologicalHistory = [
      _Message('editable',
          timestampOverride: DateTime.now().millisecondsSinceEpoch ~/ 1000)
    ];
    TencentImSDKPlugin.v2TIMManager = sdk;
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

  testWidgets('较早的文件上传完成后仍显示在后来发送的文件上方', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    TencentImSDKPlugin.v2TIMManager = _Sdk('/single');
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    addTearDown(MessageList.clearViewportSnapshots);
    const conversationId = 'c2c_visual';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          MessageList(
            conversationID: conversationId,
            localMessagesLoader: () async => [],
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    MessageInfo uploading(String id, int timestamp) => MessageInfo(
          msgID: id,
          isSentBySelf: true,
          status: MessageStatus.sending,
          timestamp: timestamp,
          messageType: MessageType.file,
          messagePayload: FileMessagePayload(fileName: '$id.pdf', fileSize: 1),
        );
    void begin(MessageInfo message) => notificationCenter.post(
          MessageSendNotifyKey.messageSendBegin,
          MessageSendEventData(
              conversationID: conversationId, message: message),
        );
    Finder row(String id) => find.byWidgetPredicate(
          (widget) => widget is MessageItem && widget.message.msgID == id,
        );
    final first = uploading('oa_upload_first', 100);
    final second = uploading('oa_upload_second', 101);
    begin(first);
    begin(second);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.getTopLeft(row(first.msgID)).dy,
        lessThan(tester.getTopLeft(row(second.msgID)).dy));

    // SDK 先追加正式消息，宿主稍后删除本地占位。
    begin(MessageInfo(
      msgID: 'sdk-first',
      isSentBySelf: true,
      status: MessageStatus.sending,
      timestamp: 102,
      messageType: MessageType.custom,
      messagePayload: CustomMessagePayload(
        extensionInfo: first.msgID,
        customData: const BigFileMessage(
                url: 'https://files.test/first.pdf', name: 'first.pdf', size: 1)
            .toCustomData(),
      ),
    ));
    await tester.pump();
    expect(row(first.msgID), findsNothing);
    notificationCenter.post(MessageActionNotifyKey.messageDelete,
        MessageDeleteEventData(messageIDList: [first.msgID]));
    await tester.pump();
    expect(tester.getTopLeft(row('sdk-first')).dy,
        lessThan(tester.getTopLeft(row(second.msgID)).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('单聊文件和视频从上传切换为已发送时卡片尺寸不变', (tester) async {
    const file = BigFileMessage(
        url: 'https://files.test/a.mp4', name: '压缩视频.mp4', size: 104857601);
    final uploading = MessageInfo(
      msgID: 'album_upload',
      isSentBySelf: true,
      status: MessageStatus.sending,
      messageType: MessageType.file,
      messagePayload: FileMessagePayload(
          fileName: file.name, fileSize: file.size, filePath: '/cache/a.mp4'),
    );
    final sent = MessageInfo(
      msgID: 'sent',
      isSentBySelf: true,
      status: MessageStatus.sendSuccess,
      messageType: MessageType.custom,
      needReadReceipt: true,
      conversationType: ConversationType.c2c,
      messagePayload: CustomMessagePayload(customData: file.toCustomData()),
    );
    Future<Rect> card(MessageInfo message, bool receipt,
        [Type type = FileMessageWidget]) async {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 358,
            child: MessageItem(
              message: message,
              conversationID: 'c2c_visual',
              maxWidth: 358,
              config: ChatMessageListConfig(
                isShowRightAvatar: true,
                enableReadReceipt: receipt,
                fileTransfers: const {
                  'album_upload': ChatFileTransferView(progress: .5)
                },
              ),
              messageListStore: _UnusedMenuListStore(),
              isHighlighted: false,
            ),
          ),
        ),
      ));
      return tester.getRect(find.byType(type));
    }

    final initial = await card(uploading, true);
    for (final receipt in [false, true]) {
      final completed = await card(sent, receipt);
      expect(completed.size, initial.size);
      expect(completed.right, initial.right);
    }
    final video = MessageInfo(
      msgID: 'video',
      isSentBySelf: true,
      status: MessageStatus.sending,
      messageType: MessageType.video,
      needReadReceipt: true,
      conversationType: ConversationType.c2c,
      messagePayload: VideoMessagePayload(
          videoSnapshotPath: 'https://files.test/cover.jpg',
          videoSnapshotWidth: 1920,
          videoSnapshotHeight: 1080),
    );
    final videoUploading = await card(video, true, VideoMessageWidget);
    video.status = MessageStatus.sendSuccess;
    final videoSent = await card(video, true, VideoMessageWidget);
    expect(videoSent.size, videoUploading.size);
    expect(videoSent.right, videoUploading.right);
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

  testWidgets('同秒实时插入对端消息后，己方下一条重新开始头像组', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/single');
    final stamp = DateTime(2026, 10, 30, 12).millisecondsSinceEpoch ~/ 1000;
    // 足够长的同秒窗口会触发旧排序的换位，打乱对端消息插入的位置。
    sdk.messages.chronologicalHistory = List.generate(
        40, (index) => _Message('history-$index', timestampOverride: stamp));
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    addTearDown(MessageList.clearViewportSnapshots);
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        MessageList(
          conversationID: 'c2c_visual',
          aggregateMessages: true,
          localMessagesLoader: () async => [],
          config: const ChatMessageListConfig(isShowRightAvatar: true),
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    Future<void> append(String id, {required bool isSelf}) async {
      final message =
          _Message(id, timestampOverride: stamp, isSelfOverride: isSelf);
      sdk.messages.listener!.onRecvNewMessage(message);
      await tester.pumpAndSettle();
    }

    Finder item(String id) => find.byWidgetPredicate(
        (widget) => widget is MessageItem && widget.message.msgID == id);
    bool continues(String id) =>
        tester.widget<MessageItem>(item(id)).isContinuation;
    await append('selfFirst', isSelf: true);
    await append('selfSecond', isSelf: true);
    expect(continues('selfSecond'), isTrue);
    await append('peer', isSelf: false);
    await append('selfRestart', isSelf: true);
    expect(continues('peer'), isFalse);
    expect(continues('selfRestart'), isFalse);
    await append('selfNext', isSelf: true);
    expect(continues('selfNext'), isTrue);
    final ids = ['selfFirst', 'selfSecond', 'peer', 'selfRestart', 'selfNext'];
    final positions = ids.map((id) => tester.getTopLeft(item(id)).dy).toList();
    expect(positions, orderedEquals(positions.toList()..sort()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('连续通话记录按展示方聚合，切换气泡侧时显示首条头像', (tester) async {
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
    final cloud = sdk.messages.historyGate =
        Completer<V2TimValueCallback<List<V2TimMessage>>>();
    final stamp = DateTime(2026, 10, 30, 12).millisecondsSinceEpoch ~/ 1000;
    MessageInfo incomingCall(String id, int timestamp, bool sentBySelf) =>
        MessageInfo(
          msgID: id,
          timestamp: timestamp,
          isSentBySelf: sentBySelf,
          from: MessageSenderInfo(userID: sentBySelf ? 'self' : 'visual'),
          to: 'visual',
          messageType: MessageType.custom,
          messagePayload: CustomMessagePayload(
            customData: '{"actionType":1,"data":{"businessID":"av_call",'
                '"call_type":2,"call_end":4,"data":{"cmd":"hangup",'
                '"inviter":"visual"}}}',
          ),
        );
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        MessageList(
          conversationID: 'c2c_visual',
          aggregateMessages: true,
          config: const ChatMessageListConfig(isShowRightAvatar: true),
          localMessagesLoader: () async => [
            MessageInfo(
              msgID: 'outgoingText',
              timestamp: stamp,
              from: MessageSenderInfo(userID: 'self'),
              isSentBySelf: true,
              messageType: MessageType.text,
              messagePayload: TextMessagePayload(text: '1'),
            ),
            // 两次来电由不同一方挂断，信令方向不同，气泡都在对端一侧。
            incomingCall('firstCall', stamp + 10, true),
            incomingCall('secondCall', stamp + 20, false),
          ],
        ),
      ]),
    ));
    await tester.pumpAndSettle();
    Finder item(String id) => find.byWidgetPredicate(
        (widget) => widget is MessageItem && widget.message.msgID == id);
    Finder bubble(String id) =>
        find.descendant(of: item(id), matching: find.byType(TextMessageWidget));
    expect(
        tester.widget<MessageItem>(item('firstCall')).isContinuation, isFalse);
    expect(
        tester.widget<MessageItem>(item('secondCall')).isContinuation, isTrue);
    final outgoing = tester.getRect(bubble('outgoingText'));
    final firstCall = tester.getRect(bubble('firstCall'));
    final secondCall = tester.getRect(bubble('secondCall'));
    expect(firstCall.left, lessThan(outgoing.left));
    expect(secondCall.left, closeTo(firstCall.left, .01));
    expect(secondCall.top - firstCall.bottom, closeTo(8, .01));
    cloud.complete(V2TimValueCallback(code: 1, desc: '离线'));
    await tester.pumpAndSettle();
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

  testWidgets('本机首屏先过滤已删除消息，SDK迟到时保留仍有效的本地多选', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/single');
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    final cloud = sdk.messages.historyGate =
        Completer<V2TimValueCallback<List<V2TimMessage>>>();
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: ChatPage(
      conversation:
          ConversationInfo(conversationID: 'c2c_visual', title: '本机窗口'),
      isShowAppBarActions: false,
      localMessagesLoader: () async => [
        ChatUtil.convertToUIMessage(_Message('first')),
        ChatUtil.convertToUIMessage(_Message('second')),
      ],
      messageListConfig: ChatMessageListConfig(
        hiddenMessageIDs: const {'first'},
        forwardHandler: (context, request) async => false,
      ),
    ))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<MessageItem>(find.byType(MessageItem))
            .map((item) => item.message.msgID),
        ['second']);
    await tester.longPress(find.byType(TextMessageWidget).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.identifier == 'tim.message.action.multiSelect'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MessageCheckbox).first);
    await tester.pumpAndSettle();
    // SDK尚未返回second时，实时third不能让本地已选项被错误剔除。
    for (final listener in [...sdk.messages.listeners]) {
      listener.onRecvNewMessage(_Message('third'));
    }
    await tester.pumpAndSettle();
    MessageItem selected() => tester
        .widgetList<MessageItem>(find.byType(MessageItem))
        .singleWhere((item) => item.message.msgID == 'second');
    expect(selected().isSelected, isTrue);
    cloud.complete(V2TimValueCallback(
        code: 0, desc: '', data: [_Message('first'), _Message('third')]));
    await tester.pumpAndSettle();
    expect(selected().isSelected, isTrue);
    expect(
        tester
            .widgetList<MessageItem>(find.byType(MessageItem))
            .any((item) => item.message.msgID == 'first'),
        isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
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

  testWidgets('仅接入宿主转发时也使用操作面板，多选可从真实聊天入口进入', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    TencentImSDKPlugin.v2TIMManager = _Sdk('/single');
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: ChatPage(
      conversation: ConversationInfo(
          conversationID: 'c2c_visual', type: ConversationType.c2c),
      messageListConfig: ChatMessageListConfig(
          isShowTimeMessage: false,
          forwardHandler: (context, request) async => false),
    ))));
    await tester.pumpAndSettle();
    final messageWindowTop = tester.getTopLeft(find.byType(MessageList)).dy;
    await tester.longPress(find.byType(TextMessageWidget).first);
    await tester.pumpAndSettle();
    expect(find.byType(MessageActionSheet), findsOneWidget);
    final id = tester
        .widget<MessageItem>(find.byType(MessageItem).first)
        .message
        .msgID;
    expect(find.bySemanticsIdentifier('tim.chat.message.$id'), findsOneWidget);
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.identifier == 'tim.message.action.multiSelect'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<MessageItem>(find.byType(MessageItem))
            .every((item) => item.isMultiSelectMode),
        isTrue);
    expect(find.byType(MultiSelectBottomBar), findsOneWidget);
    // 快选入口必须覆盖原消息窗口，不能再挤出顶部60像素的独立空白区。
    final messageWindow = tester.getRect(find.byType(MessageList));
    final selectBelow = tester.getRect(find.text('选择以下消息'));
    expect(messageWindow.top, messageWindowTop);
    expect(selectBelow.top, greaterThanOrEqualTo(messageWindow.top));
    expect(selectBelow.bottom, lessThan(messageWindow.top + 60));
    final boundary = tester.getCenter(find.text('选择以下消息')).dy;
    final before =
        tester.widgetList<MessageItem>(find.byType(MessageItem)).toList();
    final expected = {
      for (final item in before)
        if (tester.getTopLeft(find.byWidget(item)).dy >= boundary)
          item.message.msgID,
    };
    expect(expected, isNotEmpty);
    expect(expected.length, lessThan(before.length));
    await tester.tap(find.text('选择以下消息'));
    await tester.pumpAndSettle();
    expect({
      for (final item
          in tester.widgetList<MessageItem>(find.byType(MessageItem)))
        if (item.isSelected) item.message.msgID,
    }, expected);
    expect(tester.takeException(), isNull);
  });

  testWidgets('滚动后按横线实测位置补选，跨线消息排除且保留原选择', (tester) async {
    final original = TencentImSDKPlugin.v2TIMManager;
    TencentImSDKPlugin.v2TIMManager = _Sdk('/history');
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    addTearDown(MessageList.clearViewportSnapshots);
    MultiSelectState? selection;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      MessageList(
        conversationID: 'c2c_history_visual',
        config: const ChatMessageListConfig(isShowTimeMessage: false),
        onMultiSelectStateChanged: (value) => selection = value,
      ),
    ]))));
    await tester.pumpAndSettle();
    tester
        .widgetList<MessageItem>(find.byType(MessageItem))
        .first
        .onEnterMultiSelectMode!();
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(ScrollablePositionedList), const Offset(0, 400));
    await tester.pumpAndSettle();
    final visible = tester
        .widgetList<MessageItem>(find.byType(MessageItem))
        .where((item) {
      final rect = tester.getRect(find.byWidget(item));
      return rect.top >= 0 && rect.bottom < 600;
    }).toList()
      ..sort((a, b) => tester
          .getTopLeft(find.byWidget(a))
          .dy
          .compareTo(tester.getTopLeft(find.byWidget(b)).dy));
    expect(visible.length, greaterThanOrEqualTo(3));
    // 将横线置于一条消息内部，验证跨线排除；线上的原选择仍保留。
    final crossing = visible[1];
    final boundary = tester.getCenter(find.byWidget(crossing)).dy;
    visible.first.onToggleSelection!();
    await tester.pumpAndSettle();
    selection!.onSelectBelow!(boundary);
    await tester.pumpAndSettle();
    final crossingNumber = int.parse(crossing.message.msgID.split('-').last);
    final expected = {
      visible.first.message.msgID,
      for (var i = crossingNumber + 1; i <= 20; i++) 'history-$i',
    };
    expect(selection!.selectedCount, expected.length);
    for (final item
        in tester.widgetList<MessageItem>(find.byType(MessageItem))) {
      expect(item.isSelected, expected.contains(item.message.msgID),
          reason: item.message.msgID);
    }
    // 没有线下候选或边界无效时保留当前集合，不能降级成全选。
    selection!.onSelectBelow!(1000000);
    selection!.onSelectBelow!(double.nan);
    await tester.pumpAndSettle();
    expect(selection!.selectedCount, expected.length);
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
    expect(find.text('昨天 18:00'), findsOneWidget);
    expect(find.text('18:00'), findsOneWidget);
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
  testWidgets('最新消息仍部分可见时也保持阅读位置，贴底后恢复跟随', (tester) async {
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/history');
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    addTearDown(MessageList.clearViewportSnapshots);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(
            children: [MessageList(conversationID: 'c2c_history_visual')]),
      ),
    ));
    await tester.pumpAndSettle();
    final listFinder = find.byType(ScrollablePositionedList);
    final list = tester.widget<ScrollablePositionedList>(listFinder);
    await tester.drag(listFinder, const Offset(0, 35));
    await tester.pumpAndSettle();
    expect(list.itemScrollController!.isAtLeadingEdge, isFalse);
    expect(
        list.itemPositionsNotifier!.itemPositions.value
            .any((position) => position.index == 0),
        isTrue);
    final anchor = find.text('history-19');
    final anchorTop = tester.getTopLeft(anchor).dy;

    sdk.messages.listener!.onRecvNewMessage(_Message('new-21'));
    await tester.pump();
    expect(tester.getTopLeft(anchor).dy, closeTo(anchorTop, .01));
    await tester.pumpAndSettle();
    expect(find.text('1 条新消息'), findsOneWidget);

    await tester.tap(find.text('1 条新消息'));
    await tester.pumpAndSettle();
    expect(list.itemScrollController!.isAtLeadingEdge, isTrue);
    sdk.messages.listener!.onRecvNewMessage(_Message('new-22'));
    await tester.pumpAndSettle();
    expect(find.text('new-22').hitTestable(), findsOneWidget);
    expect(find.text('1 条新消息'), findsNothing);
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
    final anchorElement = tester.element(anchorFinder);

    sdk.messages.listener!.onRecvNewMessage(_Message('new-21'));
    // 首帧就要保留原位置和气泡状态，不能先错位再跳回。
    await tester.pump();
    expect(tester.getTopLeft(anchorFinder).dy, closeTo(anchorTop, .01));
    expect(tester.element(anchorFinder), same(anchorElement));
    await tester.pumpAndSettle();
    expect(find.byType(MessageTongueWidget), findsOneWidget);
    expect(find.text('1 条新消息'), findsOneWidget);
    for (var index = 22; index <= 120; index++) {
      sdk.messages.listener!.onRecvNewMessage(_Message('new-$index'));
    }
    await tester.pump();
    expect(tester.getTopLeft(anchorFinder).dy, closeTo(anchorTop, .01));
    expect(tester.element(anchorFinder), same(anchorElement));
    await tester.pumpAndSettle();
    expect(find.text('100 条新消息'), findsOneWidget);
    expect(tester.getTopLeft(anchorFinder).dy, closeTo(anchorTop, .01));
    // 新一批消息尚未完成布局就退出，旧回调也不能访问已销毁的列表。
    sdk.messages.listener!.onRecvNewMessage(_Message('new-121'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // 字体方案按首次使用的平台初始化，平台切换用例放在默认字号断言之后。
  testWidgets('iOS 聊天只在键盘收起时持续请求帧，归零、反向及超时后停止', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    TencentImSDKPlugin.v2TIMManager = _Sdk('/single');
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    addTearDown(MessageList.clearViewportSnapshots);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: ChatPage(
          conversation: ConversationInfo(
            conversationID: 'c2c_visual',
            type: ConversationType.c2c,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    Future<void> setInset(double bottom) async {
      tester.view.viewInsets = FakeViewPadding(bottom: bottom);
      await tester.pump();
    }

    // 模拟两次系统尺寸通知间没有新数据，收起阶段也应继续请求下一帧。
    await setInset(320);
    expect(tester.binding.transientCallbackCount, 0);
    await setInset(280);
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.transientCallbackCount, 1);
    await setInset(300);
    expect(tester.binding.transientCallbackCount, 0);

    // 未归零时也有时限，之后同一方向的通知不能重新开启。
    await setInset(260);
    await tester.pump(const Duration(milliseconds: 610));
    expect(tester.binding.transientCallbackCount, 0);
    await setInset(240);
    expect(tester.binding.transientCallbackCount, 0);
    await setInset(0);

    await setInset(320);
    await setInset(280);
    expect(tester.binding.transientCallbackCount, 1);
    await setInset(0);
    expect(tester.binding.transientCallbackCount, 0);
    await setInset(320);
    await setInset(280);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
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
  List<V2TimMessage>? mergedContents;
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
        #downloadMergerMessage => Future.value(
            V2TimValueCallback<List<V2TimMessage>>(
                code: 0,
                desc: '',
                data: mergedContents ??
                    List.generate(20, (index) => _Message('record-$index')))),
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
      this.isSelfOverride = false,
      this.isMerged = false});
  final int? timestampOverride;
  final int statusOverride;
  final bool isSelfOverride;
  final bool isMerged;
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
        #elemType => isMerged ? 10 : 1,
        #mergerElem => isMerged
            ? V2TimMergerElem(title: '测试合并记录', abstractList: ['测试摘要'])
            : null,
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

/// 本地删除回归只允许走宿主回调，误入原SDK方法即失败。
final class _UnusedMenuListStore implements MessageListStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('不应访问SDK列表');
}

/// 空实现阻止本地删除测试意外退回云端删除。
final class _UnusedMenuActionStore implements MessageActionStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('不应调用云端删除');
}
