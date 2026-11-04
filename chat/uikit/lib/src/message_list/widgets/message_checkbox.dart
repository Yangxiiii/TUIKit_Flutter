import 'package:flutter/material.dart';
import 'package:app_ui/app_ui.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';

/// 共用圆形勾选样式；目标选择可缩小字形，消息列表保留原尺寸。
class MessageCheckbox extends StatelessWidget {
  /// 当前目标是否已选中，不在控件内部维护另一份状态。
  final bool isSelected;

  /// 禁用时不触发点击，并沿用主题禁用色。
  final bool isEnabled;

  /// 整行已提供点击时可为空，避免重复切换选择。
  final VoidCallback? onTap;

  /// 圆形主体的逻辑像素直径，外侧仍保留4像素命中留白。
  final double size;

  const MessageCheckbox({
    super.key,
    required this.isSelected,
    this.isEnabled = true,
    this.onTap,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);

    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? colors.buttonColorPrimaryDefault
                : Colors.transparent,
            border: Border.all(
              color: isEnabled
                  ? (isSelected
                      ? colors.buttonColorPrimaryDefault
                      : colors.strokeColorPrimary)
                  : colors.textColorDisable,
              width: 1.5,
            ),
          ),
          child: isSelected
              ? Icon(AppIcons.check,
                  size: size * .6, color: context.appColors.onPrimary)
              : null,
        ),
      ),
    );
  }
}
