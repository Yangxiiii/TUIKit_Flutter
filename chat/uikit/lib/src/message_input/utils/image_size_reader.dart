import 'dart:io';
import 'dart:ui' as ui;

/// Raw pixel dimensions of an image.
///
/// 图片的原始像素尺寸。
class ImageSize {
  final int width;
  final int height;
  const ImageSize(this.width, this.height);
}

/// Decodes a local image file and returns its width / height in pixels.
///
/// Used by the message-input send pipeline to populate
/// [ImageMessagePayload.originalImageWidth] / `originalImageHeight` BEFORE the
/// message is dispatched, so the in-flight (sending) bubble in `MessageList`
/// renders with the correct aspect ratio instead of falling back to a
/// 1:1 square placeholder.
///
/// 解码本地图片文件，并返回其像素宽高。
///
/// 在消息输入发送管道中使用，用于在消息发送前填充 [ImageMessagePayload.originalImageWidth] / `originalImageHeight`，这样
/// `MessageList` 中发送中的气泡就能以正确的宽高比渲染，而不是退回到 1:1 的方形占位符。
class ImageSizeReader {
  static Future<ImageSize?> read(String filePath) async {
    if (filePath.isEmpty) return null;
    try {
      final bytes = await File(filePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final size = ImageSize(image.width, image.height);
      image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }
}
