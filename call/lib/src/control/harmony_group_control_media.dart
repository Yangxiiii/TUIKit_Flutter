import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../state/group_control_state.dart';
import 'group_control_media.dart';

/// 将共享会控的本机设备操作送给鸿蒙 SDK，仅用当前会话的实际快照生成回执。
final class HarmonyGroupControlMedia extends ChangeNotifier
    implements GroupControlMedia {
  HarmonyGroupControlMedia({
    required this.presentationId,
    required this.callId,
    required MethodChannel channel,
  }) : _channel = channel;

  /// 鸿蒙当前展示代次，同一呼叫重新接通后旧操作不能继续使用。
  final String presentationId;

  /// 当前 SDK 信令标识，原生校验时必须与展示代次同时匹配。
  final String callId;

  /// 通道只提交目标状态，设备结果由快照确认。
  final MethodChannel _channel;

  /// 等待 SDK 确认实际状态的上限。
  static const _confirmationTimeout = Duration(seconds: 4);

  /// 最近一帧 SDK 实际设备状态，不从发送成功推断。
  bool _microphoneOn = false, _cameraOn = false;

  @override
  Listenable get changes => this;

  @override
  bool get microphoneOn => _microphoneOn;

  @override
  bool get cameraOn => _cameraOn;

  /// 展示层已经校验当前 SDK 场次，只有设备位变更才通知会控。
  void update({required bool microphone, required bool camera}) {
    if (_microphoneOn == microphone && _cameraOn == camera) return;
    _microphoneOn = microphone;
    _cameraOn = camera;
    notifyListeners();
  }

  @override
  Future<GroupControlOutcome> setDevice(
    GroupControlDevice device,
    bool enabled, {
    required bool Function() isCurrent,
  }) async {
    GroupControlOutcome result(GroupControlStatus status, [String? error]) =>
        GroupControlOutcome(
          status,
          error: error,
          microphoneOn: microphoneOn,
          cameraOn: cameraOn,
        );
    bool matches() =>
        (device == GroupControlDevice.microphone ? microphoneOn : cameraOn) ==
        enabled;

    if (!isCurrent()) return result(GroupControlStatus.expired);
    if (matches()) return result(GroupControlStatus.success);
    final target = {
      'id': presentationId,
      'callId': callId,
      'device': device.name,
    };
    try {
      if (enabled) {
        final permitted = await _channel.invokeMethod<bool>(
          'harmonyPresentationGroupDevice',
          target,
        );
        // 系统授权可能跨过挂断或更高版本的关停指令，重新校验后才能采集。
        if (!isCurrent()) return result(GroupControlStatus.expired);
        if (permitted != true) {
          return result(GroupControlStatus.failed, '未获得设备权限');
        }
      }
      final confirmed = Completer<void>();
      void observe() {
        if (matches() && !confirmed.isCompleted) confirmed.complete();
      }

      addListener(observe);
      try {
        final submitted = await _channel.invokeMethod<bool>(
          'harmonyPresentationGroupDevice',
          {...target, 'enabled': enabled},
        );
        if (!isCurrent()) return result(GroupControlStatus.expired);
        if (submitted != true) {
          return result(GroupControlStatus.failed, '设备操作未执行');
        }
        observe();
        await confirmed.future.timeout(_confirmationTimeout);
        if (!isCurrent()) return result(GroupControlStatus.expired);
        return result(
          matches()
              ? GroupControlStatus.success
              : GroupControlStatus.unconfirmed,
        );
      } finally {
        removeListener(observe);
      }
    } on TimeoutException {
      return result(
        isCurrent()
            ? GroupControlStatus.unconfirmed
            : GroupControlStatus.expired,
      );
    } on PlatformException {
      return result(
        isCurrent() ? GroupControlStatus.failed : GroupControlStatus.expired,
      );
    }
  }
}
