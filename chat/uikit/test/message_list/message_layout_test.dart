import 'dart:async';
import 'dart:ui' as ui;
import 'package:atomic_x_core/impl/message/message_action_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_input_store_impl.dart';
import 'package:atomic_x_core/impl/message/message_list_store_impl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tencent_chat_uikit/src/image_viewer/image_viewer_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_bubble.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_viewport_anchor.dart'
    show MessageViewportAnchor;
import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_action_sheet.dart';
import 'package:tencent_chat_uikit/src/message_input/widget/message_edit_composer.dart';
import 'package:tencent_chat_uikit/src/message_input/widget/rich_content_editor_sheet.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/history_msg_get_type_enum.dart';
import 'package:tencent_cloud_chat_sdk/enum/image_types.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_message_manager.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_conversation_manager.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_friendship_manager.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_group_manager.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_receipt.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_online_url.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_merger_elem.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/merged_message_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/merged_message_detail_page.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_reaction_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message_reaction.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_overlay_avoider.dart';
import 'package:tencent_chat_uikit/src/third_party/visibility_detector/visibility_detector.dart';
import 'package:tencent_chat_uikit/src/third_party/scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/text_message_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/file_message_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/video_message_widget.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text/extended_text.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text_field/extended_text_field.dart'
    show ExtendedEditableText, ExtendedTextField;

void main() {
  for (final scenario in [
    (label: '群聊富文本单图', conversationId: 'group_visual', rich: true),
    (label: '单聊富文本单图', conversationId: 'c2c_visual', rich: true),
    (label: '单聊普通图片', conversationId: 'c2c_visual', rich: false),
  ]) {
    testWidgets('${scenario.label}可跨文字页左右浏览普通图片、富文本和归档图片',
        (tester) async {
      const archiveUrl = 'https://example.com/archive.png';
      const oldUrl = 'https://example.com/old.png';
      const currentUrl = 'https://example.com/current.png';
      const newUrl = 'https://example.com/new.png';
      final sdk = _Sdk('/conversation-media');
      final original = TencentImSDKPlugin.v2TIMManager;
      TencentImSDKPlugin.v2TIMManager = sdk;
      addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
      V2TimImageElem photo(String url) => V2TimImageElem(imageList: [
            V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN, url: url),
          ]);
      final groupId =
          scenario.conversationId.startsWith('group_') ? 'visual' : null;
      final current = _Message(
        'current',
        groupId: groupId,
        image: scenario.rich ? null : photo(currentUrl),
        custom: scenario.rich
            ? V2TimCustomElem(
                data: const RichContentMessage([
                  RichImageBlock(currentUrl, 160, 90),
                ]).toCustomData())
            : null,
      );
      sdk.messages.limitHistoryPages = true;
      sdk.messages.chronologicalHistory = [
        _Message('old',
            groupId: groupId, timestampOverride: 100, image: photo(oldUrl)),
        for (var i = 0; i < 41; i++) _Message('older-$i'),
        current,
        for (var i = 0; i < 21; i++) _Message('newer-$i'),
        _Message('new',
            groupId: groupId,
            custom: V2TimCustomElem(
                data: const RichContentMessage([
              RichImageBlock(newUrl, 160, 90),
            ]).toCustomData())),
      ];
      final cache = PaintingBinding.instance.imageCache;
      addTearDown(cache.clear);
      final decoded = (await tester.runAsync(() => createTestImage()))!;
      addTearDown(decoded.dispose);
      for (final provider in const [
        CachedNetworkImageProvider(archiveUrl),
        CachedNetworkImageProvider(oldUrl),
        CachedNetworkImageProvider(currentUrl),
        CachedNetworkImageProvider(newUrl),
        NetworkImage(currentUrl),
      ]) {
        cache.putIfAbsent(provider, () {
          return OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: decoded.clone())));
        });
      }
      final scale = tester.view.devicePixelRatio * 1.5;
      final thumbnail = ResizeImage(
        const CachedNetworkImageProvider(currentUrl),
        width: (200 * scale).ceil(),
        height: (112.5 * scale).ceil(),
        policy: ResizeImagePolicy.fit,
      );
      cache.putIfAbsent(
        await thumbnail.obtainKey(ImageConfiguration.empty),
        () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: decoded.clone()))),
      );
      final archiveRequests = <(int?, String?)>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: ChatUtil.convertToUIMessage(current),
            conversationID: scenario.conversationId,
            isSelf: false,
            maxWidth: 320,
            config: const ChatMessageListConfig(),
            messageListStore: _UnusedMenuListStore(),
            loadOlderMedia: ({required beforeTimestamp, required cursor}) async {
              archiveRequests.add((beforeTimestamp, cursor));
              if (cursor == null) {
                return (
                  messages: [
                    MessageInfo(msgID: 'archived-text', timestamp: 90),
                  ],
                  nextCursor: '90',
                );
              }
              return (
                messages: [
                  MessageInfo(
                    msgID: 'archived-image',
                    timestamp: 80,
                    messageType: MessageType.image,
                    messagePayload:
                        ImageMessagePayload(originalImageURL: archiveUrl),
                  ),
                ],
                nextCursor: null,
              );
            },
          ),
        ),
      ));
      await tester.tap(scenario.rich
          ? find.bySemanticsIdentifier('tim.rich.current.image.${currentUrl.hashCode}')
          : find.byType(ImageMessageWidget));
      await tester.pumpAndSettle();

      final viewer = find.byType(ImageViewerWidget);
      final pages = find.descendant(of: viewer, matching: find.byType(PageView));
      Finder picture(String url) => find.descendant(
            of: viewer,
            matching: find.byWidgetPredicate((widget) =>
                widget is Image && widget.image == CachedNetworkImageProvider(url)),
          ).hitTestable();
      Future<void> swipe(double dx) async {
        await tester.drag(pages, Offset(dx, 0));
        await tester.pumpAndSettle();
      }

      expect(picture(currentUrl), findsOneWidget);
      expect(sdk.messages.historyCursors, ['current', 'current']);
      expect(sdk.messages.historyTypes.take(2), [
        HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_OLDER_MSG,
        HistoryMsgGetTypeEnum.V2TIM_GET_CLOUD_NEWER_MSG,
      ]);
      await swipe(600);
      expect(sdk.messages.historyCursors, containsAll(['older-21', 'older-1']));
      expect(picture(currentUrl), findsOneWidget);
      await swipe(600);
      expect(picture(oldUrl), findsOneWidget);

      await swipe(-600);
      expect(picture(currentUrl), findsOneWidget);
      await swipe(-600);
      expect(sdk.messages.historyCursors, contains('newer-19'));
      await swipe(-600);
      expect(picture(newUrl), findsOneWidget);

      await swipe(600);
      expect(picture(currentUrl), findsOneWidget);
      await swipe(600);
      expect(picture(oldUrl), findsOneWidget);
      if (archiveRequests.isEmpty) await swipe(600);
      expect(archiveRequests, [(100, null), (90, '90')]);
      await swipe(600);
      expect(picture(archiveUrl), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('单聊本机首屏缺少原始 SDK 消息时可滑到邻近图片', (tester) async {
    const oldUrl = 'https://example.com/local-old.png';
    const newUrl = 'https://example.com/local-new.png';
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/cached-media');
    final history = Completer<V2TimValueCallback<List<V2TimMessage>>>();
    sdk.messages.historyGate = history;
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    final cache = PaintingBinding.instance.imageCache;
    final decoded = (await tester.runAsync(createTestImage))!;
    addTearDown(decoded.dispose);
    addTearDown(cache.clear);
    for (final provider in const [
      NetworkImage(oldUrl),
      NetworkImage(newUrl),
      CachedNetworkImageProvider(oldUrl),
      CachedNetworkImageProvider(newUrl),
    ]) {
      cache.putIfAbsent(provider, () => OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: decoded.clone()))));
    }

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          MessageList(
            conversationID: 'c2c_visual',
            localMessagesLoader: () async => [
              MessageInfo(
                msgID: 'cached-old',
                timestamp: 1700000000,
                messageType: MessageType.image,
                messagePayload: ImageMessagePayload(originalImageURL: oldUrl),
              ),
              MessageInfo(
                msgID: 'cached-new',
                timestamp: 1700000001,
                messageType: MessageType.image,
                messagePayload: ImageMessagePayload(originalImageURL: newUrl),
              ),
            ],
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier('tim.chat.message.cached-new'));
    await tester.pumpAndSettle();
    final viewer = find.byType(ImageViewerWidget);
    await tester.drag(
      find.descendant(of: viewer, matching: find.byType(PageView)),
      const Offset(600, 0),
    );
    await tester.pumpAndSettle();

    // 首屏 SDK 查询仍未结束，预览使用列表里的两张本机消息。
    expect(sdk.messages.historyCalls, 1);
    expect(
      find.descendant(
        of: viewer,
        matching: find.byWidgetPredicate((widget) =>
            widget is Image &&
            widget.image == const CachedNetworkImageProvider(oldUrl)),
      ).hitTestable(),
      findsOneWidget,
    );
    history.complete(V2TimValueCallback(code: 0, desc: '', data: []));
    await tester.pumpAndSettle();
  });

  testWidgets('群聊收到图片时先打开缩略图，原图和历史查询随后返回', (tester) async {
    const thumb = 'https://example.com/received-thumb.png';
    const full = 'https://example.com/received-full.png';
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/image-preview');
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    final onlineUrl = Completer<V2TimValueCallback<V2TimMessageOnlineUrl>>();
    final history = Completer<V2TimValueCallback<List<V2TimMessage>>>();
    sdk.messages.imageUrlLoader = () => onlineUrl.future;
    sdk.messages.historyGate = history;

    // 预置气泡与全屏所需的解码结果，异步行为只由 SDK 替身控制。
    final cache = PaintingBinding.instance.imageCache;
    addTearDown(cache.clear);
    final decoded = (await tester.runAsync(() => createTestImage()))!;
    addTearDown(decoded.dispose);
    for (final provider in const [
      NetworkImage(thumb),
      CachedNetworkImageProvider(thumb),
      CachedNetworkImageProvider(full),
    ]) {
      cache.putIfAbsent(
        provider,
        () => OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: decoded.clone())),
        ),
      );
    }
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ImageMessageWidget(
          conversationID: 'group_preview',
          message: MessageInfo(
            msgID: 'received-image',
            messageType: MessageType.image,
            rawMessage: _Message('received-image'),
            messagePayload: ImageMessagePayload(thumbImageURL: thumb),
          ),
          isSelf: false,
          maxWidth: 200,
          config: const ChatMessageListConfig(),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byType(ImageMessageWidget));
    await tester.pumpAndSettle();
    final viewer = find.byType(ImageViewerWidget);
    Finder picture(String url) => find.descendant(
          of: viewer,
          matching: find.byWidgetPredicate((widget) =>
              widget is Image &&
              widget.image == CachedNetworkImageProvider(url)),
        );
    expect(viewer, findsOneWidget);
    expect(picture(thumb), findsOneWidget);
    expect(sdk.messages.historyCalls, 0);
    onlineUrl.complete(V2TimValueCallback(
      code: 0,
      desc: '',
      data: V2TimMessageOnlineUrl(
        imageElem: V2TimImageElem(imageList: [
          V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN, url: full),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(picture(full), findsOneWidget);
    expect(sdk.messages.historyCalls, 1);

    Navigator.of(tester.element(viewer)).pop();
    await tester.pumpAndSettle();
    history.complete(V2TimValueCallback(code: 10001, desc: '模拟查询失败'));
    await tester.pumpAndSettle();
    expect(viewer, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('退出再进后，双向历史窗口超过20条仍能恢复表情回复', (tester) async {
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/layout');
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    addTearDown(MessageList.clearViewportSnapshots);
    final history = List<V2TimMessage>.generate(
      41,
      (index) =>
          _Message('reaction-$index', timestampOverride: 1700000000 + index),
    );
    sdk.messages.chronologicalHistory = history.skip(21).toList();
    final batchSizes = <int>[];
    sdk.messages.reactionLoader = (batch) async {
      batchSizes.add(batch.length);
      if (batch.length > 20) {
        return V2TimValueCallback(code: 1, desc: '超出批量读取上限');
      }
      return V2TimValueCallback(
        code: 0,
        desc: '',
        data: [
          for (final raw in batch)
            V2TimMessageReactionResult(
              resultCode: 0,
              messageID: raw.msgID!,
              reactionList: [
                V2TimMessageReaction(
                  reactionID: '[ZDEmoji_Like]',
                  totalUserCount: 1,
                  partialUserList: [],
                  reactedByMyself: false,
                ),
              ],
            ),
        ],
      );
    };

    Future<void> open() async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Column(children: [MessageList(conversationID: 'c2c_visual')]),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await open();
    expect(batchSizes, [20]);
    expect(find.byType(MessageReactionBar), findsWidgets);
    expect(
      find.ancestor(
        of: find.byType(MessageReactionBar).first,
        matching: find.byType(MessageBubble),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    sdk.messages.chronologicalHistory = history;
    batchSizes.clear();
    await open();
    expect(batchSizes, [41, 20, 20, 1]);
    expect(find.byType(MessageReactionBar), findsWidgets);
  });

  testWidgets('建群勾选可加载无本地文件的在线图片，点击图片切换选择', (tester) async {
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/single');
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    addTearDown(MessageList.clearViewportSnapshots);
    const thumbnail = 'https://example.invalid/chat-thumbnail.png';
    MultiSelectState? selection;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          MessageList(
            conversationID: 'c2c_visual',
            initialSelection: const [],
            onMultiSelectStateChanged: (state) => selection = state,
            localMessagesLoader: () async => [
              MessageInfo(
                msgID: 'remoteImage',
                timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                status: MessageStatus.sendSuccess,
                messageType: MessageType.image,
                messagePayload: ImageMessagePayload(thumbImageURL: thumbnail),
              ),
            ],
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    final image = find.byWidgetPredicate((widget) =>
        widget is Image && widget.image == const NetworkImage(thumbnail));
    expect(image, findsOneWidget);
    await tester.tapAt(tester.getCenter(image));
    await tester.pumpAndSettle();
    expect(selection?.selectedMessages?.call().single.msgID, 'remoteImage');
  });

  for (final selecting in [false, true]) {
    testWidgets('${selecting ? '建群选择' : '普通聊天'}滚动取齐 SDK 历史后自动续查归档，失败可按游标重试',
        (tester) async {
      final original = TencentImSDKPlugin.v2TIMManager;
      final sdk = _Sdk('/single');
      TencentImSDKPlugin.v2TIMManager = sdk;
      addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
      MessageList.clearViewportSnapshots();
      addTearDown(MessageList.clearViewportSnapshots);
      final olderSdkPage = sdk.messages.olderHistoryGate =
          Completer<V2TimValueCallback<List<V2TimMessage>>>();
      const boundary = 1700000000;
      sdk.messages.chronologicalHistory = List.generate(
        20,
        (index) => _Message('SDK 消息 ${index + 1}',
            timestampOverride: boundary + index + 1),
      );
      final calls = <(int?, String?)>[];
      final response = Completer<ChatOlderMessagesPage>();
      MessageInfo archived(String id, int timestamp) => MessageInfo(
            msgID: id,
            timestamp: timestamp,
            messageType: MessageType.text,
            messagePayload: TextMessagePayload(text: id),
            status: MessageStatus.sendSuccess,
          );
      final oldest = archived('归档第一条', boundary - 1);
      MultiSelectState? selection;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            MessageList(
              conversationID: 'c2c_visual',
              initialSelection: selecting ? const [] : null,
              onMultiSelectStateChanged: (state) => selection = state,
              historyConfig: ChatMessageHistoryConfig(
                load: ({required beforeTimestamp, required cursor}) async {
                  calls.add((beforeTimestamp, cursor));
                  if (calls.length == 1) return response.future;
                  if (cursor == null) {
                    return (messages: [oldest], nextCursor: 'next');
                  }
                  return (
                    messages: [oldest, archived('归档第二条', boundary - 2)],
                    nextCursor: null,
                  );
                },
                buildEntry: (context, {required status, required onLoad}) =>
                    TextButton(
                  onPressed: status.isLoading ? null : onLoad,
                  child: Text(status.isLoading
                      ? '加载归档中'
                      : status.hasError
                          ? '重试归档'
                          : '没有更多消息了'),
                ),
              ),
            ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      final entry = find.text('没有更多消息了');
      expect(sdk.messages.historyCalls, 1);
      expect(calls, isEmpty);
      expect(entry, findsNothing);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2400));
      await tester.pumpAndSettle();
      expect(sdk.messages.historyCalls, 2);
      expect(calls, isEmpty);

      olderSdkPage.complete(V2TimValueCallback(code: 0, desc: '', data: [
        _Message('SDK 最早消息', timestampOverride: boundary),
      ]));
      await tester.pumpAndSettle();
      expect(calls, [(boundary, null)]);
      expect(entry, findsNothing);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('加载归档中'), findsOneWidget);
      if (selecting) {
        final row = find.byWidgetPredicate((widget) =>
            widget is MessageItem && widget.message.msgID == 'SDK 最早消息');
        tester.widget<MessageItem>(row).onToggleSelection!.call();
        await tester.pumpAndSettle();
        expect(selection?.selectedCount, 1);
      }
      response.completeError(StateError('模拟请求失败'));
      await tester.pumpAndSettle();
      expect(calls, [(boundary, null)]);
      expect(find.text('SDK 最早消息'), findsOneWidget);
      await tester.tap(find.text('重试归档'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('归档第一条'), findsOneWidget);
      expect(calls, [(boundary, null), (boundary, null), (null, 'next')]);
      expect(tester.getTopLeft(find.text('归档第二条')).dy,
          lessThan(tester.getTopLeft(find.text('归档第一条')).dy));
      expect(entry, findsOneWidget);
      expect(tester.getTopLeft(entry).dy,
          lessThan(tester.getTopLeft(find.text('归档第二条')).dy));
      if (selecting) {
        expect(selection?.selectedMessages?.call().single.msgID, 'SDK 最早消息');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final sdkSucceeded in [true, false]) {
    testWidgets('SDK 首屏${sdkSucceeded ? '为空时续查归档' : '失败时等待 SDK 恢复'}',
        (tester) async {
      final original = TencentImSDKPlugin.v2TIMManager;
      final sdk = _Sdk('/single');
      TencentImSDKPlugin.v2TIMManager = sdk;
      addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
      MessageList.clearViewportSnapshots();
      addTearDown(MessageList.clearViewportSnapshots);
      sdk.messages.historyGate = Completer()
        ..complete(V2TimValueCallback<List<V2TimMessage>>(
          code: sdkSucceeded ? 0 : -1,
          desc: '',
          data: [],
        ));
      final calls = <(int?, String?)>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            MessageList(
              conversationID: 'c2c_visual',
              historyConfig: ChatMessageHistoryConfig(
                load: ({required beforeTimestamp, required cursor}) async {
                  calls.add((beforeTimestamp, cursor));
                  return (
                    messages: <MessageInfo>[],
                    nextCursor: cursor == null ? 'next' : null
                  );
                },
                buildEntry: (context, {required status, required onLoad}) =>
                    const SizedBox.shrink(),
              ),
            ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      expect(calls, sdkSucceeded ? [(null, null), (null, 'next')] : isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final sameId in [true, false]) {
    testWidgets('HTTP搜索${sameId ? '相同ID' : '不同ID'}定位后持续高亮，操作一秒后清除',
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
      final screen = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: screen,
        child: MaterialApp(
          home: Scaffold(
            body: Column(children: [
              MessageList(conversationID: 'c2c_visual', locateMessage: target),
            ]),
          ),
        ),
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
      final background = find.descendant(
        of: row,
        matching: find.byWidgetPredicate((widget) =>
            widget is ColoredBox && widget.color == const Color(0xFFFFF5D5)),
      );
      final rowRect = tester.getRect(row);
      expect(tester.getRect(background),
          Rect.fromLTRB(0, rowRect.top - 4, 390, rowRect.bottom + 4));
      if (sameId) {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(screen));
        final marginPixels = await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final rgba =
                (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
            return [
              rgba.getUint32((image.width * (rowRect.top - 2).floor()) * 4),
              rgba.getUint32(
                  (image.width * (rowRect.bottom + 1).floor() + 389) * 4),
            ];
          } finally {
            image.dispose();
          }
        });
        expect(marginPixels, [0xFFF5D5FF, 0xFFF5D5FF]);
      }
      await tester.pump(const Duration(seconds: 5));
      expect(tester.widget<MessageItem>(row).isHighlighted, isTrue);
      final margin = Offset(4, tester.getCenter(row).dy);
      if (sameId) {
        await tester.tapAt(margin);
      } else {
        await tester.dragFrom(margin, const Offset(0, -30));
      }
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(Offset(4, tester.getCenter(row).dy));
      await tester.pump(const Duration(milliseconds: 499));
      expect(tester.widget<MessageItem>(row).isHighlighted, isTrue);
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.widget<MessageItem>(row).isHighlighted, isFalse);
      expect(background, findsNothing);
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
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: target,
          builder: (_, message, __) => ChatPage(
            conversation: ConversationInfo(
                conversationID: 'c2c_visual', type: ConversationType.c2c),
            displayName: '联系人',
            message: message,
          ),
        ),
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
    await tester.tap(find.text('联系人'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.bySemanticsIdentifier('tim.input.text'));
    await tester.pumpAndSettle();
    expect(tester.widget<MessageItem>(row).isHighlighted, isTrue);

    // 新目标替换旧目标后，旧倒计时不能清除这次高亮。
    target.value = ChatUtil.convertToUIMessage(
        _Message('search-8', timestampOverride: stamp + 8));
    await tester.pumpAndSettle();
    final nextRow = find.byWidgetPredicate((widget) =>
        widget is MessageItem && widget.message.msgID == 'search-8');
    expect(tester.widget<MessageItem>(row).isHighlighted, isFalse);
    expect(tester.widget<MessageItem>(nextRow).isHighlighted, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.widget<MessageItem>(nextRow).isHighlighted, isTrue);

    expect(find.byKey(const Key('message_input_text_field')), findsOneWidget);
    tester.testTextInput.enterText('测试输入');
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<MessageItem>(nextRow).isHighlighted, isFalse);

    target.value = ChatUtil.convertToUIMessage(
        _Message('search-8', timestampOverride: stamp + 8));
    await tester.pumpAndSettle();
    expect(tester.widget<MessageItem>(nextRow).isHighlighted, isTrue);
    await tester.tap(find.text('联系人'));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<MessageItem>(nextRow).isHighlighted, isFalse);
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

  testWidgets('群聊顶部省略长群名和描述，保留完整人数和输入栏群名', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final groupName = '群聊天窗口标题' * 8;
    final description = '群描述单行展示' * 12;
    final conversation = ConversationInfo(
      conversationID: 'group_visual',
      type: ConversationType.group,
    );

    Future<void> show({int? count, String? subtitle, bool? muted}) =>
        tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: ChatPage(
                conversation: conversation,
                displayName: groupName,
                groupMemberCount: count,
                isNotificationMuted: muted,
                subtitle: subtitle,
                offlineMessages: const [],
              ),
            ),
          ),
        );

    await show();
    await tester.pumpAndSettle();
    final header = find.byType(AppBar);
    Finder titleText(String text) =>
        find.descendant(of: header, matching: find.text(text));
    expect(titleText(groupName), findsOneWidget);
    expect(titleText('（0）'), findsNothing);

    final muteIcon = find.descendant(
        of: header, matching: find.byIcon(AppIcons.doNotDisturb));
    expect(muteIcon, findsNothing);
    await show(count: 1234, subtitle: ' $description ', muted: true);
    await tester.pumpAndSettle();

    for (final text in [groupName, description]) {
      final widget = tester.widget<Text>(titleText(text));
      expect(widget.maxLines, 1);
      expect(widget.overflow, TextOverflow.ellipsis);
    }
    final count = titleText('（1234）');
    expect(count, findsOneWidget);
    expect(muteIcon, findsOneWidget);
    expect(tester.widget<Icon>(muteIcon).color, const Color(0xFF8E8E99));
    expect(tester.getTopLeft(count).dy,
        tester.getTopLeft(titleText(groupName)).dy);
    expect(tester.getRect(header).contains(tester.getRect(count).bottomRight),
        isTrue);
    expect(tester.widget<Text>(titleText(description)).textAlign,
        TextAlign.center);
    expect(find.descendant(of: header, matching: find.byIcon(AppIcons.expand)),
        findsNothing);
    expect(find.text('发送给 $groupName'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色聊天区分消息列表、气泡、导航和底部编辑区', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 24);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/dark-colors');
    sdk.messages.chronologicalHistory = [
      _Message('对方消息'),
      _Message('我的消息', isSelfOverride: true),
    ];
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    addTearDown(MessageList.clearViewportSnapshots);
    final unreadCount = ValueNotifier(100);
    addTearDown(unreadCount.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        initialAppearanceSelectionProvider.overrideWithValue(
            const AppAppearanceSelection(themeMode: AppThemeMode.dark)),
      ],
      child: MaterialApp(
        home: ChatPage(
          conversation: ConversationInfo(
              conversationID: 'c2c_visual', type: ConversationType.c2c),
          displayName: '联系人',
          subtitle: '行政人事部',
          totalUnreadCount: unreadCount,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final header = tester.widget<AppBar>(find.byType(AppBar));
    expect(header.backgroundColor, const Color(0xFF111111));
    expect(header.titleTextStyle?.color, const Color(0xFFD1D1D1));
    expect(tester.widget<Text>(find.text('行政人事部')).style?.color,
        const Color(0xFF909090));
    final line = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('app.page.appBarDivider')));
    final divider = (line.decoration as BoxDecoration).border as Border;
    expect(divider.bottom.color, const Color(0xFF303030));

    Color? fill(Container container) =>
        container.color ??
        switch (container.decoration) {
          BoxDecoration(:final color) => color,
          _ => null,
        };
    Iterable<Color?> fills(Finder search) => tester
        .widgetList<Container>(
            find.descendant(of: search, matching: find.byType(Container)))
        .map(fill);
    final badge =
        find.ancestor(of: find.text('99+'), matching: find.byType(Container));
    expect(tester.widgetList<Container>(badge).map(fill),
        contains(const Color(0xFF242424)));
    expect(fills(find.byType(MessageList)), contains(const Color(0xFF111111)));
    expect(fills(find.byType(TextMessageWidget)),
        containsAll(const [Color(0xFF2C2C2C), Color(0xFF212C44)]));
    expect(fills(find.byType(MessageInput)),
        containsAll(const [Color(0xFF1C1C1C), Color(0xFF2C2C2C)]));

    final placeholder = find.text('发送给 联系人');
    expect(
        tester.widget<Text>(placeholder).style?.color, const Color(0xFF5E5E5E));
    final idleInput = find.bySemanticsIdentifier('tim.input.text');
    expect(idleInput, findsOneWidget);
    await tester.tap(idleInput);
    await tester.pumpAndSettle();
    final field = tester.widget<ExtendedTextField>(
        find.byKey(const Key('message_input_text_field')));
    expect(field.decoration?.hintStyle?.color, const Color(0xFF5E5E5E));
  });

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

  final deleteConversation = ValueVariant({
    ConversationType.c2c,
    ConversationType.group,
  });
  testWidgets('仅成功消息可删除，二次确认取消零调用且删除成功通知宿主', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    final type = deleteConversation.currentValue!;
    final isGroup = type == ConversationType.group;
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
        _Message('target',
            statusOverride: status,
            isSelfOverride: true,
            groupId: isGroup ? 'visual' : null)
      ];
      TencentImSDKPlugin.v2TIMManager = sdk;
      MessageList.clearViewportSnapshots();
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
        navigatorObservers: [AppDialog.observer],
        builder: AppDialog.init(),
        home: ChatPage(
            conversation: ConversationInfo(
                conversationID: isGroup ? 'group_visual' : 'c2c_visual',
                type: type),
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
  }, variant: deleteConversation);

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

  testWidgets('断网保持原聊天列表和输入栏，重连从可见消息补拉', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/single');
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    addTearDown(MessageList.clearViewportSnapshots);
    sdk.messages.chronologicalHistory = [_Message('first'), _Message('second')];
    final conversation = ConversationInfo(
        conversationID: 'c2c_visual', type: ConversationType.c2c);
    Future<void> show(bool connectionUnavailable) async {
      await tester.pumpWidget(MaterialApp(
        home: ProviderScope(
          child: ChatPage(
            conversation: conversation,
            connectionUnavailable: connectionUnavailable,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await show(false);
    final input = find.byType(MessageInput);
    final list = find.byType(MessageList);
    final editable = find.byType(ExtendedEditableText);
    expect(tester.widget<ExtendedEditableText>(editable).controller.text,
        '你好，很高兴认识你');
    final inputState = tester.state(input);
    final listState = tester.state(list);
    final inputBounds = tester.getRect(input);
    final anchorBounds = tester.getRect(find.text('second'));
    sdk.messages.historyCursors.clear();

    await show(true);
    expect(tester.state(input), same(inputState));
    expect(tester.state(list), same(listState));
    expect(tester.widget<ExtendedEditableText>(editable).controller.text,
        '你好，很高兴认识你');
    expect(tester.getRect(input), inputBounds);
    expect(tester.getRect(find.text('second')), anchorBounds);
    expect(sdk.messages.historyCursors, isEmpty);

    sdk.messages.chronologicalHistory!.add(_Message('third'));
    await show(false);
    expect(tester.state(input), same(inputState));
    expect(tester.state(list), same(listState));
    expect(sdk.messages.historyCursors, hasLength(2));
    expect(sdk.messages.historyCursors.first, isNotNull);
    expect(sdk.messages.historyCursors.last, sdk.messages.historyCursors.first);
    expect(find.text('third'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('重连时以离线可见消息为游标，向云端补拉两侧消息', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/layout');
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    addTearDown(MessageList.clearViewportSnapshots);
    final anchorMessage = ChatUtil.convertToUIMessage(_Message('second'));
    sdk.messages.chronologicalHistory = [
      _Message('first'),
      _Message('second'),
      _Message('third'),
    ];
    final offlineViewport = createMessageViewportSnapshot(
      messages: [anchorMessage],
      anchor: MessageViewportAnchor(message: anchorMessage, alignment: 0.2),
      messagesPerSide: 20,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          MessageList(
            conversationID: 'c2c_visual',
            startAtLatest: true,
            offlineViewport: offlineViewport,
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(sdk.messages.historyCursors, ['second', 'second']);
    expect(find.text('second').hitTestable(), findsOneWidget);
    expect(find.text('third').hitTestable(), findsOneWidget);
    expect(find.text('first').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('重新进入群聊从最新消息加载，旧提及等用户点击后跳转', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/layout');
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    addTearDown(MessageList.clearViewportSnapshots);
    V2TimMessage message(int number) => _Message('group-message-$number',
        groupId: 'visual', timestampOverride: 1700000000 + number);
    sdk.messages.chronologicalHistory = List.generate(20, (i) => message(i + 1));

    Widget page({List<GroupAtInfo>? mentions}) => MaterialApp(
          home: ProviderScope(
            child: ChatPage(
              conversation: ConversationInfo(
                conversationID: 'group_visual',
                type: ConversationType.group,
                groupAtInfoList: mentions,
              ),
            ),
          ),
        );

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('group-message-20').hitTestable(), findsOneWidget);
    await tester.drag(
        find.byType(ScrollablePositionedList), const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(find.text('group-message-20').hitTestable(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    // 退出后有新消息及历史提及，重新进入优先读取最新一页。
    sdk.messages.historyCursors.clear();
    sdk.messages.chronologicalHistory!.add(message(21));
    await tester.pumpWidget(page(mentions: [
      GroupAtInfo(msgSeq: 4, atType: GroupAtType.atMe),
    ]));
    await tester.pumpAndSettle();
    expect(sdk.messages.historyCursors.first, isNull);
    expect(find.text('group-message-21').hitTestable(), findsOneWidget);
    expect(find.text('group-message-4').hitTestable(), findsNothing);
    final mention = find.byWidgetPredicate((widget) =>
        widget is MessageTongueWidget &&
        widget.tongueState.type == TongueType.atMention);
    await tester.tap(mention);
    await tester.pumpAndSettle();
    expect(find.text('group-message-4').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
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

  testWidgets('群聊仅有权限时显示取消置顶并提交对应消息', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/sticky-menu');
    sdk.messages.chronologicalHistory = [_Message('older')];
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    MessageList.clearViewportSnapshots();
    final unpinned = <String>[];
    Widget host(bool canModify) => ProviderScope(
      child: MaterialApp(
        home: ChatPage(
          conversation: ConversationInfo(
              conversationID: 'group_visual', type: ConversationType.group),
          messageStickyConfig: ChatMessageStickyConfig(
            canModify: canModify,
            pin: (_) async => throw StateError('已置顶消息不得重复提交置顶'),
            groupPinnedMessageIds: const {'older', 'latest'},
            unpinGroupMessage: (message) async {
              unpinned.add(message.msgID);
              return null;
            },
            bannerBuilder: (_, __) => const SizedBox.shrink(),
            onMessagesChanged: (_) {},
            onMessagesDeleted: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(host(false));
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(TextMessageWidget));
    await tester.pumpAndSettle();
    expect(find.text('置顶消息'), findsNothing);
    expect(find.text('取消置顶消息'), findsNothing);
    expect(find.bySemanticsIdentifier('tim.message.action.top'), findsNothing);
    expect(unpinned, isEmpty);

    // 菜单已经打开，授权和收回权限时都应同步更新这一行。
    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();
    expect(find.text('取消置顶消息'), findsOneWidget);
    await tester.pumpWidget(host(false));
    await tester.pumpAndSettle();
    expect(find.text('取消置顶消息'), findsNothing);
    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();
    expect(find.text('置顶消息'), findsNothing);
    await tester.tap(find.text('取消置顶消息'));
    await tester.pumpAndSettle();
    expect(unpinned, ['older']);
    expect(tester.takeException(), isNull);
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

  testWidgets('首屏发出已读回执后第一次长按仍能避让遮挡', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/layout');
    sdk.messages.chronologicalHistory = List.generate(
      20,
      (index) => _Message('history-${index + 1}',
          timestampOverride: 1700000000 + index, needsReceipt: index == 19),
    );
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(builder: (context) {
          // 宿主在菜单路由覆盖时重建聊天页，与实际入口的路由依赖一致。
          ModalRoute.isCurrentOf(context);
          return ChatPage(
            conversation: ConversationInfo(
                conversationID: 'c2c_history_visual', type: ConversationType.c2c),
            messageListConfig: ChatMessageListConfig(
              isShowTimeMessage: false,
              forwardHandler: (_, __) async => false,
            ),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();
    VisibilityDetectorController.instance.notifyNow();
    await tester.pump(const Duration(milliseconds: 800));
    expect(sdk.messages.receiptCalls, 1);

    final bubble = find.bySemanticsIdentifier('tim.chat.message.history-20');
    final target =
        find.ancestor(of: bubble, matching: find.byType(MessageBubble));
    final originalState = tester.state(target);
    final originalBottom = tester.getRect(bubble).bottom;
    await tester.longPress(bubble);
    await tester.pumpAndSettle();

    final sheet = find.byType(MessageActionSheet);
    final sheetTop = tester.getRect(sheet).top;
    expect(originalBottom, greaterThan(sheetTop));
    expect(sheetTop - tester.getRect(bubble).bottom, closeTo(16, .01));
    expect(tester.state(target), same(originalState));
    expect(sdk.messages.receiptCalls, 1);
  });

  testWidgets('长按被列表底部截断的消息时完整绘制气泡', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/layout');
    sdk.messages.chronologicalHistory = List.generate(
      20,
      (index) => _Message('history-${index + 1}',
          timestampOverride: 1700000000 + index, isSelfOverride: true),
    );
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    final screen = GlobalKey();
    await tester.pumpWidget(ProviderScope(
      child: RepaintBoundary(
        key: screen,
        child: MaterialApp(
          home: ChatPage(
            conversation: ConversationInfo(
                conversationID: 'c2c_visual', type: ConversationType.c2c),
            messageListConfig: ChatMessageListConfig(
              isShowTimeMessage: false,
              forwardHandler: (_, __) async => false,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final bubble = find.bySemanticsIdentifier('tim.chat.message.history-20');
    final list = find.byType(ScrollablePositionedList);
    final viewportBottom = tester.getRect(list).bottom;
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(screen));
    Future<int?> bubbleBottomPixel() {
      final rect = tester.getRect(bubble);
      return tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final pixels =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          final index =
              (image.width * (rect.bottom - 6).floor() + rect.center.dx.floor());
          return pixels.getUint32(index * 4);
        } finally {
          image.dispose();
        }
      });
    }

    final fullBubblePixel = await bubbleBottomPixel();
    final scroll = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first);
    final bottomGap = viewportBottom - tester.getRect(bubble).bottom;
    scroll.position.jumpTo(scroll.position.pixels + bottomGap + 20);
    await tester.pumpAndSettle();
    final clipped = tester.getRect(bubble);
    expect(clipped.bottom, greaterThan(viewportBottom + 6));
    expect(clipped.top, lessThan(viewportBottom));
    expect(await bubbleBottomPixel(), isNot(fullBubblePixel));
    // 从仍露出的上半部打开菜单，再检查原本超出视口的底部是否实际绘制。
    await tester.longPressAt(Offset(clipped.center.dx, clipped.top + 4));
    await tester.pumpAndSettle();
    final sheet = find.byType(MessageActionSheet);
    expect(tester.getRect(sheet).top - tester.getRect(bubble).bottom,
        closeTo(16, .01));
    expect(await bubbleBottomPixel(), fullBubblePixel);

    Navigator.of(tester.element(sheet)).pop();
    await tester.pumpAndSettle();
    expect(tester.getRect(bubble), clipped);
    expect(await bubbleBottomPixel(), isNot(fullBubblePixel));
  });

  testWidgets('长按菜单按气泡边缘避让，气泡下方的回复计数不额外抬高列表', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/single');
    sdk.messages.chronologicalHistory = [_Message('third')];
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: ChatPage(
          conversation: ConversationInfo(
              conversationID: 'c2c_visual', type: ConversationType.c2c),
          messageListConfig: ChatMessageListConfig(
            isShowTimeMessage: false,
            forwardHandler: (_, __) async => false,
          ),
          messageReplyConfig: ChatMessageReplyConfig(
            project: (_, __) => (
              quotes: {},
              replies: {'third': ['reply-id']},
            ),
            openDetails: (_, __, ___, ____) {},
            sendError: (_) => (message: '', reset: false),
            canStart: (_, __, ___) => true,
            contentTooLongMessage: '',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final bubble = find.bySemanticsIdentifier('tim.chat.message.third');
    final replyCount = find.bySemanticsIdentifier('tim.reply.count.third');
    final sheet = find.byType(MessageActionSheet);
    final originalBottom = tester.getRect(bubble).bottom;

    Future<void> openMenu() async {
      await tester.longPress(bubble);
      await tester.pumpAndSettle();
    }

    Future<void> closeMenu() async {
      Navigator.of(tester.element(sheet)).pop();
      await tester.pumpAndSettle();
    }

    await openMenu();
    final sheetHeight = tester.getSize(sheet).height;
    await closeMenu();

    // 使用实际面板高度，让菜单只挡住回复计数而不挡正文气泡。
    final unobscuredHeight = sheetHeight + originalBottom + 1;
    tester.view.physicalSize = Size(390, unobscuredHeight);
    await tester.pumpAndSettle();
    final replyBottom = tester.getRect(replyCount).bottom;
    await openMenu();
    final sheetTop = tester.getRect(sheet).top;
    expect(sheetTop, greaterThan(originalBottom));
    expect(sheetTop, lessThan(replyBottom));
    expect(tester.getRect(bubble).bottom, closeTo(originalBottom, .01));
    await closeMenu();

    // 面板真正挡住气泡时只补足设计间距，关闭后恢复原位置。
    tester.view.physicalSize = Size(390, unobscuredHeight - 10);
    await tester.pumpAndSettle();
    await openMenu();
    expect(tester.getRect(sheet).top - tester.getRect(bubble).bottom,
        closeTo(16, .01));
    await closeMenu();
    expect(tester.getRect(bubble).bottom, closeTo(originalBottom, .01));
  });

  testWidgets('消息菜单随列表滑动收起，同一次手势继续滚动', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/layout');
    sdk.messages.chronologicalHistory = List.generate(
      25,
      (index) => _Message('swipe-${index + 1}',
          timestampOverride: 1700000000 + index),
    );
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    var settingsOpened = 0;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: ChatPage(
          conversation: ConversationInfo(
              conversationID: 'c2c_menu_swipe', type: ConversationType.c2c),
          messageListConfig: ChatMessageListConfig(
            isShowTimeMessage: false,
            forwardHandler: (_, __) async => false,
          ),
          onOpenSettings: () async {
            settingsOpened++;
            return null;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final bubble = find.bySemanticsIdentifier('tim.chat.message.swipe-25');
    final settings = tester.getCenter(
        find.bySemanticsIdentifier('tim.chat.settings'));
    final list = find.byType(ScrollablePositionedList);
    final scroll = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first);
    final sheet = find.byType(MessageActionSheet);

    await tester.longPress(bubble);
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);
    expect(find.bySemanticsIdentifier('tim.message.action.dismiss'),
        findsOneWidget);
    await tester.tapAt(settings);
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(settingsOpened, 0);

    await tester.longPress(bubble);
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(sheet));
    final before = scroll.position.pixels;
    final gesture = await tester.startGesture(
        tester.getRect(sheet).topCenter - const Offset(0, 40));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pumpAndSettle();
    // 手指仍按住时收起面板；此时离开路由会取消列表正在处理的手势。
    expect(route?.animation?.status, AnimationStatus.dismissed);
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    expect(scroll.position.pixels, greaterThan(before + 80));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(find.byType(ChatPage), findsOneWidget);
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

  for (final withMention in [false, true]) {
    testWidgets('星标悬浮入口共享右下锚点，与普通提醒间隔 12（@=$withMention）', (tester) async {
      final original = TencentImSDKPlugin.v2TIMManager;
      final sdk = _Sdk('/history');
      TencentImSDKPlugin.v2TIMManager = sdk;
      addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
      MessageList.clearViewportSnapshots();
      addTearDown(MessageList.clearViewportSnapshots);
      var located = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppThemeFactory.create(
            const AppNormalColorScheme(), Brightness.light),
        home: Scaffold(
          body: Column(children: [
            MessageList(
              conversationID: 'c2c_history_visual',
              groupAtInfoList: withMention
                  ? [
                      GroupAtInfo(msgSeq: 19, atType: GroupAtType.atMe),
                      GroupAtInfo(msgSeq: 20, atType: GroupAtType.atMe),
                    ]
                  : null,
              floatingMessageAction: MessageTongueWidget.highlighted(
                text: '2 条星标消息',
                icon: AppIcons.starFull,
                onTap: () => located++,
                semanticsIdentifier: 'tim.star.locate',
                semanticsLabel: '2 条星标消息，定位最早未读',
              ),
            ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      final star = find.bySemanticsIdentifier('tim.star.locate');
      final list = find.byType(MessageList);
      final bottomRight = tester.getBottomRight(list) - const Offset(16, 16);
      if (!withMention) {
        expect(tester.getBottomRight(star), bottomRight);
        await tester.drag(
            find.byType(ScrollablePositionedList), const Offset(0, 400));
        await tester.pumpAndSettle();
        sdk.messages.listener!.onRecvNewMessage(_Message('new-21'));
        await tester.pumpAndSettle();
      }
      final navigation = find.byWidgetPredicate(
        (widget) =>
            widget is MessageTongueWidget &&
            widget.tongueState.type ==
                (withMention ? TongueType.atMention : TongueType.newMessages),
      );
      expect(navigation, findsOneWidget);
      expect(tester.getBottomRight(navigation), bottomRight);
      expect(tester.getTopRight(navigation) - tester.getBottomRight(star),
          const Offset(0, 12));

      await tester.tap(star);
      await tester.pump();
      expect(located, 1);
      expect(navigation, findsOneWidget);
    });
  }

  testWidgets('同一发送人连续消息定位到指定气泡，并避开右下角星标入口', (tester) async {
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/history');
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
            builder: (_, selected, __) => MessageList(
              conversationID: 'c2c_history_visual',
              aggregateMessages: true,
              locateMessage: selected,
              floatingMessageAction: MessageTongueWidget.highlighted(
                text: '3 条星标消息',
                icon: AppIcons.starFull,
                onTap: () => target.value =
                    ChatUtil.convertToUIMessage(_Message('history-14')),
                semanticsIdentifier: 'tim.star.locate',
                semanticsLabel: '定位最早未读星标消息',
              ),
            ),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    final star = find.bySemanticsIdentifier('tim.star.locate');
    await tester.tap(star);
    await tester.pumpAndSettle();
    // 等定位稳定后再模拟其他设备连续发送，静置时仍停留在目标。
    await tester.pump(const Duration(seconds: 3));
    final matched = find.byWidgetPredicate((widget) =>
        widget is MessageItem && widget.message.msgID == 'history-14');
    final targetBottomBeforeArrival = tester.getBottomLeft(matched).dy;
    for (final sequence in [21, 22, 23]) {
      sdk.messages.listener!
          .onRecvNewMessage(_Message('new-$sequence', isSelfOverride: true));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(matched.hitTestable(), findsOneWidget);
    expect(tester.widget<MessageItem>(matched).isHighlighted, isTrue);
    final targetBottom = tester.getBottomLeft(matched).dy;
    expect(targetBottom, closeTo(targetBottomBeforeArrival, 1));
    expect(targetBottom, lessThan(tester.getTopLeft(star).dy));
    expect(
      tester
          .widgetList<MessageItem>(find.byType(MessageItem))
          .where((row) => row.isHighlighted)
          .map((row) => row.message.msgID),
      ['history-14'],
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

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

    message.conversationType = ConversationType.group;
    await mount(false);
    final groupText = tester.getRect(find.byType(ExtendedText));
    final groupBubble = tester.getRect(find.byType(TextMessageWidget));
    expect(groupText.height, closeTo(20, .01));
    expect(groupText.top - groupBubble.top, closeTo(10, .01));
    expect(groupBubble.bottom - groupText.bottom, closeTo(10, .01));
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

  testWidgets('普通输入键盘打开时回到最新消息，后续尺寸变化允许继续浏览历史', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final original = TencentImSDKPlugin.v2TIMManager;
    final sdk = _Sdk('/layout');
    TencentImSDKPlugin.v2TIMManager = sdk;
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
    sdk.messages.chronologicalHistory = List.generate(
      20,
      (index) => _Message('history-${index + 1}',
          timestampOverride: 1700000000 + index),
    );

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: ChatPage(
          conversation: ConversationInfo(
            conversationID: 'c2c_history_visual',
            type: ConversationType.c2c,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final latest = find.text('history-20').hitTestable();
    final list = find.byType(ScrollablePositionedList);
    expect(latest, findsOneWidget);
    await tester.drag(list, const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(latest, findsNothing);

    await tester.tap(find.bySemanticsIdentifier('tim.input.text'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpAndSettle();
    expect(latest, findsOneWidget);

    // 键盘已显示时允许翻看旧消息，改变输入法高度不会触发第二次回底。
    await tester.drag(list, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(latest, findsNothing);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(latest, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final keyboardVisible in [false, true]) {
    final keyboardState = keyboardVisible ? '键盘已打开' : '键盘未打开';
    testWidgets('$keyboardState时展开富文本编辑器会回到最新消息', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final original = TencentImSDKPlugin.v2TIMManager;
      final sdk = _Sdk('/layout');
      TencentImSDKPlugin.v2TIMManager = sdk;
      addTearDown(() => TencentImSDKPlugin.v2TIMManager = original);
      sdk.messages.chronologicalHistory = List.generate(
        20,
        (index) => _Message('history-${index + 1}',
            timestampOverride: 1700000000 + index),
      );

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: ChatPage(
            conversation: ConversationInfo(
              conversationID: 'c2c_history_visual',
              type: ConversationType.c2c,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      if (keyboardVisible) {
        await tester.tap(find.bySemanticsIdentifier('tim.input.text'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        await tester.pumpAndSettle();
      }

      final list = find.byType(ScrollablePositionedList);
      final scroll =
          tester.widget<ScrollablePositionedList>(list).itemScrollController!;
      await tester.drag(list, const Offset(0, 700));
      await tester.pumpAndSettle();
      expect(scroll.isAtLeadingEdge, isFalse);

      await tester.tap(find.bySemanticsIdentifier('tim.input.expand'));
      await tester.pumpAndSettle();
      expect(find.byType(RichContentEditorSheet), findsOneWidget);
      // 编辑器覆盖消息区，直接检查反向列表是否贴住最新端。
      expect(scroll.isAtLeadingEdge, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

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
  final groups = _Groups();
  @override
  dynamic noSuchMethod(Invocation call) => switch (call.memberName) {
        #getConversationManager => conversations,
        #getMessageManager => messages,
        #getFriendshipManager => friends,
        #getGroupManager => groups,
        #addGroupListener => Future<void>.value(),
        #callExperimentalAPI => Future.value(
            V2TimValueCallback<String>(code: 0, desc: '', data: ''),
          ),
        _ => throw StateError('夹具未覆盖SDK入口: ${call.memberName}'),
      };
}

final class _Groups implements V2TIMGroupManager {
  @override
  Future<V2TimValueCallback<List<V2TimGroupInfoResult>>> getGroupsInfo({
    required List<String> groupIDList,
  }) async =>
      V2TimValueCallback(code: 0, desc: '', data: []);

  @override
  dynamic noSuchMethod(Invocation call) => super.noSuchMethod(call);
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

  /// 让群聊图片的在线地址可晚于预览页返回。
  Future<V2TimValueCallback<V2TimMessageOnlineUrl>> Function()? imageUrlLoader;

  /// 单独控制 SDK 旧页的返回时机，验证归档等待 SDK 取齐。
  Completer<V2TimValueCallback<List<V2TimMessage>>>? olderHistoryGate;
  int historyCalls = 0;

  /// 保留 SDK 请求游标，用于确认恢复时查询的是当前锚点两侧。
  final historyCursors = <String?>[];

  /// 记录原始 SDK 历史请求方向，供预览测试区分本机与云端查询。
  final historyTypes = <HistoryMsgGetTypeEnum?>[];
  List<V2TimMessage>? mergedContents;
  int deleteCalls = 0;

  /// 记录首屏可见消息已实际发出的回执批次。
  int receiptCalls = 0;

  /// 按时间正序排列的可变历史，用于模拟页面关闭期间收到新消息。
  List<V2TimMessage>? chronologicalHistory;

  /// 媒体分页回归按 SDK 请求上限截取，其他夹具仍返回完整窗口。
  bool limitHistoryPages = false;

  /// 测试可注入批量表情回包，默认继续返回空的表情列表。
  Future<V2TimValueCallback<List<V2TimMessageReactionResult>>> Function(
      List<V2TimMessage>)? reactionLoader;

  /// 可变历史按 SDK 游标分页，其他场景继续使用原有挂起或固定响应。
  Future<V2TimValueCallback<List<V2TimMessage>>> _loadHistory(Invocation call) {
    historyCalls++;
    final cursor = (call.namedArguments[#lastMsg] as V2TimMessage?)?.msgID;
    historyCursors.add(cursor);
    historyTypes.add(call.namedArguments[#getType] as HistoryMsgGetTypeEnum?);
    final olderGate = olderHistoryGate;
    if (cursor != null && olderGate != null) return olderGate.future;
    final history = chronologicalHistory;
    if (history != null) {
      // SDK 旧消息页倒序、新消息页正序，且两页均不重复返回游标自身。
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
          V2TimValueCallback(code: 0, desc: '', data: limitHistoryPages
              ? messages.take(call.namedArguments[#count] as int).toList()
              : messages));
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
        #getMessageReadReceipts =>
          Future.value(V2TimValueCallback<List<V2TimMessageReceipt>>(
              code: 0, desc: '', data: [])),
        #sendMessageReadReceipts => Future<V2TimCallback>.sync(() {
            receiptCalls++;
            return V2TimCallback(code: 0, desc: '');
          }),
        #getMessageOnlineUrl => imageUrlLoader!(),
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
        #getMessageReactions => reactionLoader?.call(
              call.namedArguments[#messageList] as List<V2TimMessage>,
            ) ??
            Future.value(
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
      this.needsReceipt = false,
      this.isMerged = false,
      this.groupId,
      this.custom,
      this.image});
  final int? timestampOverride;
  final int statusOverride;
  final bool isSelfOverride;

  /// 标记对端消息需要在首屏过半可见时发送已读回执。
  final bool needsReceipt;
  final bool isMerged;
  final String? groupId;
  final V2TimCustomElem? custom;
  final V2TimImageElem? image;
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
        #elemType => isMerged ? 10 : custom != null ? 2 : image != null ? 3 : 1,
        #groupID => groupId,
        #customElem => custom,
        #imageElem => image,
        #mergerElem => isMerged
            ? V2TimMergerElem(title: '测试合并记录', abstractList: ['测试摘要'])
            : null,
        #sender || #userID => msgID.contains('-') ? 'history_visual' : 'visual',
        #isSelf => isSelfOverride,
        #needReadReceipt => needsReceipt,
        #isRead ||
        #isPeerRead ||
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
