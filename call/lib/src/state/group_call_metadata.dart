import 'dart:convert';

/// 兼容只有一名受邀者的临时多人展示标识，不作为身份、群关系或会控权限依据。
class GroupCallMetadata {
  const GroupCallMetadata._();

  /// 宿主发起临时多人时放入 CallParams.userData 的展示元数据。
  static const temporaryMultiUserData = '{"zdoaCallScene":"multi","version":1}';

  /// 仅识别当前版本的明确标识；不解析失败、未知版本和其他业务载荷。
  static bool isTemporaryMulti(String userData) {
    try {
      final value = jsonDecode(userData);
      return value is Map<String, dynamic> &&
          value['version'] == 1 &&
          value['zdoaCallScene'] == 'multi';
    } catch (_) {
      return false;
    }
  }
}
