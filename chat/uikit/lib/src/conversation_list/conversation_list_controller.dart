import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../message_list/message_list.dart';

final conversationListControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ConversationListController, ConversationListViewState,
        ConversationListStore>(ConversationListController.new);

/// 会话列表的不可变页面状态，由 SDK Store 的通知统一生成快照。
final class ConversationListViewState {
  const ConversationListViewState({
    required this.conversations,
    required this.hasMoreConversations,
  });

  /// SDK 当前已加载并按会话顺序排列的不可变快照。
  final List<ConversationInfo> conversations;

  /// SDK 是否还有下一页会话可加载。
  final bool hasMoreConversations;
}

/// 将会话 SDK 的可变监听状态转换为 Riverpod 状态，并统一处理列表操作。
final class ConversationListController
    extends AsyncNotifier<ConversationListViewState> {
  ConversationListController(this._store);

  final ConversationListStore _store;

  ConversationListViewState _snapshot() => ConversationListViewState(
        conversations: List.unmodifiable(_store.state.conversationList.value),
        hasMoreConversations: _store.state.hasMoreConversations.value,
      );

  @override
  Future<ConversationListViewState> build() async {
    void syncFromStore() => state = AsyncData(_snapshot());

    _store.state.conversationList.addListener(syncFromStore);
    ref.onDispose(
      () => _store.state.conversationList.removeListener(syncFromStore),
    );

    final result = await _store.loadConversations(
      option: ConversationLoadOption(),
    );
    if (!result.isSuccess) {
      throw StateError(result.errorMessage ?? '会话列表加载失败');
    }
    return _snapshot();
  }

  /// 加载下一页，并保留当前数据避免分页时整块列表闪烁。
  Future<void> loadMore() async {
    if (state.isLoading || state.value?.hasMoreConversations != true) return;
    state = const AsyncLoading<ConversationListViewState>();
    final result = await _store.loadMoreConversations();
    if (!result.isSuccess) {
      state = AsyncError<ConversationListViewState>(
        StateError(result.errorMessage ?? '更多会话加载失败'),
        StackTrace.current,
      );
      return;
    }
    state = AsyncData(_snapshot());
  }

  /// 切换指定会话的置顶状态。
  Future<void> pin(ConversationInfo conversation) => _store.pinConversation(
        conversationID: conversation.conversationID,
        pin: !conversation.isPinned,
      );

  /// 清空指定会话的历史消息。
  Future<void> clearHistory(ConversationInfo conversation) async {
    final result = await _store.clearConversationMessages(
      conversationID: conversation.conversationID,
    );
    if (result.isSuccess) {
      MessageList.removeViewportSnapshot(conversation.conversationID);
    }
  }

  /// 删除指定会话。
  Future<void> delete(ConversationInfo conversation) async {
    final result = await _store.deleteConversation(
      conversationID: conversation.conversationID,
    );
    if (result.isSuccess) {
      MessageList.removeViewportSnapshot(conversation.conversationID);
    }
  }

  /// 清除真实未读数和手工未读标记。
  Future<void> markAsRead(ConversationInfo conversation) async {
    await _store.clearConversationUnreadCount(
      conversationID: conversation.conversationID,
    );
    await _store.markConversation(
      conversationIDList: [conversation.conversationID],
      markType: ConversationMarkType.unread,
      enable: false,
    );
  }

  /// 添加手工未读标记，不修改 SDK 的真实未读数。
  Future<void> markAsUnread(ConversationInfo conversation) =>
      _store.markConversation(
        conversationIDList: [conversation.conversationID],
        markType: ConversationMarkType.unread,
        enable: true,
      );
}
