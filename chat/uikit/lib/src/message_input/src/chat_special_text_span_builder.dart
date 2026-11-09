import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/common/utils/uikit_util.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_markdown_format.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_markdown_span.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text/extended_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 在聊天输入框中统一渲染表情、链接和 Markdown 编辑样式。
///
/// 显示样式不改变底层原始文本，确保光标位置、草稿和发送内容仍使用同一份 Markdown。
class ChatSpecialTextSpanBuilder extends SpecialTextSpanBuilder {
  /// 直接定位表情和链接起始标记，避免逐字符复制此前的普通正文。
  static final _chatTokenStartPattern = RegExp(
      '${RegExp.escape(HttpText.flag)}|${RegExp.escape(EmojiText.flag)}');

  /// 点击可识别 URL 时的回调。
  final ValueChanged<String> onTapUrl;

  /// 输入框当前使用的语义颜色。
  SemanticColorScheme colorScheme;

  /// 是否为 ExtendedTextField 输出带原文映射的隐藏标签。
  final bool mapMarkdownMarkers;

  ChatSpecialTextSpanBuilder({
    this.showAtBackground = false,
    this.mapMarkdownMarkers = false,
    required this.onTapUrl,
    required this.colorScheme,
  });

  /// 是否为 @ 提醒显示输入背景。
  final bool showAtBackground;

  /// 子类支持额外令牌时，将对应的起始标记加入此规则。
  RegExp get tokenStartPattern => _chatTokenStartPattern;

  @override
  TextSpan build(
    String data, {
    TextStyle? textStyle,
    SpecialTextGestureTapCallback? onTap,
  }) {
    final source = _buildTokenSpans(data, textStyle, onTap);
    if (!richContentMarkdownStartPattern.hasMatch(data)) return source;

    final children = <InlineSpan>[];
    var sourceOffset = 0;
    for (final span in source.children ?? const <InlineSpan>[]) {
      if (span is TextSpan &&
          span is! SpecialInlineSpanBase &&
          span.children == null &&
          span.text != null) {
        children.addAll(
          _buildMarkdownSpans(
            span.text!,
            span.style ?? textStyle,
            sourceOffset,
          ),
        );
      } else {
        children.add(span);
      }
      final specialSpan =
          span is SpecialInlineSpanBase ? span as SpecialInlineSpanBase : null;
      sourceOffset +=
          specialSpan?.actualText.length ?? span.toPlainText().length;
    }
    return TextSpan(children: children, style: source.style ?? textStyle);
  }

  /// 按起始标记扫描令牌，普通文字整段输出并保留原文偏移。
  TextSpan _buildTokenSpans(
    String data,
    TextStyle? textStyle,
    SpecialTextGestureTapCallback? onTap,
  ) {
    if (data.isEmpty) return TextSpan(text: '', style: textStyle);
    final children = <InlineSpan>[];
    var offset = 0;
    for (final match in tokenStartPattern.allMatches(data)) {
      // 跳过已被前一个令牌消费的范围；其中的起始标记属于该令牌正文。
      if (match.start < offset) continue;
      final token = createSpecialText(
        match[0]!,
        textStyle: textStyle,
        onTap: onTap,
        index: match.end - 1,
      );
      if (token == null) continue;
      if (offset < match.start) {
        children.add(TextSpan(
          text: data.substring(offset, match.start),
          style: textStyle,
        ));
      }
      final end = data.indexOf(token.endFlag, match.end);
      // 输入尚未闭合时保留原文，包括它后面的候选标记。
      if (end < 0) {
        offset = match.start;
        break;
      }
      offset = end + token.endFlag.length;
      token.appendContent(data.substring(match.end, offset));
      children.add(token.finishText());
    }
    if (offset < data.length) {
      children.add(TextSpan(text: data.substring(offset), style: textStyle));
    }
    return TextSpan(children: children, style: textStyle);
  }

  /// 将普通文本分成原始标记和可见内容，并按输入控件选择等长或原文映射标签。
  List<InlineSpan> _buildMarkdownSpans(
    String text,
    TextStyle? baseStyle,
    int sourceStart,
  ) {
    final spans = <InlineSpan>[];
    var offset = 0;
    var plainStart = 0;
    // 仅隐藏已经完整配对的共享格式片段，未闭合的输入和普通文字必须原样保留。
    while (
        (offset = text.indexOf(richContentMarkdownStartPattern, offset)) >= 0) {
      final combined = _formatAt(text, offset, sourceStart, baseStyle);
      final match = combined == null
          ? richContentMarkdownPattern.matchAsPrefix(text, offset)
          : null;
      if (combined == null && match == null) {
        offset++;
        continue;
      }
      if (plainStart < offset) {
        spans.add(TextSpan(
            text: text.substring(plainStart, offset), style: baseStyle));
      }
      if (combined != null) {
        spans.add(combined.span);
        offset = combined.end;
      } else {
        spans.add(_buildMarkdownSpan(match!, sourceStart, baseStyle));
        offset = match.end;
      }
      plainStart = offset;
    }
    if (plainStart < text.length) {
      spans.add(TextSpan(text: text.substring(plainStart), style: baseStyle));
    }
    return spans.isEmpty ? [TextSpan(text: text, style: baseStyle)] : spans;
  }

  /// 用共用格式边界叠加样式，隐藏标签仍保留编辑器所需的原文偏移。
  _CombinedFormatMatch? _formatAt(
    String text,
    int start,
    int sourceStart,
    TextStyle? baseStyle,
  ) {
    final nested = parseRichContentMarkdownFormatAt(text, start);
    if (nested == null) return null;
    final markers = nested.markers;
    final closing = markers.reversed.join();

    final contentStyle = richContentMarkdownStyle(
      baseStyle ?? const TextStyle(),
      markers,
    );
    final hiddenStyle = (baseStyle ?? const TextStyle()).copyWith(
      color: Colors.transparent,
      fontSize: 0.01,
      height: 0.01,
    );
    return _CombinedFormatMatch(
      nested.closeEnd,
      TextSpan(
        children: [
          _hiddenMarkdownMarker(
            markers.join(),
            sourceStart + start,
            hiddenStyle,
          ),
          TextSpan(
            style: contentStyle,
            // 子格式继续使用同一解析入口，原文偏移累加以保留选择和删除位置。
            children: _buildMarkdownSpans(
              text.substring(nested.contentStart, nested.contentEnd),
              contentStyle,
              sourceStart + nested.contentStart,
            ),
          ),
          _hiddenMarkdownMarker(
            closing,
            sourceStart + nested.contentEnd,
            hiddenStyle,
          ),
        ],
      ),
    );
  }

  /// 为链接和代码保留隐藏标记及原文偏移，正文格式由共用入口递归处理。
  InlineSpan _buildMarkdownSpan(
    Match match,
    int sourceStart,
    TextStyle? baseStyle,
  ) {
    final hiddenStyle = (baseStyle ?? const TextStyle()).copyWith(
      color: Colors.transparent,
      fontSize: 0.01,
      height: 0.01,
    );
    // 链接的标签正文可以继续嵌套格式，地址仍作为不可见原文保存，避免影响编辑位置。
    if (match.group(10) case final label?) {
      final linkStyle = richContentMarkdownStyle(
        baseStyle ?? const TextStyle(),
        const ['~'],
      ).copyWith(color: colorScheme.textColorLink);
      return TextSpan(
        children: [
          _hiddenMarkdownMarker('[', sourceStart + match.start, hiddenStyle),
          TextSpan(
            style: linkStyle,
            children: _buildMarkdownSpans(
                label, linkStyle, sourceStart + match.start + 1),
          ),
          _hiddenMarkdownMarker(
            '](${match.group(11)})',
            sourceStart + match.start + label.length + 1,
            hiddenStyle,
          ),
        ],
      );
    }
    // 代码内容不进入格式解析，星号及波浪号在这里都是用户需要保留的字面内容。
    final code = match.group(13) ?? '';
    return TextSpan(
      children: [
        _hiddenMarkdownMarker('```', sourceStart + match.start, hiddenStyle),
        TextSpan(
          text: code,
          style: (baseStyle ?? const TextStyle()).copyWith(
            // 代码块沿用宿主字体，避免输入与普通消息使用不同字族。
            backgroundColor: colorScheme.bgColorInput,
          ),
        ),
        _hiddenMarkdownMarker('```', sourceStart + match.end - 3, hiddenStyle),
      ],
    );
  }

  /// 为普通 TextField 保留等长标签，为 ExtendedTextField 建立原文偏移映射。
  InlineSpan _hiddenMarkdownMarker(
    String marker,
    int start,
    TextStyle hiddenStyle,
  ) {
    if (!mapMarkdownMarkers) {
      return TextSpan(text: marker, style: hiddenStyle);
    }
    return SpecialTextSpan(
      text: '',
      actualText: marker,
      start: start,
      deleteAll: true,
      style: hiddenStyle,
    );
  }

  @override
  SpecialText? createSpecialText(
    String flag, {
    TextStyle? textStyle,
    SpecialTextGestureTapCallback? onTap,
    int? index,
  }) {
    if (flag == '') {
      return null;
    }

    /// index 是起始标记的结束索引，因此文本起始索引应为 index-(flag.length-1)
    if (isStart(flag, HttpText.flag)) {
      return HttpText(
        colorScheme: colorScheme,
        textStyle,
        onTap,
        onTapUrl: onTapUrl,
        start: index! - (HttpText.flag.length - 1),
      );
    } else if (isStart(flag, EmojiText.flag)) {
      return EmojiText(
        colorScheme: colorScheme,
        textStyle,
        start: index! - (EmojiText.flag.length - 1),
      );
    }
    return null;
  }
}

final class _CombinedFormatMatch {
  final int end;
  final TextSpan span;

  const _CombinedFormatMatch(this.end, this.span);
}

/// 为已注册业务表情创建带原文偏移的图片，保留输入、复制与整项删除语义。
class EmojiText extends SpecialText {
  /// 仅识别业务表情命名空间，旧腾讯令牌不进入图片解析。
  static const String flag = '[ZDEmoji_';

  /// 令牌在原文中的UTF-16偏移，供输入框定位与删除。
  final int? start;

  /// 当前语义颜色，由输入与正文渲染入口提供。
  SemanticColorScheme colorScheme;

  EmojiText(TextStyle? textStyle, {this.start, required this.colorScheme})
      : super(EmojiText.flag, ']', textStyle);

  @override
  InlineSpan finishText() {
    final String key = toString();
    final emoji = EmojiManager.getEmoji(key);
    // 未知令牌可能来自其他客户端，保留原文以避免空路径图片和错误的整项删除。
    if (emoji == null) return TextSpan(text: key, style: textStyle);

    return ImageSpan(
      AssetImage(emoji.path, package: EmojiManager.assetPackage),
      actualText: key,
      imageWidth: 22,
      imageHeight: 22,
      start: start!,
      margin: const EdgeInsets.all(0),
    );
  }
}

class HttpText extends SpecialText {
  static const String flag = '!@TURL#*&\$';
  final int? start;
  SemanticColorScheme colorScheme;

  HttpText(
    TextStyle? textStyle,
    SpecialTextGestureTapCallback? onTap, {
    required this.colorScheme,
    required this.onTapUrl,
    this.start,
  }) : super(flag, flag, textStyle, onTap: onTap);
  final ValueChanged<String> onTapUrl;

  @override
  InlineSpan finishText() {
    final String text = getContent();
    final isValidUrl = UIKitUtil.urlReg.hasMatch(text);
    return isValidUrl
        ? SpecialTextSpan(
            text: text,
            actualText: toString(),
            start: start!,

            ///caret can move into special text
            ///
            /// 光标可以移动到特殊文本中
            deleteAll: true,
            style: TextStyle(color: colorScheme.textColorLink),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                onTapUrl(text);
              },
          )
        : TextSpan(text: toString(), style: textStyle);
  }
}
