import 'package:tuikit_atomic_x/atomicx.dart';
import 'package:flutter/material.dart';

import 'package:app_ui/app_ui.dart';

/// 读取 SDK 连接时长并展示分钟与秒，不将等待接听时间计入通话。
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
                formatDuration(activeCall.duration.toInt(),
                    showHours: activeCall.chatGroupId.isNotEmpty ||
                        activeCall.inviteeIds.length > 1),
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

  /// 单聊上限为 60 分钟，累计分钟在 3600 秒显示 60:00；群聊保留既有小时格式。
  String formatDuration(int timeCount, {bool showHours = false}) {
    final seconds = timeCount < 0 ? 0 : timeCount;
    final minutes = showHours ? (seconds % 3600) ~/ 60 : seconds ~/ 60;
    final time =
        '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    if (showHours && seconds >= 3600) {
      return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:$time';
    }
    return time;
  }
}
