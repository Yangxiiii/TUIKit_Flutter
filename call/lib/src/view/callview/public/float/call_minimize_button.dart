import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 全屏通话左上角的共享小窗入口，权限和路由由平台处理。
class CallMinimizeButton extends StatelessWidget {
  const CallMinimizeButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Positioned(
        left: 12,
        top: 52,
        width: 40,
        height: 40,
        child: IconButton(
          onPressed: onPressed,
          icon: Semantics(
            identifier: 'call.minimize',
            label: AppLocalization.of(context)
                .resolve('chat.uikit.callMinimize', '最小化通话'),
            child:
                Icon(AppIcons.copy, size: 24, color: context.appColors.onScrim),
          ),
        ),
      );
}
