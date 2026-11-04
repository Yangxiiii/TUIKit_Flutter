import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/api/message/message_action_store.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart' hide IconButton;
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/message_utils.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_item.dart';
import 'package:tencent_chat_uikit/src/third_party/scrollable_positioned_list/scrollable_positioned_list.dart';

/// 统一展示已发送合并记录和待转发记录，只允许内容预览与包内引用定位。
class MergedMessageDetailPage extends StatefulWidget {
  /// 已发送记录的原始合并载荷；直接展示待转发消息时为空。
  final MessageInfo? message;

  /// 待转发的当前消息集合；已发送记录为空，由本组件下载原合并包。
  final List<MessageInfo>? messages;

  /// 待转发记录标题；已发送记录沿用合并载荷中的原始标题。
  final String? title;

  /// 供消息组件读取来源资料与媒体能力，预览集合始终取自当前记录。
  final MessageListStore messageListStore;

  /// 沿用来源布局与媒体预览配置，操作能力在详情内统一关闭。
  final MessageListConfigProtocol? config;

  const MergedMessageDetailPage({
    super.key,
    required MessageInfo message,
    required this.messageListStore,
    this.config,
  }) : message = message,
       messages = null,
       title = null;

  /// 直接展示调用方持有的消息，撤回筛选与来源状态仍由调用方负责。
  const MergedMessageDetailPage.preview({
    super.key,
    required List<MessageInfo> messages,
    required String title,
    required this.messageListStore,
    this.config,
  }) : messages = messages,
       title = title,
       message = null;

  @override
  State<MergedMessageDetailPage> createState() =>
      _MergedMessageDetailPageState();
}

/// 下载已发送记录并持有引用高亮状态，两种来源共用标题、消息布局和只读交互。
class _MergedMessageDetailPageState extends State<MergedMessageDetailPage> {
  /// 本次成功下载的原始合并包，不用外层聊天的同ID编辑结果覆盖。
  List<MessageInfo> _downloadedMessages = [];

  /// 待转发集合直接追随调用方更新，已发送记录始终使用原下载包。
  List<MessageInfo> get _mergedMessages => widget.messages ?? _downloadedMessages;
  bool _isLoading = true;

  /// 下载失败与成功空包分开呈现，允许用户显式重试。
  bool _failed = false;

  /// 复用来源Store供消息组件读取，不用原会话历史替换当前记录集合。
  MessageListStore get _mergedMessageStore => widget.messageListStore;

  /// 两种来源共用的记录内引用滚动控制器，不加载包外历史。
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  /// 当前引用目标的高亮标识，动画结束后清空。
  String? _highlightedMessageId;

  /// 复用来源消息布局与媒体能力；只读详情不提供发送、长按菜单或回执操作。
  ChatMessageListConfig get _config => ChatMessageListConfig(
        enableReadReceipt: false,
        isSupportCopy: false,
        isSupportDelete: false,
        isSupportRecall: false,
        isSupportForward: false,
        imageLoadingPlaceholder: widget.config?.imageLoadingPlaceholder,
        videoLoadingPlaceholder: widget.config?.videoLoadingPlaceholder,
        videoPlayIcon: widget.config?.videoPlayIcon,
        fileDownloader: widget.config?.fileDownloader,
        fileIconBuilder: widget.config?.fileIconBuilder,
        alignment: widget.config?.alignment,
        isShowLeftAvatar: widget.config?.isShowLeftAvatar,
        isShowRightAvatar: widget.config?.isShowRightAvatar ?? true,
        isShowLeftNickname: widget.config?.isShowLeftNickname,
        isShowRightNickname: widget.config?.isShowRightNickname,
        isShowTimeMessage: widget.config?.isShowTimeMessage,
        isShowTimeInBubble: widget.config?.isShowTimeInBubble,
        isShowSystemMessage: widget.config?.isShowSystemMessage,
        isShowUnsupportMessage: widget.config?.isShowUnsupportMessage,
        cellSpacing: widget.config?.cellSpacing,
        avatarSpacing: widget.config?.avatarSpacing,
        textBubbleCornerRadius: widget.config?.textBubbleCornerRadius ?? 8,
        isSupportReaction: false,
        isSupportQuote: false,
        isSupportMultiSelect: false,
        isSupportTranslate: false,
        isSupportTongue: false,
      );

  @override
  void initState() {
    super.initState();
    if (widget.message != null) _loadMergedMessagePayloads();
  }

  /// 显式下载或重试同一原包，失败保留错误态，不能显示为成功的空记录。
  Future<void> _loadMergedMessagePayloads() async {
    final message = widget.message;
    if (message == null) return;
    setState(() {
      _isLoading = true;
      _failed = false;
    });

    // 每次重试重新下载同一原包，不能借用外层聊天窗口作为包内内容。
    try {
      final actionStore = MessageActionStore.create(message);
      final result = await actionStore.downloadMergedMessageList();
      // 只有明确成功才发布包内消息；失败和成功空包保留不同反馈。
      if (result.isSuccess && mounted) {
        setState(() {
          _downloadedMessages = result.messageList;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _failed = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _failed = true;
        });
      }
    }
  }

  /// 只定位当前记录集合内的引用；包外目标不可达，不加载外部会话历史。
  void _onQuotePreviewTap(MessageInfo message) {
    final quoteInfo = message.quoteInfo;
    if (quoteInfo == null || quoteInfo.msgID.isEmpty) return;

    final targetIndex =
        _mergedMessages.indexWhere((m) => m.msgID == quoteInfo.msgID);

    if (targetIndex == -1) {
      // 缺失目标沿用聊天窗口提示，不把包外消息补入当前记录。
      Toast.info(context,
          AppLocalization.of(context).quotedOriginalMessageUnreachable);
      return;
    }

    // 可见目标仅高亮，避免短记录跳转后在顶部产生额外空白。
    if (!_isTargetFullyVisible(targetIndex) &&
        _itemScrollController.isAttached) {
      // 正向列表把目标贴齐顶部，不能使用聊天反向列表的分数对齐。
      _itemScrollController.jumpTo(index: targetIndex, alignment: 0);
    }
    setState(() {
      _highlightedMessageId = _mergedMessages[targetIndex].msgID;
    });
  }

  /// 定位监听器按视口比例报告边界，只有整条目标可见时才省略跳转。
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
    final mergedInfo = widget.message?.messagePayload as MergedMessagePayload?;
    final title = widget.title ?? mergedInfo?.title ?? _getDefaultTitle();
    // 高度由同一组件管理，两个入口及嵌套预览都只预留一次系统安全区。
    final media = MediaQueryData.fromView(View.of(context));

    return SizedBox(
      height: media.size.height - media.padding.top - media.padding.bottom - 12,
      child: Scaffold(
        // 记录组件已预留系统安全区，内层不再增加顶部安全区占位。
        primary: false,
        backgroundColor: context.appColors.surface,
        appBar: AppBar(
          primary: false,
          toolbarHeight: 48,
          backgroundColor: context.appColors.surface,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          leading: Semantics(
            identifier: widget.messages == null
                ? 'tim.forward.merged.close'
                : 'tim.forward.preview.close',
            label: '关闭预览',
            button: true,
            child: GestureDetector(
              onTap: AppDialog.dismiss,
              child: Center(
                child: Icon(AppIcons.close, color: colors.textColorPrimary),
              ),
            )),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FontScheme.body4Medium.copyWith(
              color: colors.textColorPrimary,
            ),
          ),
          centerTitle: true,
        ),
        body: _buildBody(colors),
      ),
    );
  }

  Widget _buildBody(SemanticColorScheme colors) {
    if (widget.messages == null && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_mergedMessages.isEmpty) {
      return _failed
          ? Center(
              child: Semantics(
                  identifier: 'tim.forward.merged.retry',
                  child: TextButton(
                      onPressed: _loadMergedMessagePayloads,
                      child: const Text('加载失败，点击重试'))))
          : const Center(child: Text('消息不存在'));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth - 32;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ScrollablePositionedList.builder(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        itemScrollController: _itemScrollController,
        itemPositionsListener: _itemPositionsListener,
        itemCount: _mergedMessages.length,
        addRepaintBoundaries: true,
        addAutomaticKeepAlives: true,
        addSemanticIndexes: false,
        itemBuilder: (context, index) => _recordItem(index, colors, maxWidth),
      ),
    );
  }

  /// 包内时间组和气泡使用同一列表项，引用定位仍保持原消息索引。
  Widget _recordItem(int index, SemanticColorScheme colors, double maxWidth) {
    final message = _mergedMessages[index];
    final isHighlighted =
        _highlightedMessageId != null && message.msgID == _highlightedMessageId;
    final previous = index == 0 ? null : _mergedMessages[index - 1];
    final timestamp = message.timestamp ?? 0;
    final showTime = _config.isShowTimeMessage &&
        (previous == null ||
            (timestamp - (previous.timestamp ?? 0)).abs() > 300);
    final isContinuation =
        previous != null && MessageUtil.isAvatarContinuation(previous, message);
    // 时间分组、同发送人聚合和普通间距沿用聊天列表规则，正文宽度不重复扣头像列。
    final topSpacing = previous == null
        ? 0.0
        : showTime
            ? 24.0
            : isContinuation
                ? 8.0
                : _config.cellSpacing;
    return Padding(
        padding: EdgeInsets.only(top: topSpacing),
        child: Column(children: [
          if (showTime && timestamp > 0)
            Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Center(
                    child: Text(
                        MessageUtil.formatMessageTime(timestamp, context),
                        style: FontScheme.caption2Regular.copyWith(
                            height: 1.5, color: colors.textColorSecondary)))),
          MessageItem(
            key: ValueKey(message.msgID),
            message: message,
            conversationID: '',
            isGroup: false,
            isContinuation: isContinuation,
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
          ),
        ]));
  }

  String _getDefaultTitle() {
    final locale = AppLocalization.of(context);
    return locale.chatHistory;
  }
}
