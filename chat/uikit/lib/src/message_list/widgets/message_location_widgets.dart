import 'package:app_ui/app_ui.dart';
import 'package:flutter/widgets.dart';

/// 在可见的聊天窗口内观察真实输入，子组件继续处理原有点击和滚动。
final class MessageLocationInteraction extends StatelessWidget {
  const MessageLocationInteraction({
    required this.onInteraction,
    required this.child,
    super.key,
  });

  /// 指针触摸、滚轮或触控板滚动开始时通知当前窗口。
  final VoidCallback onInteraction;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => onInteraction(),
        onPointerSignal: (_) => onInteraction(),
        onPointerPanZoomStart: (_) => onInteraction(),
        child: child,
      );
}

/// 给定位目标画整行背景，沿用正常消息内边距和滚动高度。
final class MessageLocationRow extends StatelessWidget {
  const MessageLocationRow({
    required this.highlighted,
    required this.horizontalPadding,
    required this.child,
    super.key,
  });

  /// 只为已完成定位的目标绘制背景。
  final bool highlighted;

  /// 正文沿用消息列表边距，背景始终绘制到行边缘。
  final double horizontalPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // 上下各多绘制 4 dp，清除背景时无需调整消息位置。
          if (highlighted)
            Positioned(
              top: -4,
              bottom: -4,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: ColoredBox(
                  color: context.appColors.chatLocatedMessageBackground,
                ),
              ),
            ),
          Padding(
            key: const ValueKey('message-row-content'),
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: child,
          ),
        ],
      ));
}
