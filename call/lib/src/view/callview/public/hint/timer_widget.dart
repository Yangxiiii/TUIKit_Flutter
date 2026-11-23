import 'package:app_core/app_core.dart' show formatCallDuration;
import 'package:tuikit_atomic_x/atomicx.dart';
import 'package:flutter/material.dart';

import 'package:app_ui/app_ui.dart';

/// 展示 SDK 接通后的计时，满一小时切换为时分秒。
class TimerWidget extends StatelessWidget {
  final double? fontSize;
  final FontWeight? fontWeight;

  const TimerWidget({super.key, this.fontSize, this.fontWeight});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: CallStore.shared.state.selfInfo,
      builder: (context, info, child) {
        if (info.status == CallParticipantStatus.accept) {
          return ValueListenableBuilder(
            valueListenable: CallStore.shared.state.activeCall,
            builder: (context, activeCall, child) {
              return Text(
                formatDuration(activeCall.duration.toInt()),
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.25,
                  fontWeight: fontWeight,
                  color: context.appColors.onScrim,
                ),
              );
            },
          );
        } else {
          return Container();
        }
      },
    );
  }

  /// 全屏和浮窗共用通话时长格式，挂断完成前的显示不超过一小时。
  String formatDuration(int timeCount) => formatCallDuration(timeCount);
}
