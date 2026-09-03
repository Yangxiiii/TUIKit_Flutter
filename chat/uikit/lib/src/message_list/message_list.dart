import 'package:app_ui/app_ui.dart';
import 'dart:async';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/cupertino.dart';

import 'package:flutter/material.dart' hide AlertDialog;
import 'package:flutter/services.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/at_mention_utils.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/asr_display_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/call_ui_extension.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_viewport_anchor.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_utils.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/translation_display_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/translation_text_parser.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/asr_popup_menu.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_item.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_tongue_widget.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/forward/forward_service.dart';
import 'package:tencent_chat_uikit/src/third_party/scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:tencent_chat_uikit/src/third_party/visibility_detector/visibility_detector.dart';

export 'message_list_config.dart';
export 'widgets/message_bubble.dart';
export 'widgets/message_item.dart';
export 'widgets/message_types/custom_message_widget.dart';
export 'widgets/message_types/system_message_widget.dart';
export 'widgets/multi_select_bottom_bar.dart';
export 'widgets/message_checkbox.dart';
export 'widgets/message_reaction_bar.dart';
export 'widgets/reaction_emoji_picker.dart';
export 'widgets/reaction_detail_sheet.dart';
export 'utils/recent_emoji_manager.dart';
export 'widgets/message_tongue_widget.dart';

typedef OnUserClick = void Function(String userID);

/// Callback when user long presses on avatar (for @ mention feature)
/// [userID] is the user ID of the message sender
/// [displayName] is the display name of the message sender
///
/// 当用户长按头像时的回调（用于@提及功能）[userID] 是消息发送者的用户ID [displayName] 是消息发送者的显示名称
typedef OnUserLongPress = void Function(String userID, String displayName);

/// Callback when call message is clicked in C2C conversation
/// [userID] is the user ID of the other party
/// [isVideoCall] is true for video call, false for voice call
///
/// 当在C2C会话中点击通话消息时的回调 [userID] 是对方的用户ID [isVideoCall] 视频通话为true，语音通话为false
typedef OnCallMessageClick = void Function(String userID, bool isVideoCall);

/// Multi-select mode state callback
///
/// 多选模式状态回调
typedef OnMultiSelectModeChanged = void Function(
    bool isMultiSelectMode, int selectedCount);

/// Multi-select mode state
///
/// 多选模式状态
class MultiSelectState {
  final bool isActive;
  final int selectedCount;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final Future<void> Function(BuildContext context) onForward;

  const MultiSelectState({
    required this.isActive,
    required this.selectedCount,
    required this.onCancel,
    required this.onDelete,
    required this.onForward,
  });
}

/// Multi-select mode action callbacks
///
/// 多选模式操作回调
class MultiSelectCallbacks {
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onForward;

  const MultiSelectCallbacks({
    required this.onCancel,
    required this.onDelete,
    required this.onForward,
  });
}

class MessageCustomAction {
  final String title;
  final String assetName;
  final String? package;
  final IconData? systemIconFallback;
  final void Function(MessageInfo) action;

  const MessageCustomAction({
    required this.title,
    this.assetName = '',
    this.package,
    this.systemIconFallback,
    required this.action,
  });
}

class MessageList extends StatefulWidget {
  final String conversationID;
  final MessageListConfigProtocol config;
  final MessageInfo? locateMessage;
  final OnUserClick? onUserClick;

  /// Callback when user long presses on avatar (for @ mention feature in group chat)
  ///
  /// 当用户长按头像时的回调（用于群聊中的@提及功能）
  final OnUserLongPress? onUserLongPress;

  /// Callback when call message is clicked in C2C conversation
  ///
  /// 当在C2C会话中点击通话消息时的回调
  final OnCallMessageClick? onCallMessageClick;

  /// Callback when user taps "Quote" in the long-press menu
  ///
  /// 当用户在长按菜单中点击“引用”时的回调
  final void Function(MessageInfo message)? onQuoteMessage;
  final List<MessageCustomAction> customActions;

  /// Multi-select mode change callback
  ///
  /// 多选模式变化回调
  final OnMultiSelectModeChanged? onMultiSelectModeChanged;

  /// Multi-select state change callback (includes action methods)
  ///
  /// 多选状态变化回调（包括操作方法）
  final void Function(MultiSelectState? state)? onMultiSelectStateChanged;

  /// Group at-mention info list from ConversationInfo for tongue navigation
  ///
  /// 来自ConversationInfo的群@提及信息列表，用于小舌头导航
  final List<GroupAtInfo>? groupAtInfoList;

  /// Initial unread count from ConversationInfo when entering the chat
  ///
  /// 进入聊天时从 ConversationInfo 获取的初始未读计数
  final int initialUnreadCount;

  const MessageList({
    super.key,
    required this.conversationID,
    this.config = const ChatMessageListConfig(),
    this.locateMessage,
    this.onUserClick,
    this.onUserLongPress,
    this.onCallMessageClick,
    this.onQuoteMessage,
    this.customActions = const [],
    this.onMultiSelectModeChanged,
    this.onMultiSelectStateChanged,
    this.groupAtInfoList,
    this.initialUnreadCount = 0,
  });

  /// 清除当前进程内的全部会话浏览快照；用户登出时调用。
  static void clearViewportSnapshots() {
    _MessageListState._viewportSnapshots.clear();
  }

  /// 清除当前登录用户的指定会话快照；删除会话或清空历史时调用。
  static void removeViewportSnapshot(String conversationID) {
    final userID = LoginStore.shared.loginState.loginUserInfo?.userID ?? '';
    _MessageListState._viewportSnapshots.remove(
      _MessageListState._viewportKey(userID, conversationID),
    );
  }

  @override
  State<MessageList> createState() => _MessageListState();
}

/// What the message list is currently doing, navigation-wise.
///
/// All four "in-flight" states are mutually exclusive: the list can be
/// navigating to the oldest unread message, or to an @ mention, or to a
/// quoted message, or reloading to the latest page — never two at once.
/// Modelling them as a sealed hierarchy instead of as a bag of independent
/// booleans (the previous design) makes that exclusivity a compile-time
/// guarantee, lets the scroll listener short-circuit on the single check
/// `_navigationState is _NavIdle`, and gives the inbound
/// `_onMessageListStateChanged` dispatcher exhaustive pattern matching
/// over each navigation kind.
///
/// `_NavToAtMention.targetSeq` and `_NavToQuotedMessage.targetMsgID` are
/// nullable on purpose: setting them to null after the inbound branch has
/// run is the "processed once" guard that prevents a second
/// notifyListeners (e.g. from a reaction/extension fetch in the same
/// 2-frame settle window) from re-applying the jump/highlight and yanking
/// the user away from where they just landed.
///
/// 当前消息列表在导航方面正在做什么。
///
/// 四种“进行中”状态是互斥的：列表可以导航到最旧的未读消息，或者 @
/// 提醒，或者引用的消息，或者重新加载到最新页面——永远不会同时出现两种。将它们建模为一个封闭的层次结构，而不是一堆独立的布尔值（之前的设计），可以在编译时保证这种互斥性，让滚动监听器在
/// `_navigationState is _NavIdle` 的单次检查上就能短路，并且让传入的 `_onMessageListStateChanged` 分发器能对每种导航类型进行穷尽模式匹配。
///
/// `_NavToAtMention.targetSeq` 和 `_NavToQuotedMessage.targetMsgID` 是故意设计成可空的：在入站分支运行后将它们设置为
/// null，是“只处理一次”的保护措施，可以防止第二次 notifyListeners（例如在同一个两帧稳定窗口里的反应/扩展获取）重新应用跳转/高亮，把用户从刚到达的位置拉走。
sealed class _NavigationState {
  const _NavigationState();
}

class _NavIdle extends _NavigationState {
  const _NavIdle();
}

class _NavToUnread extends _NavigationState {
  const _NavToUnread();
}

class _NavToAtMention extends _NavigationState {
  final int? targetSeq;
  const _NavToAtMention(this.targetSeq);
}

class _NavToQuotedMessage extends _NavigationState {
  final String? targetMsgID;

  /// Tongue type to commit when the inbound branch lands on the target.
  ///
  /// Forward navigation (tap on quote preview → go to the quoted target)
  /// passes [TongueType.backToQuote] so the user can round-trip back to
  /// the source. The reverse navigation (tap on backToQuote tongue → go
  /// back to the source) passes [TongueType.none] so the scroll listener
  /// can re-derive the "natural" tongue (backToLatest / atMention) after
  /// the round-trip completes — we do not want a second backToQuote
  /// tongue chaining off the back-navigation.
  ///
  /// 当入站分支到达目标时，要提交的小舌头类型。
  ///
  /// 前向导航（点击引用预览 → 跳转到被引用的目标）会传递 [TongueType.backToQuote]，这样用户可以往返回到源消息。反向导航（点击 backToQuote 小舌头 →
  /// 回到源消息）会传递 [TongueType.none]，这样滚动监听器在往返完成后可以重新推导出“自然”的小舌头（backToLatest /
  /// atMention）——我们不希望在反向导航上再生成第二个 backToQuote 链接。
  final TongueType tongueAfter;

  /// Whether to highlight the landed-on message.
  ///
  /// Forward navigation highlights the quoted target so the user can see
  /// what they landed on. Reverse navigation does NOT highlight the
  /// source — the user already knows where they came from, and a re-flash
  /// of the originating message is just visual noise.
  ///
  /// Kept as a separate field from [tongueAfter] on purpose: the two
  /// happen to align for the current forward/back uses, but they are
  /// orthogonal concerns and a future caller (e.g. "navigate to a search
  /// hit") might want one but not the other.
  ///
  /// 是否高亮显示跳转到的消息。
  ///
  /// 前向导航会高亮被引用的目标，这样用户可以清楚知道自己跳转到了哪里。反向导航不会高亮源消息——用户已经知道自己从哪里来的，重新闪烁原始消息只是视觉噪音。
  ///
  /// 故意将其作为独立字段与 [tongueAfter] 分开：目前在前进/后退的使用中两者碰巧一致，但它们是正交概念，将来主叫方（例如“导航到搜索结果”）可能只需要其中一个而不是另一个。
  final bool highlightTarget;

  const _NavToQuotedMessage(
    this.targetMsgID,
    this.tongueAfter,
    this.highlightTarget,
  );
}

class _NavReloadingLatest extends _NavigationState {
  const _NavReloadingLatest();
}

/// 协调消息分页、可见性已读回执与列表内跳转状态。
class _MessageListState extends State<MessageList>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  /// 每个锚点两侧各缓存 20 条，与 SDK 双向分页的单侧页大小保持一致。
  static const int _snapshotMessagesPerSide = 20;

  /// 以“登录用户 + 会话”隔离快照，避免切换账号后复用其他用户的消息窗口。
  static final Map<String, MessageViewportSnapshot> _viewportSnapshots = {};

  static String _viewportKey(String userID, String conversationID) =>
      '$userID\u0000$conversationID';

  late MessageListStore _messageListStore;

  /// 当前会话在进程内快照表中的稳定键。
  late final String _viewportAnchorKey;

  /// 进入页面前命中的快照；仅用于首屏同步渲染和随后的一次 SDK 刷新。
  MessageViewportSnapshot? _restoreViewportSnapshot;

  /// SDK 刷新快照期间需要保持不动的锚点，刷新完成后立即清空。
  MessageViewportAnchor? _refreshViewportAnchor;

  /// 滚动过程中最近一次有效锚点，退出页面采样失败时作为兜底。
  MessageViewportAnchor? _currentViewportAnchor;

  /// 列表首次创建时使用的消息索引和视口对齐比例。
  int _initialScrollIndex = 0;
  double _initialScrollAlignment = 0;

  /// 为 false 时暂不创建列表，避免初始索引尚未确定就先渲染 index 0。
  bool _isInitialViewportReady = false;
  GroupInfo? _groupInfo;
  late AppLocalizedText _atomicLocale;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  List<MessageInfo> _messages = [];
  StreamSubscription<MessageEvent>? _messageEventSubscription;
  bool isLoading = false;
  bool _isLoadingNewer = false;

  /// Single source of truth for "what kind of navigation is in flight".
  /// See [_NavigationState] for why this replaces the previous bag of
  /// `_isNavigatingTo* / _isReloadingLatest` booleans.
  ///
  /// 关于“正在进行哪种类型的导航”的单一真实来源。请参见 [_NavigationState]，了解为什么这取代了之前的一堆 `_isNavigatingTo* / _isReloadingLatest`
  /// 布尔值。
  _NavigationState _navigationState = const _NavIdle();

  bool _isInitialLoad = true;
  bool _isInitialRenderComplete = false;
  bool _initialLoadStarted = false;

  String? _highlightedMessageId;

  /// The source message of an in-progress quote round-trip — i.e. the
  /// message whose quote preview the user just tapped. Stored as the
  /// full [MessageInfo] (not just `msgID`) because when the
  /// quote-target navigation triggered a Store reload and the source
  /// was wholesale-replaced out of the loaded list, we need its
  /// `sequence` / `timestamp` to reload the page around it on the
  /// reverse leg (`_onBackToQuoteTongueTap`). Cleared after the
  /// round-trip completes.
  ///
  /// 正在进行的引用往返的源消息——也就是用户刚点击其引用预览的那条消息。以完整的 [MessageInfo] 存储（而不仅仅是 `msgID`），因为当引用目标导航触发 Store
  /// 重新加载且源消息从加载列表中被整体替换时，我们需要其 `sequence` / `timestamp` 来在回程（`_onBackToQuoteTongueTap`）时重新加载页面。往返完成后清空。
  MessageInfo? _quoteReturnSource;

  Widget? _callStatusWidget;

  static const int _messageAggregationTime = 300;

  final Set<String> _pendingReceiptMessageIDs = {};
  final Set<String> _sentReceiptMessageIDs = {};
  Timer? _receiptTimer;
  static const Duration _receiptDebounceInterval = Duration(milliseconds: 800);
  // Threshold: auto-load older messages when within this many items of the oldest message
  //
  // 阈值：当接近最旧消息的这么多项目时自动加载旧消息
  static const int _loadOlderMessagesThreshold = 5;

  // Multi-select mode state
  //
  // 多选模式状态
  bool _isMultiSelectMode = false;
  final Set<String> _selectedMessageIDs = {};

  // Tongue (小舌头) state
  TongueType _tongueType = TongueType.none;
  int _newMessageCount = 0;
  final List<MessageInfo> _pendingNewMessages = [];
  String? _atMentionText;
  int? _atMessageSeq;
  static const int _tongueScrollThreshold = 15;

  // Unread messages tongue (右上角未读消息小舌头) state
  TongueType _unreadTongueType = TongueType.none;
  int _initialUnreadCount = 0;
  int _unreadTongueCount = 0;
  int? _oldestUnreadMessageSeq;
  int? _viewedUnreadMinSequence;
  int? _viewedUnreadMaxSequence;
  bool _pendingUnreadCheck =
      false; // Defer tongue display until visibility check

  // @mention tracking for sequential navigation
  //
  // @提及跟踪用于顺序导航
  List<GroupAtInfo> _remainingAtInfoList = [];

  // ASR display manager for voice-to-text feature
  //
  // ASR显示管理器，用于语音转文字功能
  late AsrDisplayManager _asrDisplayManager;

  // Translation display manager for text translation feature
  //
  // 翻译显示管理器，用于文本翻译功能
  late TranslationDisplayManager _translationDisplayManager;

  // Listener references for proper removal
  //
  // 监听器引用以便正确移除
  late final VoidCallback _messageListStateChangedListener;
  late final VoidCallback _scrollListenerCallback;
  late final VoidCallback _joinedGroupListChangedListener;

  // AutomaticKeepAliveClientMixin requires this method to be implemented
  // Returning true indicates that the state is maintained even if the Widget is not in the view.
  //
  // AutomaticKeepAliveClientMixin 需要实现此方法，返回 true 表示即使 Widget 不在视图中状态也会被保持
  @override
  bool get wantKeepAlive => true;

  /// Whether in multi-select mode
  ///
  /// 是否处于多选模式
  bool get isMultiSelectMode => _isMultiSelectMode;

  /// List of selected messages
  ///
  /// 选中消息列表
  List<MessageInfo> get selectedMessages => _messages
      .where((m) => m.msgID != null && _selectedMessageIDs.contains(m.msgID))
      .toList();

  /// Number of selected messages
  ///
  /// 选中消息数量
  int get selectedCount => _selectedMessageIDs.length;

  @override
  void initState() {
    super.initState();

    final currentUserID =
        LoginStore.shared.loginState.loginUserInfo?.userID ?? '';
    _viewportAnchorKey = _viewportKey(currentUserID, widget.conversationID);

    // 外部指定消息用于搜索、@ 或引用跳转，优先级高于普通浏览位置恢复。
    if (widget.locateMessage == null) {
      final snapshot = _viewportSnapshots[_viewportAnchorKey];
      if (snapshot != null) {
        // initState 内同步注入消息窗口，让缓存会话在页面转场的第一帧就有内容。
        _restoreViewportSnapshot = snapshot;
        _messages = snapshot.messages;
        _isInitialViewportReady = _setInitialViewport(
          snapshot.anchor.message,
          alignment: snapshot.anchor.alignment,
        );
      }
    }

    _asrDisplayManager = AsrDisplayManager();
    _translationDisplayManager = TranslationDisplayManager();

    // Initialize listener references
    //
    // 初始化监听器引用
    _messageListStateChangedListener = _onMessageListStateChanged;
    _scrollListenerCallback = _scrollListener;
    _joinedGroupListChangedListener = _onJoinedGroupListChanged;

    _messageListStore =
        MessageListStore.create(conversationID: widget.conversationID);
    _messageListStore.state.messageList
        .addListener(_messageListStateChangedListener);
    _messageEventSubscription =
        _messageListStore.messageEventStream.listen(_onMessageEvent);
    _itemPositionsListener.itemPositions.addListener(_scrollListenerCallback);

    if (widget.conversationID.startsWith(groupConversationIDPrefix)) {
      // Initial pull for call banner; subsequent attribute pushes arrive via
      // GroupStore.joinedGroupList (see _onJoinedGroupListChanged).
      //
      // 通话横幅的初始拉取；后续属性推送通过 GroupStore.joinedGroupList 到达（见 _onJoinedGroupListChanged）
      GroupStore.shared.state.joinedGroupList
          .addListener(_joinedGroupListChangedListener);
      _loadGroupAttributes();
    }

    _initAtMentionTongue();
    _initUnreadTongue();
  }

  Widget _buildTimeDivider(String timeString, SemanticColorScheme colorsTheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: colorsTheme.strokeColorPrimary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            timeString,
            style: FontScheme.caption3Regular.copyWith(
              color: colorsTheme.textColorTertiary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // 优先读取退出瞬间的真实视口；路由销毁导致位置丢失时退回最近一次滚动采样。
    final viewportAnchor = selectMessageViewportAnchor(
          messages: _messages,
          positions: _itemPositionsListener.itemPositions.value,
        ) ??
        _currentViewportAnchor;
    if (viewportAnchor != null && _messages.isNotEmpty) {
      final snapshot = createMessageViewportSnapshot(
        messages: _messages,
        anchor: viewportAnchor,
        messagesPerSide: _snapshotMessagesPerSide,
        unreadAboveCount: _unreadTongueCount,
        unreadBelowCount: _newMessageCount,
        oldestUnreadSequence: _oldestUnreadMessageSeq,
        viewedUnreadMinSequence: _viewedUnreadMinSequence,
        viewedUnreadMaxSequence: _viewedUnreadMaxSequence,
      );
      if (snapshot != null) {
        _viewportSnapshots[_viewportAnchorKey] = snapshot;
      }
    }
    _messageListStore.state.messageList
        .removeListener(_messageListStateChangedListener);
    _messageEventSubscription?.cancel();
    _itemPositionsListener.itemPositions
        .removeListener(_scrollListenerCallback);
    if (widget.conversationID.startsWith(groupConversationIDPrefix)) {
      GroupStore.shared.state.joinedGroupList
          .removeListener(_joinedGroupListChangedListener);
    }
    _receiptTimer?.cancel();
    _asrDisplayManager.dispose();
    _translationDisplayManager.dispose();
    super.dispose();
  }

  void _scrollListener() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    // Single-pass: compute minIndex, maxIndex, isAtBottom in one traversal
    //
    // 单次遍历：在一次遍历中计算 minIndex、maxIndex、isAtBottom
    int minIndex = positions.first.index;
    int maxIndex = minIndex;
    bool isAtBottom = minIndex <= 1;
    for (final pos in positions) {
      final idx = pos.index;
      if (idx < minIndex) minIndex = idx;
      if (idx > maxIndex) maxIndex = idx;
      if (!isAtBottom && idx <= 1) isAtBottom = true;
    }

    // Don't kick off auto-loads while any user-initiated navigation is in
    // flight. Each of those nav states drives its own scroll/jumpTo and
    // would race with the scroll-listener-driven _loadNewer/_loadPrevious.
    //
    // 当有用户发起的导航正在进行时，不要启动自动加载。这些导航状态中的每一个都会驱动自己的滚动/jumpTo，并且会与由滚动监听器触发的 _loadNewer/_loadPrevious 发生竞争。
    final isNavIdle = _navigationState is _NavIdle;
    if (_isInitialViewportReady && isNavIdle) {
      final viewportAnchor = selectMessageViewportAnchor(
        messages: _messages,
        positions: positions,
      );
      if (viewportAnchor != null) {
        _consumeVisibleUnread(positions);
        _currentViewportAnchor = viewportAnchor;
      }
    }

    // Load newer messages when the user has scrolled to the bottom
    // (reverse:true → "bottom" = newest = index 0 area).
    //
    // Uses `isAtBottom` (minIndex <= 1) rather than the stricter
    // `minIndex <= 0` so this trigger matches the rest of the file's
    // notion of "at bottom" (see `_isUserAtBottom()` and the
    // `isAtBottom` flag above). With reverse:true,
    // ScrollablePositionedList does not always pin index 0 at the
    // leading edge once a scroll reaches its physical limit — index 0
    // may stay fully visible while minIndex sits at 1 — so requiring
    // `<= 0` would silently skip the load even after the user is
    // visibly at the bottom of the loaded page.
    //
    // 当用户滚动到底部时加载更新的消息
    //
    // 使用 `isAtBottom`（minIndex <= 1）而不是更严格的 `minIndex <= 0`，这样触发条件与文件中其他 “到底部” 的定义一致（参见
    // `_isUserAtBottom()` 和上面的 `isAtBottom` 标志）。使用 reverse:true 时，ScrollablePositionedList
    // 并不总是在滚动到物理极限时把索引 0 固定在前端——索引 0 可能仍完全可见，而 minIndex 为 1——所以要求 `<= 0` 会导致即使用户看起来已经到底，加载也会被静默跳过。
    if (!_isLoadingNewer &&
        isNavIdle &&
        _messageListStore.state.hasNewerMessages.value) {
      if (_highlightedMessageId == null && isAtBottom) {
        _loadNewerMessages();
      }
    }

    // Auto-load older messages when scrolled near the oldest message (reverse list: largest index = oldest)
    if (!isLoading &&
        isNavIdle &&
        _messageListStore.state.hasOlderMessages.value) {
      if (maxIndex >= _messages.length - _loadOlderMessagesThreshold) {
        _loadPreviousMessages();
      }
    }

    // Tongue visibility logic
    //
    // 小舌头可见性逻辑
    if (!widget.config.isSupportTongue || !_isInitialRenderComplete) return;
    _updateTongueState(minIndex, isAtBottom);
  }

  void _updateTongueState(int minIndex, bool isAtBottom) {
    // Any user-initiated navigation owns the tongue state for the duration
    // of its 2-frame settle window — the corresponding branch in
    // `_onMessageListStateChanged` set tongue/highlight/scroll atomically
    // and any scroll-driven re-derivation here would race with that.
    // Reload-latest needs the tongue's loading spinner kept on too, until
    // the Completer-driven cleanup hides it.
    //
    // 任何用户发起的导航在其 2 帧的稳定窗口期间控制小舌头状态 —— `_onMessageListStateChanged`
    // 中对应的分支会原子地设置小舌头/高亮/滚动，任何由滚动触发的重新推导都会和它竞争。刷新最新需要小舌头的加载旋转保持显示，直到由 Completer 控制的清理隐藏它。
    if (_navigationState is! _NavIdle) return;

    if (isAtBottom) {
      final hasNewerMessages = _messageListStore.state.hasNewerMessages.value;
      final isAtLatest = isAtConversationLatest(
        isAtLoadedWindowBottom: isAtBottom,
        hasNewerMessages: hasNewerMessages,
      );
      if (_tongueType != TongueType.none || _newMessageCount > 0) {
        setState(() {
          if (_remainingAtInfoList.isEmpty) {
            // 当前可能只是历史分页窗口的底部；SDK 仍有更新消息时必须保留未读数量。
            if (!isAtLatest) {
              _tongueType = _newMessageCount > 0
                  ? TongueType.newMessages
                  : TongueType.backToLatest;
            } else {
              _newMessageCount = 0;
              _pendingNewMessages.clear();
              _tongueType = TongueType.none;
            }
          }
        });
      }
      return;
    }

    final isScrolledPastThreshold = minIndex > _tongueScrollThreshold;

    if (isScrolledPastThreshold) {
      // Don't override backToQuote tongue — it stays until user taps it or scrolls to bottom
      //
      // 不要覆盖 backToQuote 小舌头 —— 它会保持显示，直到用户点击它或滚动到底部。
      if (_tongueType != TongueType.backToQuote) {
        final newType = _computeTongueType();
        if (newType != _tongueType) {
          setState(() {
            _tongueType = newType;
          });
        }
      }
    } else {
      // Not scrolled past threshold — only hide tongue types that require
      // the threshold (atMention).  Keep newMessages and backToLatest tongue
      // visible: the user is NOT at bottom (handled above) so they should
      // still see the indicator to jump back to the latest position.
      //
      // 没有滚动超过阈值 —— 只隐藏那些需要阈值的小舌头类型（如 @提及）。保持 newMessages 和 backToLatest
      // 小舌头可见：用户不在底部（前面已经处理），所以他们仍然应该看到指示器以跳回最新位置。
      if (_tongueType != TongueType.none &&
          _tongueType != TongueType.newMessages &&
          _tongueType != TongueType.backToLatest &&
          _tongueType != TongueType.backToQuote &&
          _remainingAtInfoList.isEmpty) {
        setState(() {
          _tongueType = TongueType.none;
        });
      }
    }
  }

  TongueType _computeTongueType() {
    if (_remainingAtInfoList.isNotEmpty && _unreadTongueType == TongueType.none)
      return TongueType.atMention;
    if (_newMessageCount > 0) return TongueType.newMessages;
    return TongueType.backToLatest;
  }

  /// 根据显式定位、进程内快照或最新消息的优先级完成首次加载。
  Future<void> _loadInitialMessages() async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
    });

    final requestedMessage = widget.locateMessage;
    final restoredSnapshot = _restoreViewportSnapshot;
    if (requestedMessage != null) {
      // 搜索、@ 和引用跳转必须围绕业务指定的消息加载，不能被浏览快照覆盖。
      debugPrint('messageList, _loadInitialMessages->_loadMessagesAround');
      await _loadMessagesAround(requestedMessage);
      _setInitialViewport(requestedMessage, alignment: 0);
    } else if (restoredSnapshot != null) {
      // 页面已同步显示快照，这里只负责用 SDK 数据静默更新其消息窗口。
      debugPrint('messageList, _loadInitialMessages->restoreViewport');
      final restoredAnchor = restoredSnapshot.anchor;
      var refreshSucceeded = true;
      _refreshViewportAnchor = restoredAnchor;
      try {
        await _loadMessagesAround(restoredAnchor.message);
      } catch (error) {
        // 已有内存快照时刷新失败不阻塞页面，继续展示离开前的消息窗口。
        refreshSucceeded = false;
        debugPrint('messageList, restore viewport refresh failed: $error');
      } finally {
        _refreshViewportAnchor = null;
      }
      if (refreshSucceeded &&
          !_setInitialViewport(
            restoredAnchor.message,
            alignment: restoredAnchor.alignment,
          )) {
        // SDK 已无法返回原锚点时丢弃失效快照，并降级展示最新消息。
        _viewportSnapshots.remove(_viewportAnchorKey);
        await _loadLatestMessages();
      }
    } else {
      // 首次访问或进程重启后没有内存快照，按原有规则进入最新消息位置。
      debugPrint('messageList, _loadInitialMessages->_loadLatestMessages');
      await _loadLatestMessages();
    }

    final initialRenderComplete =
        _messages.length == _messageListStore.state.messageList.value.length;
    if (!mounted) return;
    setState(() {
      isLoading = false;
      _isInitialLoad = false;
      _isInitialRenderComplete = initialRenderComplete;
      _isInitialViewportReady = true;
    });

    if (_pendingUnreadCheck && initialRenderComplete) {
      _scheduleUnreadTongueVisibilityCheck();
    }
  }

  /// 将稳定消息标识转换为本次消息窗口内的初始列表索引。
  bool _setInitialViewport(MessageInfo message, {required double alignment}) {
    final index = _messages.indexWhere((item) => item.msgID == message.msgID);
    if (index == -1) return false;
    _initialScrollIndex = index;
    _initialScrollAlignment = alignment;
    return true;
  }

  void _onMessageListStateChanged() {
    final state = _messageListStore.state;

    debugPrint('messageList, _onMessageListStateChanged, '
        'msgCount: ${state.messageList.value.length}, '
        'navState: ${_navigationState.runtimeType}');

    // 快照已在首帧展示；SDK 回包后仍围绕原锚点替换窗口，避免刷新把用户拉回最新消息。
    final refreshAnchor = _refreshViewportAnchor;
    if (refreshAnchor != null) {
      final refreshedMessages = state.messageList.value.reversed.toList();
      final previousTargetIndex = _messages.indexWhere(
        (message) => message.msgID == refreshAnchor.message.msgID,
      );
      final targetIndex = refreshedMessages.indexWhere(
        (message) => message.msgID == refreshAnchor.message.msgID,
      );
      if (targetIndex != -1) {
        _initialScrollIndex = targetIndex;
        _initialScrollAlignment = refreshAnchor.alignment;
      }
      setState(() {
        _messages = refreshedMessages;
      });
      // 索引未变化时保持当前视口；变化时同步补偿，避免先渲染错误位置再于下一帧跳回。
      if (targetIndex != -1 &&
          targetIndex != previousTargetIndex &&
          _itemScrollController.isAttached) {
        _itemScrollController.jumpTo(
          index: targetIndex,
          alignment: refreshAnchor.alignment,
        );
      }
      return;
    }

    // Each navigation kind owns an "atomic-frame" branch: messages +
    // scroll + highlight + tongue are applied in one setState while we
    // still hold the notifyListeners stack, so a stray _scrollListener /
    // _updateTongueState invocation can never observe a half-applied
    // intermediate state (e.g. list already swapped, but jumpTo hasn't
    // run yet, so positions still report index 0 / isAtBottom=true).
    //
    // `_NavToAtMention` and `_NavToQuotedMessage` carry a nullable
    // target; null means "this nav has already been processed once" —
    // the 2-frame settle window may see additional notifyListeners
    // (e.g. reaction/extension fetch) and we don't want to re-fire the
    // jump and yank the user away from where they just landed.
    //
    // 每种导航类型都有一个“原子帧”分支：messages + scroll + highlight + tongue 会在一次 setState 中应用，同时我们仍然持有 notifyListeners
    // 栈，所以偶然的 _scrollListener / _updateTongueState 调用永远不会观察到半应用的中间状态（例如 list 已经换了，但 jumpTo 还没运行，所以
    // positions 仍然报告 index 0 / isAtBottom=true）。
    //
    // `_NavToAtMention` 和 `_NavToQuotedMessage` 带有可空的 target；null 意味着“这个导航已经处理过一次”——两帧的稳定窗口可能会看到额外的
    // notifyListeners（例如 reaction/extension fetch），而我们不想重新触发 jump，把用户从刚落下的地方拉走。
    final navState = _navigationState;
    switch (navState) {
      case _NavToUnread()
          when _oldestUnreadMessageSeq != null && _oldestUnreadMessageSeq! > 0:
        setState(() {
          _messages = state.messageList.value.reversed.toList();
          isLoading = false;
        });
        _scrollToSeq(_oldestUnreadMessageSeq!);
        return;

      case _NavToAtMention(targetSeq: final targetSeq?):
        debugPrint('messageList, _onMessageListStateChanged [AT_MENTION], '
            'targetSeq: $targetSeq, '
            'messageCount: ${state.messageList.value.length}');
        setState(() {
          _messages = state.messageList.value.reversed.toList();
          isLoading = false;
        });
        _scrollToSeq(targetSeq, alignment: 0);
        final idx = _messages.indexWhere((m) {
          final seq = int.tryParse(m.rawMessage?.seq ?? '') ?? 0;
          return seq == targetSeq;
        });
        if (idx != -1 && _messages[idx].msgID != null) {
          setState(() {
            _highlightedMessageId = _messages[idx].msgID;
          });
        }
        _remainingAtInfoList.removeWhere((info) => info.msgSeq == targetSeq);
        _consumeNewMessagesThrough(targetSeq);
        // Mark this nav "processed" without leaving the 2-frame settle
        // window — a subsequent notifyListeners in this window will fall
        // through this switch to the default branch instead of
        // re-jumping back to the @ message.
        //
        // 在不离开 2 框架结算窗口的情况下，将此导航标记为“已处理”——在此窗口中的后续 notifyListeners 调用将会穿过此 switch 到默认分支，而不会重新跳回 @ 消息。
        _navigationState = const _NavToAtMention(null);
        _activateAtMentionTongueIfNeeded();
        return;

      case _NavToQuotedMessage(
          targetMsgID: final targetMsgID?,
          tongueAfter: final tongueAfter,
          highlightTarget: final highlightTarget,
        ):
        debugPrint('messageList, _onMessageListStateChanged [QUOTE], '
            'targetMsgID: $targetMsgID, '
            'tongueAfter: $tongueAfter, '
            'highlight: $highlightTarget, '
            'messageCount: ${state.messageList.value.length}');
        setState(() {
          _messages = state.messageList.value.reversed.toList();
          isLoading = false;
          if (highlightTarget) {
            _highlightedMessageId = targetMsgID;
          }
          _tongueType = tongueAfter;
          // Same processed-once guard as the at-mention branch.
          //
          // 与 @ 提及分支相同的“已处理一次”保护。
          _navigationState =
              _NavToQuotedMessage(null, tongueAfter, highlightTarget);
        });
        final targetIndex =
            _messages.indexWhere((msg) => msg.msgID == targetMsgID);
        if (targetIndex != -1 && _itemScrollController.isAttached) {
          _itemScrollController.jumpTo(index: targetIndex, alignment: 0.3);
        }
        return;

      case _NavIdle():
      case _NavToUnread():
      case _NavToAtMention():
      case _NavToQuotedMessage():
      case _NavReloadingLatest():
        break;
    }

    final nextMessages = state.messageList.value.reversed.toList();
    final oldLength = _messages.length;
    // Remember the first message's ID to detect head-insertion (new messages)
    // vs tail-append (older history messages).
    //
    // 记住第一条消息的 ID，以便检测是头部插入（新消息）还是尾部追加（历史旧消息）。
    final oldFirstMsgID = _messages.isNotEmpty ? _messages.first.msgID : null;

    setState(() {
      _messages = nextMessages;
    });

    // Only compensate when new messages are inserted at the HEAD of the list
    // (index 0 = newest in reverse list).  Detect this by checking whether
    // the first message's ID has changed — if it changed, newer messages were
    // prepended; if it didn't, older messages were appended at the tail and
    // no compensation is needed (existing item indices are unchanged).
    //
    // 仅当新消息插入在列表的 HEAD 时才进行补偿。
    //
    // 第一条消息的 ID 已更改——如果它更改了，说明有新消息被添加到前面；如果没有更改，说明旧消息被追加到尾部，不需要补偿（现有条目索引保持不变）。
    final insertedCount = _messages.length - oldLength;
    final newFirstMsgID = _messages.isNotEmpty ? _messages.first.msgID : null;
    final isHeadInsertion = insertedCount > 0 &&
        oldFirstMsgID != null &&
        newFirstMsgID != oldFirstMsgID;

    // If the new head message is sent by self, auto-scroll to bottom.
    //
    // Must also skip while _loadNewerMessages is in flight: when a page of
    // newer messages happens to include a self-sent tail (e.g. the user
    // earlier sent a quote message and we now scroll-to-load the page
    // containing it), the new _messages.first will be self-sent — but
    // this was not a fresh "user just hit send" event. _loadNewerMessages
    // is already running its own scroll-preserving jumpTo(insertedCount)
    // after the await, and if we also schedule a postFrame jumpTo(0)
    // here, that postFrame fires last and clobbers the scroll-preserve,
    // visibly snapping the user to the very bottom on every second load.
    //
    // 在 _loadNewerMessages 正在进行时也必须跳过：当一页更新的消息恰好包含自己发送的尾部（例如用户之前发送了一条引用消息，而我们现在滚动加载包含它的页面），新的
    // _messages.first 会是自己发送的消息——但这并不是一个新的“用户刚发送消息”的事件。_loadNewerMessages 已经在 await 之后运行它自己的滚动保持
    // jumpTo(insertedCount)，如果我们在这里还安排 postFrame jumpTo(0)，postFrame 会最后触发，覆盖滚动保持，让用户在每次第二次加载时明显地跳到最底部。
    if (isHeadInsertion &&
        !_isLoadingNewer &&
        _messages.isNotEmpty &&
        _messages.first.isSentBySelf) {
      if (_messageListStore.state.hasNewerMessages.value) {
        // List was loaded around an older position, need to reload latest
        //
        // 列表加载到一个较旧的位置附近，需要重新加载最新内容
        _reloadLatestMessages();
      } else if (_itemScrollController.isAttached) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _itemScrollController.isAttached) {
            _itemScrollController.jumpTo(index: 0);
          }
        });
      }
    }
    // Skip compensation when _loadNewerMessages is in progress — it already
    // does its own jumpTo after the await returns.
    //
    // 当 _loadNewerMessages 进行中时跳过补偿——它自己在 await 返回后已经做了 jumpTo。
    else if (isHeadInsertion &&
        !_isLoadingNewer &&
        !_isUserAtBottom() &&
        _itemScrollController.isAttached) {
      final positions = _itemPositionsListener.itemPositions.value;
      if (positions.isNotEmpty) {
        final anchor = positions.reduce(
          (a, b) => a.itemLeadingEdge < b.itemLeadingEdge ? a : b,
        );
        // Jump immediately (synchronously) — same approach as _loadNewerMessages —
        // to avoid the visible "scroll then snap back" flicker that
        // addPostFrameCallback would cause.
        //
        // 立即跳转（同步）——与_loadNewerMessages的做法相同——以避免addPostFrameCallback导致的“滚动然后回弹”闪烁。
        _itemScrollController.jumpTo(
          index: anchor.index + insertedCount,
          alignment: anchor.itemLeadingEdge,
        );
      }
    }

    if (widget.locateMessage != null && _isInitialLoad) {
      _isInitialLoad = false;
      _scrollToMessageAndHighlight(widget.locateMessage!.msgID!);
      return;
    }
  }

  void _onMessageEvent(MessageEvent event) {
    switch (event) {
      case OnReceiveNewMessage(:final message):
        debugPrint('messageList, onReceiveNewMessage: ${message.msgID}');
        _clearUnreadCount();
        final isAtBottom = _isUserAtBottom();
        if (!isLoading && isAtBottom) {
          _scrollToBottom();
        } else if (!isAtBottom && widget.config.isSupportTongue) {
          final atType = message.conversationType == ConversationType.group &&
                  !message.isSentBySelf
              ? resolveGroupAtType(
                  message.atUserList,
                  LoginStore.shared.loginState.loginUserInfo?.userID,
                )
              : null;
          setState(() {
            final sequence = message.sequence;
            if (atType != null &&
                sequence != null &&
                sequence > 0 &&
                !_remainingAtInfoList.any((info) => info.msgSeq == sequence)) {
              // 实时到达的 @ 消息不会写回初始 groupAtInfoList，
              // 因此在本地补入队列，确保历史位置也能直接跳转。
              _remainingAtInfoList.add(
                GroupAtInfo(msgSeq: sequence, atType: atType),
              );
              _remainingAtInfoList.sort((a, b) => a.msgSeq.compareTo(b.msgSeq));
              final nextAt = _remainingAtInfoList.first;
              _atMessageSeq = nextAt.msgSeq;
              _atMentionText = _getAtMentionTextForType(nextAt.atType);
            }
            if (!_pendingNewMessages
                .any((pending) => pending.msgID == message.msgID)) {
              _pendingNewMessages.add(message);
              _newMessageCount++;
            }
            _tongueType = _computeTongueType();
          });
        }
        // Fetch reactions for new message
        //
        // 获取新消息的反应
        if (widget.config.isSupportReaction) {
          _fetchMessageReactions([message]);
        }
    }
  }

  Future<void> _fetchMessageReactions(List<MessageInfo> messages) async {
    // Reactions are now auto-fetched by MessageListStore's internal listener
    // when new messages are added to the message list.
    //
    // 当新消息添加到消息列表时，MessageListStore的内部监听器现在会自动获取反应。
  }

  bool _isUserAtBottom() {
    if (!_itemScrollController.isAttached) return true;
    final positions = _itemPositionsListener.itemPositions.value;
    return positions.isNotEmpty && positions.any((pos) => pos.index <= 1);
  }

  Future<void> _loadLatestMessages() async {
    final option = MessageLoadOption()
      ..direction = MessageLoadDirection.older
      ..pageCount = 20;

    await _messageListStore.loadMessages(option: option);
    // No local mirroring of has-more flags — Store resets both to false on
    // loadMessages entry and only flips hasOlderMessages back to true if
    // more older pages exist. Read sites check
    // `_messageListStore.state.hasOlderMessages.value` directly.
    //
    // 没有本地的has-more标记镜像——Store在loadMessages入口时将两者重置为false，并且只有在存在更多旧页时才将hasOlderMessages翻回true。阅读网站直接检查`_messageListStore.state.hasOlderMessages.value`。
  }

  Future<void> _loadMessagesAround(MessageInfo message) async {
    debugPrint('messageList, _loadMessagesAround');
    final option = MessageLoadOption()
      ..cursor = message
      ..direction = MessageLoadDirection.both
      ..pageCount = 20;
    await _messageListStore.loadMessages(option: option);
  }

  Future<void> _loadPreviousMessages() async {
    if (isLoading || !_messageListStore.state.hasOlderMessages.value) return;

    debugPrint('messageList, _loadPreviousMessages');

    setState(() {
      isLoading = true;
    });

    await _messageListStore.loadOlderMessages();
    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadNewerMessages() async {
    if (_isLoadingNewer || !_messageListStore.state.hasNewerMessages.value)
      return;

    setState(() {
      _isLoadingNewer = true;
    });

    final oldListLength = _messages.length;
    await _messageListStore.loadNewerMessages();
    final newListLength = _messages.length;
    if (mounted && newListLength > oldListLength) {
      final newIndex = newListLength - oldListLength;
      _itemScrollController.jumpTo(index: newIndex);
    }

    if (mounted) {
      setState(() {
        _isLoadingNewer = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_itemScrollController.isAttached && _messages.isNotEmpty) {
        _itemScrollController.jumpTo(index: 0);
      }
    });
  }

  void _scrollToMessageAndHighlight(String messageID) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_itemScrollController.isAttached) return;

      final targetIndex = _messages.indexWhere((m) => m.msgID == messageID);
      if (targetIndex != -1) {
        debugPrint(
            'messageList, _scrollToMessageAndHighlight, jumpToIndex:$targetIndex');

        _itemScrollController.jumpTo(index: targetIndex);

        setState(() {
          _highlightedMessageId = messageID;
        });
      }
    });
  }

  String _getMessageKey(MessageInfo message) {
    return '${message.msgID}-${message.timestamp}';
  }

  Widget _renderItem(BuildContext context, int index) {
    if (index >= _messages.length) return Container();
    final message = _messages[index];
    final colors = SemanticColorScheme.of(context);

    final timeString = _getMessageTimeString(index);
    final shouldShowTime =
        widget.config.isShowTimeMessage && timeString != null;
    Widget messageWidget = _buildMessageItem(message, colors);

    // Add spacing between messages
    //
    // 在消息之间添加间距
    final spacing = index < _messages.length - 1
        ? SizedBox(height: widget.config.cellSpacing)
        : const SizedBox.shrink();

    // Loading indicator at the newest end (index 0 area in reverse list, visually at bottom)
    //
    // 在最新端显示加载指示器（反向列表的索引0区域，视觉上在底部）
    if (_isLoadingNewer && index == _messages.length - 1) {
      return Column(
        children: [
          if (shouldShowTime) _buildTimeDivider(timeString, colors),
          messageWidget,
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: CupertinoActivityIndicator(),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (shouldShowTime) _buildTimeDivider(timeString, colors),
        messageWidget,
        spacing,
      ],
    );
  }

  Widget _buildMessageItem(MessageInfo message, SemanticColorScheme colors) {
    bool isGroup = widget.conversationID.startsWith(groupConversationIDPrefix);

    final messageWidget = RepaintBoundary(
      child: ListenableBuilder(
        listenable:
            Listenable.merge([_asrDisplayManager, _translationDisplayManager]),
        builder: (context, child) {
          return MessageItem(
            key: ValueKey(_getMessageKey(message)),
            message: message,
            conversationID: widget.conversationID,
            isGroup: isGroup,
            maxWidth: MediaQuery.sizeOf(context).width - 32,
            messageListStore: _messageListStore,
            isHighlighted: _highlightedMessageId == message.msgID,
            onHighlightComplete: () {
              debugPrint(
                  'messageList, onHighlightComplete, msgID: ${message.msgID}, sequence:${message.sequence}');
              if (_highlightedMessageId == message.msgID) {
                _highlightedMessageId = null;
              }
            },
            onUserClick: widget.onUserClick,
            onUserLongPress: isGroup ? widget.onUserLongPress : null,
            onCallMessageClick: widget.onCallMessageClick,
            customActions: widget.customActions,
            config: widget.config,
            isMultiSelectMode: _isMultiSelectMode,
            isSelected: isMessageSelected(message),
            onToggleSelection: () => toggleMessageSelection(message),
            onEnterMultiSelectMode: () =>
                enterMultiSelectMode(initialMessage: message),
            asrDisplayManager: _asrDisplayManager,
            onAsrBubbleLongPress: _showAsrTextMenu,
            translationDisplayManager: _translationDisplayManager,
            onTranslationBubbleLongPress: _showTranslationTextMenu,
            onQuotePreviewTap: _onQuotePreviewTap,
            onQuoteMessage: widget.onQuoteMessage,
          );
        },
      ),
    );

    if (_shouldTrackVisibility(message)) {
      return VisibilityDetector(
        key: Key('visibility_${message.msgID}'),
        onVisibilityChanged: (info) {
          if (info.visibleFraction > 0.5) {
            _handleMessageAppear(message);
          }
        },
        child: messageWidget,
      );
    }

    return messageWidget;
  }

  bool _shouldTrackVisibility(MessageInfo message) {
    // 首屏消息完成提交后再启用已读检测，避免加载期间误报可见状态。
    if (!_isInitialRenderComplete) return false;

    if (message.isSentBySelf) return false;

    if (!message.needReadReceipt) return false;

    if (message.messageType == MessageType.tips) return false;

    if (message.status == MessageStatus.revoked) return false;

    final msgID = message.msgID;
    if (msgID == null) return false;

    if (_sentReceiptMessageIDs.contains(msgID)) return false;

    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Super.build must be called; AutomaticKeepAliveClientMixin is required.
    //
    // 必须调用super.build；需要AutomaticKeepAliveClientMixin。
    super.build(context);
    final colorsTheme = SemanticColorScheme.of(context);

    return Expanded(
      child: Container(
        color: colorsTheme.bgColorDefault,
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: _callStatusWidget != null ? 70 : 8,
                    bottom: 8,
                  ),
                  // 缓存会话会在 initState 直接就绪；无缓存时等待首批消息和目标索引同时准备完成。
                  child: !_isInitialViewportReady
                      ? const SizedBox.shrink()
                      : ScrollablePositionedList.builder(
                          reverse: true,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemScrollController: _itemScrollController,
                          itemPositionsListener: _itemPositionsListener,
                          initialScrollIndex: _initialScrollIndex,
                          initialAlignment: _initialScrollAlignment,
                          itemCount: _messages.length,
                          itemBuilder: _renderItem,
                          addRepaintBoundaries: true,
                          addAutomaticKeepAlives: true,
                          addSemanticIndexes: false,
                        ),
                ),
              ),
            ),
            if (_callStatusWidget != null)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: _callStatusWidget!,
              ),
            // Top-right unread messages tongue
            //
            // 右上角未读消息标签
            if (widget.config.isSupportTongue &&
                _unreadTongueType == TongueType.unreadMessages)
              Positioned(
                top: _callStatusWidget != null ? 78 : 16,
                right: 16,
                child: MessageTongueWidget(
                  tongueState: TongueState(
                    type: TongueType.unreadMessages,
                    unreadCount: _unreadTongueCount,
                    isLoading: _navigationState is _NavToUnread,
                  ),
                  onTap: _onUnreadTongueTap,
                  backToLatestText: _atomicLocale.backToLatest,
                  newMessageCountText: (count) =>
                      _atomicLocale.newMessageCount(count),
                ),
              ),
            // Bottom-right tongue (back to latest / new messages / @mention)
            //
            // 右下角气泡（返回到最新/新的消息/@提及）
            if (widget.config.isSupportTongue && _tongueType != TongueType.none)
              Positioned(
                bottom: 16,
                right: 16,
                child: MessageTongueWidget(
                  tongueState: TongueState(
                    type: _tongueType,
                    newMessageCount: _newMessageCount,
                    atMentionText: _atMentionText,
                    atMessageSeq: _atMessageSeq,
                    isLoading: _navigationState is _NavToAtMention ||
                        _navigationState is _NavReloadingLatest,
                  ),
                  onTap: _onTongueTap,
                  backToLatestText: _atomicLocale.backToLatest,
                  newMessageCountText: (count) =>
                      _atomicLocale.newMessageCount(count),
                  backToQuoteText: _atomicLocale.backToQuotePosition,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _clearUnreadCount() {
    ConversationListStore conversationListStore =
        ConversationListStore.create();
    conversationListStore.clearConversationUnreadCount(
        conversationID: widget.conversationID);
  }

  // ==================== Tongue (小舌头) ====================

  void _initAtMentionTongue() {
    final atInfoList = widget.groupAtInfoList;
    if (atInfoList == null || atInfoList.isEmpty) return;

    // Sort by msgSeq ascending (oldest first) for sequential navigation
    //
    // 按 msgSeq 升序排序（最旧的在前）以便顺序浏览
    _remainingAtInfoList = List.from(atInfoList)
      ..sort((a, b) => a.msgSeq.compareTo(b.msgSeq));

    // Don't show @mention tongue immediately; it will be shown
    // after the unread tongue is consumed or if there's no unread tongue
    // and the @messages are not visible on screen
    //
    // 不要立即显示 @提及气泡；只有在未读气泡被处理后，或者如果没有未读气泡且屏幕上看不到 @消息时，它才会显示
    final oldest = _remainingAtInfoList.first;
    _atMessageSeq = oldest.msgSeq;

    // Store atType for later text resolution
    //
    // 存储 atType 以备后续文本解析
    _pendingAtType = oldest.atType;
  }

  /// Initialize unread messages tongue (右上角)
  /// Only for group conversations — C2C message seq is not sequential,
  /// so seq-based positioning is not possible.
  ///
  /// 仅限群聊 — C2C 消息 seq 不是连续的，所以无法基于 seq 定位
  void _initUnreadTongue() {
    if (!widget.config.isSupportTongue) return;
    if (widget.locateMessage != null) return;

    final snapshot = _restoreViewportSnapshot;
    if (snapshot != null) {
      // 恢复位置时保留两侧尚未浏览的消息；离开后新增的未读只会出现在当前锚点下方。
      _unreadTongueCount = snapshot.unreadAboveCount;
      _newMessageCount = snapshot.unreadBelowCount + widget.initialUnreadCount;
      _oldestUnreadMessageSeq = snapshot.oldestUnreadSequence;
      _viewedUnreadMinSequence = snapshot.viewedUnreadMinSequence;
      _viewedUnreadMaxSequence = snapshot.viewedUnreadMaxSequence;
      _unreadTongueType =
          _unreadTongueCount > 0 ? TongueType.unreadMessages : TongueType.none;
      _tongueType =
          _newMessageCount > 0 ? TongueType.newMessages : TongueType.none;
      return;
    }

    if (widget.initialUnreadCount <= 0) return;
    if (!widget.conversationID.startsWith(groupConversationIDPrefix)) return;

    _initialUnreadCount = widget.initialUnreadCount;
    _pendingUnreadCheck = true;
  }

  /// Check if unread messages exceed visible count; if so, show unread tongue.
  /// Called after messages are loaded and layout is settled.
  /// Tongue is NOT shown until this check confirms it's needed (avoids flash).
  ///
  /// 检查未读消息是否超过可见数量；如果是，则显示未读气泡。在消息加载完成并布局稳定后调用。气泡不会显示，直到此检查确认需要（避免闪烁）
  void _scheduleUnreadTongueVisibilityCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkUnreadTongueVisibility();
      });
    });
  }

  void _checkUnreadTongueVisibility() {
    if (!_pendingUnreadCheck) return;
    _pendingUnreadCheck = false;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) {
      // Layout not ready yet — show tongue as fallback (unread count > 0)
      //
      // 布局尚未准备好 — 作为回退显示气泡（未读数 > 0）
      setState(() {
        _unreadTongueCount = _initialUnreadCount;
        _unreadTongueType = TongueType.unreadMessages;
      });
      return;
    }

    // 只扣除未读区间内实际进入屏幕的消息，避免把可见的历史已读消息也算进去。
    int visibleUnreadCount = 0;
    final visibleUnreadSequences = <int>[];
    for (final pos in positions) {
      if (pos.index < _initialUnreadCount &&
          pos.itemLeadingEdge < 1.0 &&
          pos.itemTrailingEdge > 0.0) {
        visibleUnreadCount++;
        final sequence = _messages[pos.index].sequence;
        if (sequence != null) visibleUnreadSequences.add(sequence);
      }
    }
    final remainingUnreadCount = _initialUnreadCount - visibleUnreadCount;

    if (remainingUnreadCount <= 0) {
      // All unread messages are visible, no need for the tongue
      // _unreadTongueType remains TongueType.none — tongue was never shown
      //
      // 所有未读消息都可见，不需要显示提示 _unreadTongueType 仍然是 TongueType.none — 提示从未显示过
      _activateAtMentionTongueIfNeeded();
    } else {
      // Unread messages exceed visible area, NOW show the tongue
      //
      // 未读消息超过可见区域，现在显示提示
      setState(() {
        _unreadTongueCount = remainingUnreadCount;
        _unreadTongueType = TongueType.unreadMessages;
        if (visibleUnreadSequences.isNotEmpty) {
          visibleUnreadSequences.sort();
          _viewedUnreadMinSequence = visibleUnreadSequences.first;
          _viewedUnreadMaxSequence = visibleUnreadSequences.last;
        }
      });
      _computeOldestUnreadSeq();
    }
  }

  /// Compute the seq of the oldest unread message based on the latest message seq and unread count
  ///
  /// 根据最新消息的序列号和未读数量计算最旧未读消息的序列号
  void _computeOldestUnreadSeq() {
    if (_messages.isEmpty) return;

    // Messages are in reverse order (newest first), so first message is newest
    //
    // 消息是倒序的（最新在前），所以第一条消息是最新的
    final newestMessage = _messages.first;
    final newestSeq = int.tryParse(newestMessage.rawMessage?.seq ?? '') ?? 0;
    if (newestSeq > 0) {
      _oldestUnreadMessageSeq = newestSeq - _initialUnreadCount + 1;
    }
  }

  /// 消耗刚进入视口的未读消息，确保提示数字与实际可见范围同步。
  void _consumeVisibleUnread(Iterable<ItemPosition> positions) {
    int? visibleMinSequence;
    int? visibleMaxSequence;
    for (final position in positions) {
      if (position.index < 0 || position.index >= _messages.length) continue;
      final sequence = _messages[position.index].sequence;
      if (sequence == null) continue;
      if (visibleMinSequence == null || sequence < visibleMinSequence) {
        visibleMinSequence = sequence;
      }
      if (visibleMaxSequence == null || sequence > visibleMaxSequence) {
        visibleMaxSequence = sequence;
      }
    }

    final counts = consumeUnreadInVisibleRange(
      above: _unreadTongueCount,
      below: _newMessageCount,
      viewedMinSequence: _viewedUnreadMinSequence,
      viewedMaxSequence: _viewedUnreadMaxSequence,
      visibleMinSequence: visibleMinSequence,
      visibleMaxSequence: visibleMaxSequence,
    );
    if (counts.above == _unreadTongueCount &&
        counts.below == _newMessageCount &&
        counts.viewedMinSequence == _viewedUnreadMinSequence &&
        counts.viewedMaxSequence == _viewedUnreadMaxSequence) {
      return;
    }

    setState(() {
      _unreadTongueCount = counts.above;
      _newMessageCount = counts.below;
      _viewedUnreadMinSequence = counts.viewedMinSequence;
      _viewedUnreadMaxSequence = counts.viewedMaxSequence;
      _unreadTongueType =
          counts.above > 0 ? TongueType.unreadMessages : TongueType.none;
      if (counts.below > 0 &&
          _tongueType != TongueType.atMention &&
          _tongueType != TongueType.backToQuote) {
        _tongueType = TongueType.newMessages;
      } else if (counts.below == 0 && _tongueType == TongueType.newMessages) {
        _tongueType = TongueType.none;
      }
    });
  }

  GroupAtType? _pendingAtType;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _atomicLocale = AppLocalization.of(context);

    // Resolve @mention text after locale is available
    //
    // 在本地化信息可用后解析 @提及 文本
    if (_pendingAtType != null) {
      _atMentionText = _getAtMentionTextForType(_pendingAtType!);
      _pendingAtType = null;
    }

    // 不再等待路由动画结束，让 SDK 本地查询与页面转场并行进行。
    _startInitialLoad();
  }

  /// 保证依赖变化或重复构建期间只触发一次首屏加载。
  void _startInitialLoad() {
    if (_initialLoadStarted) return;
    _initialLoadStarted = true;
    _loadInitialMessages();
  }

  String _getAtMentionTextForType(GroupAtType atType) {
    switch (atType) {
      case GroupAtType.atMe:
      case GroupAtType.atAllAtMe:
        return _atomicLocale.conversationListAtMe;
      case GroupAtType.atAll:
        return _atomicLocale.conversationListAtAll;
    }
  }

  void _onTongueTap() {
    switch (_tongueType) {
      case TongueType.atMention:
        _onAtMentionTongueTap();
        break;
      case TongueType.newMessages:
      case TongueType.backToLatest:
        _onBackToLatestTongueTap();
        break;
      case TongueType.backToQuote:
        _onBackToQuoteTongueTap();
        break;
      case TongueType.none:
      case TongueType.unreadMessages:
        break;
    }
  }

  /// Handle tap on the top-right unread messages tongue
  ///
  /// 处理点击右上角未读消息提示的操作
  Future<void> _onUnreadTongueTap() async {
    if (_unreadTongueCount <= 0) return;

    if (_oldestUnreadMessageSeq == null || _oldestUnreadMessageSeq! <= 0) {
      _computeOldestUnreadSeq();
    }

    final targetSeq = _oldestUnreadMessageSeq;
    if (targetSeq == null || targetSeq <= 0) return;
    final targetIndex = _messages.indexWhere(
      (message) => message.sequence == targetSeq,
    );
    final unreadMovedBelow =
        _unreadTongueCount > 1 ? _unreadTongueCount - 1 : 0;

    setState(() {
      _navigationState = const _NavToUnread();
      _unreadTongueCount = 0;
      _unreadTongueType = TongueType.none;
      _newMessageCount += unreadMovedBelow;
      _viewedUnreadMinSequence = targetSeq;
      _viewedUnreadMaxSequence = targetSeq;
      if (_newMessageCount > 0) _tongueType = TongueType.newMessages;
    });

    if (targetIndex != -1) {
      _itemScrollController.jumpTo(index: targetIndex, alignment: 0.9);
    } else {
      setState(() {
        isLoading = true;
      });

      // Use both direction to load messages around the oldest unread message.
      // This gives us some older (read) messages above and newer (unread) messages below,
      // matching WeChat's experience of showing context above the first unread message.
      //
      // 同时使用两个方向加载最早未读消息附近的消息。这样我们可以在其上方显示一些较早的（已读）消息，下方显示较新的（未读）消息，和微信展示首条未读消息上下文的体验一致。
      final cursorMsg = MessageInfo(sequence: targetSeq);
      final option = MessageLoadOption()
        ..cursor = cursorMsg
        ..direction = MessageLoadDirection.both
        ..pageCount = 20;

      final result = await _messageListStore.loadMessages(option: option);

      if (mounted) {
        // All state (messages, isLoading, hasMore*) and the jumpTo have
        // already been applied inside _onMessageListStateChanged (which
        // fires synchronously via notifyListeners during fetchMessageList).
        // No additional setState is needed here — doing one would cause a
        // second build frame (visible as a "list flicker").
        //
        // 所有状态（消息、isLoading、hasMore*）和 jumpTo 已经在 _onMessageListStateChanged 内部应用（在 fetchMessageList 中通过
        // notifyListeners 同步触发）。这里不需要额外的 setState —— 如果再做一次会导致第二次构建帧（在列表上会看到“闪烁”）。

        debugPrint('messageList, _onUnreadTongueTap, fetchComplete, '
            'result.isSuccess: ${result.isSuccess}, messageCount: ${_messages.length}, '
            'oldestUnreadSeq: $_oldestUnreadMessageSeq');
      }
    }

    // Delay clearing _NavToUnread by TWO frames.
    // After _scrollToSeq's jumpTo executes, _itemPositionsListener only
    // fires after layout completes (next frame).  _scrollListener then
    // re-checks `_navigationState is _NavIdle` — if we cleared it
    // immediately and hasNewerMessages is true with index 0 visible
    // (few messages), _loadNewerMessages would be triggered, pulling
    // in the latest messages and causing a second visual change.
    // Frame 1: jumpTo → build + layout, positions update
    // Frame 2: scroll listener has fired; safe to exit nav state.
    //
    // 延迟清除 _NavToUnread 两帧。在 _scrollToSeq 的 jumpTo 执行后，_itemPositionsListener 只有在布局完成（下一帧）后才会触发。然后
    // _scrollListener 再次检查 `_navigationState 是否为 _NavIdle` — 如果我们立即清除它，并且 hasNewerMessages 为 true 且索引 0
    // 可见（几条消息），_loadNewerMessages 就会被触发，拉取最新消息并导致第二次视觉变化。帧 1：jumpTo → 构建 + 布局，位置更新 帧
    // 2：滚动监听器已触发；可以安全退出导航状态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _navigationState is _NavToUnread) {
          setState(() {
            _navigationState = const _NavIdle();
            _unreadTongueType = TongueType.none;
          });
          _activateAtMentionTongueIfNeeded();
        }
      });
    });
  }

  /// Scroll to a message by its seq number.
  /// In a reversed list (reverse: true), the alignment is used as CustomScrollView's anchor.
  /// anchor: 0.0 places the center item at the top of the viewport.
  ///
  /// 通过消息的序列号滚动到该消息。在反向列表（reverse: true）中，对齐方式用作 CustomScrollView 的锚点。anchor: 0.0 会把中心消息放在视口顶部。
  void _scrollToSeq(int targetSeq, {double alignment = 0.9}) {
    // Try exact match first
    //
    // 先尝试完全匹配
    int targetIndex = _messages.indexWhere((m) {
      final seq = int.tryParse(m.rawMessage?.seq ?? '') ?? 0;
      return seq == targetSeq;
    });

    // Fallback: find the message with the closest seq
    //
    // 备用：找到 seq 最接近的消息
    if (targetIndex == -1 && _messages.isNotEmpty) {
      int bestIndex = -1;
      int bestDiff = 999999999;
      for (int i = 0; i < _messages.length; i++) {
        final seq = int.tryParse(_messages[i].rawMessage?.seq ?? '') ?? 0;
        if (seq <= 0) continue;
        final diff = (seq - targetSeq).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          bestIndex = i;
        }
      }
      targetIndex = bestIndex;
    }

    if (targetIndex != -1) {
      _itemScrollController.jumpTo(index: targetIndex, alignment: alignment);
    }
  }

  /// Activate @mention tongue if there are remaining @messages
  ///
  /// 如果还有 @消息，就激活 @mention 小舌头
  void _activateAtMentionTongueIfNeeded() {
    if (_remainingAtInfoList.isEmpty) {
      setState(() {
        _tongueType = _computeTongueType();
      });
      return;
    }

    // Show tongue for the oldest remaining @message
    //
    // 对最早的剩余@消息显示小舌头
    final nextAt = _remainingAtInfoList.first;
    setState(() {
      _atMessageSeq = nextAt.msgSeq;
      _atMentionText = _getAtMentionTextForType(nextAt.atType);
      // Only show @mention tongue when unread tongue is not displayed
      //
      // 仅当未读小舌头未显示时显示@提及小舌头
      if (_unreadTongueType == TongueType.none) {
        _tongueType = TongueType.atMention;
      }
    });
  }

  void _onBackToLatestTongueTap() {
    if (_messageListStore.state.hasNewerMessages.value) {
      // Keep the tongue visible with a loading spinner while reloading.
      // The _NavReloadingLatest state is cleared inside
      // _reloadLatestMessages AFTER scrollToBottom + layout settle.
      //
      // 重新加载时保持小舌头可见并显示加载动画。_NavReloadingLatest状态在_scrollToBottom+布局稳定后在_reloadLatestMessages中清除。
      setState(() {
        _newMessageCount = 0;
        _pendingNewMessages.clear();
        _navigationState = const _NavReloadingLatest();
      });

      _reloadLatestMessages();
    } else {
      setState(() {
        _tongueType = TongueType.none;
        _newMessageCount = 0;
        _pendingNewMessages.clear();
      });
      if (_itemScrollController.isAttached && _messages.isNotEmpty) {
        _itemScrollController.jumpTo(index: 0);
      }
    }
  }

  /// Handle tap on quote preview inside a message bubble — navigate to quoted message
  ///
  /// 处理消息气泡内引用预览的点击 — 导航到被引用的消息
  void _onQuotePreviewTap(MessageInfo message) {
    final quoteInfo = message.quoteInfo;
    if (quoteInfo == null || quoteInfo.msgID.isEmpty) return;

    // Capture the full source MessageInfo (not just msgID) — the reverse
    // leg in `_onBackToQuoteTongueTap` needs seq/timestamp to reload
    // around the source when the forward leg wholesale-replaced the
    // list and the source is no longer in it.
    //
    // 捕获完整的源MessageInfo（不仅仅是msgID） —
    // 在`_onBackToQuoteTongueTap`中的反向操作需要序列号/时间戳，以便在前向操作整体替换列表后重新加载源消息周围内容，而源消息可能已经不在列表中。
    _quoteReturnSource = message;

    // Search for the quoted message in current loaded list
    //
    // 在当前加载列表中搜索引用的消息
    final targetMsgID = quoteInfo.msgID;
    final targetIndex = _messages.indexWhere((msg) => msg.msgID == targetMsgID);

    debugPrint(
        'messageList, _onQuotePreviewTap, sourceMsgID: ${message.msgID}, '
        'sourceSequence: ${message.sequence}, targetMsgID: $targetMsgID, '
        'targetMsgSequence: ${quoteInfo.sequence}, '
        'targetIndex: $targetIndex, listSize: ${_messages.length}');

    if (targetIndex != -1) {
      // Found in current list - scroll to it and highlight
      //
      // 在当前列表中找到 - 滚动到它并高亮显示
      _scrollToIndexAndHighlight(targetIndex, targetMsgID);
    } else {
      // Not in current list - need to reload around the quoted message
      //
      // 当前列表中未找到 - 需要围绕引用消息重新加载
      _loadAndNavigateToQuotedMessage(quoteInfo);
    }
  }

  void _scrollToIndexAndHighlight(int index, String msgID) {
    // Check if target is already visible on screen
    //
    // 检查目标是否已在屏幕上可见
    bool isVisible = false;
    if (_itemScrollController.isAttached) {
      final positions = _itemPositionsListener.itemPositions.value;
      isVisible = positions.any((pos) => pos.index == index);
    }

    if (!isVisible && _itemScrollController.isAttached) {
      // Target not visible - scroll to it and show "back to quote" tongue
      //
      // 目标不可见 - 滚动到它并显示“返回引用”提示
      _itemScrollController.jumpTo(index: index, alignment: 0.3);
      setState(() {
        _highlightedMessageId = msgID;
        _tongueType = TongueType.backToQuote;
      });
    } else {
      // Target already visible - just highlight, no scroll, no tongue
      //
      // 目标已可见 - 只需高亮，无需滚动，无需提示
      setState(() {
        _highlightedMessageId = msgID;
      });
    }
  }

  /// Forward leg of the quote round-trip: tap on a quote preview when the
  /// quoted target isn't in the currently-loaded list. Loads around the
  /// target (Store's `_fetchTwoSideMessageList`), jumps to it, highlights
  /// it, and commits a `backToQuote` tongue so the user can round-trip
  /// back to the source.
  ///
  /// The cursor is constructed from `quoteInfo`'s msgID/seq/timestamp
  /// (without a rawMessage) — Store falls back to `lastMsgSeq`-based
  /// positioning in that case.
  ///
  /// 引用往返的前向环节：当引用目标不在当前加载的列表中时，点击引用预览。会加载目标附近的数据（Store 的 `_fetchTwoSideMessageList`），跳转到目标，高亮它，并触发一个
  /// `backToQuote` 提示，让用户可以回到源消息。
  ///
  /// 光标是根据 `quoteInfo` 的 msgID/seq/timestamp 构建的（没有 rawMessage）——在这种情况下，Store 会退回到基于 `lastMsgSeq` 的定位。
  Future<void> _loadAndNavigateToQuotedMessage(MessageQuoteInfo quoteInfo) {
    final cursorMessage = MessageInfo(
      msgID: quoteInfo.msgID,
      timestamp: quoteInfo.timestamp,
      sequence: quoteInfo.sequence,
    );
    return _loadAndNavigateToMessage(
      cursorMessage: cursorMessage,
      targetMsgID: quoteInfo.msgID,
      tongueAfter: TongueType.backToQuote,
      highlightTarget: true,
      debugLabel: 'quote-forward',
    );
  }

  /// Generic "load around a message and jump to it" routine.
  ///
  /// Both forward navigation (tap on quote preview) and reverse
  /// navigation (tap on backToQuote tongue when the source got
  /// wholesale-replaced out of the list) feed through here. The two
  /// callers differ only in:
  ///   - which message is the navigation target (quoted target vs. the
  ///     source message of the quote round-trip), and
  ///   - what tongue to commit when the landing branch runs in
  ///     `_onMessageListStateChanged`.
  ///
  /// 通用的“加载某条消息附近的数据并跳转到它”的流程。
  ///
  /// 前向导航（点击引用预览）和反向导航（当来源消息在列表中被批量替换时点击 backToQuote 按钮）都会通过这里。两个调用者的不同之处仅在于：- 导航目标消息是哪条（引用的目标消息 vs.
  /// 引用往返的来源消息），以及 - 当落地分支在 `_onMessageListStateChanged` 里运行时要提交哪个按钮。
  Future<void> _loadAndNavigateToMessage({
    required MessageInfo cursorMessage,
    required String targetMsgID,
    required TongueType tongueAfter,
    required bool highlightTarget,
    String debugLabel = 'message',
  }) async {
    debugPrint('messageList, _loadAndNavigateToMessage [$debugLabel], '
        'targetMsgID: $targetMsgID, '
        'seq: ${cursorMessage.sequence}, '
        'ts: ${cursorMessage.timestamp}, '
        'tongueAfter: $tongueAfter, '
        'highlight: $highlightTarget');

    // Enter "quote navigation in progress" state. The actual
    // setState/jumpTo/tongue work happens inside `_onMessageListStateChanged`
    // (the `_NavToQuotedMessage` case) when the Store fires
    // notifyListeners — same atomic-frame pattern as _NavToAtMention /
    // _NavToUnread.
    //
    // 进入“引用导航进行中”状态。实际的 setState/jumpTo/按钮操作是在 `_onMessageListStateChanged` 里面发生的（`_NavToQuotedMessage`
    // 情况），当 Store 触发 notifyListeners 时 —— 跟 _NavToAtMention 的原子帧模式一样。
    setState(() {
      _navigationState =
          _NavToQuotedMessage(targetMsgID, tongueAfter, highlightTarget);
      isLoading = true;
    });

    final option = MessageLoadOption(
      messageListType: MessageListType.history,
      cursor: cursorMessage,
      direction: MessageLoadDirection.both,
    );

    await _messageListStore.loadMessages(option: option);

    // Defer exiting the nav state by two frames so the scroll listener
    // that fires off the back of our synchronous jumpTo has settled
    // before _scrollListener / _updateTongueState are allowed to react
    // again. Mirrors the _NavToAtMention / _NavToUnread tail.
    //
    // 将退出导航状态的操作延迟两帧，以便在 _scrollListener / _updateTongueState 可以再次响应之前，触发我们同步 jumpTo 后的滚动监听器有时间稳定下来。对应
    // _NavToAtMention / _NavToUnread 的尾部操作。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _navigationState is _NavToQuotedMessage) {
          setState(() {
            _navigationState = const _NavIdle();
          });
        }
      });
    });
  }

  /// Handle tap on "back to quote position" tongue.
  ///
  /// Reverse leg of the quote round-trip: jump back to the source
  /// message whose quote preview the user tapped earlier.
  ///
  /// If the forward leg had to wholesale-reload the list around the
  /// quoted target (because the target wasn't in the loaded page),
  /// the source itself has been evicted — the previous implementation
  /// fell through to `_reloadLatestMessages()` here, which is the
  /// reported bug: tapping "back to quote" was silently jumping the
  /// user to the latest page instead of returning them to where they
  /// had tapped. Fix: when the source isn't in the current list,
  /// load around it the same way the forward leg loads around the
  /// quoted target, but pass `tongueAfter: TongueType.none` so we
  /// don't chain a second backToQuote tongue off the back-navigation.
  ///
  /// 处理点击“返回引用位置”提示的操作。
  ///
  /// 引用往返的逆向操作：跳回用户之前点击引用预览的源消息。
  ///
  /// 引用的目标（因为目标不在已加载的页面中），源本身已被驱逐——之前的实现会回退到这里的 `_reloadLatestMessages()`，这就是报告的
  /// bug：点击“返回引用”会悄悄地将用户跳到最新页面，而不是返回到他们点击的位置。修复方法：当源不在当前列表中时，像前向加载引用目标那样加载它周围的内容，但传入 `tongueAfter:
  /// TongueType.none`，这样我们就不会在后退导航上 chaining 第二个 backToQuote tongue。
  void _onBackToQuoteTongueTap() {
    final returnSource = _quoteReturnSource;
    _quoteReturnSource = null;
    if (returnSource == null) return;

    final returnMsgID = returnSource.msgID;
    if (returnMsgID == null || returnMsgID.isEmpty) {
      setState(() {
        _tongueType = _computeTongueType();
      });
      return;
    }

    final returnIndex = _messages.indexWhere((msg) => msg.msgID == returnMsgID);
    if (returnIndex != -1 && _itemScrollController.isAttached) {
      _itemScrollController.jumpTo(index: returnIndex, alignment: 0.3);
      // No highlight on the reverse leg — the user just left this exact
      // message a moment ago and re-flashing it is visual noise.
      //
      // Tongue decision is split into "position-agnostic" and
      // "position-sensitive":
      //   - atMention / newMessages depend only on app state, so commit
      //     them here.
      //   - backToLatest depends on whether the post-jumpTo position
      //     is at the bottom — info we don't have until the next
      //     layout. Committing backToLatest here when the source
      //     happens to be the latest message would produce a visible
      //     1-frame "回到最新位置" flash before _updateTongueState
      //     (isAtBottom branch) wipes it. So coerce backToLatest → none
      //     and let the listener materialise it next frame if needed.
      //
      // 反向路径没有高亮——用户刚刚离开了这条消息，重新闪烁反而是视觉噪音。
      //
      // 小舌头决策拆分为“与位置无关”和
      //
      // - atMention / newMessages 只依赖于应用状态，所以在这里提交它们。- backToLatest
      // 依赖于跳到某个位置后是否在底部——这个信息要到下一个布局才知道。如果在源消息恰好是最新消息时在这里提交 backToLatest，会产生可见的
      //
      // （isAtBottom 分支）会覆盖它。所以强制 backToLatest → none，让监听器在下一个帧里根据需要再实现它。
      setState(() {
        final derived = _computeTongueType();
        _tongueType =
            derived == TongueType.backToLatest ? TongueType.none : derived;
      });
      return;
    }

    // Source not in the current loaded list — reload around it. Reuses
    // the forward-leg's load + atomic jump + tongue machinery via
    // `_loadAndNavigateToMessage`; the reverse leg differs in
    // `tongueAfter: none` (round-trip complete) and
    // `highlightTarget: false` (no need to flash the source).
    //
    // 源不在当前加载的列表里——围绕它重新加载。复用了 forward-leg 的加载 + 原子跳转 + 小舌头机制，通过 `_loadAndNavigateToMessage`；反向流程在
    // `tongueAfter: none`（往返完成）和 `highlightTarget: false`（不用闪烁源）方面有所不同。
    _loadAndNavigateToMessage(
      cursorMessage: returnSource,
      targetMsgID: returnMsgID,
      tongueAfter: TongueType.none,
      highlightTarget: false,
      debugLabel: 'quote-back',
    );
  }

  Future<void> _reloadLatestMessages() async {
    setState(() {
      isLoading = true;
    });

    await _loadLatestMessages();

    if (mounted) {
      setState(() {
        isLoading = false;
      });
      // Use a Completer so we can await the scroll + layout settling.
      // Frame 1: jumpTo executes the scroll.
      // Frame 2: layout completes, itemPositions are updated.
      // Only then is it safe to exit _NavReloadingLatest and hide the tongue.
      //
      // 使用 Completer，这样我们就可以等待滚动和布局稳定。第1帧：jumpTo 执行滚动。第2帧：布局完成，itemPositions 更新。只有这样才能安全退出
      // _NavReloadingLatest 并隐藏提示。
      final completer = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_itemScrollController.isAttached && _messages.isNotEmpty) {
          _itemScrollController.jumpTo(index: 0);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _navigationState is _NavReloadingLatest) {
            setState(() {
              _navigationState = const _NavIdle();
              _tongueType = TongueType.none;
            });
          }
          completer.complete();
        });
      });
      await completer.future;
    }
  }

  Future<void> _onAtMentionTongueTap() async {
    if (_atMessageSeq == null) return;

    final targetSeq = _atMessageSeq!;
    debugPrint(
        'messageList, _onAtMentionTongueTap, targetSeq: $targetSeq, messagesCount: ${_messages.length}');

    // Try to find the @message in the current list
    //
    // 尝试在当前列表中找到 @message
    final targetIndex = _messages.indexWhere((m) {
      final seq = int.tryParse(m.rawMessage?.seq ?? '') ?? 0;
      return seq == targetSeq;
    });

    if (targetIndex != -1) {
      // Message found in current list
      //
      // 在当前列表中找到消息
      final targetMessage = _messages[targetIndex];
      if (targetMessage.msgID != null) {
        // Only scroll if target is not already visible on screen
        //
        // 只有当目标在屏幕上不可见时才滚动
        final positions = _itemPositionsListener.itemPositions.value;
        final isVisible = positions.any((pos) => pos.index == targetIndex);
        if (!isVisible) {
          _itemScrollController.jumpTo(index: targetIndex, alignment: 0);
        }
        setState(() {
          _highlightedMessageId = targetMessage.msgID;
        });
      }
      // Mark this @message as consumed, activate next
      //
      // 将此 @message 标记为已使用，并激活下一个
      _remainingAtInfoList.removeWhere((info) => info.msgSeq == targetSeq);
      _consumeNewMessagesThrough(targetSeq);
      _activateAtMentionTongueIfNeeded();
    } else {
      // Message not in current list, reload around the target seq.
      // Enter _NavToAtMention(targetSeq) so the _onMessageListStateChanged
      // switch handles messages / scroll / highlight atomically.
      //
      // 消息不在当前列表中，重新加载目标 seq 附近的内容。进入 _NavToAtMention(targetSeq) ，从而触发 _onMessageListStateChanged
      debugPrint(
          'messageList, _onAtMentionTongueTap, message NOT in list, will fetchMessageList for seq: $targetSeq');
      setState(() {
        _navigationState = _NavToAtMention(targetSeq);
        isLoading = true;
      });

      final atCursorMsg = MessageInfo(sequence: targetSeq);
      final option = MessageLoadOption()
        ..cursor = atCursorMsg
        ..direction = MessageLoadDirection.both
        ..pageCount = 20;

      await _messageListStore.loadMessages(option: option);
    }

    // Delay exiting the nav state by TWO frames (same pattern as
    // _NavToUnread in _onUnreadTongueTap). After _scrollToSeq's jumpTo
    // executes, _itemPositionsListener only fires after layout completes
    // (next frame). _scrollListener then re-checks `is _NavIdle` — if
    // we exited immediately, it could fire off an unwanted load.
    // Frame 1: jumpTo → build + layout, positions update
    // Frame 2: scroll listener has fired; safe to exit nav state.
    //
    // 将退出导航状态的延迟设置为两帧（与 _onUnreadTongueTap 中的 _NavToUnread 模式相同）。在 _scrollToSeq 的 jumpTo
    // 执行后，_itemPositionsListener 只有在布局完成后（下一帧）才会触发。然后 _scrollListener 再次检查 `is _NavIdle`
    // ——如果立即退出，可能会触发不想要的加载。第 1 帧：jumpTo → 构建 + 布局，位置更新 第 2 帧：滚动监听器触发；此时退出导航状态是安全的。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _navigationState is _NavToAtMention) {
          setState(() {
            _navigationState = const _NavIdle();
          });
        }
      });
    });
  }

  /// 跳转后移除目标及其之前的新消息，保留下方尚未查看的数量。
  void _consumeNewMessagesThrough(int targetSeq) {
    final previousCount = _pendingNewMessages.length;
    _pendingNewMessages
        .removeWhere((message) => !isMessageAfterSequence(message, targetSeq));
    final consumedCount = previousCount - _pendingNewMessages.length;
    _newMessageCount =
        _newMessageCount > consumedCount ? _newMessageCount - consumedCount : 0;
  }

  // ==================== Multi-select mode ====================
  //
  // ==================== 多选模式 ====================

  /// Enter multi-select mode
  ///
  /// 进入多选模式
  void enterMultiSelectMode({MessageInfo? initialMessage}) {
    setState(() {
      _isMultiSelectMode = true;
      _selectedMessageIDs.clear();
      if (initialMessage != null && initialMessage.msgID != null) {
        _selectedMessageIDs.add(initialMessage.msgID!);
      }
    });
    _notifyMultiSelectModeChanged();
  }

  /// Exit multi-select mode
  ///
  /// 退出多选模式
  void exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedMessageIDs.clear();
    });
    _notifyMultiSelectModeChanged();
  }

  /// Toggle message selection state
  ///
  /// 切换消息选择状态
  void toggleMessageSelection(MessageInfo message) {
    final msgID = message.msgID;
    if (msgID == null) return;

    setState(() {
      if (_selectedMessageIDs.contains(msgID)) {
        _selectedMessageIDs.remove(msgID);
      } else {
        _selectedMessageIDs.add(msgID);
      }
    });
    _notifyMultiSelectModeChanged();
  }

  /// Check if message is selected
  ///
  /// 检查消息是否被选中
  bool isMessageSelected(MessageInfo message) {
    return message.msgID != null && _selectedMessageIDs.contains(message.msgID);
  }

  /// Notify multi-select mode change
  ///
  /// 通知多选模式变化
  void _notifyMultiSelectModeChanged() {
    widget.onMultiSelectModeChanged
        ?.call(_isMultiSelectMode, _selectedMessageIDs.length);

    // Notify full state
    //
    // 通知完整状态
    if (_isMultiSelectMode) {
      widget.onMultiSelectStateChanged?.call(MultiSelectState(
        isActive: true,
        selectedCount: _selectedMessageIDs.length,
        onCancel: exitMultiSelectMode,
        onDelete: deleteSelectedMessages,
        onForward: forwardSelectedMessages,
      ));
    } else {
      widget.onMultiSelectStateChanged?.call(null);
    }
  }

  /// Delete selected messages
  ///
  /// 删除选中消息
  Future<void> deleteSelectedMessages() async {
    if (_selectedMessageIDs.isEmpty) return;

    // Show confirmation dialog
    //
    // 显示确认对话框
    AtomicAlertDialog.showWithConfig(
      context,
      config: AlertDialogConfig(
        content: _atomicLocale.deleteMessagesConfirmTip,
        cancelConfig: ButtonConfig(text: _atomicLocale.cancel),
        confirmConfig: ButtonConfig(
          text: _atomicLocale.confirm,
          type: TextColorPreset.red,
          onClick: () async {
            final messagesToDelete = selectedMessages;
            await _messageListStore.deleteMessages(
                messageList: messagesToDelete);
            exitMultiSelectMode();
          },
        ),
      ),
    );
  }

  /// Forward selected messages
  ///
  /// 转发选中消息
  Future<void> forwardSelectedMessages(BuildContext context) async {
    if (_selectedMessageIDs.isEmpty) return;

    // Get selected messages in the order they appear in _messages.
    // _messages is reversed from messageListStore (newest first), so we need to reverse it back to get oldest first
    //
    // 按 _messages 中出现的顺序获取已选择的消息。_messages 是从 messageListStore 反转过来的（最新的在前），所以我们需要再反转一次才能按最旧的顺序获取
    final messages = _messages.reversed
        .where((message) =>
            message.msgID != null &&
            _selectedMessageIDs.contains(message.msgID))
        .toList();

    // 1. Validate message status first (don't exit multi-select if failed)
    //
    // 1. 先验证消息状态（如果失败，不退出多选）
    final statusError =
        ForwardService.validateMessagesStatus(context, messages);
    if (statusError != null) {
      Toast.error(context, statusError);
      return;
    }

    // 2. Select forward type
    //
    // 2. 选择转发类型
    final forwardType = await ForwardService.showForwardTypeSelector(context);
    if (forwardType == null) {
      return;
    }

    // 3. Validate separate forward limit (don't exit multi-select if failed)
    //
    // 3. 验证单独转发限制（如果失败，不退出多选）
    final limitError = ForwardService.validateSeparateForwardLimit(
        context, messages, forwardType);
    if (limitError != null) {
      Toast.error(context, limitError);
      return;
    }

    // 4. Exit multi-select mode before showing target selector
    //
    // 4. 在显示目标选择器前退出多选模式
    exitMultiSelectMode();

    // 5. Continue with forward flow (target selection and execution)
    //
    // 5. 继续进行转发流程（目标选择和执行）
    ForwardService.forwardMessagesWithType(
      context: context,
      messages: messages,
      messageListStore: _messageListStore,
      config: widget.config,
      forwardType: forwardType,
      sourceConversationID: widget.conversationID,
    );
  }

  // ==================== Multi-select mode end ====================
  //
  // ==================== 多选模式结束 ====================

  bool _isSystemMessage(MessageInfo message) {
    if (message.messageType == MessageType.tips) {
      return true;
    }

    if (message.status == MessageStatus.revoked) {
      return true;
    }

    if (MessageUtil.isSystemStyleCustomMessagePayload(message, context)) {
      return true;
    }

    return false;
  }

  String? _getMessageTimeString(int index) {
    if (index < 0 || index >= _messages.length) return null;

    final message = _messages[index];

    // Skip time display for system messages when they are hidden
    //
    // 当系统消息被隐藏时跳过时间显示
    if (!widget.config.isShowSystemMessage && _isSystemMessage(message)) {
      return null;
    }

    if (index == _messages.length - 1) {
      return _getTimeString(message.timestamp ?? 0);
    }

    // Find the previous message, skipping system messages if they are hidden
    //
    // 找到上一条消息，如果系统消息被隐藏就跳过它们
    int prevIndex = index + 1;
    MessageInfo? prevMessage;

    while (prevIndex < _messages.length) {
      final candidate = _messages[prevIndex];

      // If system messages are hidden, skip them when calculating time intervals
      if (!widget.config.isShowSystemMessage && _isSystemMessage(candidate)) {
        prevIndex++;
        continue;
      }

      prevMessage = candidate;
      break;
    }

    // If no valid previous message found, show time for this message
    if (prevMessage == null) {
      return _getTimeString(message.timestamp ?? 0);
    }

    final timeInterval =
        _getIntervalSeconds(message.timestamp!, prevMessage.timestamp!);
    if (timeInterval > _messageAggregationTime) {
      return _getTimeString(message.timestamp ?? 0);
    }

    return null;
  }

  int _getIntervalSeconds(int timestamp1, int timestamp2) {
    return (timestamp2 - timestamp1).abs();
  }

  String? _getTimeString(int timestamp) {
    final DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final DateTime now = DateTime.now();

    final String timeStr =
        "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";

    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime messageDay = DateTime(date.year, date.month, date.day);
    final int daysDiff = today.difference(messageDay).inDays;

    if (daysDiff == 0) {
      return timeStr;
    }

    if (daysDiff == 1) {
      return "${_atomicLocale.yesterday} $timeStr";
    }

    // Compute Monday-based week start to determine "same week".
    //
    // 计算基于周一的周开始时间来确定“同一周”
    final int nowWeekIndex = (now.weekday + 6) % 7;
    final int dateWeekIndex = (date.weekday + 6) % 7;
    final DateTime nowWeekStart = today.subtract(Duration(days: nowWeekIndex));
    final DateTime dateWeekStart =
        messageDay.subtract(Duration(days: dateWeekIndex));

    if (now.year == date.year && nowWeekStart == dateWeekStart) {
      final weekdays = [
        _atomicLocale.weekdaySunday,
        _atomicLocale.weekdayMonday,
        _atomicLocale.weekdayTuesday,
        _atomicLocale.weekdayWednesday,
        _atomicLocale.weekdayThursday,
        _atomicLocale.weekdayFriday,
        _atomicLocale.weekdaySaturday,
      ];
      return "${weekdays[date.weekday % 7]} $timeStr";
    }

    if (now.year == date.year) {
      return "${date.month}/${date.day} $timeStr";
    }

    return "${date.year}/${date.month}/${date.day} $timeStr";
  }

  Future<void> _loadGroupAttributes() async {
    final groupId =
        widget.conversationID.replaceFirst(groupConversationIDPrefix, '');
    final result = await GroupStore.shared.getGroupInfo(groupID: groupId);
    if (result.isSuccess && result.groupInfo != null && mounted) {
      // Prefer the joinedGroupList entry (same instance attribute pushes mutate)
      // so the call banner stays in sync with subsequent _onGroupAttributeChanged.
      //
      // 优先使用 joinedGroupList 条目（相同实例属性会推动变更），这样通话横幅会与后续 _onGroupAttributeChanged 保持同步。
      final list = GroupStore.shared.state.joinedGroupList.value;
      GroupInfo? fromList;
      for (final g in list) {
        if (g.groupID == groupId) {
          fromList = g;
          break;
        }
      }
      setState(() {
        _groupInfo = fromList ?? result.groupInfo;
      });
      _updateCallStatusWidget();
    }
  }

  /// Sync call banner when GroupStore pushes group attribute / profile updates
  /// (e.g. in-group call start / end while this chat page is already open).
  ///
  /// 当 GroupStore 推送群组属性/资料更新时同步通话横幅（例如在群内通话开始/结束时，此聊天页面已打开）。
  void _onJoinedGroupListChanged() {
    if (!mounted) return;
    final groupId =
        widget.conversationID.replaceFirst(groupConversationIDPrefix, '');
    final list = GroupStore.shared.state.joinedGroupList.value;
    GroupInfo? updated;
    for (final g in list) {
      if (g.groupID == groupId) {
        updated = g;
        break;
      }
    }
    if (updated == null) return;
    _groupInfo = updated;
    _updateCallStatusWidget();
  }

  void _updateCallStatusWidget() {
    if (_groupInfo == null) return;

    final groupId =
        widget.conversationID.replaceFirst(groupConversationIDPrefix, '');
    final groupAttributes = _groupInfo!.groupAttributes;

    debugPrint('_updateCallStatusWidget: $groupAttributes');

    final callWidget =
        CallUIExtension.getJoinInGroupCallWidget(groupId, groupAttributes);

    if (mounted) {
      setState(() {
        _callStatusWidget = callWidget is SizedBox ? null : callWidget;
      });
    }
  }

  // ==================== readReceipt ====================
  //
  // ==================== 已读回执 ====================

  void _handleMessageAppear(MessageInfo message) {
    if (message.isSentBySelf) return;

    if (!message.needReadReceipt) return;

    final msgID = message.msgID;
    if (msgID == null) return;

    if (_sentReceiptMessageIDs.contains(msgID)) return;

    _pendingReceiptMessageIDs.add(msgID);

    _debounceReadReceipt();
  }

  void _debounceReadReceipt() {
    _receiptTimer?.cancel();
    _receiptTimer = Timer(_receiptDebounceInterval, () {
      _sendBatchReadReceipts();
    });
  }

  Future<void> _sendBatchReadReceipts() async {
    if (_pendingReceiptMessageIDs.isEmpty) return;

    final messagesToSend = _messages.where((message) {
      final msgID = message.msgID;
      return msgID != null && _pendingReceiptMessageIDs.contains(msgID);
    }).toList();

    if (messagesToSend.isEmpty) {
      _pendingReceiptMessageIDs.clear();
      return;
    }

    debugPrint(
        'messageList, _sendBatchReadReceipts: ${messagesToSend.length} messages');

    final result = await _messageListStore.sendMessageReadReceipts(
        messageList: messagesToSend);

    if (result.isSuccess) {
      for (final message in messagesToSend) {
        final msgID = message.msgID;
        if (msgID != null) {
          _sentReceiptMessageIDs.add(msgID);
        }
      }
    }

    // 清空待发送列表
    _pendingReceiptMessageIDs.clear();
  }

  // ==================== ASR text bubble menu ====================
  //
  // ==================== ASR 文本气泡菜单 ====================

  /// Show ASR text bubble long press menu (popup above the target)
  ///
  /// 显示 ASR 文本气泡长按菜单（弹窗显示在目标上方）
  void _showAsrTextMenu(MessageInfo message, GlobalKey asrBubbleKey) {
    final asrText =
        (message.messagePayload as AudioMessagePayload?)?.asrText ?? '';
    if (asrText.isEmpty) return;

    showAsrPopupMenu(
      context: context,
      targetKey: asrBubbleKey,
      isSelf: message.isSentBySelf,
      actions: [
        // TODO: 暂时屏蔽"隐藏"入口，后续会重新支持，请勿删除
        // AsrPopupMenuAction(
        //   label: _atomicLocale.hide,
        //   iconAsset: 'chat_assets/icon/hide.svg',
        //   onTap: () => _hideAsrText(message),
        // ),
        //
        // 标签: _atomicLocale.hide, 图标资源: 'chat_assets/icon/hide.svg',
        AsrPopupMenuAction(
          label: _atomicLocale.forward,
          iconAsset: 'chat_assets/icon/forward.svg',
          onTap: () => _forwardAsrText(message),
        ),
        AsrPopupMenuAction(
          label: _atomicLocale.copy,
          iconAsset: 'chat_assets/icon/copy.svg',
          onTap: () => _copyAsrText(message),
        ),
      ],
    );
  }

  // TODO: 暂时屏蔽"隐藏"功能，后续会重新支持，请勿删除
  // /// Hide ASR text bubble (only for this session)
  // void _hideAsrText(MessageInfo message) {
  //   final messageID = message.msgID ?? '';
  //   _asrDisplayManager.hide(messageID);
  // }
  //
  // /// 隐藏 ASR 文本气泡（仅针对本次会话） void _hideAsrText(MessageInfo message) {

  /// Forward ASR text as text message
  ///
  /// 转发 ASR 文本为文本消息
  void _forwardAsrText(MessageInfo message) {
    final asrText =
        (message.messagePayload as AudioMessagePayload?)?.asrText ?? '';
    if (asrText.isEmpty) return;

    ForwardService.forwardText(
      context: context,
      text: asrText,
      excludeConversationID: widget.conversationID,
    );
  }

  /// Copy ASR text to clipboard
  ///
  /// 将 ASR 文本复制到剪贴板
  void _copyAsrText(MessageInfo message) {
    final asrText =
        (message.messagePayload as AudioMessagePayload?)?.asrText ?? '';
    if (asrText.isEmpty) return;

    Clipboard.setData(ClipboardData(text: asrText));
  }

  // ==================== Translation text bubble menu ====================
  //
  // ==================== 翻译文本气泡菜单 ====================

  /// Show translation text bubble long press menu (popup above the target)
  ///
  /// 显示翻译文本气泡长按菜单（在目标上方弹出）
  void _showTranslationTextMenu(
      MessageInfo message, GlobalKey translationBubbleKey) {
    final translatedTextMap =
        (message.messagePayload as TextMessagePayload?)?.translatedText;
    if (translatedTextMap == null || translatedTextMap.isEmpty) return;

    showAsrPopupMenu(
      context: context,
      targetKey: translationBubbleKey,
      isSelf: message.isSentBySelf,
      actions: [
        // TODO: 暂时屏蔽"隐藏"入口，后续会重新支持，请勿删除
        // AsrPopupMenuAction(
        //   label: _atomicLocale.hide,
        //   iconAsset: 'chat_assets/icon/hide.svg',
        //   onTap: () => _hideTranslationText(message),
        // ),
        //
        // 标签: _atomicLocale.hide, 图标资源: 'chat_assets/icon/hide.svg',
        AsrPopupMenuAction(
          label: _atomicLocale.forward,
          iconAsset: 'chat_assets/icon/forward.svg',
          onTap: () => _forwardTranslationText(message),
        ),
        AsrPopupMenuAction(
          label: _atomicLocale.copy,
          iconAsset: 'chat_assets/icon/copy.svg',
          onTap: () => _copyTranslationText(message),
        ),
      ],
    );
  }

  // TODO: 暂时屏蔽"隐藏"功能，后续会重新支持，请勿删除
  // /// Hide translation text bubble (only for this session)
  // void _hideTranslationText(MessageInfo message) {
  //   final messageID = message.msgID ?? '';
  //   _translationDisplayManager.hide(messageID);
  // }
  //
  // /// 隐藏翻译文本气泡（仅限本次会话）void _hideTranslationText(MessageInfo message) {

  /// Forward translated text as text message
  ///
  /// 将翻译后的文本作为文本消息转发
  void _forwardTranslationText(MessageInfo message) {
    final translatedTextMap =
        (message.messagePayload as TextMessagePayload?)?.translatedText;
    if (translatedTextMap == null || translatedTextMap.isEmpty) return;

    // Build translated display text with emoji preserved (same as copy logic)
    //
    // 构建保留表情符的翻译显示文本（与复制逻辑相同）
    final originalText =
        (message.messagePayload as TextMessagePayload?)?.text ?? '';
    final translatedText = TranslationTextParser.buildTranslatedDisplayText(
      originalText,
      translatedTextMap,
      [],
    );
    if (translatedText.isEmpty) return;

    ForwardService.forwardText(
      context: context,
      text: translatedText,
      excludeConversationID: widget.conversationID,
    );
  }

  /// Copy translated text to clipboard
  ///
  /// 将翻译文本复制到剪贴板
  void _copyTranslationText(MessageInfo message) {
    final translatedTextMap =
        (message.messagePayload as TextMessagePayload?)?.translatedText;
    if (translatedTextMap == null || translatedTextMap.isEmpty) return;

    // Get the translated display text with emoji preserved (no need to fetch atUserNames)
    //
    // 获取保留表情符的翻译显示文本（无需获取 atUserNames）
    final originalText =
        (message.messagePayload as TextMessagePayload?)?.text ?? '';
    final textToCopy = TranslationTextParser.buildTranslatedDisplayText(
      originalText,
      translatedTextMap,
      [],
    );

    Clipboard.setData(ClipboardData(text: textToCopy));
  }
}
