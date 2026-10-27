import 'package:flutter/material.dart';

import '../../image_viewer/image_element.dart';
import '../../image_viewer/image_viewer.dart';
import '../../message_input/chat_media_sender.dart';
import 'big_file_message.dart';
import 'rich_content_message.dart';

/// 将同一富文本中的媒体按正文顺序交给普通消息预览器，视频复用宿主账号隔离下载。
void showRichContentMediaViewer(
    BuildContext context, RichContentMessage content, int blockIndex,
    {ChatFileDownloader? downloadVideo}) {
  final media = <({int index, RichContentBlock block, ImageElement element})>[];
  for (final (index, block) in content.blocks.indexed) {
    switch (block) {
      case RichImageBlock(:final url):
        media.add((
          index: index,
          block: block,
          element: ImageElement(type: 0, imagePath: url, mediaId: url)
        ));
      case RichFileBlock(:final url, :final mimeType, :final thumbnailUrl)
          when mimeType.startsWith('video/'):
        media.add((
          index: index,
          block: block,
          element:
              ImageElement(type: 1, imagePath: thumbnailUrl ?? '', mediaId: url)
        ));
      default:
        break;
    }
  }
  final initial = media.indexWhere((item) => item.index == blockIndex);
  if (initial < 0) return;
  // SDK的历史媒体接口不认识自定义消息中的块，当前气泡内的有序媒体作为独立预览集合。
  ImageViewer.view(context,
      imageElements: media.map((item) => item.element).toList(growable: false),
      initialIndex: initial, onEventTriggered: (event, complete) async {
    if (event['event'] == 'onLoadMore') {
      complete({'elements': <ImageElement>[], 'hasMoreData': false});
      return;
    }
    if (event['event'] != 'onDownloadVideo') {
      complete(null);
      return;
    }
    final id = (event['param'] as Map?)?['mediaId'];
    final target =
        media.where((item) => item.element.mediaId == id).firstOrNull;
    if (target?.block case final RichFileBlock video) {
      try {
        if (downloadVideo == null) throw StateError('未配置视频下载');
        final path = await downloadVideo(
            BigFileMessage(url: video.url, name: video.name, size: video.size));
        complete([path]);
        return;
      } catch (_) {
        // 失败交还预览器恢复播放入口并提示，页面关闭后的迟到结果不再产生UI动作。
      }
    }
    complete(<String>[]);
  });
}
