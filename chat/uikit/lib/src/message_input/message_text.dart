import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import '../emoji_picker/emoji_picker_data.dart';

/// 单条文字消息的可见字符上限，换行也参与计数。
const messageTextCharacterLimit = 4000;

/// 只有实际可渲染的表情令牌才作为一个字符，未知令牌按原文计算。
final _emojiTokenPattern = RegExp(
  emojiPickerDataDefault.values.map(RegExp.escape).join('|'),
);

/// 按可见字素计数；SDK表情令牌和CRLF各视为一个字符。
int messageTextCharacterCount(String text) => text
    .replaceAll(_emojiTokenPattern, '\uFFFC')
    .replaceAll('\r\n', '\n')
    .characters
    .length;

/// 删除光标前的完整表情或字素，同时返回与删除边界一致的选区。
TextEditingValue deleteMessageCharacterBefore(TextEditingValue value) {
  final text = value.text;
  final caret = value.selection.baseOffset.clamp(0, text.length);
  if (caret == 0) return value;

  // SDK表情在底层由多个字符表示，删除时必须保留其原子性。
  for (final match in _emojiTokenPattern.allMatches(text)) {
    if (caret > match.start && caret <= match.end) {
      return value.copyWith(
        text: text.replaceRange(match.start, match.end, ''),
        selection: TextSelection.collapsed(offset: match.start),
        composing: TextRange.empty,
      );
    }
  }

  // 组合Emoji可能包含多个码点，不能按一个UTF-16单元退格。
  var start = 0;
  for (final character in text.characters) {
    final end = start + character.length;
    if (caret <= end) {
      return value.copyWith(
        text: text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
        composing: TextRange.empty,
      );
    }
    start = end;
  }
  return value;
}
