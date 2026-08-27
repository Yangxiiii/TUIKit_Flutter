import 'dart:async';

import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'conversation_list_controller.dart';
import 'conversation_list_config.dart';
import 'widgets/conversation_item.dart';

export 'conversation_list_config.dart';
export 'widgets/conversation_item.dart';

class ConversationCustomAction {
  final String title;
  final void Function(ConversationInfo) action;

  const ConversationCustomAction({
    required this.title,
    required this.action,
  });
}

/// 展示并管理 TUIKit 会话列表，宿主可选地筛选可见会话。
class ConversationList extends ConsumerStatefulWidget {
  /// 可选的会话 Store；调用方需要主动刷新或复用状态时传入同一实例。
  final ConversationListStore? store;
  final Function(ConversationInfo)? onConversationClick;
  final List<ConversationCustomAction> customActions;
  final ConversationActionConfigProtocol config;

  /// 列表空隙和滚动区域背景；为空时沿用 TUIKit 默认操作区颜色。
  final Color? backgroundColor;

  /// 普通会话行背景；为空时沿用 TUIKit 默认列表颜色。
  final Color? itemBackgroundColor;

  /// 置顶会话行背景；为空时与普通会话行一致。
  final Color? pinnedItemBackgroundColor;

  /// 返回 `true` 的会话才会显示；为空时显示全部会话。
  final bool Function(ConversationInfo)? filter;

  const ConversationList({
    super.key,
    this.store,
    this.onConversationClick,
    this.customActions = const [],
    this.config = const ChatConversationActionConfig(),
    this.filter,
    this.backgroundColor,
    this.itemBackgroundColor,
    this.pinnedItemBackgroundColor,
  });

  @override
  ConsumerState<ConversationList> createState() => _ConversationListState();
}

/// 仅持有滚动控制器，业务列表状态由 Riverpod Controller 管理。
class _ConversationListState extends ConsumerState<ConversationList> {
  late final ConversationListStore conversationListStore;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    conversationListStore = widget.store ?? ConversationListStore.create();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels !=
        _scrollController.position.maxScrollExtent) {
      return;
    }
    final provider = conversationListControllerProvider(conversationListStore);
    final listState = ref.read(provider);
    if (!listState.isLoading && listState.value?.hasMoreConversations == true) {
      unawaited(ref.read(provider.notifier).loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorsTheme = SemanticColorScheme.of(context);
    final provider = conversationListControllerProvider(conversationListStore);
    final layout = ref.watch(
      provider.select((asyncState) {
        final conversations = asyncState.value?.conversations ?? const [];
        final visibleIDs = conversations
            .where(widget.filter ?? (_) => true)
            .map((item) => item.conversationID)
            .join('\u0000');
        return (
          visibleIDs: visibleIDs,
          isLoading: asyncState.isLoading,
          hasMore: asyncState.value?.hasMoreConversations ?? false,
          hasError: asyncState.hasError,
          isEmpty: conversations.isEmpty,
        );
      }),
    );
    final visibleConversationIDs = layout.visibleIDs.isEmpty
        ? const <String>[]
        : layout.visibleIDs.split('\u0000');

    return Container(
      color: widget.backgroundColor ?? colorsTheme.bgColorOperate,
      child: Stack(
        children: [
          ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: visibleConversationIDs.length +
                (layout.isLoading && layout.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (layout.isLoading &&
                  layout.hasMore &&
                  index == visibleConversationIDs.length) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          colorsTheme.buttonColorPrimaryDefault),
                    ),
                  ),
                );
              }

              return _ConversationRow(
                store: conversationListStore,
                conversationID: visibleConversationIDs[index],
                itemBackgroundColor: widget.itemBackgroundColor,
                pinnedItemBackgroundColor: widget.pinnedItemBackgroundColor,
                customActions: widget.customActions,
                config: widget.config,
                onConversationClick: widget.onConversationClick,
              );
            },
          ),
          if (layout.isLoading && layout.isEmpty)
            Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                    colorsTheme.buttonColorPrimaryDefault),
              ),
            ),
          if (layout.hasError && layout.isEmpty)
            Center(
              child: TextButton(
                onPressed: () => ref.invalidate(provider),
                child: const Text('加载失败，点击重试'),
              ),
            ),
        ],
      ),
    );
  }
}

/// 仅订阅单个会话的可变字段，使 SDK 更新不会重建其他会话行。
final class _ConversationRow extends ConsumerWidget {
  const _ConversationRow({
    required this.store,
    required this.conversationID,
    required this.itemBackgroundColor,
    required this.pinnedItemBackgroundColor,
    required this.customActions,
    required this.config,
    required this.onConversationClick,
  });

  final ConversationListStore store;
  final String conversationID;
  final Color? itemBackgroundColor;
  final Color? pinnedItemBackgroundColor;
  final List<ConversationCustomAction> customActions;
  final ConversationActionConfigProtocol config;
  final Function(ConversationInfo)? onConversationClick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = conversationListControllerProvider(store);
    final row = ref.watch(
      provider.select((asyncState) {
        ConversationInfo? conversation;
        for (final item in asyncState.value?.conversations ?? const []) {
          if (item.conversationID == conversationID) {
            conversation = item;
            break;
          }
        }
        if (conversation == null) return null;
        return (
          conversation: conversation,
          title: conversation.title,
          draft: conversation.draft,
          unreadCount: conversation.unreadCount,
          isPinned: conversation.isPinned,
          receiveOption: conversation.receiveOption,
          lastMessageID: conversation.lastMessage?.msgID,
          lastMessageTime: conversation.lastMessage?.timestamp,
          markTypes: conversation.conversationMarkList
              .map((item) => item.rawValue)
              .join(','),
        );
      }),
    );
    final conversation = row?.conversation;
    if (conversation == null) return const SizedBox.shrink();
    final controller = ref.read(provider.notifier);

    return ConversationItem(
      conversation: conversation,
      backgroundColor: conversation.isPinned
          ? pinnedItemBackgroundColor ?? itemBackgroundColor
          : itemBackgroundColor,
      onPinToggle: () => unawaited(controller.pin(conversation)),
      onDelete: () => unawaited(controller.delete(conversation)),
      onClearHistory: () => unawaited(controller.clearHistory(conversation)),
      onMarkAsRead: () => unawaited(controller.markAsRead(conversation)),
      onMarkAsUnread: () => unawaited(controller.markAsUnread(conversation)),
      onTap: () {
        // 进入会话前清除未读状态，保持与原生 UIKit 的交互一致。
        unawaited(controller.markAsRead(conversation));
        onConversationClick?.call(conversation);
      },
      customActions: customActions,
      config: config,
    );
  }
}
