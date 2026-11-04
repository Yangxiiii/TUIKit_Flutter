import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_input/src/chat_special_text_span_builder.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/merged_message_detail_page.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text/extended_text.dart';

/// 展示原合并消息摘要，并从统一详情Sheet查看或再次转发内层消息。
class MergedMessageWidget extends StatefulWidget {
  /// 原合并消息的标题、摘要及下载载荷。
  final MessageInfo message;

  /// 使用原发送方向选择气泡背景，不改变下载包内发送者。
  final bool isSelf;

  /// 父消息行分配的可用宽度，长标题按两行省略。
  final double maxWidth;

  /// 沿用来源圆角、媒体和宿主转发能力。
  final MessageListConfigProtocol config;

  /// 来源允许时打开消息操作，详情只读模式可为空。
  final VoidCallback? onLongPress;

  /// 外部浮层定位的稳定气泡锚点。
  final GlobalKey? bubbleKey;

  /// 来源消息Store，仅用于公开消息操作，不重新加载包外历史。
  final MessageListStore messageListStore;

  /// 合并详情不显示包外发送回执，媒体使用包内静态集合。
  final bool isInMergedDetailView;

  /// Optional override for bubble background color — used by the
  /// "highlight after navigate" animation in `MessageBubble`. Matches
  /// the same hook on [SoundMessageWidget] / [FileMessageWidget].
  ///
  /// 气泡背景颜色的可选覆盖 — 用于 `MessageBubble` 中的“导航后高亮”动画。与 [SoundMessageWidget] / [FileMessageWidget] 上的同样钩子匹配。
  final Color? bubbleColor;

  const MergedMessageWidget({
    super.key,
    required this.message,
    required this.isSelf,
    required this.maxWidth,
    required this.config,
    this.onLongPress,
    this.bubbleKey,
    required this.messageListStore,
    this.isInMergedDetailView = false,
    this.bubbleColor,
  });

  @override
  State<MergedMessageWidget> createState() => _MergedMessageWidgetState();
}

/// 根据真实合并载荷呈现三条摘要，并协调原包详情面板的生命周期。
class _MergedMessageWidgetState extends State<MergedMessageWidget> {
  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    final mergedInfo = (widget.message.messagePayload as MergedMessagePayload?);

    return GestureDetector(
      onTap: () => _openMergedMessagePayloadDetail(context),
      onLongPress: widget.onLongPress,
      child: Container(
        key: widget.bubbleKey,
        constraints: BoxConstraints(
          maxWidth: widget.maxWidth,
          minWidth: 120,
        ),
        decoration: BoxDecoration(
          color: widget.bubbleColor ??
              (widget.isSelf
                  ? colors.bgColorBubbleOwn
                  : colors.bgColorBubbleReciprocal),
          borderRadius: _getBubbleBorderRadius(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题最多两行，摘要与其分区留白，不增加设计中不存在的分隔线。
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                mergedInfo?.title ?? _getDefaultTitle(context),
                style: TextStyle(
                    fontSize: 16, height: 1.5, color: colors.textColorPrimary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 回执与时间由外层MessageItem统一展示，卡片内部只保留真实摘要。
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildAbstractList(context, mergedInfo?.abstractList, colors),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAbstractList(
    BuildContext context,
    List<String>? abstractList,
    SemanticColorScheme colors,
  ) {
    if (abstractList == null || abstractList.isEmpty) {
      return Text(
        _getChatRecordsText(context),
        style: FontScheme.caption3Regular.copyWith(
          color: colors.textColorSecondary,
        ),
      );
    }

    // 产品展示前三条摘要，收到更多SDK摘要时也不改变固定卡片密度。
    final displayList = abstractList.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: displayList.map((abstract) {
        // Use ExtendedText with ChatSpecialTextSpanBuilder to render emoji images
        //
        // 使用 ExtendedText 和 ChatSpecialTextSpanBuilder 渲染表情图片
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: ExtendedText(
            abstract,
            specialTextSpanBuilder: ChatSpecialTextSpanBuilder(
              colorScheme: colors,
              onTapUrl: (_) {},
            ),
            style: TextStyle(
                fontSize: 14,
                height: 22 / 14,
                color: colors.textColorSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
    );
  }

  BorderRadius _getBubbleBorderRadius() {
    if (widget.config.textBubbleCornerRadius != 18) {
      return BorderRadius.circular(widget.config.textBubbleCornerRadius);
    }
    if (widget.isSelf) {
      return const BorderRadius.only(
        topLeft: Radius.circular(18),
        topRight: Radius.circular(18),
        bottomLeft: Radius.circular(18),
        bottomRight: Radius.circular(0),
      );
    } else {
      return const BorderRadius.only(
        topLeft: Radius.circular(18),
        topRight: Radius.circular(18),
        bottomLeft: Radius.circular(0),
        bottomRight: Radius.circular(18),
      );
    }
  }

  /// 原包详情保留顶部安全区及12像素留白，遮罩沿用普通弹窗的统一配置。
  void _openMergedMessagePayloadDetail(BuildContext context) {
    AppDialog.showSheet<void>(
      showCloseButton: false,
      topRadius: 16,
      maxHeightFactor: 1,
      backgroundColor: context.appColors.surface,
      child: MergedMessageDetailPage(
        message: widget.message,
        messageListStore: widget.messageListStore,
        config: widget.config,
      ),
    );
  }

  String _getDefaultTitle(BuildContext context) {
    final locale = AppLocalization.of(context);
    return locale.chatHistory;
  }

  String _getChatRecordsText(BuildContext context) {
    final locale = AppLocalization.of(context);
    return locale.chatHistory;
  }
}
