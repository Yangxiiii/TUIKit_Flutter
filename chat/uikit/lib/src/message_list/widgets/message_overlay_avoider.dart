import 'package:flutter/widgets.dart';

/// 仅在实际遮挡时计算上移距离；间隔不足但尚未遮挡时必须保持0。
double messageOverlayLift(
        {required double messageBottom, required double overlayTop}) =>
    messageBottom > overlayTop ? messageBottom - overlayTop + 16 : 0;

/// 聊天页提供实测浮层边界，列表临时平移绘制而不改动历史浏览和分页锚点。
class MessageOverlayController
    extends ValueNotifier<({GlobalKey bubble, double top})?> {
  MessageOverlayController() : super(null);

  /// 同一气泡与顶部边界只通知一次，避免布局测量形成无效重绘循环。
  void avoid(GlobalKey bubble, double top) {
    if (value?.bubble == bubble && value?.top == top) {
      return;
    }
    value = (bubble: bubble, top: top);
  }

  /// 关闭浮层后移除临时位移，原始滚动位置不需要重建或重新定位。
  void clear() => value = null;
}

/// 裁剪并上移真实列表，保持逻辑视口及普通草稿不受浮层占位影响。
class MessageOverlayAvoider extends StatefulWidget {
  const MessageOverlayAvoider(
      {super.key, required this.controller, required this.child});

  /// 由聊天页创建和释放的当前浮层边界。
  final MessageOverlayController? controller;

  /// 保持原布局尺寸的消息列表，不用固定偏移猜测目标消息位置。
  final Widget child;

  @override
  State<MessageOverlayAvoider> createState() => _MessageOverlayAvoiderState();
}

/// 在布局结束后按屏幕坐标重测，已应用的位移先还原后再计算，避免重复累加。
class _MessageOverlayAvoiderState extends State<MessageOverlayAvoider> {
  /// 只在本浮层存活期间存在的绘制位移，单位为逻辑像素。
  double _lift = 0;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_schedule);
  }

  @override
  void didUpdateWidget(MessageOverlayAvoider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_schedule);
      widget.controller?.addListener(_schedule);
    }
    _schedule();
  }

  /// 合并同帧测量，在布局完成后从屏幕坐标还原基准位置并更新临时位移。
  void _schedule() {
    if (_scheduled) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) {
        return;
      }
      final target = widget.controller?.value;
      final box = target?.bubble.currentContext?.findRenderObject();
      var next = 0.0;
      if (target != null && box is RenderBox && box.attached && box.hasSize) {
        // 气泡已被上一次绘制位移抬高，先加回才能避免同一浮层重复累加。
        final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
        next = messageOverlayLift(
            messageBottom: bottom + _lift, overlayTop: target.top);
      }
      if ((next - _lift).abs() > 0.01) {
        setState(() => _lift = next);
      }
    });
    // 浮层关闭可能发生在空闲帧，单独注册postFrame不会主动触发重绘。
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_schedule);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
        child:
            Transform.translate(offset: Offset(0, -_lift), child: widget.child),
      );
}
