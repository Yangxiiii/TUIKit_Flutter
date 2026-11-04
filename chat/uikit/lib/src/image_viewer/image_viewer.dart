import 'package:flutter/material.dart';
import 'package:app_ui/app_ui.dart';
import 'image_element.dart';
import 'image_viewer_widget.dart';

/// 为聊天页面和全局转发Sheet复用同一媒体预览器，关闭后保留原消息界面。
class ImageViewer {
  /// 普通页面使用透明路由，全局Sheet没有Navigator时叠加独立的全屏预览。
  static Future<void> view(
    BuildContext context, {
    required List<ImageElement> imageElements,
    required int initialIndex,
    required EventHandler onEventTriggered,
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
            onClose: AppDialog.dismiss,
          ),
        ),
      );
      return;
    }
    // 图片预览依赖透明 Route 叠加在当前页面之上，因此保留 Overlay 导航。
    navigator.push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            ImageViewerWidget(
          imageElements: imageElements,
          initialIndex: initialIndex,
          onEventTriggered: onEventTriggered,
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
