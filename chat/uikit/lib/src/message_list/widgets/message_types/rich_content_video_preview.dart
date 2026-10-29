import 'package:app_ui/app_ui.dart' show AppIcons, AppColorBuildContext;
import 'package:flutter/material.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart'
    show SemanticColorScheme;

/// 共用视频封面；编辑态展示时长角标，消息气泡保留中央播放入口。
final class RichContentVideoPreview extends StatelessWidget {
  /// 首帧封面来源；兼容无封面的旧消息及加载失败时的占位。
  final ImageProvider? image;

  /// 已按当前正文宽度和封面比例限制的展示尺寸。
  final Size size;

  /// 消息气泡使用的原色播放图标，不随主题染色；编辑态忽略此项。
  final ImageProvider? playIcon;

  /// 编辑态使用 4px 圆角及右下角时长，不创建播放交互。
  final bool isEditing;

  /// 视频时长，单位为毫秒；旧草稿缺少时以未知时长展示。
  final int? durationMs;

  const RichContentVideoPreview(
      {super.key,
      required this.image,
      required this.size,
      this.playIcon,
      this.isEditing = false,
      this.durationMs});

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    return IgnorePointer(
      child: SizedBox.fromSize(
        size: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isEditing ? 4 : 8),
          child: Stack(fit: StackFit.expand, children: [
            // 编辑尺寸已按原比例计算，完整显示封面；消息气泡沿用原展示方式。
            ColoredBox(color: colors.bgColorInput),
            if (image != null)
              Image(
                  image: image!,
                  fit: isEditing ? BoxFit.contain : BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                      Icons.broken_image_outlined,
                      color: colors.textColorTertiary)),
            if (isEditing)
              _buildDurationBadge(context, colors)
            else
              Center(
                  child: playIcon == null
                      ? Icon(AppIcons.videoPlay,
                          size: 40, color: colors.textColorAntiPrimary)
                      : Image(
                          image: playIcon!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.contain,
                          excludeFromSemantics: true)),
          ]),
        ),
      ),
    );
  }

  /// 角标与封面右下边缘各留 4px，使用设计稿的实心图标和完整圆角。
  Widget _buildDurationBadge(BuildContext context, SemanticColorScheme colors) {
    // 使用深色遮罩上的白色前景，避免浅色主题的反色正文把角标染成黑色。
    final foreground = context.appColors.onScrim;
    final seconds = durationMs == null ? null : durationMs! ~/ 1000;
    final duration = seconds == null
        ? '--:--'
        : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Positioned(
      right: 4,
      bottom: 4,
      child: Container(
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: colors.textColorSecondary,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(AppIcons.cameraOn, size: 16, color: foreground),
          const SizedBox(width: 2),
          Text(duration,
              style: TextStyle(fontSize: 10, height: 1, color: foreground)),
        ]),
      ),
    );
  }
}
