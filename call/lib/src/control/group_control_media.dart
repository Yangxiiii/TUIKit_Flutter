import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tuikit_atomic_x/atomicx.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';
import '../state/group_control_state.dart';

/// 会控只操作本端设备；远端实际状态必须由目标端执行后通过 ACK 返回。
abstract interface class GroupControlMedia {
  /// 真实 SDK available 状态变化，不能使用业务乐观开关替代。
  Listenable get changes;

  /// SDK 报告的本端麦克风可用状态。
  bool get microphoneOn;

  /// SDK 报告的本端摄像头可用状态。
  bool get cameraOn;

  /// 权限拒绝、SDK 错误、状态未确认均返回非成功；失效入会不能继续开启设备。
  Future<GroupControlOutcome> setDevice(GroupControlDevice device, bool enabled,
      {required bool Function() isCurrent});
}

/// 调用 TUICallEngine 真实 Future 接口，并以 CallStore available 事件确认结果。
/// DeviceStore 的 Call 模式摄像头接口会立即乐观返回成功，因此不能用于控制 ACK。
class SdkGroupControlMedia implements GroupControlMedia {
  SdkGroupControlMedia({
    CallStore? store,
    TUICallEngine? engine,
    Future<bool> Function(GroupControlDevice)? requestPermission,
    bool Function()? isFrontCamera,
    this.confirmationTimeout = const Duration(seconds: 4),
  })  : _storeOverride = store,
        _engineOverride = engine,
        _permissionOverride = requestPermission,
        _frontCameraOverride = isFrontCamera;

  /// 原生执行及实际状态确认的最长等待，超时只表示未确认而非设备成功。
  final Duration confirmationTimeout;

  /// 测试显式替换外部依赖，生产仍使用已登录的共享实例，不创建第二套媒体实例。
  final CallStore? _storeOverride;
  final TUICallEngine? _engineOverride;

  /// 仅替换系统权限边界，权限异步完成后仍复核入会有效性。
  final Future<bool> Function(GroupControlDevice)? _permissionOverride;
  final bool Function()? _frontCameraOverride;
  CallStore get _store => _storeOverride ?? CallStore.shared;
  TUICallEngine get _engine => _engineOverride ?? TUICallEngine.instance;

  @override
  Listenable get changes => _store.state.selfInfo;
  @override
  bool get microphoneOn => _store.state.selfInfo.value.isMicrophoneOpened;
  @override
  bool get cameraOn => _store.state.selfInfo.value.isCameraOpened;

  @override
  Future<GroupControlOutcome> setDevice(GroupControlDevice device, bool enabled,
      {required bool Function() isCurrent}) async {
    try {
      // 远端要求打开设备同样受本机系统权限约束，拒绝只回执失败，不挂断整场。
      if (!isCurrent()) return _result(GroupControlStatus.expired);
      if (enabled) {
        final permitted = await (_permissionOverride?.call(device) ??
            _requestPermission(device));
        if (!isCurrent()) return _result(GroupControlStatus.expired);
        if (!permitted) {
          return _result(GroupControlStatus.denied, '未获得设备权限');
        }
      }
      if (!isCurrent()) return _result(GroupControlStatus.expired);
      // 摄像头用公开 openCamera 的原生完成结果；不调用乐观的 experimental 包装。
      if (enabled) {
        final result = await (device == GroupControlDevice.microphone
                ? _engine.openMicrophone()
                : _engine.openCamera(
                    (_frontCameraOverride?.call() ??
                            DeviceStore.shared.state.isFrontCamera.value)
                        ? TUICamera.front
                        : TUICamera.back,
                    null))
            .timeout(confirmationTimeout);
        if (result.code.rawValue != 0) {
          return _result(
              GroupControlStatus.failed, '设备开启失败（${result.code.rawValue}）');
        }
      } else {
        await (device == GroupControlDevice.microphone
                ? _engine.closeMicrophone()
                : _engine.closeCamera())
            .timeout(confirmationTimeout);
      }
      if (!isCurrent()) return _result(GroupControlStatus.expired);
      final observed = await _waitForState(device, enabled, isCurrent);
      return _result(
          observed
              ? GroupControlStatus.success
              : GroupControlStatus.unconfirmed,
          observed ? null : '设备状态尚未确认');
    } on TimeoutException {
      return _result(GroupControlStatus.unconfirmed, '设备操作未在时限内确认');
    } catch (_) {
      return _result(GroupControlStatus.failed, '设备操作失败');
    }
  }

  /// 普通成员和主持远程打开都必须得到本机授权，拒绝不结束整场通话。
  Future<bool> _requestPermission(GroupControlDevice device) async {
    final permission = device == GroupControlDevice.microphone
        ? PermissionType.microphone
        : PermissionType.camera;
    var status = await Permission.check(permission);
    if (status != PermissionStatus.granted &&
        status != PermissionStatus.limited) {
      final requested = await Permission.request([permission]);
      status = requested[permission] ?? PermissionStatus.denied;
    }
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
  }

  /// 原生完成后仍需媒体事实一致；等待期间入会失效立即按未确认处理。
  Future<bool> _waitForState(GroupControlDevice device, bool expected,
      bool Function() isCurrent) async {
    bool matches() =>
        isCurrent() &&
        (device == GroupControlDevice.microphone ? microphoneOn : cameraOn) ==
            expected;
    if (matches()) return true;
    final completed = Completer<bool>();
    void changed() {
      if (!completed.isCompleted && (!isCurrent() || matches())) {
        completed.complete(matches());
      }
    }

    changes.addListener(changed);
    try {
      changed();
      return await completed.future
          .timeout(confirmationTimeout, onTimeout: () => false);
    } finally {
      changes.removeListener(changed);
    }
  }

  GroupControlOutcome _result(GroupControlStatus status, [String? error]) =>
      GroupControlOutcome(status,
          error: error, microphoneOn: microphoneOn, cameraOn: cameraOn);
}
