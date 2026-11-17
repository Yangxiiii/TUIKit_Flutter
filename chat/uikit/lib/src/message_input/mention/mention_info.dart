/// 将一次选人操作绑定到编辑区内的成员身份与原文位置。
class MentionInfo {
  /// 编辑区使用的全体标识；SDK 发送时由 SDK 常量提供。
  static const String atAllUserID = '__kImSDK_MesssageAtALL__';

  /// 腾讯 IM 用户标识，或编辑区全体标识。
  final String userID;

  /// 插入时的名称快照，不含 @ 和末尾分隔空格。
  final String displayName;

  /// 相对当前文字块的 UTF-16 起点，编辑时随正文移动。
  int startIndex;

  MentionInfo({
    required this.userID,
    required this.displayName,
    required this.startIndex,
  });

  bool get isAtAll => userID == atAllUserID;
  int get length => mentionText.length;
  int get endIndex => startIndex + length;
  String get mentionText => '@$displayName ';

  /// 按最终原文验证身份绑定，末尾分隔空格不属于消息定位。
  bool matches(String text) =>
      userID.trim().isNotEmpty &&
      displayName.isNotEmpty &&
      startIndex >= 0 &&
      endIndex - 1 <= text.length &&
      text.substring(startIndex, endIndex - 1) == '@$displayName';

  MentionInfo copyWith({
    String? userID,
    String? displayName,
    int? startIndex,
  }) {
    return MentionInfo(
      userID: userID ?? this.userID,
      displayName: displayName ?? this.displayName,
      startIndex: startIndex ?? this.startIndex,
    );
  }

  @override
  String toString() {
    return 'MentionInfo(userID: $userID, displayName: $displayName, startIndex: $startIndex, length: $length)';
  }
}
