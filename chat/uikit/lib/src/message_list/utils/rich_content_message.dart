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

  /// 编码为腾讯 IM 自定义消息的 customData；图片和视频必须提供正整数宽高。
  String toCustomData() {
    return jsonEncode({
      'businessID': businessID,
      'version': version,
      'payload': {'blocks': blocks.map(_encodeBlock).toList()},
    });
  }

  /// 提取离线推送和会话摘要可用的纯文本内容。
  String get plainTextPreview => blocks
      .whereType<RichTextBlock>()
      .map((block) => block.text)
      .join(' ')
      .trim();

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
        // 历史消息可能只有地址，接收仍兼容缺省尺寸；新发送在编码边界强制补齐。
        if (!_isWebUrl(url) ||
            (width != null && (width is! int || width <= 0)) ||
            (height != null && (height is! int || height <= 0))) {
          return null;
        }
        return RichImageBlock(url, width, height);
      case 'file':
        final url = data['url'];
        final name = data['name'];
        final size = data['size'];
        final mimeType = data['mimeType'];
        final thumbnailUrl = data['thumbnailUrl'];
        final width = data['width'];
        final height = data['height'];
        if (!_isWebUrl(url) ||
            name is! String ||
            name.isEmpty ||
            size is! int ||
            size < 0 ||
            mimeType is! String ||
            mimeType.isEmpty ||
            (thumbnailUrl != null && !_isWebUrl(thumbnailUrl)) ||
            (width != null && (width is! int || width <= 0)) ||
            (height != null && (height is! int || height <= 0))) {
          return null;
        }
        return RichFileBlock(url, name, size, mimeType,
            thumbnailUrl: thumbnailUrl, width: width, height: height);
      default:
        return null;
    }
  }

  /// 将已校验的内容块编码为协议字段。
  static Map<String, Object> _encodeBlock(RichContentBlock block) {
    return switch (block) {
      RichTextBlock block => {'type': 'text', 'text': block.text},
      RichImageBlock block => {
          'type': 'image',
          'url': block.url,
          'width': _requirePositiveDimension(block.width),
          'height': _requirePositiveDimension(block.height),
        },
      RichFileBlock block => {
          'type': 'file',
          'url': block.url,
          'name': block.name,
          'size': block.size,
          'mimeType': block.mimeType,
          if (block.thumbnailUrl != null) 'thumbnailUrl': block.thumbnailUrl!,
          if (block.width != null || block.mimeType.startsWith('video/'))
            'width': _requirePositiveDimension(block.width),
          if (block.height != null || block.mimeType.startsWith('video/'))
            'height': _requirePositiveDimension(block.height),
        },
    };
  }

  /// 发送边界拒绝缺省或无效尺寸，避免接收端只能等待解码后确定媒体比例。
  static int _requirePositiveDimension(int? value) {
    if (value == null || value <= 0) {
      throw ArgumentError.value(value, 'dimension', '媒体宽高必须是正整数');
    }
    return value;
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

  /// 与 height 一起确定气泡中图片的展示比例；大于 0，单位为像素，历史消息可缺省。
  final int? width;

  /// 与 width 一起确定气泡中图片的展示比例；大于 0，单位为像素，历史消息可缺省。
  final int? height;

  const RichImageBlock(this.url, [this.width, this.height]);
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

  /// 视频可选的远端首帧封面；旧消息缺省时保留视频占位，不影响正文解析。
  final String? thumbnailUrl;

  /// 视频画面宽度，与 height 一起描述视频的宽高比；大于 0，单位为像素。
  /// 新视频必填，历史消息及普通文件可缺省。
  final int? width;

  /// 视频画面高度，与 width 一起描述视频的宽高比；大于 0，单位为像素。
  /// 新视频必填，历史消息及普通文件可缺省。
  final int? height;

  const RichFileBlock(this.url, this.name, this.size, this.mimeType,
      {this.thumbnailUrl, this.width, this.height});
}
