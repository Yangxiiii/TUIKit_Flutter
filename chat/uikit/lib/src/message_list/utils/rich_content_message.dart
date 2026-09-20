import 'dart:convert';

/// 解析应用的图文自定义消息；其他业务类型和未知版本不在此协议中处理。
final class RichContentMessage {
  /// 当前应用图文消息的业务标识，与其他自定义消息区分。
  static const businessID = 'oa_rich_content';

  /// 当前图文消息体的结构版本；版本变化时须保留旧版本解析或明确降级。
  static const version = 1;

  /// 气泡内按发送时顺序排列的内容块。
  final List<RichContentBlock> blocks;

  const RichContentMessage(this.blocks);

  /// 从 SDK 的 customData 解析图文消息；不属于本协议或内容不完整时返回 null。
  static RichContentMessage? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    // 自定义消息来自会话成员，不能让无效 JSON 或错误字段类型打断整页消息渲染。
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['businessID'] != businessID ||
          decoded['version'] != version) {
        return null;
      }

      final payload = decoded['payload'];
      if (payload is! Map<String, dynamic>) return null;
      final rawBlocks = payload['blocks'];
      if (rawBlocks is! List || rawBlocks.isEmpty) return null;

      final blocks = <RichContentBlock>[];
      for (final rawBlock in rawBlocks) {
        if (rawBlock is! Map<String, dynamic>) return null;
        final block = _parseBlock(rawBlock);
        if (block == null) return null;
        blocks.add(block);
      }
      return RichContentMessage(List.unmodifiable(blocks));
    } on FormatException {
      return null;
    }
  }

  /// 校验并解析单个内容块；拒绝未知类型，避免静默丢失消息中的一段内容。
  static RichContentBlock? _parseBlock(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'text':
        final text = data['text'];
        return text is String && text.isNotEmpty ? RichTextBlock(text) : null;
      case 'image':
        final url = data['url'];
        final width = data['width'];
        final height = data['height'];
        if (!_isWebUrl(url) ||
            width is! int ||
            width <= 0 ||
            height is! int ||
            height <= 0) {
          return null;
        }
        return RichImageBlock(url, width, height);
      case 'file':
        final url = data['url'];
        final name = data['name'];
        final size = data['size'];
        final mimeType = data['mimeType'];
        if (!_isWebUrl(url) ||
            name is! String ||
            name.isEmpty ||
            size is! int ||
            size < 0 ||
            mimeType is! String ||
            mimeType.isEmpty) {
          return null;
        }
        return RichFileBlock(url, name, size, mimeType);
      default:
        return null;
    }
  }

  /// 只接受可供网络图片和文件组件访问的 HTTP(S) 地址。
  static bool _isWebUrl(Object? value) {
    if (value is! String) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }
}

/// 图文气泡内的一个有序内容块。
sealed class RichContentBlock {
  const RichContentBlock();
}

/// 保留原始 Markdown、换行和空格的文字段。
final class RichTextBlock extends RichContentBlock {
  /// 原始 Markdown 文本，不进行 trim，以免改变用户输入的排版。
  final String text;

  const RichTextBlock(this.text);
}

/// 使用远端 URL 展示的图片段。
final class RichImageBlock extends RichContentBlock {
  /// 已上传图片的可访问地址。
  final String url;

  /// 原图宽度，单位为像素，用于计算气泡中的展示比例。
  final int width;

  /// 原图高度，单位为像素，用于计算气泡中的展示比例。
  final int height;

  const RichImageBlock(this.url, this.width, this.height);
}

/// 使用远端 URL 下载的文件段。
final class RichFileBlock extends RichContentBlock {
  /// 已上传文件的可访问地址。
  final String url;

  /// 接收端展示的原始文件名。
  final String name;

  /// 文件大小，单位为字节。
  final int size;

  /// 文件的 MIME 类型。
  final String mimeType;

  const RichFileBlock(this.url, this.name, this.size, this.mimeType);
}
