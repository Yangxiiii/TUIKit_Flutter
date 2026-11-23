import 'package:flutter/material.dart';

/// 通话圆形操作共用字体图标、既有资源与明确的可访问启用状态。
class ControlsButton extends StatelessWidget {
  const ControlsButton({
    this.imgUrl = '',
    this.icon,
    this.iconSize = 40,
    this.dimension = 72,
    this.labelSpacing = 10,
    this.labelMaxLines,
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

  /// 以字体绘制的操作图标；为空时使用对应的 SDK 图片。
  final IconData? icon;

  /// 字体字面的尺寸；补偿字体内边距，使可见字形与设计对齐。
  final double iconSize;

  /// 圆形点击区域的逻辑像素尺寸；单聊与定制群通话均显式传入 60。
  final double dimension;

  /// 标签与圆形按钮之间的逻辑像素间距，群通话使用设计的 8 像素。
  final double labelSpacing;

  /// 群通话短标签固定单行；未指定时保留其他场景的自动换行。
  final int? labelMaxLines;

  /// 单聊圆形操作底色，由当前主题提供。
  final Color? backgroundColor;

  /// 实际点击节点的稳定标识。
  final String? semanticsIdentifier;

  /// SDK 图片相对路径；提供字体图标时可为空。
  final String imgUrl;

  /// 图片的逻辑像素边长；完整圆钮按点击区域绘制，未指定时沿用各布局的默认值。
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
      // 完整圆钮图片与点击区等大，通过墨水层绘制以保留点击反馈。
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
                    button: true,
                    enabled: onTap != null,
                    child: SizedBox.square(
                        dimension: dimension,
                        child: icon != null
                            ? Icon(icon, size: iconSize, color: imgColor)
                            : Center(
                                child: SizedBox.square(
                                    dimension: imgHeight > 0 ? imgHeight : 32,
                                    child: Ink.image(
                                      image: AssetImage(imgUrl,
                                          package: 'tuikit_atomic_x'),
                                      fit: BoxFit.contain,
                                      colorFilter: imgColor == null
                                          ? null
                                          : ColorFilter.mode(
                                              imgColor!, BlendMode.srcIn),
                                    ))))),
              ),
            ),
          ),
          SizedBox(height: labelSpacing),
          Text(tips,
              maxLines: labelMaxLines,
              softWrap: labelMaxLines != 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                  color: textColor)),
        ],
      );
    }
    // SDK 旧布局仍按调用方指定的偏移和图片动画绘制。
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
