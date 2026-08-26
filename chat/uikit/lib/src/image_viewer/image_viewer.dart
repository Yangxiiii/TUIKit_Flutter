import 'package:flutter/material.dart';
import 'image_element.dart';
import 'image_viewer_widget.dart';

class ImageViewer {
  static Future<void> view(
    BuildContext context, {
    required List<ImageElement> imageElements,
    required int initialIndex,
    required EventHandler onEventTriggered,
  }) async {
    // 图片预览依赖透明 Route 叠加在当前页面之上，因此保留 Overlay 导航。
    Navigator.of(context).push(
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
