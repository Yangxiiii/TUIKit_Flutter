import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/common/utils/uikit_util.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_picker_data.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_markdown_format.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_markdown_span.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text/extended_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 在聊天输入框中统一渲染表情、链接和 Markdown 编辑样式。
///
/// 显示样式不改变底层原始文本，确保光标位置、草稿和发送内容仍使用同一份 Markdown。
class ChatSpecialTextSpanBuilder extends SpecialTextSpanBuilder {
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

  @override
  TextSpan build(
    String data, {
    TextStyle? textStyle,
    SpecialTextGestureTapCallback? onTap,
  }) {
    final source = super.build(data, textStyle: textStyle, onTap: onTap);
    if (!richContentMarkdownPattern.hasMatch(data)) return source;

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
    while (offset < text.length) {
      final combined = _formatAt(text, offset, sourceStart, baseStyle);
      final match = richContentMarkdownPattern.matchAsPrefix(text, offset);
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

    ///index is end index of start flag, so text start index should be index-(flag.length-1)
    ///
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

class EmojiText extends SpecialText {
  static const String flag = '[TUIEmoji_';
  final int? start;
  SemanticColorScheme colorScheme;

  EmojiText(TextStyle? textStyle, {this.start, required this.colorScheme})
      : super(EmojiText.flag, ']', textStyle);

  @override
  InlineSpan finishText() {
    final String key = toString();
    String res = "";
    if (emojiPickerDataDefault.containsValue(key)) {
      emojiPickerDataDefault.forEach((emojiAssets, value) {
        if (value == key) {
          res = emojiAssets;
        }
      });
    }

    return ImageSpan(
      AssetImage(res, package: 'tencent_chat_uikit'),
      actualText: key,
      imageWidth: 22,
      imageHeight: 22,
      start: start!,
      // fit: BoxFit.cover,
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

String getMarkDownStringData({String? text}) {
  String formattedText = _addSpaceAfterLeftBracket(
    _addSpaceBeforeHttp(_replaceSingleNewlineWithTwo(text ?? "")),
  );
  RegExp emojiExp = RegExp(r"\[TUIEmoji_(\w{2,})\]");
  formattedText = formattedText.replaceAllMapped(emojiExp, (match) {
    String emojiName = match.group(0) ?? "";
    if (emojiName.isNotEmpty) {
      if (emojiPickerDataDefault.containsValue(emojiName)) {
        emojiPickerDataDefault.forEach((emojiAssets, value) {
          if (value == emojiName) {
            emojiName = '![$value](resource:$emojiAssets#30x30)';
          }
        });
      }
    }

    return emojiName;
  });

  return formattedText;
}

String _addSpaceAfterLeftBracket(String inputText) {
  return inputText.splitMapJoin(
    RegExp(r'<\w+[^<>]*>'),
    onMatch: (match) {
      return match.group(0)!.replaceFirst('<', '< ');
    },
    onNonMatch: (text) => text,
  );
}

String _replaceSingleNewlineWithTwo(String inputText) {
  return inputText.split('\n').join('\n\n');
}

String _addSpaceBeforeHttp(String inputText) {
  return inputText.splitMapJoin(
    RegExp(r'http'),
    onMatch: (match) {
      return ' http';
    },
    onNonMatch: (text) => text,
  );
}
