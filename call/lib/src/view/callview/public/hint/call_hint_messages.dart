import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 只绘制等待文字或独立提示胶囊，生产网络事件与本地预览复用相同外观。
class CallHintMessages extends StatelessWidget {
  const CallHintMessages(
      {super.key, required this.messages, this.waiting = false});

  /// 各条提示独立渲染，双方网络差可以同时显示。
  final List<String> messages;

  /// 等待接听时使用普通画面文字，已接通及网络提示使用胶囊。
  final bool waiting;
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (var index = 0; index < messages.length; index++) ...[
        if (index > 0) const SizedBox(height: 8),
        // 等待提示为画面文字，已接通与网络提示使用各自独立的深色胶囊。
        Container(
          padding: waiting
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: waiting
              ? null
              : BoxDecoration(
                  color: context.appColors.callHintBackground,
                  borderRadius: BorderRadius.circular(40)),
          child: Text(messages[index],
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: waiting ? 16 : 14,
                  height: waiting ? 1.25 : 18 / 14,
                  fontWeight: FontWeight.w500,
                  color: waiting
                      ? context.appColors.callStatusText
                      : context.appColors.onScrim)),
        ),
      ],
    ]);
  }
}
