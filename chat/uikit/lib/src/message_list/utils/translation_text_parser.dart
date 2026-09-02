import 'package:atomic_x_core/atomicxcore.dart';
import 'package:tencent_chat_uikit/src/emoji_picker/emoji_manager.dart';
import 'package:tencent_chat_uikit/src/message_input/mention/mention_info.dart';

/// Parser for text translation that handles emoji and @ mentions.
/// This implementation mirrors iOS/Android TranslationTextParser logic.
///
/// 用于处理表情符号和@提及的文本翻译解析器。此实现与iOS/Android的TranslationTextParser逻辑一致。
class TranslationTextParser {
  static const String kSplitStringResultKey = 'result';
  static const String kSplitStringTextKey = 'text';
  static const String kSplitStringTextIndexKey = 'textIndex';

  /// Parse text message and return components for translation.
  /// - [text]: The original text to parse
  /// - [atUserNames]: List of @ user names (without @ prefix)
  /// Returns: Map with "result", "text", and "textIndex" keys
  ///
  /// 解析文本消息并返回用于翻译的组件。- [text]：要解析的原始文本 - [atUserNames]：@用户名列表（不含@前缀）
  /// 返回：包含“result”、“text”和“textIndex”键的映射
  static Map<String, dynamic>? splitTextByEmojiAndAtUsers(
    String text, {
    List<String>? atUserNames,
  }) {
    if (text.isEmpty) return null;

    List<String> result = [];

    // Build @user strings with @ prefix and trailing space
    //
    // 构建带@前缀和尾随空格的@用户字符串
    List<String> atUsers = [];
    atUserNames?.forEach((user) {
      atUsers.add('@$user ');
    });

    // Find @user ranges in string
    //
    // 查找字符串中的@用户范围
    List<_TextRange> atUserRanges = _rangeOfAtUsers(atUsers, text);

    // Split text using @user ranges
    //
    // 使用@用户范围拆分文本
    var splitResult = _splitArrayWithRanges(atUserRanges, text);
    if (splitResult == null) return null;

    List<String> splitArrayByAtUser = splitResult.strings;
    Set<int> atUserIndex = splitResult.specialIndexes.toSet();

    // Iterate split array to match emoji in non-@ parts
    //
    // 遍历拆分数组，在非@部分匹配表情符号
    int k = -1;
    List<int> textIndexArray = [];

    for (int i = 0; i < splitArrayByAtUser.length; i++) {
      String str = splitArrayByAtUser[i];
      if (atUserIndex.contains(i)) {
        // str is @user info, keep as-is
        //
        // str是@用户信息，保持原样
        result.add(str);
        k++;
      } else {
        // str is not @user info, parse emoji
        //
        // str不是@用户信息，解析表情符号
        List<_TextRange> emojiRanges = _matchTextByEmoji(str);
        var emojiSplitResult = _splitArrayWithRanges(emojiRanges, str);
        if (emojiSplitResult != null) {
          List<String> splitArrayByEmoji = emojiSplitResult.strings;
          Set<int> emojiIndex = emojiSplitResult.specialIndexes.toSet();

          for (int j = 0; j < splitArrayByEmoji.length; j++) {
            String tmp = splitArrayByEmoji[j];
            result.add(tmp);
            k++;
            if (!emojiIndex.contains(j)) {
              // This is text that needs translation
              //
              // 这是需要翻译的文本
              textIndexArray.add(k);
            }
          }
        }
      }
    }

    // Extract text array from result using indices
    //
    // 使用索引从结果中提取文本数组
    List<String> textArray = [];
    for (int n in textIndexArray) {
      if (n < result.length) {
        textArray.add(result[n]);
      }
    }

    return {
      kSplitStringResultKey: result,
      kSplitStringTextKey: textArray,
      kSplitStringTextIndexKey: textIndexArray,
    };
  }

  /// Reconstruct translated text by replacing text segments with translations.
  ///
  /// 通过用翻译文本替换文本段重建翻译后的文本。
  static String? replacedStringWithArray(
    List<String> array,
    List<int> indexArray,
    Map<String, String>? replaceDict,
  ) {
    if (replaceDict == null) return null;
    List<String> mutableArray = List.from(array);

    for (int value in indexArray) {
      if (value < 0 || value >= mutableArray.length) continue;
      String? replacement = replaceDict[mutableArray[value]];
      if (replacement != null) {
        mutableArray[value] = replacement;
      }
    }

    return mutableArray.join();
  }

  /// Get @ user names from message's atUserList.
  /// Returns a list of user display names (without @ prefix)
  /// [allMembersText] - The localized text for "All" (e.g., "All", "所有人")
  ///
  /// 从消息的 atUserList 获取 @ 用户名。返回用户显示名列表（不带 @ 前缀）
  static Future<List<String>?> getAtUserNames(
    MessageInfo? messageInfo, {
    String allMembersText = 'All',
  }) async {
    if (messageInfo == null || messageInfo.atUserList.isEmpty) {
      return null;
    }

    List<String> atUserIDs = messageInfo.atUserList;

    // Separate @All from regular users
    //
    // 将 @All 与普通用户分开
    List<String> regularUserIDs = [];
    List<int> atAllIndexes = [];

    for (int i = 0; i < atUserIDs.length; i++) {
      String userID = atUserIDs[i];
      if (userID == MentionInfo.atAllUserID) {
        atAllIndexes.add(i);
      } else {
        regularUserIDs.add(userID);
      }
    }

    // If only @All
    if (regularUserIDs.isEmpty) {
      // Use localized "All" as the display name for @All
      //
      // 使用本地化的“全部”作为 @All 的显示名
      return List.filled(atAllIndexes.length, allMembersText);
    }

    // Fetch user info for regular users using ContactStore
    //
    // 使用 ContactStore 获取普通用户信息
    List<String> names = List.filled(regularUserIDs.length, '');

    final handler =
        await ContactStore.shared.getContactInfo(userIDList: regularUserIDs);
    if (handler.isSuccess) {
      for (int index = 0; index < regularUserIDs.length; index++) {
        final userID = regularUserIDs[index];
        final contactInfo = handler.contactInfoList
            .where((c) => c.userID == userID)
            .firstOrNull;
        if (contactInfo != null && (contactInfo.nickname?.isNotEmpty == true)) {
          names[index] = contactInfo.nickname!;
        } else {
          names[index] = userID;
        }
      }
    } else {
      for (int index = 0; index < regularUserIDs.length; index++) {
        names[index] = regularUserIDs[index];
      }
    }

    // Restore @All at original positions
    //
    // 在原始位置恢复 @All
    for (int idx in atAllIndexes) {
      if (idx <= names.length) {
        names.insert(idx, allMembersText);
      }
    }

    return names;
  }

  // Private helpers
  //
  // 私有辅助函数

  static List<_TextRange> _rangeOfAtUsers(List<String> atUsers, String string) {
    if (atUsers.isEmpty) return [];

    // Find all '@' positions
    //
    // 查找所有 '@' 的位置
    List<int> atPositions = [];
    for (int i = 0; i < string.length; i++) {
      if (string[i] == '@') {
        atPositions.add(i);
      }
    }

    List<_TextRange> result = [];
    Set<int> usedPositions = {};

    for (String user in atUsers) {
      for (int idx in atPositions) {
        if (usedPositions.contains(idx)) continue;
        if (string.length >= user.length &&
            idx <= string.length - user.length) {
          String substring = string.substring(idx, idx + user.length);
          if (substring == user) {
            result.add(_TextRange(idx, user.length));
            usedPositions.add(idx);
          }
        }
      }
    }
    return result;
  }

  static _SplitResult? _splitArrayWithRanges(
      List<_TextRange> ranges, String string) {
    if (ranges.isEmpty) return _SplitResult([string], []);
    if (string.isEmpty) return null;

    // Sort by location
    //
    // 按位置排序
    ranges.sort((a, b) => a.location.compareTo(b.location));

    List<String> result = [];
    List<int> indexes = [];
    int prev = 0;
    int j = -1;

    for (int i = 0; i < ranges.length; i++) {
      _TextRange cur = ranges[i];

      // Add text before current range
      //
      // 在当前范围前添加文本
      if (cur.location > prev) {
        String str = string.substring(prev, cur.location);
        result.add(str);
        j++;
      }

      // Add content within current range (special element)
      //
      // 在当前范围内添加内容（特殊元素）
      String str = string.substring(cur.location, cur.location + cur.length);
      result.add(str);
      j++;
      indexes.add(j);

      prev = cur.location + cur.length;

      // Handle text after last range
      //
      // 处理最后一个范围后的文本
      if (i == ranges.length - 1 && prev < string.length) {
        String last = string.substring(prev);
        result.add(last);
      }
    }

    return _SplitResult(result, indexes);
  }

  /// Match emoji in text using EmojiManager.findEmojiKeyListFromText.
  /// Returns ranges of emoji positions in the text.
  ///
  /// 使用 EmojiManager.findEmojiKeyListFromText 匹配文本中的表情。返回文本中表情的位置范围。
  static List<_TextRange> _matchTextByEmoji(String text) {
    List<_TextRange> result = [];

    // Get emoji list from EmojiManager
    //
    // 从 EmojiManager 获取表情列表
    List<String> emojiList = EmojiManager.findEmojiKeyListFromText(text);
    if (emojiList.isEmpty) return result;

    // Find positions of each emoji in text
    //
    // 查找每个表情在文本中的位置
    Set<int> usedPositions = {};

    for (String emoji in emojiList) {
      int searchStart = 0;
      while (searchStart < text.length) {
        int index = text.indexOf(emoji, searchStart);
        if (index == -1) break;

        // Skip if this position is already used
        //
        // 如果该位置已被使用则跳过
        if (!usedPositions.contains(index)) {
          result.add(_TextRange(index, emoji.length));
          usedPositions.add(index);
          searchStart = index + emoji.length;
        } else {
          searchStart = index + 1;
        }
      }
    }

    return result;
  }

  /// Build translated display text from original text and translation map.
  /// This handles emoji and @ reconstruction.
  ///
  /// 根据原文和翻译映射构建翻译显示文本。这个会处理表情和@重建。
  static String buildTranslatedDisplayText(
    String originalText,
    Map<String, String> translatedTextMap,
    List<String>? atUserNames,
  ) {
    if (translatedTextMap.isEmpty) return originalText;

    // Parse the original text
    //
    // 解析原文
    final splitResult = splitTextByEmojiAndAtUsers(
      originalText,
      atUserNames: atUserNames,
    );

    if (splitResult == null) {
      // If parsing fails, try direct lookup
      return translatedTextMap[originalText] ?? originalText;
    }

    final resultArray =
        splitResult[kSplitStringResultKey] as List<String>? ?? [];
    final textIndexArray =
        splitResult[kSplitStringTextIndexKey] as List<int>? ?? [];

    // Reconstruct with translations
    //
    // 用翻译重建
    final translated = replacedStringWithArray(
      resultArray,
      textIndexArray,
      translatedTextMap,
    );

    return translated ?? originalText;
  }
}

class _TextRange {
  final int location;
  final int length;
  _TextRange(this.location, this.length);
}

class _SplitResult {
  final List<String> strings;
  final List<int> specialIndexes;
  _SplitResult(this.strings, this.specialIndexes);
}
