import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text_field/extended_text_field.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_conversation_manager.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_friendship_manager.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_message_manager.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_msg_create_info_result.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

void main() {
  late V2TIMManager original;
  late _Sdk sdk;
  setUp(() {
    original = TencentImSDKPlugin.v2TIMManager;
    sdk = _Sdk();
    TencentImSDKPlugin.v2TIMManager = sdk;
  });
  tearDown(() => TencentImSDKPlugin.v2TIMManager = original);

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          theme: AppThemeFactory.create(
            const AppNormalColorScheme(),
            Brightness.light,
          ),
          home: Scaffold(
            body: MessageInput(
              conversationID: 'c2c_test',
              config: ChatMessageInputConfig(actionGuard: ActionGuard()),
            ),
          ),
        ),
      );

  Future<void> enter(WidgetTester tester, String text) async {
    if (find.byType(ExtendedTextField).evaluate().isEmpty) {
      await tester.tap(find.textContaining('发送给 '));
      await tester.pump();
    }
    final input =
        tester.widget<ExtendedTextField>(find.byType(ExtendedTextField).first);
    input.controller!.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    await tester.pump();
  }

  testWidgets('320宽输入与格式工具栏保持可切换且不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('文字格式'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('粗体'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('恢复草稿显示正文但不主动弹出键盘', (tester) async {
    await mount(tester);
    sdk.conversations.completeDraft('原草稿');
    await tester.pump();
    final input =
        tester.widget<ExtendedTextField>(find.byType(ExtendedTextField).first);
    expect(input.controller!.text, '原草稿');
    expect(input.focusNode!.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('迟到的旧草稿不能覆盖新输入且新内容继续保存', (tester) async {
    await mount(tester);
    await enter(tester, '新输入');
    sdk.conversations.completeDraft('旧草稿');
    await tester.pump();
    expect(
      tester
          .widget<ExtendedTextField>(find.byType(ExtendedTextField).first)
          .controller!
          .text,
      '新输入',
    );
    await tester.pump(const Duration(milliseconds: 850));
    expect(sdk.conversations.saved.last, '新输入');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('读取未完成便退出既不清空旧草稿也不操作销毁的输入框', (tester) async {
    await mount(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(sdk.conversations.saved, isEmpty);
    sdk.conversations.completeDraft('仍应保留');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(sdk.conversations.saved, isEmpty);
  });

  testWidgets('草稿读取异常后仍能保存新输入', (tester) async {
    await mount(tester);
    sdk.conversations.pending.completeError(StateError('读取失败'));
    await tester.pump();
    await enter(tester, '读取失败后的新输入');
    await tester.pump(const Duration(milliseconds: 850));
    expect(sdk.conversations.saved.last, '读取失败后的新输入');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('草稿读取失败后直接退出不会把旧草稿清空', (tester) async {
    await mount(tester);
    sdk.conversations.pending.complete(
      V2TimValueCallback<V2TimConversation>(code: 1, desc: '读取失败'),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(sdk.conversations.saved, isEmpty);
  });

  testWidgets('4000字符可发、4001禁发并保留输入，回退后恢复', (tester) async {
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    final text = '${'字' * 3999}😀';
    await enter(tester, text);
    final send = find.bySemanticsIdentifier('tim.message_input_toolbar.send');
    expect(send, findsOneWidget);
    expect(
        tester
            .getSemantics(send)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue);
    expect(find.bySemanticsIdentifier('tim.input.text'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsIdentifier('tim.input.text'))
          .getSemanticsData()
          .hasAction(SemanticsAction.setText),
      isTrue,
    );
    await enter(tester, '$text甲');
    await tester.pump();
    expect(
        tester
            .getSemantics(send)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse);
    expect(find.text('字数超出限制无法发送'), findsOneWidget);
    expect(
      tester
          .widget<ExtendedTextField>(find.byType(ExtendedTextField).first)
          .controller!
          .text,
      '$text甲',
    );
    // 表情面板的回调也是实际发送入口，禁用态不能只由按钮外观保证。
    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    await state.getEmojiPanelWidget();
    (state.stickerWidget as EmojiPicker).onSendClick!();
    await tester.pump();
    expect(sdk.messages.created, 0);
    await enter(tester, text);
    expect(
        tester
            .getSemantics(send)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('内联富文本重复提交合并，成功不会清掉等待期间新增文字', (tester) async {
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    await enter(tester, '待发送');
    await tester.tap(find.byTooltip('文字格式'));
    await tester.pump(const Duration(milliseconds: 200));
    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    await state.getEmojiPanelWidget();
    final send = (state.stickerWidget as EmojiPicker).onSendClick!;
    send();
    send();
    await tester.pump();
    expect(sdk.messages.created, 1);
    expect(sdk.messages.pending, hasLength(1));
    await enter(tester, '等待期间新输入');
    sdk.messages.completeSend();
    await tester.pump();
    expect(
      tester
          .widget<ExtendedTextField>(find.byType(ExtendedTextField).first)
          .controller!
          .text,
      '等待期间新输入',
    );
    send();
    await tester.pump();
    expect(sdk.messages.created, 2);
    sdk.messages.completeSend();
    await tester.pump();
    expect(
      tester
          .widget<ExtendedTextField>(find.byType(ExtendedTextField).first)
          .controller!
          .text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('发送失败显示精确提示并允许重试', (tester) async {
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    await enter(tester, '失败前输入');
    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    await state.getEmojiPanelWidget();
    final send = (state.stickerWidget as EmojiPicker).onSendClick!;
    send();
    await tester.pump();
    sdk.messages.completeSend(code: 1);
    await tester.pump();
    expect(find.text('消息发送失败'), findsOneWidget);
    await enter(tester, '再次发送');
    send();
    await tester.pump();
    expect(sdk.messages.created, 2);
    sdk.messages.completeSend();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('SDK异常也会释放发送任务并保留重试能力', (tester) async {
    await mount(tester);
    sdk.conversations.completeDraft('');
    await tester.pump();
    await enter(tester, '异常前输入');
    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    await state.getEmojiPanelWidget();
    final send = (state.stickerWidget as EmojiPicker).onSendClick!;
    send();
    await tester.pump();
    sdk.messages.pending.removeAt(0).completeError(StateError('模拟SDK异常'));
    await tester.pump();
    expect(find.text('消息发送失败'), findsOneWidget);
    await enter(tester, '异常后重试');
    send();
    await tester.pump();
    expect(sdk.messages.created, 2);
    sdk.messages.completeSend();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class _Sdk implements V2TIMManager {
  final conversations = _Conversations();
  final messages = _Messages();
  final friends = _Friends();

  @override
  dynamic noSuchMethod(Invocation call) => switch (call.memberName) {
        #getConversationManager => conversations,
        #getMessageManager => messages,
        #getFriendshipManager => friends,
        #callExperimentalAPI => Future.value(
            V2TimValueCallback<String>(code: 0, desc: '', data: ''),
          ),
        _ => super.noSuchMethod(call),
      };
}

final class _Conversations implements V2TIMConversationManager {
  Completer<V2TimValueCallback<V2TimConversation>>? _pending;
  // 在Widget测试的异步区域内创建Future，避免结果跨测试回合才回填。
  Completer<V2TimValueCallback<V2TimConversation>> get pending =>
      _pending ??= Completer<V2TimValueCallback<V2TimConversation>>();
  final saved = <String?>[];

  void completeDraft(String draft) => pending.complete(
        V2TimValueCallback(
          code: 0,
          desc: '',
          data: V2TimConversation(
            conversationID: 'c2c_test',
            type: 1,
            userID: 'test',
            showName: '测试会话',
            draftText: draft,
          ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation call) {
    switch (call.memberName) {
      case #getConversation:
        return pending.future;
      case #setConversationDraft:
        saved.add(call.namedArguments[#draftText] as String?);
        return Future.value(V2TimCallback(code: 0, desc: ''));
      case #getTotalUnreadMessageCount:
        return Future.value(
            V2TimValueCallback<int>(code: 0, desc: '', data: 0));
      case #getConversationListByFilter:
        return Future.value(
          V2TimValueCallback<V2TimConversationResult>(
            code: 0,
            desc: '',
            data:
                V2TimConversationResult(isFinished: true, conversationList: []),
          ),
        );
      case #addConversationListener:
      case #removeConversationListener:
        return Future<void>.value();
      default:
        return super.noSuchMethod(call);
    }
  }
}

final class _Messages implements V2TIMMessageManager {
  int created = 0;
  final pending = <Completer<V2TimValueCallback<V2TimMessage>>>[];

  void completeSend({int code = 0}) => pending.removeAt(0).complete(
        V2TimValueCallback<V2TimMessage>(code: code, desc: ''),
      );

  @override
  dynamic noSuchMethod(Invocation call) {
    switch (call.memberName) {
      case #createTextMessage:
      case #createCustomMessage:
        created++;
        return Future.value(
          V2TimValueCallback<V2TimMsgCreateInfoResult>(
            code: 0,
            desc: '',
            data: V2TimMsgCreateInfoResult(
              messageInfo: _Message('test_$created'),
            ),
          ),
        );
      case #sendMessage:
        final result = Completer<V2TimValueCallback<V2TimMessage>>();
        pending.add(result);
        return result.future;
      default:
        return super.noSuchMethod(call);
    }
  }
}

final class _Friends implements V2TIMFriendshipManager {
  @override
  dynamic noSuchMethod(Invocation call) => switch (call.memberName) {
        #addFriendListener || #removeFriendListener => Future<void>.value(),
        _ => super.noSuchMethod(call),
      };
}

final class _Message implements V2TimMessage {
  _Message(this.msgID);

  @override
  String? msgID;
  @override
  int? timestamp = 1;
  @override
  bool? isSupportMessageExtension;
  @override
  bool? needReadReceipt;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
