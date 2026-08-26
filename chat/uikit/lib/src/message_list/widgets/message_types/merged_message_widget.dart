import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/navigation/chat_uikit_navigation.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_input/src/chat_special_text_span_builder.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/merged_message_detail_page.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_status_mixin.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text/extended_text.dart';

/// Merged message display widget
class MergedMessageWidget extends StatefulWidget {
  final MessageInfo message;
  final bool isSelf;
  final double maxWidth;
  final MessageListConfigProtocol config;
  final VoidCallback? onLongPress;
  final GlobalKey? bubbleKey;
  final MessageListStore messageListStore;
  final bool isInMergedDetailView;

  /// Optional override for bubble background color — used by the
  /// "highlight after navigate" animation in `MessageBubble`. Matches
  /// the same hook on [SoundMessageWidget] / [FileMessageWidget].
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

class _MergedMessageWidgetState extends State<MergedMessageWidget>
    with MessageStatusMixin {
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
          maxWidth: widget.maxWidth * 0.7,
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
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                mergedInfo?.title ?? _getDefaultTitle(context),
                style: FontScheme.caption2Medium.copyWith(
                  color: colors.textColorPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Divider
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: colors.strokeColorPrimary.withOpacity(0.5),
            ),
            // Abstract list with status and time
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildAbstractList(context, mergedInfo?.abstractList, colors),
                  const SizedBox(height: 6),
                  // Status and time row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: buildStatusAndTimeWidgets(
                      message: widget.message,
                      isSelf: widget.isSelf,
                      colors: colors,
                      isShowTimeInBubble: widget.config.isShowTimeInBubble,
                      enableReadReceipt: widget.config.enableReadReceipt,
                      isInMergedDetailView: widget.isInMergedDetailView,
                    ),
                  ),
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

    // Show max 4 abstracts
    final displayList = abstractList.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: displayList.map((abstract) {
        // Use ExtendedText with ChatSpecialTextSpanBuilder to render emoji images
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: ExtendedText(
            abstract,
            specialTextSpanBuilder: ChatSpecialTextSpanBuilder(
              colorScheme: colors,
              onTapUrl: (_) {},
            ),
            style: FontScheme.caption3Regular.copyWith(
              color: colors.textColorSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
    );
  }

  BorderRadius _getBubbleBorderRadius() {
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

  void _openMergedMessagePayloadDetail(BuildContext context) {
    context.pushChatUIKitPage(
      MergedMessageDetailPage(
        message: widget.message,
        messageListStore: widget.messageListStore,
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
