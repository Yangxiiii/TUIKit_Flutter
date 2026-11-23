import 'dart:io';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:app_ui/app_ui.dart';
import 'image_element.dart';
import 'image_viewer_widget.dart';

/// 为聊天页面和全局转发Sheet复用同一媒体预览器，关闭后保留原消息界面。
class ImageViewer {
  /// 复用全屏预览，仅打开设备上仍存在的照片或视频文件。
  static Future<void> viewLocalMessage(
    BuildContext context,
    MessageInfo message, {
    List<MessageInfo>? mediaMessages,
  }) async {
    final elements = <ImageElement>[];
    var initialIndex = -1;
    // 本机窗口不触发远端分页，并以消息标识定位用户点击的照片。
    for (final candidate in mediaMessages ?? [message]) {
      final media = _localMedia(candidate);
      if (media == null ||
          (media.isImage ? media.imagePath.isEmpty : !media.hasVideoFile))
        continue;
      if (candidate.msgID == message.msgID) initialIndex = elements.length;
      elements.add(media);
    }
    if (!context.mounted || initialIndex < 0) return;
    await view(context,
        imageElements: elements,
        initialIndex: initialIndex,
        onEventTriggered: (_, complete) => complete(null));
  }

  /// 离线预览只从当前设备取得资源，缺失文件不会展示为空白页。
  static ImageElement? _localMedia(MessageInfo message) =>
      switch (message.messagePayload) {
        ImageMessagePayload(
          :final largeImagePath,
          :final originalImagePath,
          :final thumbImagePath,
        ) =>
          ImageElement(
            type: 0,
            imagePath: _firstLocalFile(
                [largeImagePath, originalImagePath, thumbImagePath]),
          ),
        VideoMessagePayload(:final videoSnapshotPath, :final videoPath) =>
          ImageElement(
            type: 1,
            imagePath: _firstLocalFile([videoSnapshotPath]),
            videoPath: _firstLocalFile([videoPath]),
          ),
        _ => null,
      };

  /// 缩略图可在原图已清理时继续用于本机预览。
  static String _firstLocalFile(List<String?> paths) {
    for (final path in paths) {
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        return path;
      }
    }
    return '';
  }

  /// 打开全屏预览并在关闭后返回。可分页会话允许越界滑动请求历史。
  static Future<void> view(
    BuildContext context, {
    required List<ImageElement> imageElements,
    required int initialIndex,
    required EventHandler onEventTriggered,
    Stream<List<ImageElement>>? imageUpdates,
    bool loadMoreOnOverscroll = false,
  }) async {
    if (imageElements.isEmpty) return;
    final navigator = Navigator.maybeOf(context);
    if (navigator == null) {
      // 全局Sheet位于路由树外，直接push会找不到导航器；关闭时只收起媒体预览。
      final media = MediaQueryData.fromView(View.of(context));
      await AppDialog.showSheet<void>(
        showCloseButton: false,
        topRadius: 0,
        maxHeightFactor: 1,
        backgroundColor: context.appColors.scrim.withValues(alpha: 1),
        child: SizedBox(
          height: media.size.height - media.padding.bottom,
          child: ImageViewerWidget(
            imageElements: imageElements,
            initialIndex: initialIndex,
            onEventTriggered: onEventTriggered,
            imageUpdates: imageUpdates,
            loadMoreOnOverscroll: loadMoreOnOverscroll,
            onClose: AppDialog.dismiss,
          ),
        ),
      );
      return;
    }
    // 路由关闭后再释放消息查看器，保证预览期间可以继续加载媒体。
    await navigator.push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            ImageViewerWidget(
          imageElements: imageElements,
          initialIndex: initialIndex,
          onEventTriggered: onEventTriggered,
          imageUpdates: imageUpdates,
          loadMoreOnOverscroll: loadMoreOnOverscroll,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }
}
