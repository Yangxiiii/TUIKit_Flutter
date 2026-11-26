import 'package:app_ui/app_ui.dart';
import 'package:flutter/widgets.dart';

/// 保留 UIKit 的提示类型参数，宿主的文字反馈使用统一外观。
enum ToastType { loading, info, success, warning, error, help }

/// 将 UIKit 的各类短时反馈交给宿主 Toast，独立页面也使用相同浮层。
abstract final class Toast {
  static void success(BuildContext context, String message,
          {Duration duration = AppToast.defaultDuration,
          bool useRootOverlay = false}) =>
      show(context, message, duration: duration);

  static void info(BuildContext context, String message,
          {Duration duration = AppToast.defaultDuration,
          bool useRootOverlay = false}) =>
      show(context, message, duration: duration);

  static void warning(BuildContext context, String message,
          {Duration duration = AppToast.defaultDuration,
          bool useRootOverlay = false}) =>
      show(context, message, duration: duration);

  static void error(BuildContext context, String message,
          {Duration duration = AppToast.defaultDuration,
          bool useRootOverlay = false}) =>
      show(context, message, duration: duration);

  static void loading(BuildContext context, String message,
          {Duration duration = AppToast.defaultDuration,
          bool useRootOverlay = false}) =>
      show(context, message, duration: duration);

  static void simple(BuildContext context, String message,
          {Duration duration = AppToast.defaultDuration,
          bool useRootOverlay = false}) =>
      show(context, message, duration: duration);

  /// 忽略 SDK 返回的空提示；旧位置参数保留供 UIKit 调用方兼容。
  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
    Duration duration = AppToast.defaultDuration,
    bool useRootOverlay = false,
  }) {
    if (message.trim().isEmpty) return;
    AppToast.show(message, context: context, duration: duration);
  }

  /// 主动结束当前提示，沿用公共浮层的退场动画。
  static void hide() => AppToast.dismiss();
}
