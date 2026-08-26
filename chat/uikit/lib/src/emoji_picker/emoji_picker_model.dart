class EmojiPickerModelItem {
  String path = "";
  String name = "";

  EmojiPickerModelItem({
    required this.name,
    required this.path,
  });
  static EmojiPickerModelItem fromJson(json) {
    return EmojiPickerModelItem(
        name: json["name"] ?? "", path: json["path"] ?? "");
  }

  Map<String, dynamic> toJson() {
    return Map<String, dynamic>.from({
      "name": name,
      "path": path,
    });
  }
}

class EmojiPickerModel {
  String name = "";
  List<EmojiPickerModelItem> stickers = [];
  int rowNum = 7;
  String iconPath = "";
  double? iconSize = 40;
  int type = 0; // 0 default 1 custom
  int index = 0;

  EmojiPickerModel({
    required this.iconPath,
    required this.stickers,
    required this.rowNum,
    required this.name,
    required this.type,
    required this.index,
    this.iconSize,
  });

  Map<String, dynamic> toJson() {
    return Map<String, dynamic>.from({
      "name": name,
      "stickers": stickers.map((e) => e.toJson()).toList(),
      "iconPath": iconPath,
      "rowNum": rowNum,
      "type": type,
      "index": index,
      "iconSize": iconSize,
    });
  }

  static EmojiPickerModel fromJson(json) {
    return EmojiPickerModel(
      name: json["name"] ?? "",
      stickers: (List<Map<String, dynamic>>.from((json["stickers"] ?? [])))
          .map((e) => EmojiPickerModelItem.fromJson(e))
          .toList(),
      iconPath: json["iconPath"] ?? "",
      rowNum: json["rowNum"] ?? 7,
      type: json["type"] ?? 0,
      index: json["index"] ?? 0,
      iconSize: json["iconSize"] ?? 40,
    );
  }
}
