import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../../../../state/group_control_state.dart';

/// 各平台共用主持人请求开麦或开摄像头的本人确认文案。
Widget buildGroupDeviceOpenDialog(
  BuildContext context,
  GroupControlDevice device,
  ValueChanged<bool> finish,
) {
  final text = AppLocalization.of(context);
  return AppAlertDialog(
    semanticsIdentifier: 'call.group.requestOpen.${device.name}',
    title: device == GroupControlDevice.microphone
        ? text.groupCallRequestMic
        : text.groupCallRequestCamera,
    cancelText: text.groupCallDeclineDevice,
    confirmText: text.groupCallEnableDevice,
    onCancel: () => finish(false),
    onConfirm: () => finish(true),
  );
}
