/// 表情目录项；令牌、展示名称和资源保持同源，不保存消息发送状态。
class EmojiPickerModelItem {
  /// 基准资源路径，加载时使用当前目录的所属包。
  final String path;

  /// 包含方括号的完整令牌，用于混合文字、表情消息自定义数据和回应标识。
  final String name;

  /// 原始资源的展示名称，不用作消息传输键。
  final String label;

  const EmojiPickerModelItem({
    required this.name,
    required this.path,
    required this.label,
  });
}

/// 表情面板分组；由当前目录构建，不提供旧表情包配置。
class EmojiPickerModel {
  /// 分组展示名称。
  String name = "";

  /// 按业务顺序排列的表情目录。
  List<EmojiPickerModelItem> stickers = [];

  /// 每行表情数量，移动端默认七列。
  int rowNum = 7;

  /// 分组标签使用的基准资源路径。
  String iconPath = "";

  /// 标签图标逻辑尺寸。
  double? iconSize = 40;

  /// 发送类型；零表示插入文字令牌。
  int type = 0;

  /// 面板分组编号。
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
}
