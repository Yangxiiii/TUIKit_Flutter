import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/conversation_list/conversation_list_controller.dart';

void main() {
  test('会话加载成功后生成不可变页面快照', () async {
    final store = _FakeConversationListStore(
      conversations: [
        ConversationInfo(
          conversationID: 'c2c_user1',
          type: ConversationType.c2c,
        ),
      ],
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = await container.read(
      conversationListControllerProvider(store).future,
    );

    expect(state.conversations.single.conversationID, 'c2c_user1');
    expect(state.hasMoreConversations, isFalse);
  });

  test('会话加载失败时进入 AsyncError', () async {
    final store = _FakeConversationListStore(errorCode: 1001);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = conversationListControllerProvider(store);

    await expectLater(container.read(provider.future), throwsStateError);
    expect(container.read(provider).hasError, isTrue);
  });
}

final class _FakeConversationListState implements ConversationListState {
  _FakeConversationListState(List<ConversationInfo> conversations)
      : conversationList = ValueNotifier(conversations);

  @override
  final ValueNotifier<List<ConversationInfo>> conversationList;

  @override
  final ValueNotifier<bool> hasMoreConversations = ValueNotifier(false);

  @override
  final ValueNotifier<int> totalUnreadCount = ValueNotifier(0);
}

final class _FakeConversationListStore implements ConversationListStore {
  _FakeConversationListStore({
    List<ConversationInfo> conversations = const [],
    this.errorCode = 0,
  }) : state = _FakeConversationListState(conversations);

  final int errorCode;

  @override
  final ConversationListState state;

  @override
  Future<CompletionHandler> loadConversations({
    ConversationLoadOption? option,
  }) async =>
      CompletionHandler()..errorCode = errorCode;

  @override
  Future<CompletionHandler> loadMoreConversations() async =>
      CompletionHandler();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
