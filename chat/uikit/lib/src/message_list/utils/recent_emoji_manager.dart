import 'package:flutter/widgets.dart';
import 'package:tuikit_atomic_x/base_component/utils/storage_util.dart';
import '../../emoji_picker/emoji_manager.dart';
import '../../emoji_picker/emoji_picker_model.dart';

/// 为表情键盘和消息回应提供共用近期目录；旧编码不参与快捷项，也不提供回退。
class RecentEmojiManager {
  /// 使用独立缓存键，弃用腾讯表情的近期排序。
  static const String _recentEmojiKey = 'zd_emoji_v1_recent_reactions';

  /// 最多保留二十项近期表情，避免缓存无限增长。
  static const int _maxRecentCount = 20;

  /// 表情键盘常用行与消息操作栏共用六项快捷表情。
  static const int _quickEmojiCount = 6;

  /// 只返回仍在当前目录中的令牌，损坏或过期的存储项不会进入面板。
  static Future<List<String>> getRecentEmojiIds() async {
    final result = await StorageUtil.get(_recentEmojiKey);
    if (result is! List) return [];
    return result
        .whereType<String>()
        .where((id) => EmojiManager.getEmoji(id) != null)
        .toSet()
        .toList();
  }

  /// 当前目录之外的回应不写入缓存，成功选择的表情移到最前。
  static Future<void> addRecentEmoji(String emojiId) async {
    if (EmojiManager.getEmoji(emojiId) == null) return;
    final recent = await getRecentEmojiIds();
    recent.remove(emojiId);
    recent.insert(0, emojiId);
    await StorageUtil.set<List<String>>(
        _recentEmojiKey, recent.take(_maxRecentCount).toList());
  }

  /// 先展示当前目录的近期项，再按原始目录顺序补足六项。
  static Future<List<EmojiPickerModelItem>> getQuickEmojis(
      BuildContext context) async {
    final recent = await getRecentEmojiIds();
    final ids = {...recent, ...EmojiManager.emojis.map((emoji) => emoji.name)};
    return ids
        .take(_quickEmojiCount)
        .map((id) => EmojiManager.getEmoji(id)!)
        .toList();
  }

  /// 完整回应选择器与文字面板使用相同顺序。
  static List<EmojiPickerModelItem> getAllEmojis(BuildContext context) =>
      EmojiManager.emojis.toList();

  /// 仅返回当前目录资源，旧腾讯回应不解析成图片。
  static String? getEmojiPath(String reactionID) =>
      EmojiManager.getEmoji(reactionID)?.path;

  /// 回应标识与文字令牌使用同一精确查找入口。
  static EmojiPickerModelItem? getEmojiByReactionID(
          BuildContext context, String reactionID) =>
      EmojiManager.getEmoji(reactionID);
}
