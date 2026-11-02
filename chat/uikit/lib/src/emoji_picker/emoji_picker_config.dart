import 'package:flutter/cupertino.dart';

import 'emoji_manager.dart';
import 'emoji_picker_model.dart';
import 'emoji_picker_utils.dart';

/// 根据已注册的唯一表情目录构建面板，不再提供腾讯内置表情包开关。
class EmojiPickerConfig {
  /// 当前设备对应的面板分组；每次加载均从唯一目录重建，避免保留旧目录缓存。
  static List<EmojiPickerModel> customStickerLists = [];

  /// 在面板展示前按业务顺序准备表情，空目录不提供默认回退。
  static void loadData(BuildContext buildContext) {
    final stickers = EmojiManager.emojis.toList();
    final type = EmojiPickerUtils.getDeviceType(buildContext);
    customStickerLists = stickers.isEmpty
        ? []
        : [
            EmojiPickerModel(
              name: 'ZDEmoji',
              stickers: stickers,
              iconPath: stickers.first.path,
              type: 0,
              rowNum: type == StickerDeviceScreenType.mobile ? 7 : 10,
              index: 0,
            ),
          ];
  }
}
