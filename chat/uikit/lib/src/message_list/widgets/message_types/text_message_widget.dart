import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_input/src/chat_special_text_span_builder.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_status_mixin.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text/extended_text.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:tencent_chat_uikit/src/common/utils/uikit_util.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

typedef BackgroundBuilder = Widget Function(Widget child);

class TextMessageWidget extends StatefulWidget {
  final MessageInfo message;
  final bool isSelf;
  final double maxWidth;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final GlobalKey? bubbleKey;
  final BackgroundBuilder? backgroundBuilder;
  final VoidCallback? onResendTap;
  final MessageListConfigProtocol config;
  final bool isInMergedDetailView;

  const TextMessageWidget({
    super.key,
    required this.message,
    required this.isSelf,
    required this.maxWidth,
    required this.config,
    this.onTap,
    this.onLongPress,
    this.bubbleKey,
    this.backgroundBuilder,
    this.onResendTap,
    this.isInMergedDetailView = false,
  });

  @override
  State<TextMessageWidget> createState() => _TextMessageWidgetState();
}

class _TextMessageWidgetState extends State<TextMessageWidget>
    with MessageStatusMixin {
  // The translation bubble used to be rendered here as a sibling of the
  // text bubble inside a Column. That made the read-receipt and status
  // icon (placed by MessageItem with CrossAxisAlignment.end) drift to
  // the bottom of the column whenever the translation expanded, see
  // Bug-956459. The translation bubble is now built by
  // `MessageAttachmentBuilder` and rendered by `MessageItem` *outside*
  // the row that holds the receipt — see
  // `lib/src/message_list/widgets/message_attachments.dart`.
  //
  // 翻译气泡以前是在 Column 里的文本气泡的同级中渲染的。这会导致已读回执和状态图标（由带 CrossAxisAlignment.end 的 MessageItem
  // 放置）在翻译扩展时漂到列的底部，见 Bug-956459。现在翻译气泡是由 `MessageAttachmentBuilder` 构建，并由 `MessageItem` 渲染在放置回执的行的*外面*
  // —— 参见 `lib/src/message_list/widgets/message_attachments.dart`。

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);

    final content = Container(
      key: widget.bubbleKey,
      constraints: BoxConstraints(
        maxWidth: widget.maxWidth * 0.9,
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: _buildTextWithStatusAndTime(colors),
    );

    final bubble = widget.backgroundBuilder?.call(content) ??
        Container(
          decoration: BoxDecoration(
            color: _getBubbleColor(colors),
            borderRadius: _getBubbleBorderRadius(),
          ),
          child: content,
        );

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: bubble,
    );
  }

  Widget _buildTextWithStatusAndTime(SemanticColorScheme colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: _buildTextContent(colors),
        ),
        ...[
          const SizedBox(width: 8),
          ...buildStatusAndTimeWidgets(
            message: widget.message,
            isSelf: widget.isSelf,
            colors: colors,
            onResendTap: widget.onResendTap,
            isShowTimeInBubble: widget.config.isShowTimeInBubble,
            enableReadReceipt: widget.config.enableReadReceipt,
            isInMergedDetailView: widget.isInMergedDetailView,
          ),
        ],
      ],
    );
  }

  Widget _buildTextContent(SemanticColorScheme colorsTheme) {
    final text =
        (widget.message.messagePayload as TextMessagePayload?)?.text ?? '';

    return ExtendedText(
      _getContentSpan(text, colorsTheme),
      specialTextSpanBuilder: ChatSpecialTextSpanBuilder(
        colorScheme: colorsTheme,
        onTapUrl: _launchUrl,
        showAtBackground: true,
      ),
      style: FontScheme.caption1Regular.copyWith(
        color: widget.isSelf
            ? colorsTheme.textColorAntiPrimary
            : colorsTheme.textColorPrimary,
      ),
    );
  }

  void _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      debugPrint('cannot open url: $url');
    }
  }

  String _getContentSpan(String text, SemanticColorScheme colors) {
    String contentData = "";
    Iterable<RegExpMatch> matches = UIKitUtil.urlReg.allMatches(text);

    int index = 0;
    for (RegExpMatch match in matches) {
      String c = text.substring(match.start, match.end);
      if (match.start == index) {
        index = match.end;
      }
      if (index < match.start) {
        String a = text.substring(index, match.start);
        index = match.end;
        contentData += a;
      }

      if (UIKitUtil.urlReg.hasMatch(c)) {
        contentData += '${HttpText.flag}$c${HttpText.flag}';
      } else {
        contentData += c;
      }
    }

    if (index < text.length) {
      String a = text.substring(index, text.length);
      contentData += a;
    }

    return contentData.isNotEmpty ? contentData : text;
  }

  Color _getBubbleColor(SemanticColorScheme colorsTheme) {
    if (widget.isSelf) {
      return colorsTheme.bgColorBubbleOwn;
    } else {
      return colorsTheme.bgColorBubbleReciprocal;
    }
  }

  BorderRadius _getBubbleBorderRadius() {
    switch (widget.config.alignment) {
      case 'left':
        return BorderRadius.only(
          topLeft: Radius.circular(widget.config.textBubbleCornerRadius),
          topRight: Radius.circular(widget.config.textBubbleCornerRadius),
          bottomLeft: const Radius.circular(0),
          bottomRight: Radius.circular(widget.config.textBubbleCornerRadius),
        );
      case 'right':
        return BorderRadius.only(
          topLeft: Radius.circular(widget.config.textBubbleCornerRadius),
          topRight: Radius.circular(widget.config.textBubbleCornerRadius),
          bottomLeft: Radius.circular(widget.config.textBubbleCornerRadius),
          bottomRight: const Radius.circular(0),
        );
      case 'two-sided':
      default:
        if (widget.isSelf) {
          return BorderRadius.only(
            topLeft: Radius.circular(widget.config.textBubbleCornerRadius),
            topRight: Radius.circular(widget.config.textBubbleCornerRadius),
            bottomLeft: Radius.circular(widget.config.textBubbleCornerRadius),
            bottomRight: const Radius.circular(0),
          );
        } else {
          return BorderRadius.only(
            topLeft: Radius.circular(widget.config.textBubbleCornerRadius),
            topRight: Radius.circular(widget.config.textBubbleCornerRadius),
            bottomLeft: const Radius.circular(0),
            bottomRight: Radius.circular(widget.config.textBubbleCornerRadius),
          );
        }
    }
  }
}
