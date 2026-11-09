import 'package:app_ui/app_ui.dart'
    show AppColorBuildContext, AppImageLoadingPlaceholder;
import 'package:flutter/material.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart'
    show SemanticColorScheme;

/// 在既有媒体尺寸内显示灰底加载状态或宿主提供的占位图。
final class ChatMediaPlaceholder extends StatelessWidget {
  /// 宿主提供的原色占位图；为空时使用聊天媒体的灰底样式。
  final ImageProvider? image;

  /// 本地导出或下载阶段保留加载提示，已存在播放入口的封面不重复叠加。
  final bool showLoading;

  const ChatMediaPlaceholder({super.key, this.image, this.showLoading = false});

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return showLoading
          ? const AppImageLoadingPlaceholder()
          : ColoredBox(
              color: context.appColors.chatMediaLoadingBackground,
              child: const SizedBox.expand(),
            );
    }

    final colors = SemanticColorScheme.of(context);
    return Stack(fit: StackFit.expand, children: [
      // 占位图填满媒体区域且不染色，外层继续负责原有圆角。
      ColoredBox(color: colors.bgColorTopBar),
      Image(
          image: image!,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink()),
      // 耗时处理保留进度提示，静态占位图不能被误认为资源已经就绪。
      if (showLoading)
        Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: colors.buttonColorPrimaryDefault))),
    ]);
  }
}
