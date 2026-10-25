import 'dart:convert';

/// 识别跨业务自定义消息中的大文件协议；未知版本或损坏字段交还通用兜底。
final class BigFileMessage {
  const BigFileMessage(
      {required this.url, required this.name, required this.size});

  /// 大文件消息与其他自定义业务的隔离标识。
  static const businessID = 'oa_big_file';

  /// 当前支持的整数协议版本。
  static const version = 1;

  /// 后端文件访问地址，不包含上传临时凭证。
  final String url;

  /// 原始文件名，用于展示和文件类型图标选择。
  final String name;

  /// 原文件字节数，展示时才转换单位。
  final int size;

  /// 编码用户已确认的消息结构，不向对端暴露本地文件路径。
  String toCustomData() => jsonEncode({
        'businessID': businessID,
        'version': version,
        'payload': {'url': url, 'name': name, 'size': size},
      });

  /// 入口是多业务、多版本动态协议，手写判别解析以拒绝未知结构，不能直接强制转换DTO。
  static BigFileMessage? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      // 会话成员可发送任意自定义内容；每层先校验类型再读取字段。
      if (json is! Map<String, dynamic> ||
          json['businessID'] != businessID ||
          json['version'] is! int ||
          json['version'] != version) return null;
      final payload = json['payload'];
      if (payload is! Map<String, dynamic>) return null;
      final url = payload['url'],
          name = payload['name'],
          size = payload['size'];
      if (url is! String ||
          name is! String ||
          name.trim().isEmpty ||
          size is! int ||
          size < 0 ||
          size > 10 * 1024 * 1024 * 1024) return null;
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) return null;
      return BigFileMessage(url: url, name: name, size: size);
    } on FormatException {
      return null;
    }
  }
}
