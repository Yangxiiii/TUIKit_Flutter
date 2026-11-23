import 'package:flutter/material.dart';

import '../../image_viewer/image_element.dart';
import '../../image_viewer/image_viewer.dart';
import '../../message_input/chat_media_sender.dart';
import 'big_file_message.dart';
import 'rich_content_message.dart';

/// 同一 URL 可以出现在不同消息或块中，位置以消息标识和块序号区分。
List<({int index, RichContentBlock block, ImageElement element})>
    richContentMediaEntries(RichContentMessage content, {String messageId = ''}) {
  final media = <({int index, RichContentBlock block, ImageElement element})>[];
  for (final (index, block) in content.blocks.indexed) {
    final mediaId = 'rich:${Uri.encodeComponent(messageId)}:$index';
    switch (block) {
      case RichImageBlock(:final url):
        media.add((
          index: index,
          block: block,
          element: ImageElement(type: 0, imagePath: url, mediaId: mediaId)
        ));
      case RichFileBlock(:final mimeType, :final thumbnailUrl)
          when mimeType.startsWith('video/'):
        media.add((
          index: index,
          block: block,
          element:
              ImageElement(type: 1, imagePath: thumbnailUrl ?? '', mediaId: mediaId)
        ));
      default:
        break;
    }
  }
  return media;
}

/// 独立正文只浏览自身附件，视频下载继续使用宿主的账号隔离下载。
void showRichContentMediaViewer(
    BuildContext context, RichContentMessage content, int blockIndex,
    {ChatFileDownloader? downloadVideo}) {
  final media = richContentMediaEntries(content);
  final initial = media.indexWhere((item) => item.index == blockIndex);
  if (initial < 0) return;
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
        complete(await downloadRichContentVideo(video, downloadVideo));
        return;
      } catch (_) {
        // 失败交还预览器恢复播放入口并提示，页面关闭后的迟到结果不再产生UI动作。
      }
    }
    complete(<String>[]);
  });
}

/// 富文本视频的地址由协议校验，实际下载继续委托给会话宿主。
Future<List<String>> downloadRichContentVideo(
    RichFileBlock video, ChatFileDownloader? download) async {
  if (download == null) return const [];
  final path = await download(
      BigFileMessage(url: video.url, name: video.name, size: video.size));
  return [path];
}
