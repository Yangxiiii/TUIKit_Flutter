import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/common/utils/uikit_util.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_picker_data.dart';
import 'package:tencent_chat_uikit/src/message_input/rich_content_draft.dart';
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

  static final RegExp _markdownPattern = RegExp(
    r'(\*\*([^*\n]+)\*\*)|(~~([^~\n]+)~~)|(\*([^*\n]+)\*)|(~([^~\n]+)~)|(\[([^\]\n]+)\]\((https?://[^)\s]+)\))|(```([\s\S]*?)```)',
  );
  ChatSpecialTextSpanBuilder({
    this.showAtBackground = false,
    this.mapMarkdownMarkers = false,
    required this.onTapUrl,
    required this.colorScheme,
  });

  /// whether show background for @somebody
  ///
  /// 是否为 @某人 显示背景
  final bool showAtBackground;

  @override
  TextSpan build(
    String data, {
    TextStyle? textStyle,
    SpecialTextGestureTapCallback? onTap,
  }) {
    final source = super.build(data, textStyle: textStyle, onTap: onTap);
    if (!_markdownPattern.hasMatch(data)) return source;

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
    while (offset < text.length) {
      final combined = _nestedFormatAt(text, offset, sourceStart, baseStyle);
      final match = _markdownPattern.matchAsPrefix(text, offset);
      if (combined == null && match == null) {
        offset++;
        continue;
      }
      if (plainStart < offset) {
        spans.add(TextSpan(text: text.substring(plainStart, offset)));
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
      spans.add(TextSpan(text: text.substring(plainStart)));
    }
    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }

  /// 识别任意顺序的多层格式，并把全部样式叠加到同一段文字。
  _CombinedFormatMatch? _nestedFormatAt(
    String text,
    int start,
    int sourceStart,
    TextStyle? baseStyle,
  ) {
    final nested = parseNestedMarkdownFormat(text, start);
    if (nested == null) return null;
    final markers = nested.markers;
    final closing = markers.reversed.join();

    final decorations = <TextDecoration>[];
    if (markers.contains('~~')) decorations.add(TextDecoration.lineThrough);
    if (markers.contains('~')) decorations.add(TextDecoration.underline);
    final contentStyle = (baseStyle ?? const TextStyle()).copyWith(
      fontWeight: markers.contains('**') ? FontWeight.bold : null,
      fontStyle: markers.contains('*') ? FontStyle.italic : null,
      decoration:
          decorations.isEmpty ? null : TextDecoration.combine(decorations),
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
            text: text.substring(nested.contentStart, nested.contentEnd),
            style: contentStyle,
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

  /// 把单个 Markdown 匹配转换为带正文样式和隐藏标签的片段。
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
    if (match.group(2) case final content?) {
      return _markedSpan(
        '**',
        content,
        sourceStart + match.start,
        baseStyle?.copyWith(fontWeight: FontWeight.bold) ??
            const TextStyle(fontWeight: FontWeight.bold),
        hiddenStyle,
      );
    }
    if (match.group(4) case final content?) {
      return _markedSpan(
        '~~',
        content,
        sourceStart + match.start,
        baseStyle?.copyWith(decoration: TextDecoration.lineThrough) ??
            const TextStyle(decoration: TextDecoration.lineThrough),
        hiddenStyle,
      );
    }
    if (match.group(6) case final content?) {
      return _markedSpan(
        '*',
        content,
        sourceStart + match.start,
        baseStyle?.copyWith(fontStyle: FontStyle.italic) ??
            const TextStyle(fontStyle: FontStyle.italic),
        hiddenStyle,
      );
    }
    if (match.group(8) case final content?) {
      return _markedSpan(
        '~',
        content,
        sourceStart + match.start,
        baseStyle?.copyWith(decoration: TextDecoration.underline) ??
            const TextStyle(decoration: TextDecoration.underline),
        hiddenStyle,
      );
    }
    if (match.group(10) case final label?) {
      return TextSpan(
        children: [
          _hiddenMarkdownMarker('[', sourceStart + match.start, hiddenStyle),
          TextSpan(
            text: label,
            style: (baseStyle ?? const TextStyle()).copyWith(
              color: colorScheme.textColorLink,
              decoration: TextDecoration.underline,
            ),
          ),
          _hiddenMarkdownMarker(
            '](${match.group(11)})',
            sourceStart + match.start + label.length + 1,
            hiddenStyle,
          ),
        ],
      );
    }
    final code = match.group(13) ?? '';
    return TextSpan(
      children: [
        _hiddenMarkdownMarker('```', sourceStart + match.start, hiddenStyle),
        TextSpan(
          text: code,
          style: (baseStyle ?? const TextStyle()).copyWith(
            fontFamily: 'monospace',
            backgroundColor: colorScheme.bgColorInput,
          ),
        ),
        _hiddenMarkdownMarker('```', sourceStart + match.end - 3, hiddenStyle),
      ],
    );
  }

  /// 组合一对相同标签及其中的可见正文。
  TextSpan _markedSpan(
    String marker,
    String content,
    int start,
    TextStyle contentStyle,
    TextStyle hiddenStyle,
  ) {
    return TextSpan(
      children: [
        _hiddenMarkdownMarker(marker, start, hiddenStyle),
        TextSpan(text: content, style: contentStyle),
        _hiddenMarkdownMarker(
          marker,
          start + marker.length + content.length,
          hiddenStyle,
        ),
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
