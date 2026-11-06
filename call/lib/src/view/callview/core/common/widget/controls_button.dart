import 'package:flutter/material.dart';

/// 保留群聊位图按钮，同时为单聊提供可访问的字体图标圆形操作。
class ControlsButton extends StatelessWidget {
  const ControlsButton({
    this.imgUrl = '',
    this.icon,
    this.iconSize = 40,
    this.backgroundColor,
    this.semanticsIdentifier,
    this.tips = "",
    this.onTap,
    this.imgHeight = 0,
    this.imgOffsetX = 0,
    this.imgOffsetY = 0,
    this.imgColor,
    this.textColor,
    this.duration = const Duration(milliseconds: 200),
    this.useAnimation = false,
    this.isDisabled = false,
    super.key,
  }) : assert(icon != null || imgUrl != '', '字体图标和既有图片至少提供一种');

  /// 单聊字体图标；缺少同语义字形时沿用 SDK 已有位图，不以其他含义图标替代。
  final IconData? icon;

  /// 字体字面的尺寸；补偿字体内边距，使可见字形与设计对齐。
  final double iconSize;

  /// 单聊圆形操作底色，由当前主题提供。
  final Color? backgroundColor;

  /// 实际点击节点的稳定标识。
  final String? semanticsIdentifier;

  /// 群聊沿用的 SDK 位图路径；提供字体图标时可为空。
  final String imgUrl;
  final double imgHeight;
  final Color? imgColor;
  final double imgOffsetX;
  final double imgOffsetY;
  final String tips;
  final GestureTapCallback? onTap;
  final Color? textColor;
  final bool? useAnimation;
  final Duration duration;
  final bool isDisabled;

  Widget _buildImage() {
    return Image.asset(imgUrl, package: 'tuikit_atomic_x', color: imgColor);
  }

  Widget _buildImageView() {
    final image = _buildImage();
    return useAnimation!
        ? AnimatedContainer(
            duration: duration,
            height: imgHeight > 0 ? imgHeight : 52.0,
            width: imgHeight > 0 ? imgHeight : 52.0,
            child: image,
          )
        : SizedBox(
            height: imgHeight > 0 ? imgHeight : 52.0,
            width: imgHeight > 0 ? imgHeight : 52.0,
            child: image,
          );
  }

  @override
  Widget build(BuildContext context) {
    if (isDisabled) {
      return const SizedBox();
    }
    if (icon != null || semanticsIdentifier != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            child: Material(
              color: backgroundColor,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Semantics(
                    identifier: semanticsIdentifier,
                    label: tips,
                    child: SizedBox.square(
                        dimension: 72,
                        child: icon != null
                            ? Icon(icon, size: iconSize, color: imgColor)
                            : Center(
                                child: SizedBox.square(
                                    dimension: 32, child: _buildImage())))),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(tips,
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 14, height: 20 / 14, color: textColor)),
        ],
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTap: () {
        onTap?.call();
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.translate(
            offset: Offset(imgOffsetX, imgOffsetY),
            child: _buildImageView(),
          ),
          Container(
            width: 100,
            height: 15,
            margin: const EdgeInsets.only(top: 10),
            alignment: Alignment.center,
            child: Text(
              tips,
              textScaleFactor: 1.0,
              style: TextStyle(fontSize: 12, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}
