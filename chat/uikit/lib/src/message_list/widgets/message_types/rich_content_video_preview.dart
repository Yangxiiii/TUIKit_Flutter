import 'package:app_ui/app_ui.dart' show AppIcons;
import 'package:flutter/material.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart'
    show SemanticColorScheme;

/// 共用视频封面与中央播放标识；只负责展示，编辑器和消息气泡自行决定交互。
final class RichContentVideoPreview extends StatelessWidget {
  /// 首帧封面来源；兼容无封面的旧消息及加载失败时的占位。
  final ImageProvider? image;

  /// 已按当前正文宽度和封面比例限制的展示尺寸。
  final Size size;

  /// 宿主的原色播放图标，编辑器与接收端使用同一来源且不随主题染色。
  final ImageProvider? playIcon;

  const RichContentVideoPreview(
      {super.key, required this.image, required this.size, this.playIcon});

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    return IgnorePointer(
      child: SizedBox.fromSize(
        size: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(fit: StackFit.expand, children: [
            // 封面与播放标识使用同一尺寸，编辑态不创建播放器或点击回调。
            ColoredBox(color: colors.bgColorInput),
            if (image != null)
              Image(
                  image: image!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                      Icons.broken_image_outlined,
                      color: colors.textColorTertiary)),
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
}
