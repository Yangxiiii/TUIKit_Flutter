import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tuikit_atomic_x/atomicx.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';
import '../state/group_control_state.dart';

/// 会控只操作本端设备；远端实际状态必须由目标端执行后通过 ACK 返回。
abstract interface class GroupControlMedia {
  /// 本端设备操作或 SDK 媒体事件引起的状态变化。
  Listenable get changes;

  /// SDK 报告的本端麦克风可用状态。
  bool get microphoneOn;

  /// 本机摄像头状态，按 SDK 的本机开启和关闭结果更新。
  bool get cameraOn;

  /// 执行当前入会的本机设备操作，权限拒绝和 SDK 错误保持非成功。
  Future<GroupControlOutcome> setDevice(GroupControlDevice device, bool enabled,
      {required bool Function() isCurrent});
}

/// 管理本次入会的本机设备操作和状态，入会结束后释放观察者。
class SdkGroupControlMedia extends ChangeNotifier implements GroupControlMedia {
  SdkGroupControlMedia({
    CallStore? store,
    TUICallEngine? engine,
    Future<bool> Function(GroupControlDevice)? requestPermission,
    bool Function()? isFrontCamera,
    int? Function()? readLocalVideoView,
    Listenable? localVideoViewChanges,
    this.confirmationTimeout = const Duration(seconds: 4),
  })  : _storeOverride = store,
        _engineOverride = engine,
        _permissionOverride = requestPermission,
        _readFrontCamera = isFrontCamera,
        _readLocalVideoView = readLocalVideoView,
        _localVideoViewChanges = localVideoViewChanges {
    final self = _store.state.selfInfo.value;
    _selfId = self.id;
    _cameraOn = self.isCameraOpened;
    _observedMicrophone = _microphoneOn = self.isMicrophoneOpened;
    _store.state.selfInfo.addListener(_observeStore);
    unawaited(_observeNative());
  }

  /// 单次原生调用及麦克风关闭状态等待的时间上限。
  final Duration confirmationTimeout;

  /// 接通可能早于预览挂载，稍候句柄；浮窗或后台没有预览时仍可请求开启。
  static const _localVideoViewWait = Duration(milliseconds: 500);

  /// 测试显式替换外部依赖，生产仍使用已登录的共享实例，不创建第二套媒体实例。
  final CallStore? _storeOverride;
  final TUICallEngine? _engineOverride;

  /// 仅替换系统权限边界，权限异步完成后仍复核入会有效性。
  final Future<bool> Function(GroupControlDevice)? _permissionOverride;

  /// 读取本场镜头方向，未提供时首次开启使用前置。
  final bool Function()? _readFrontCamera;
  CallStore get _store => _storeOverride ?? CallStore.shared;
  TUICallEngine get _engine => _engineOverride ?? TUICallEngine.instance;

  /// 仅在本场预览视图仍存活时取得非空原生句柄，浮窗可能没有视图。
  final int? Function()? _readLocalVideoView;

  /// 本端预览句柄变化，开启操作只读取本次入会对应的句柄。
  final Listenable? _localVideoViewChanges;

  /// 媒体事件必须归属本次入会的账号。
  late final String _selfId;

  /// 入会销毁后的迟到事件与结果均不再发布。
  bool _disposed = false;

  /// 最近一次成功返回的本机摄像头操作，驱动按钮及下一次切换。
  late bool _cameraOn;

  /// 保存 SDK 最近一次确认的本机麦克风状态。
  late bool _microphoneOn;

  /// 记录 CallStore 的麦克风原始位，资料更新不能用旧值覆盖操作结果。
  late bool _observedMicrophone;

  /// 保留麦克风的已有确认路径；远端视频流通知不参与本机摄像头状态。
  late final TUICallObserver _observer = TUICallObserver(
      onUserAudioAvailable: (id, enabled) {
        if (id == _selfId) _confirm(GroupControlDevice.microphone, enabled);
      });

  @override
  Listenable get changes => this;
  @override
  bool get microphoneOn => _microphoneOn;
  @override
  bool get cameraOn => _cameraOn;

  /// 保留 CallStore 已有媒体观察链，注册失败时仍可使用明确的开启回调。
  Future<void> _observeNative() async {
    try {
      await _engine.addObserver(_observer);
      if (_disposed) await _engine.removeObserver(_observer);
    } catch (error) {
      debugPrint('会控设备监听初始化失败：$error');
    }
  }

  /// 只消费当前账号的麦克风位变化，跳过其他成员及资料更新。
  void _observeStore() {
    final self = _store.state.selfInfo.value;
    if (self.id != _selfId) return;
    if (_observedMicrophone != self.isMicrophoneOpened) {
      _observedMicrophone = self.isMicrophoneOpened;
      _confirm(GroupControlDevice.microphone, _observedMicrophone);
    }
  }

  /// 只在对应设备状态变化时通知控制器，避免两个按钮互相影响。
  void _confirm(GroupControlDevice device, bool enabled) {
    if (_disposed) return;
    if (device == GroupControlDevice.camera) {
      if (_cameraOn == enabled) return;
      _cameraOn = enabled;
    } else {
      if (_microphoneOn == enabled) return;
      _microphoneOn = enabled;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _store.state.selfInfo.removeListener(_observeStore);
    unawaited(_engine.removeObserver(_observer).catchError((Object error) {
      debugPrint('会控设备监听清理失败：$error');
    }));
    super.dispose();
  }

  @override
  Future<GroupControlOutcome> setDevice(GroupControlDevice device, bool enabled,
      {required bool Function() isCurrent}) async {
    try {
      // 远端要求打开设备同样受本机系统权限约束，拒绝只回执失败，不挂断整场。
      if (!isCurrent() || _disposed) return _result(GroupControlStatus.expired);
      if (enabled) {
        final permitted = await (_permissionOverride?.call(device) ??
            _requestPermission(device));
        if (!isCurrent() || _disposed) return _result(GroupControlStatus.expired);
        if (!permitted) {
          return _result(GroupControlStatus.failed, '未获得设备权限');
        }
      }
      if (!isCurrent() || _disposed) return _result(GroupControlStatus.expired);
      // 标准开启接口有明确回包，失败时保留当前设备状态。
      if (enabled) {
        final result = await _open(device, isCurrent);
        if (!isCurrent() || _disposed) return _result(GroupControlStatus.expired);
        if (result == null) return _result(GroupControlStatus.expired);
        if (result.code.rawValue != 0) {
          return _result(GroupControlStatus.failed,
              '设备开启失败（${result.code.rawValue}）');
        }
        _confirm(device, true);
        return _result(GroupControlStatus.success);
      }
      await (device == GroupControlDevice.microphone
              ? _engine.closeMicrophone()
              : _engine.closeCamera())
          .timeout(confirmationTimeout);
      if (!isCurrent() || _disposed) return _result(GroupControlStatus.expired);
      if (device == GroupControlDevice.camera) {
        // 腾讯关闭接口返回后更新本机状态，避免等待远端视频流变化。
        _confirm(device, false);
        return _result(GroupControlStatus.success);
      }
      final observed = await _waitForMicrophoneOff(isCurrent);
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

  /// 群视频重开时先恢复仍存活的本端预览，再使用 SDK 开启接口的明确回包。
  Future<TUIActionCallback?> _open(
      GroupControlDevice device, bool Function() isCurrent) async {
    if (device == GroupControlDevice.microphone) {
      return _engine.openMicrophone().timeout(confirmationTimeout);
    }
    final viewId = await _waitForLocalVideoView(isCurrent);
    if (_disposed || !isCurrent()) return null;
    if (viewId != null && viewId != 0) {
      await _engine.callExperimentalAPI({
        'api': 'setLocalView',
        'params': {'videoView': viewId},
      }).timeout(confirmationTimeout);
    }
    if (_disposed || !isCurrent()) return null;
    // 绑定期间视图可能销毁或替换，重新读取句柄；无预览时传空值。
    final currentViewId = _readLocalVideoView?.call();
    final isFront = _readFrontCamera?.call() ?? true;
    return _engine
        .openCamera(isFront ? TUICamera.front : TUICamera.back,
            currentViewId == 0 ? null : currentViewId)
        .timeout(confirmationTimeout);
  }

  /// 接通后的首帧可以补齐本端原生句柄，未挂载时仍由 SDK 的开启回包决定结果。
  Future<int?> _waitForLocalVideoView(bool Function() isCurrent) async {
    final changes = _localVideoViewChanges;
    final viewId = _readLocalVideoView?.call();
    if ((viewId != null && viewId != 0) || changes == null) return viewId;

    final ready = Completer<int?>();
    void onViewChanged() {
      if (ready.isCompleted) return;
      final currentViewId = _readLocalVideoView?.call();
      if (_disposed || !isCurrent()) {
        ready.complete(null);
      } else if (currentViewId != null && currentViewId != 0) {
        ready.complete(currentViewId);
      }
    }

    changes.addListener(onViewChanged);
    try {
      onViewChanged();
      return await ready.future.timeout(_localVideoViewWait,
          onTimeout: () => null);
    } finally {
      changes.removeListener(onViewChanged);
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

  /// 保留麦克风关闭的事件确认，等待期间入会失效不能报告成功。
  Future<bool> _waitForMicrophoneOff(bool Function() isCurrent) async {
    bool matches() => !_disposed && isCurrent() && !microphoneOn;
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
