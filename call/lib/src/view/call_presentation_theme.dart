import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 为通话浮层锁定原有配色，同时沿用宿主的尺寸设置。
class CallPresentationTheme extends StatelessWidget {
  const CallPresentationTheme({super.key, required this.builder});

  /// 在通话主题内构建内容，供直接读取语义色的布局使用。
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => Theme(
    data: AppThemeFactory.create(
      const AppNormalColorScheme(),
      Brightness.light,
      sizes: context.appSizes,
    ),
    child: Builder(builder: builder),
  );
}
