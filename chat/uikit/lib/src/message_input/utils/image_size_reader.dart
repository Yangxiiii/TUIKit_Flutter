import 'dart:ui' as ui;

/// Raw pixel dimensions of an image.
///
/// 图片的原始像素尺寸。
class ImageSize {
  final int width;
  final int height;
  const ImageSize(this.width, this.height);
}

/// 读取本地图片的原始像素尺寸，供输入预览和发送中的气泡保持正确比例；不解码完整帧。
class ImageSizeReader {
  /// 路径为空、文件不可读或编码格式不支持时返回 null，并释放已创建的图像资源。
  static Future<ImageSize?> read(String filePath) async {
    if (filePath.isEmpty) return null;
    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(filePath);
      try {
        // 只查询编码元数据，避免为读取宽高分配原图大小的像素缓冲区。
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          return ImageSize(descriptor.width, descriptor.height);
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
    } catch (_) {
      return null;
    }
  }
}
