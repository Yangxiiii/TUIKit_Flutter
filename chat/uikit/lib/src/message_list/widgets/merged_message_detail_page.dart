import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/api/message/message_action_store.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart' hide IconButton;
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_item.dart';
import 'package:tencent_chat_uikit/src/third_party/scrollable_positioned_list/scrollable_positioned_list.dart';

/// Merged message detail page
///
/// 合并消息详情页
class MergedMessageDetailPage extends StatefulWidget {
  final MessageInfo message;
  final MessageListStore messageListStore;

  const MergedMessageDetailPage({
    super.key,
    required this.message,
    required this.messageListStore,
  });

  @override
  State<MergedMessageDetailPage> createState() =>
      _MergedMessageDetailPageState();
}

class _MergedMessageDetailPageState extends State<MergedMessageDetailPage> {
  List<MessageInfo> _mergedMessages = [];
  bool _isLoading = true;

  /// MessageListStore for merged messages — needed by [MessageItem] for
  /// the same widget contract as the main chat. The store itself is
  /// unused inside the merged-detail flow (messages are loaded via
  /// MessageActionStore.downloadMergedMessageList and held locally
  /// in [_mergedMessages]); it exists only to satisfy MessageItem's
  /// required `messageListStore` parameter.
  ///
  /// 合并消息的 MessageListStore——[MessageItem] 需要它来维持和主聊天相同的Widget契约。这个 store 本身在合并详情流程中未使用（消息是通过
  /// MessageActionStore.downloadMergedMessageList 加载并本地保存在 [_mergedMessages] 中的）；它存在只是为了满足 MessageItem
  /// 所需的 `messageListStore` 参数。
  late MessageListStore _mergedMessageStore;

  /// In-list scroll controller used by [ScrollablePositionedList] to
  /// jumpTo the index of a tapped quote target.
  ///
  /// 列表内滚动控制器，由 [ScrollablePositionedList] 使用，以跳转到点击的引用目标的索引。
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  /// msgID of the message currently flashing the highlight animation
  /// (after a quote tap). Cleared by [MessageBubble.onHighlightComplete].
  ///
  /// 当前正在闪烁高亮动画的消息的 msgID（在点击引用后）。由 [MessageBubble.onHighlightComplete] 清除。
  String? _highlightedMessageId;

  /// Config for merged detail view - disable read receipt
  ///
  /// 合并详情视图配置 - 禁用已读回执
  static const _config = ChatMessageListConfig(
    enableReadReceipt: false,
    isSupportCopy: false,
    isSupportDelete: false,
    isSupportRecall: false,
    isSupportForward: false,
    isSupportMultiSelect: false,
  );

  @override
  void initState() {
    super.initState();
    _mergedMessageStore = MessageListStore.create(conversationID: '');
    _loadMergedMessagePayloads();
  }

  Future<void> _loadMergedMessagePayloads() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final actionStore = MessageActionStore.create(widget.message);
      final result = await actionStore.downloadMergedMessageList();
      if (result.isSuccess && mounted) {
        setState(() {
          _mergedMessages = result.messageList;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Handle tap on a quote preview INSIDE the merged-detail list.
  ///
  /// Merged-detail is a bounded, in-memory list — there is no
  /// "load around an external message" affordance here (unlike the
  /// main chat's `_loadAndNavigateToQuotedMessage`). So the behaviour
  /// is strictly:
  ///   - target msgID present in [_mergedMessages]   → jumpTo (if
  ///     not already visible) + highlight the target.
  ///   - target msgID NOT in [_mergedMessages]       → toast the
  ///     reusable "quoted original unreachable" string. There's no
  ///     equivalent of `_NavToQuotedMessage` reload here because
  ///     merged forwards are immutable: nothing outside the bundle
  ///     is reachable.
  ///
  /// 处理在合并详情列表中点击引用预览的操作。
  ///
  /// 合并详情是一个有界的内存列表——这里没有“在外部消息周围加载”的功能（不像主聊天的 `_loadAndNavigateToQuotedMessage`）。所以行为严格来说是：- 目标 msgID
  /// 存在于 [_mergedMessages] → 跳转到该消息（如果还没可见的话）+ 高亮目标。- 目标 msgID 不在 [_mergedMessages] →
  /// 弹出可重用的“原始引用不可访问”提示。这里没有 `_NavToQuotedMessage` 重新加载的等效功能，因为合并转发是不可变的：包外的任何内容都无法访问。
  void _onQuotePreviewTap(MessageInfo message) {
    final quoteInfo = message.quoteInfo;
    if (quoteInfo == null || quoteInfo.msgID.isEmpty) return;

    final targetIndex =
        _mergedMessages.indexWhere((m) => m.msgID == quoteInfo.msgID);

    if (targetIndex == -1) {
      // Reuses the same string as the main chat shows when an original
      // quoted message can't be located — keeps the user-facing copy
      // consistent across the two surfaces.
      //
      // 重用主聊天在找不到原始引用消息时显示的同一个字符串——保持两个界面向用户显示的文案一致。
      Toast.info(context,
          AppLocalization.of(context).quotedOriginalMessageUnreachable);
      return;
    }

    // Only scroll when the target is actually off-screen. For short
    // bundles (a few messages, the common case) the target is already
    // fully visible — issuing a jumpTo would needlessly redraw and,
    // worse, force ScrollablePositionedList to honour the requested
    // alignment exactly, which on a list shorter than the viewport
    // leaves a band of blank space above the pinned item. Skipping the
    // jump in that case keeps the layout natural and the user simply
    // sees the flash highlight on the existing position.
    //
    // 只有目标确实不在屏幕上时才滚动。对于短列表（几个消息，这种情况最常见），目标已经完全可见——执行 jumpTo 会产生不必要的重绘，更糟的是，会强制 ScrollablePositionedList
    // 精确遵守请求的对齐方式，而在比视口短的列表中，这会在固定项目上方留下一个空白区。这种情况下跳过 jump 可以保持布局自然，用户只会看到当前位置信息的闪烁高亮。
    if (!_isTargetFullyVisible(targetIndex) &&
        _itemScrollController.isAttached) {
      // alignment 0 (NOT 0.3 like the main chat) because this list is
      // forward-scrolled (`reverse: false`), so 0 means "pin to the
      // top of the viewport". A fractional alignment here would
      // re-introduce the same blank-band issue described above.
      //
      // 对齐方式为 0（不是像主聊天那样的 0.3），因为这个列表是向前滚动的（`reverse: false`），所以 0 意味着
      // “固定在视口顶部”。如果这里使用小数对齐，同样会重新出现上面描述的空白区问题。
      _itemScrollController.jumpTo(index: targetIndex, alignment: 0);
    }
    setState(() {
      _highlightedMessageId = _mergedMessages[targetIndex].msgID;
    });
  }

  /// Whether the item at [index] is wholly inside the current viewport.
  /// `itemLeadingEdge` and `itemTrailingEdge` are expressed as fractions
  /// of the viewport's main axis: leading >= 0 and trailing <= 1 means
  /// the item is fully on-screen.
  ///
  /// 检查位于 [index] 的项目是否完全在当前视口内。`itemLeadingEdge` 和 `itemTrailingEdge` 以视口主轴的分数表示：leading >= 0 且 trailing
  /// <= 1 表示该项目完全在屏幕上。
  bool _isTargetFullyVisible(int index) {
    final positions = _itemPositionsListener.itemPositions.value;
    for (final pos in positions) {
      if (pos.index == index) {
        return pos.itemLeadingEdge >= 0 && pos.itemTrailingEdge <= 1;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    final mergedInfo = widget.message.messagePayload as MergedMessagePayload?;
    final title = mergedInfo?.title ?? _getDefaultTitle();

    return Scaffold(
      backgroundColor: colors.bgColorOperate,
      appBar: AppBar(
        backgroundColor: colors.bgColorDefault,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: Icon(Icons.arrow_back_ios, color: colors.textColorPrimary),
          ),
        ),
        title: Text(
          title,
          style: FontScheme.body4Medium.copyWith(
            color: colors.textColorPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(colors),
    );
  }

  Widget _buildBody(SemanticColorScheme colors) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_mergedMessages.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth - 32 - 36 - _config.avatarSpacing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScrollController,
        itemPositionsListener: _itemPositionsListener,
        itemCount: _mergedMessages.length,
        addRepaintBoundaries: true,
        addAutomaticKeepAlives: true,
        addSemanticIndexes: false,
        itemBuilder: (context, index) {
          final message = _mergedMessages[index];
          final isHighlighted = _highlightedMessageId != null &&
              message.msgID == _highlightedMessageId;
          return MessageItem(
            message: message,
            conversationID: '',
            isGroup: false,
            maxWidth: maxWidth,
            messageListStore: _mergedMessageStore,
            isHighlighted: isHighlighted,
            onHighlightComplete: () {
              if (_highlightedMessageId == message.msgID && mounted) {
                setState(() {
                  _highlightedMessageId = null;
                });
              }
            },
            onQuotePreviewTap: _onQuotePreviewTap,
            config: _config,
            isInMergedDetailView: true,
            mergedMediaMessages: _mergedMessages,
          );
        },
      ),
    );
  }

  String _getDefaultTitle() {
    final locale = AppLocalization.of(context);
    return locale.chatHistory;
  }
}
