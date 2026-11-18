import 'package:tencent_calls_uikit/src/state/group_control_state.dart';

/// 判断弹层是否仍属于原场次；允许 SDK 在同一代次内为等待中的呼叫补齐 ID。
bool isCurrentGroupCallPresentation({
  required int capturedEpoch,
  required int currentEpoch,
  required String capturedCallId,
  required String currentCallId,
  required bool presentationIsCurrent,
}) =>
    presentationIsCurrent &&
    capturedEpoch == currentEpoch &&
    (capturedCallId.isEmpty || capturedCallId == currentCallId);

/// 确认框返回时核对入会、主持人与版本，过期的策略草稿不能覆盖当前权限。
bool isCurrentGroupControlOperation({
  required GroupControlState expected,
  required GroupControlState? current,
  required bool presentationIsCurrent,
}) =>
    presentationIsCurrent &&
    current != null &&
    expected.callId == current.callId &&
    expected.selfId == current.selfId &&
    expected.sessionId == current.sessionId &&
    expected.hostId == current.hostId &&
    expected.version == current.version;
