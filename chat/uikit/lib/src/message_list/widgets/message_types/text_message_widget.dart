import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_input/src/chat_special_text_span_builder.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_status_mixin.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text/extended_text.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:tencent_chat_uikit/src/common/utils/uikit_util.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../message_actions_scope.dart';

typedef BackgroundBuilder = Widget Function(Widget child);

/// 渲染文字正文与气泡外观，发送状态及头像由外层消息项协调。
class TextMessageWidget extends StatefulWidget {
  /// 当前正文及发送状态的数据来源。
  final MessageInfo message;

  /// 仅决定己方与对方气泡颜色，不推断已读状态。
  final bool isSelf;

  /// 外层消息项分配的最大宽度，单位为逻辑像素。
  final double maxWidth;

  /// 正文单击回调；为空时保留链接自身的点击行为。
  final VoidCallback? onTap;

  /// 长按操作由外层消息菜单处理。
  final VoidCallback? onLongPress;

  /// 供菜单定位与高亮复用的正文气泡锚点。
  final GlobalKey? bubbleKey;

  /// 自定义背景包裹器；未提供时使用配置中的气泡外观。
  final BackgroundBuilder? backgroundBuilder;

  /// 交由业务重发失败消息，不在展示组件内创建发送任务。
  final VoidCallback? onResendTap;

  /// 正文圆角、时间和回执等展示配置。
  final MessageListConfigProtocol config;

  /// 合并消息详情中关闭原会话的回执操作。
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

/// 保留正文链接、格式和手势，按消息配置绘制统一圆角气泡。
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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

  /// 只有实际显示内部时间或状态时才预留间隔，普通正文不保留空白尾槽。
  Widget _buildTextWithStatusAndTime(SemanticColorScheme colors) {
    final indicators = buildStatusAndTimeWidgets(
      message: widget.message,
      isSelf: widget.isSelf,
      colors: colors,
      onResendTap: widget.onResendTap,
      isShowTimeInBubble: widget.config.isShowTimeInBubble,
      enableReadReceipt: widget.config.enableReadReceipt,
      isInMergedDetailView: widget.isInMergedDetailView,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: _buildTextContent(colors),
        ),
        if (indicators.isNotEmpty) ...[
          const SizedBox(width: 8),
          ...indicators,
        ],
      ],
    );
  }

  /// 保留正文的链接及表情解析，仅在SDK附加数据已确认编辑后追加展示标签。
  Widget _buildTextContent(SemanticColorScheme colorsTheme) {
    final text =
        (widget.message.messagePayload as TextMessagePayload?)?.text ?? '';

    final edited = MessageActionsScope.maybeOf(context)
            ?.config
            .editedMessageIds
            .contains(widget.message.msgID) ??
        false;
    // 编辑标识仅是展示文本，复制、引用和SDK正文仍使用原messagePayload。
    final style = FontScheme.caption1Regular.copyWith(
      height: 1.5,
      color: widget.isSelf
          ? colorsTheme.textColorAntiPrimary
          : colorsTheme.textColorPrimary,
    );
    final builder = ChatSpecialTextSpanBuilder(
      colorScheme: colorsTheme,
      onTapUrl: _launchUrl,
      showAtBackground: true,
    );
    final content = _getContentSpan(text, colorsTheme);
    if (!edited) {
      return ExtendedText(content,
          specialTextSpanBuilder: builder, style: style);
    }
    // 此版本ExtendedText.rich不能同时使用specialTextSpanBuilder，先构建正文再附加标签。
    return ExtendedText.rich(
        TextSpan(children: [
          builder.build(content, textStyle: style),
          TextSpan(
              text: ' (已编辑)',
              style: TextStyle(
                  fontSize: 12, color: colorsTheme.textColorSecondary)),
        ]),
        style: style);
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

  /// 方向由气泡左右归属表达，四角统一使用宿主配置的圆角。
  BorderRadius _getBubbleBorderRadius() =>
      BorderRadius.circular(widget.config.textBubbleCornerRadius);
}
