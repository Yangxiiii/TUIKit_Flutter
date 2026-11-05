import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_input/src/chat_special_text_span_builder.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/asr_display_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/translation_display_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/translation_text_parser.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text/extended_text.dart';
import 'package:url_launcher/url_launcher.dart';

/// 在主消息行下方展示识别或翻译附件，保持回执和失败标记锚定主气泡。
class MessageAttachmentBuilder {
  MessageAttachmentBuilder._();

  /// 依据当前会话显示状态生成附件；合并转发不承载识别或翻译操作。
  static Widget? buildIfAny({
    required MessageInfo message,
    required bool isSelf,
    required double maxWidth,
    required MessageListConfigProtocol config,
    bool isInMergedDetailView = false,
    AsrDisplayManager? asrDisplayManager,
    void Function(MessageInfo message, GlobalKey asrBubbleKey)?
        onAsrBubbleLongPress,
    TranslationDisplayManager? translationDisplayManager,
    void Function(MessageInfo message, GlobalKey translationBubbleKey)?
        onTranslationBubbleLongPress,
  }) {
    if (isInMergedDetailView) return null;
    final messageID = message.msgID;
    if (messageID.isEmpty) return null;

    if (message.messageType == MessageType.audio) {
      final hasAsr = (message.messagePayload as AudioMessagePayload?)
              ?.asrText
              ?.isNotEmpty ==
          true;
      final isConverting = asrDisplayManager?.isConverting(messageID) ?? false;
      final isAsrHidden = asrDisplayManager?.isHidden(messageID) ?? false;
      final failed =
          (asrDisplayManager?.hasFailed(messageID) ?? false) && !hasAsr;
      final shouldShow = isConverting || failed || (hasAsr && !isAsrHidden);
      if (!shouldShow) return null;
      return AsrAttachmentBubble(
        key: ValueKey('asr-attachment-$messageID'),
        message: message,
        isSelf: isSelf,
        maxWidth: maxWidth,
        isConverting: isConverting,
        isFailed: failed,
        onLongPress: onAsrBubbleLongPress,
      );
    }

    if (message.messageType == MessageType.text) {
      if (!config.isSupportTranslate) return null;
      final translatedTextMap =
          (message.messagePayload as TextMessagePayload?)?.translatedText;
      final hasTranslation =
          translatedTextMap != null && translatedTextMap.isNotEmpty;
      final isTranslating =
          translationDisplayManager?.isTranslating(messageID) ?? false;
      final isTranslationHidden =
          translationDisplayManager?.isHidden(messageID) ?? true;
      final shouldShow =
          !isTranslationHidden && (isTranslating || hasTranslation);
      if (!shouldShow) return null;
      return TranslationAttachmentBubble(
        key: ValueKey('translation-attachment-$messageID'),
        message: message,
        isSelf: isSelf,
        maxWidth: maxWidth,
        isTranslating: isTranslating,
        onLongPress: onTranslationBubbleLongPress,
      );
    }

    return null;
  }
}

/// 展示原音频下方的识别结果及等待、失败状态，不改变主气泡的回执位置。
class AsrAttachmentBubble extends StatefulWidget {
  /// 识别正文由SDK音频payload提供，此组件不维护第二份缓存。
  final MessageInfo message;

  /// 决定附件气泡与原消息相同的收发颜色。
  final bool isSelf;

  /// 宿主消息行可用逻辑宽度，正文最多占其70%。
  final double maxWidth;

  /// 当前请求尚未返回，期间不能对半成品正文打开菜单。
  final bool isConverting;

  /// 本次识别失败但仍可重试，不代表音频资源已经过期。
  final bool isFailed;

  /// 只有完整识别正文才交给既有菜单，等待或失败时禁用。
  final void Function(MessageInfo message, GlobalKey asrBubbleKey)? onLongPress;

  const AsrAttachmentBubble({
    super.key,
    required this.message,
    required this.isSelf,
    required this.maxWidth,
    required this.isConverting,
    this.isFailed = false,
    this.onLongPress,
  });

  @override
  State<AsrAttachmentBubble> createState() => _AsrAttachmentBubbleState();
}

/// 识别附件保持在主音频气泡下方，进度与失败不会改变主气泡回执锚点。
class _AsrAttachmentBubbleState extends State<AsrAttachmentBubble> {
  final GlobalKey _asrBubbleKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    final voiceDesign = widget.message.conversationType == ConversationType.c2c;
    final appColors = context.appColors;
    final text =
        (widget.message.messagePayload as AudioMessagePayload?)?.asrText ?? '';
    return Semantics(
      identifier: 'chat.voice.asr_text.${widget.message.msgID}',
      child: GestureDetector(
        onLongPress: widget.isConverting || widget.isFailed
            ? null
            : () {
                widget.onLongPress?.call(widget.message, _asrBubbleKey);
              },
        child: Container(
          key: _asrBubbleKey,
          margin: EdgeInsets.only(top: voiceDesign ? 8 : 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(maxWidth: widget.maxWidth * 0.7),
          decoration: BoxDecoration(
            color: voiceDesign
                ? (widget.isSelf
                    ? appColors.chatOutgoingBubble
                    : appColors.chatIncomingBubble)
                : _bubbleColor(colors),
            borderRadius: BorderRadius.circular(12),
          ),
          // 等待与失败图标和正文保持同列，长正文只在剩余宽度内换行。
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.isConverting) ...[
              SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: appColors.primary)),
              const SizedBox(width: 8),
            ] else if (widget.isFailed) ...[
              Icon(AppIcons.triangleAlert, size: 20, color: appColors.warning),
              const SizedBox(width: 8),
            ],
            Flexible(
                child: Text(
                    widget.isConverting
                        ? '正在识别'
                        : widget.isFailed
                            ? '无法识别'
                            : text,
                    style: voiceDesign
                        ? TextStyle(
                            color: appColors.textPrimary,
                            fontSize: 16,
                            height: 22 / 16)
                        : FontScheme.caption2Regular.copyWith(
                            color: widget.isSelf
                                ? colors.textColorAntiPrimary
                                : colors.textColorPrimary))),
          ]),
        ),
      ),
    );
  }

  Color _bubbleColor(SemanticColorScheme colors) =>
      widget.isSelf ? colors.bgColorBubbleOwn : colors.bgColorBubbleReciprocal;
}

/// Translation bubble shown directly underneath the text bubble.
///
/// Owns the asynchronous load of `@user` display names so the parent
/// text widget no longer has to. Until the names are loaded the bubble
/// renders nothing rather than a half-resolved string (the legacy
/// in-bubble translation had the same gate on `_atUserNamesLoaded`).
///
/// 翻译气泡直接显示在文本气泡下方。
///
/// 负责异步加载 `@user` 显示名，这样父文本控件就不必处理了。在名字加载之前，气泡不会渲染任何内容，而不是显示半完成的字符串（遗留的气泡内翻译对 `_atUserNamesLoaded`
/// 也有同样的限制）。
class TranslationAttachmentBubble extends StatefulWidget {
  final MessageInfo message;
  final bool isSelf;
  final double maxWidth;
  final bool isTranslating;
  final void Function(MessageInfo message, GlobalKey translationBubbleKey)?
      onLongPress;

  const TranslationAttachmentBubble({
    super.key,
    required this.message,
    required this.isSelf,
    required this.maxWidth,
    required this.isTranslating,
    this.onLongPress,
  });

  @override
  State<TranslationAttachmentBubble> createState() =>
      _TranslationAttachmentBubbleState();
}

class _TranslationAttachmentBubbleState
    extends State<TranslationAttachmentBubble> {
  final GlobalKey _translationBubbleKey = GlobalKey();

  List<String>? _atUserNames;
  bool _atUserNamesLoaded = false;
  bool _isLoadingAtUserNames = false;

  bool get _hasAtUsers => widget.message.atUserList.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadAtUserNamesIfNeeded();
  }

  @override
  void didUpdateWidget(TranslationAttachmentBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.msgID != widget.message.msgID) {
      _atUserNames = null;
      _atUserNamesLoaded = false;
      _isLoadingAtUserNames = false;
      _loadAtUserNamesIfNeeded();
    } else if (!_atUserNamesLoaded && !_isLoadingAtUserNames) {
      _loadAtUserNamesIfNeeded();
    }
  }

  void _loadAtUserNamesIfNeeded() {
    final translatedTextMap =
        (widget.message.messagePayload as TextMessagePayload?)?.translatedText;
    final hasTranslation =
        translatedTextMap != null && translatedTextMap.isNotEmpty;
    if (!hasTranslation || _atUserNamesLoaded || _isLoadingAtUserNames) return;

    if (!_hasAtUsers) {
      _atUserNamesLoaded = true;
      return;
    }

    _isLoadingAtUserNames = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final localizations = AppLocalization.of(context);
      final atUserNames = await TranslationTextParser.getAtUserNames(
        widget.message,
        allMembersText: localizations.messageInputAllMembers,
      );
      if (mounted) {
        setState(() {
          _atUserNames = atUserNames;
          _atUserNamesLoaded = true;
          _isLoadingAtUserNames = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    final localizations = AppLocalization.of(context);
    final translatedTextMap =
        (widget.message.messagePayload as TextMessagePayload?)?.translatedText;

    Widget bubbleContent;
    if (widget.isTranslating) {
      bubbleContent = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor:
                  AlwaysStoppedAnimation<Color>(colors.textColorSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            localizations.translating,
            style: FontScheme.caption2Regular.copyWith(
              color: colors.textColorSecondary,
            ),
          ),
        ],
      );
    } else if (!_atUserNamesLoaded) {
      // Same gating as the legacy in-bubble translation: until names are
      // resolved, render nothing rather than a half-resolved string.
      //
      // 和遗留的气泡内翻译一样：在名字解析之前，不渲染内容，而不是显示半完成的字符串。
      return const SizedBox.shrink();
    } else {
      final originalText =
          (widget.message.messagePayload as TextMessagePayload?)?.text ?? '';
      final translatedDisplayText =
          TranslationTextParser.buildTranslatedDisplayText(
        originalText,
        translatedTextMap ?? {},
        _atUserNames,
      );
      bubbleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ExtendedText(
            translatedDisplayText,
            specialTextSpanBuilder: ChatSpecialTextSpanBuilder(
              colorScheme: colors,
              onTapUrl: _launchUrl,
              showAtBackground: true,
            ),
            style: FontScheme.caption2Regular.copyWith(
              color: widget.isSelf
                  ? colors.textColorAntiPrimary
                  : colors.textColorPrimary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                size: 10,
                color: widget.isSelf
                    ? colors.textColorAntiPrimary.withValues(alpha: 0.6)
                    : colors.textColorSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                localizations.translateDefaultTips,
                style: FontScheme.caption4Regular.copyWith(
                  color: widget.isSelf
                      ? colors.textColorAntiPrimary.withValues(alpha: 0.6)
                      : colors.textColorSecondary,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return GestureDetector(
      onLongPress: () {
        widget.onLongPress?.call(widget.message, _translationBubbleKey);
      },
      child: Container(
        key: _translationBubbleKey,
        margin: const EdgeInsets.only(top: 4),
        constraints: BoxConstraints(maxWidth: widget.maxWidth * 0.9),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        decoration: BoxDecoration(
          color: colors.bgColorBubbleReciprocal.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colors.strokeColorPrimary.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: bubbleContent,
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
}
