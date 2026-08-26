import 'package:flutter/cupertino.dart';

import 'emoji_picker_data.dart';
import 'emoji_picker_model.dart';
import 'emoji_picker_utils.dart';

class EmojiPickerConfig {
  static bool useDefaultSticker = true;
  static bool useDefaultCustomFace_4350 = false;
  static bool useDefaultCustomFace_4351 = false;
  static bool useDefaultCustomFace_4352 = false;

  static List<EmojiPickerModel> customStickerLists = [];

  static void loadData(BuildContext buildContext) {
    if (customStickerLists.isNotEmpty) {
      return;
    }

    var type = EmojiPickerUtils.getDeviceType(buildContext);
    if (useDefaultCustomFace_4350 == true) {
      // add default sticker to sticker list;
      List<EmojiPickerModelItem> stickers = [];
      emojiPickerDataCustomFace4350.forEach((key, value) {
        stickers.add(
          EmojiPickerModelItem(name: value, path: key),
        );
      });
      customStickerLists.insert(
        0,
        EmojiPickerModel(
          name: "",
          stickers: stickers,
          iconPath: emojiPickerDataCustomFace4350.keys.first,
          type: 1,
          rowNum: type == StickerDeviceScreenType.mobile ? 4 : 8,
          iconSize: 30,
          index: 1,
        ),
      );
    }
    if (useDefaultCustomFace_4351 == true) {
      // add default sticker to sticker list;
      List<EmojiPickerModelItem> stickers = [];
      emojiPickerDataCustomFace4351.forEach((key, value) {
        stickers.add(
          EmojiPickerModelItem(name: value, path: key),
        );
      });
      customStickerLists ??= [];
      customStickerLists!.insert(
        0,
        EmojiPickerModel(
          name: "",
          stickers: stickers,
          iconPath: emojiPickerDataCustomFace4351.keys.first,
          type: 1,
          iconSize: 30,
          rowNum: type == StickerDeviceScreenType.mobile ? 4 : 8,
          index: 2,
        ),
      );
    }
    if (useDefaultCustomFace_4352 == true) {
      // add default sticker to sticker list;
      List<EmojiPickerModelItem> stickers = [];
      emojiPickerDataCustomFace4352.forEach((key, value) {
        stickers.add(
          EmojiPickerModelItem(name: value, path: key),
        );
      });
      customStickerLists ??= [];
      customStickerLists!.insert(
        0,
        EmojiPickerModel(
          name: "",
          stickers: stickers,
          iconPath: emojiPickerDataCustomFace4352.keys.first,
          type: 1,
          iconSize: 30,
          rowNum: type == StickerDeviceScreenType.mobile ? 4 : 6,
          index: 3,
        ),
      );
    }
    if (useDefaultSticker == true) {
      // add default sticker to sticker list;
      List<EmojiPickerModelItem> stickers = [];
      emojiPickerDataDefault.forEach((key, value) {
        stickers.add(
          EmojiPickerModelItem(name: value, path: key),
        );
      });
      customStickerLists ??= [];
      customStickerLists!.insert(
        0,
        EmojiPickerModel(
          name: "All Stickers",
          stickers: stickers,
          iconPath: emojiPickerDataDefault.keys.first,
          type: 0,
          rowNum: type == StickerDeviceScreenType.mobile ? 7 : 10,
          index: 0,
        ),
      );
    }
  }

  static void fromJson(Map<String, dynamic> json) {
    EmojiPickerConfig.useDefaultSticker = json["useDefaultSticker"] ?? true;
    EmojiPickerConfig.customStickerLists =
        (List<Map<String, dynamic>>.from(json["customStickerLists"] ?? []))
            .map((e) => EmojiPickerModel.fromJson(e))
            .toList();
    EmojiPickerConfig.useDefaultCustomFace_4350 =
        json["useDefaultCustomFace_4350"] ?? false;
    EmojiPickerConfig.useDefaultCustomFace_4351 =
        json["useDefaultCustomFace_4351"] ?? false;
    EmojiPickerConfig.useDefaultCustomFace_4352 =
        json["useDefaultCustomFace_4352"] ?? false;
  }
}
