import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';

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
class ConversationList extends StatefulWidget {
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
    this.onConversationClick,
    this.customActions = const [],
    this.config = const ChatConversationActionConfig(),
    this.filter,
    this.backgroundColor,
    this.itemBackgroundColor,
    this.pinnedItemBackgroundColor,
  });

  @override
  State<ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends State<ConversationList> {
  late ConversationListStore conversationListStore;
  final ScrollController _scrollController = ScrollController();
  List<ConversationInfo> conversations = [];
  bool isLoading = false;
  bool hasMoreConversations = true;

  // Listener references for proper removal
  late final VoidCallback _conversationListChangedListener;
  late final VoidCallback _scrollListenerCallback;

  @override
  void initState() {
    super.initState();

    // Initialize listener references
    _conversationListChangedListener = _onConversationListChanged;
    _scrollListenerCallback = _scrollListener;

    conversationListStore = ConversationListStore.create();

    conversationListStore.state.conversationList
        .addListener(_conversationListChangedListener);

    _scrollController.addListener(_scrollListenerCallback);

    _loadConversations();
  }

  @override
  void dispose() {
    conversationListStore.state.conversationList
        .removeListener(_conversationListChangedListener);
    _scrollController.removeListener(_scrollListenerCallback);
    _scrollController.dispose();
    super.dispose();
  }

  void _onConversationListChanged() {
    setState(() {
      conversations =
          conversationListStore.state.conversationList.value.toList();
    });
  }

  void _scrollListener() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      if (!isLoading && hasMoreConversations) {
        _loadMoreConversations();
      }
    }
  }

  Future<void> _loadConversations() async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
    });
    final option = ConversationLoadOption();

    final result =
        await conversationListStore.loadConversations(option: option);
    setState(() {
      hasMoreConversations = result.isSuccess &&
          conversationListStore.state.hasMoreConversations.value;
      isLoading = false;
    });
  }

  Future<void> _loadMoreConversations() async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
    });
    final result = await conversationListStore.loadMoreConversations();
    setState(() {
      hasMoreConversations = result.isSuccess &&
          conversationListStore.state.hasMoreConversations.value;
      isLoading = false;
    });
  }

  void _handlePinConversation(ConversationInfo conversationInfo) async {
    if (conversationInfo.isPinned) {
      conversationListStore.pinConversation(
          conversationID: conversationInfo.conversationID, pin: false);
    } else {
      conversationListStore.pinConversation(
          conversationID: conversationInfo.conversationID, pin: true);
    }
  }

  void _handleClearHistoryMessage(ConversationInfo conversationInfo) async {
    conversationListStore.clearConversationMessages(
        conversationID: conversationInfo.conversationID);
  }

  void _handleDeleteConversation(ConversationInfo conversationInfo) async {
    conversationListStore.deleteConversation(
        conversationID: conversationInfo.conversationID);
  }

  /// Marks a conversation as read by clearing unread count and removing unread mark.
  void _handleMarkAsRead(ConversationInfo conversationInfo) async {
    // Clear real unread count
    conversationListStore.clearConversationUnreadCount(
        conversationID: conversationInfo.conversationID);
    // Remove unread mark from markList
    conversationListStore.markConversation(
      conversationIDList: [conversationInfo.conversationID],
      markType: ConversationMarkType.unread,
      enable: false,
    );
  }

  /// Marks a conversation as unread by adding unread mark (does not affect unreadCount).
  void _handleMarkAsUnread(ConversationInfo conversationInfo) async {
    // Add unread mark to markList
    conversationListStore.markConversation(
      conversationIDList: [conversationInfo.conversationID],
      markType: ConversationMarkType.unread,
      enable: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorsTheme = SemanticColorScheme.of(context);
    final visibleConversations = widget.filter == null
        ? conversations
        : conversations.where(widget.filter!).toList();

    return Container(
      color: widget.backgroundColor ?? colorsTheme.bgColorOperate,
      child: Stack(
        children: [
          ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: visibleConversations.length +
                (isLoading && hasMoreConversations ? 1 : 0),
            itemBuilder: (context, index) {
              if (isLoading &&
                  hasMoreConversations &&
                  index == visibleConversations.length) {
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

              final conversation = visibleConversations[index];

              return ConversationItem(
                conversation: conversation,
                backgroundColor: conversation.isPinned
                    ? widget.pinnedItemBackgroundColor ??
                        widget.itemBackgroundColor
                    : widget.itemBackgroundColor,
                onPinToggle: () {
                  _handlePinConversation(conversation);
                },
                onDelete: () {
                  _handleDeleteConversation(conversation);
                },
                onClearHistory: () {
                  _handleClearHistoryMessage(conversation);
                },
                onMarkAsRead: () {
                  _handleMarkAsRead(conversation);
                },
                onMarkAsUnread: () {
                  _handleMarkAsUnread(conversation);
                },
                onTap: () {
                  // Clear unread status before entering conversation (same as Swift implementation)
                  _handleMarkAsRead(conversation);
                  if (widget.onConversationClick != null) {
                    widget.onConversationClick!(conversation);
                  }
                },
                customActions: widget.customActions,
                config: widget.config,
              );
            },
          ),
          if (isLoading && conversations.isEmpty)
            Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                    colorsTheme.buttonColorPrimaryDefault),
              ),
            ),
        ],
      ),
    );
  }
}
