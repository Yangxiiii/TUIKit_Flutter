import '../../emoji_picker/emoji_manager.dart';

/// Removes emoji from [text] so they are not spoken by TTS.
///
/// Handles both IM custom emoji tokens (e.g. `[微笑]`) and universal unicode
/// emoji, reusing [EmojiManager.findEmojiKeyListFromText] (regex-based, no
/// async/asset dependency).
///
/// 从 [text] 中移除表情符号，这样 TTS 就不会读出它们。
///
/// 表情符号，重用 [EmojiManager.findEmojiKeyListFromText]（基于正则表达式，无异步/资源依赖）。
String sanitizeTextForTts(String text) {
  if (text.isEmpty) return text;
  var result = text;
  for (final key in EmojiManager.findEmojiKeyListFromText(text)) {
    if (key.isEmpty) continue;
    result = result.replaceAll(key, '');
  }
  // Collapse whitespace left behind by removed emoji.
  //
  // 折叠被移除表情符号留下的空白。
  result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
  return result;
}
