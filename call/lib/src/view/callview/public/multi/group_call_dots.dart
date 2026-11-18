import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 按设计的1200毫秒周期错峰播放呼叫中指示，组件卸载时释放动画。
class GroupCallDots extends StatefulWidget {
  const GroupCallDots({super.key});

  @override
  State<GroupCallDots> createState() => _GroupCallDotsState();
}

/// 三个圆点共用时钟，仅变换透明度和位置，不触发媒体布局重排。
class _GroupCallDotsState extends State<GroupCallDots>
    with SingleTickerProviderStateMixin {
  /// 每 1200 毫秒重复一轮，状态退出后由 dispose 停止时钟。
  late final _animation = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (index) {
              // 每点只运动600毫秒，后续间歇保留35%透明度。
              final elapsed = (_animation.value * 1200 - index * 150) % 1200;
              final progress =
                  elapsed < 600 ? 1 - (elapsed / 300 - 1).abs() : 0.0;
              final value = Curves.easeInOut.transform(progress);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Transform.translate(
                  offset: Offset(0, -3 * value),
                  child: Transform.scale(
                    scale: 1 + .15 * value,
                    child: Opacity(
                      opacity: .35 + .65 * value,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: context.appColors.onScrim),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      );
}
