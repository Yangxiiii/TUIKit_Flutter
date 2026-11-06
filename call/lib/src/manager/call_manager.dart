import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';
import 'package:app_service/app_service.dart';
import 'package:app_ui/app_ui.dart';
import '../common/widget/global.dart';
import '../common/utils/error_parser.dart';
import 'package:tuikit_atomic_x/atomicx.dart';
import 'package:tencent_calls_uikit/src/manager/call_page_router.dart';

/// 统一校验通话入口、权限及设备操作，SDK 负责信令与通话状态。
class CallManager {
  CallManager._();

  static final CallManager _instance = CallManager._();
  static CallManager get instance => _instance;

  CallPageRouter? _pageManager;

  /// 设备准备的异步代次；SDK 在主叫等待时尚未分配 callId，以代次阻止旧结果影响新通话。
  int _deviceEpoch = 0;

  /// 仅记录本次邀请中是否主动操作过设备；开关值始终取 DeviceStore，不复制设备状态。
  final Set<String> _selectedDevices = {};

  /// 新来电、结束及登出使先前尚未完成的设备准备失效。
  void invalidateDevicePreparation() {
    _deviceEpoch++;
    _selectedDevices.clear();
  }

  void bindPageManager(CallPageRouter pageManager) {
    _pageManager = pageManager;
  }

  Future<CompletionHandler> setSelfInfo(UserProfile userInfo) {
    return LoginStore.shared.setSelfInfo(userInfo: userInfo);
  }

  /// 统一验证登录、参与者和忙线，单聊使用 45 秒服务端振铃超时。
  Future<CompletionHandler> calls(
    List<String> userIdList,
    CallMediaType callMediaType, [
    CallParams? params,
  ]) async {
    // 在弹出权限前校验身份和忙线，避免无效操作占用麦克风或覆盖已有通话。
    final selfId = LoginStore.shared.loginState.loginUserInfo?.userID ?? '';
    if (selfId.isEmpty) return _failure(-1201, 'Not logged in');
    if (userIdList.isEmpty ||
        userIdList.any((id) => id.trim().isEmpty || id == selfId)) {
      return _failure(101002, 'Invalid participants');
    }
    if (CallStore.shared.state.activeCall.value.mediaType != null ||
        CallStore.shared.state.selfInfo.value.status !=
            CallParticipantStatus.none) {
      return _failure(-1203, 'Already in a call');
    }
    final epoch = _deviceEpoch;
    final deniedPermission = await _deniedMediaPermission(callMediaType);
    // 权限返回后先核对账号和代次，不能把新来电当作本次缺权限的旧请求拒绝。
    if (LoginStore.shared.loginState.loginUserInfo?.userID != selfId) {
      return _failure(-1201, 'Login changed while requesting permissions');
    }
    if (epoch != _deviceEpoch) {
      return _failure(-1203, 'Call changed while requesting permissions');
    }
    if (deniedPermission != null) {
      await _pageManager?.handleNoPermissionAndEndCall(type: deniedPermission);
      final handler = CompletionHandler();
      handler.errorCode = -1101;
      handler.errorMessage = 'Failed to obtain audio and video permissions';
      return handler;
    }

    // 权限交互期间可能收到来电；再次检查，不能用迟到结果覆盖当前通话。
    if (CallStore.shared.state.activeCall.value.mediaType != null ||
        CallStore.shared.state.selfInfo.value.status !=
            CallParticipantStatus.none) {
      return _failure(-1203, 'Already in a call');
    }
    final effectiveParams = params ?? CallParams();
    if (userIdList.length == 1 && effectiveParams.chatGroupId.isEmpty) {
      effectiveParams.timeout = 45;
    }
    invalidateDevicePreparation();
    return CallStore.shared.calls(userIdList, callMediaType, effectiveParams);
  }

  /// 在 SDK 调用前保持相同的错误返回契约，由统一入口展示已知错误。
  CompletionHandler _failure(int code, String message) => CompletionHandler()
    ..errorCode = code
    ..errorMessage = message;

  Future<CompletionHandler> join(String callId) {
    return CallStore.shared.join(callId);
  }

  /// 权限校验通过且邀请仍有效时接听，失败不触发展开通话。
  Future<bool> accept() => AppServiceLocator.get<ActionGuard>()
      .singleFlight('tim.call.accept', _accept);

  /// 在权限及设备准备结束后再次核对邀请，SDK 失败不打开已接通页面。
  Future<bool> _accept() async {
    final activeCall = CallStore.shared.state.activeCall.value;
    final mediaType = activeCall.mediaType;
    if (mediaType == null) {
      return false;
    }

    final canProceed = await _runPermissionGate(
      callId: activeCall.callId,
      mediaType: mediaType,
    );
    if (!canProceed) {
      return false;
    }
    if (!await _openDevices(mediaType, preserveSelections: true)) return false;
    if (_activeCallMatching(activeCall.callId) == null) return false;
    return _checkResult(await CallStore.shared.accept());
  }

  /// 拒绝与挂断共享结束守卫，只有 SDK 确认成功才返回 true。
  Future<bool> reject() => AppServiceLocator.get<ActionGuard>().singleFlight(
      'tim.call.end',
      () async => _checkResult(await CallStore.shared.reject()));

  /// 结束失败保留现有页面和设备状态，允许后续重试。
  Future<bool> hangup() => AppServiceLocator.get<ActionGuard>().singleFlight(
      'tim.call.end',
      () async => _checkResult(await CallStore.shared.hangup()));

  /// 权限及 SDK 返回成功后才视为麦克风开启，失败不更改界面状态。
  Future<bool> openLocalMicrophone() async {
    final epoch = _deviceEpoch;
    final callId = CallStore.shared.state.activeCall.value.callId;
    final permitted = await _ensurePermission(PermissionType.microphone);
    if (epoch != _deviceEpoch || _activeCallMatching(callId) == null) {
      return false;
    }
    if (!permitted) {
      await _pageManager?.handleNoPermissionAndEndCall(
          type: PermissionType.microphone);
      return false;
    }
    return _checkResult(await DeviceStore.shared.openLocalMicrophone());
  }

  /// 来电等待期间的主动选择在接听时保留，避免默认准备重新开启已关闭设备。
  Future<void> toggleMicrophone() async {
    _selectedDevices.add('microphone');
    if (DeviceStore.shared.state.microphoneStatus.value == DeviceStatus.on) {
      await closeLocalMicrophone();
    } else {
      await openLocalMicrophone();
    }
  }

  /// 摄像头选择只影响本端，接听不会覆盖等待期间的关闭操作。
  Future<void> toggleCamera() async {
    _selectedDevices.add('camera');
    if (DeviceStore.shared.state.cameraStatus.value == DeviceStatus.on) {
      await closeLocalCamera();
    } else {
      await openLocalCamera(DeviceStore.shared.state.isFrontCamera.value);
    }
  }

  /// 保留等待期间主动选择的声音路由。
  Future<void> toggleSpeaker() async {
    _selectedDevices.add('speaker');
    await setAudioRoute(DeviceStore.shared.state.currentAudioRoute.value ==
            AudioRoute.speakerphone
        ? AudioRoute.earpiece
        : AudioRoute.speakerphone);
  }

  Future<void> closeLocalMicrophone() async {
    DeviceStore.shared.closeLocalMicrophone();
  }

  /// 摄像头权限结果只作用于触发操作的当前通话。
  Future<void> openLocalCamera(bool isFront) async {
    final epoch = _deviceEpoch;
    final callId = CallStore.shared.state.activeCall.value.callId;
    final hasPermission = await _ensurePermission(PermissionType.camera);
    if (epoch != _deviceEpoch || _activeCallMatching(callId) == null) return;
    if (!hasPermission) {
      await _pageManager?.handleNoPermissionAndEndCall(
          type: PermissionType.camera);
      return;
    }
    _checkResult(await DeviceStore.shared.openLocalCamera(isFront));
  }

  Future<void> closeLocalCamera() async {
    DeviceStore.shared.closeLocalCamera();
  }

  Future<void> switchCamera(bool isFront) async {
    DeviceStore.shared.switchCamera(isFront);
  }

  Future<void> setAudioRoute(AudioRoute route) async {
    DeviceStore.shared.setAudioRoute(route);
  }

  Future<void> prepareCallDevices({
    required String callId,
    required CallMediaType mediaType,
    required bool isCalled,
  }) async {
    final activeCall = _activeCallMatching(callId);
    if (activeCall == null ||
        activeCall.mediaType != mediaType ||
        (!isCalled &&
            activeCall.inviterId != CallStore.shared.state.selfInfo.value.id)) {
      return;
    }

    final canProceed = await _runPermissionGate(
      callId: callId,
      mediaType: mediaType,
    );
    if (!canProceed) {
      return;
    }
    if (!await _openDevices(mediaType)) await hangup();
  }

  /// 来电预览只使用已授予权限；等待权限检查时结束的邀请不能重新打开摄像头。
  Future<void> openLocalCameraIfPermitted() async {
    final epoch = _deviceEpoch;
    final callId = CallStore.shared.state.activeCall.value.callId;
    final cameraStatus = await Permission.check(PermissionType.camera);
    if (_selectedDevices.contains('camera') ||
        !_isUsable(cameraStatus) ||
        epoch != _deviceEpoch ||
        _activeCallMatching(callId) == null) {
      return;
    }
    _checkResult(await DeviceStore.shared.openLocalCamera(true));
  }

  CallInfo? _activeCallMatching(String expectedCallId) {
    final activeCall = CallStore.shared.state.activeCall.value;
    if (activeCall.mediaType == null ||
        (expectedCallId.isNotEmpty && activeCall.callId != expectedCallId)) {
      return null;
    }
    return activeCall;
  }

  Future<bool> _runPermissionGate({
    required String callId,
    required CallMediaType mediaType,
  }) async {
    final epoch = _deviceEpoch;
    final deniedPermission = await _deniedMediaPermission(mediaType);
    if (epoch != _deviceEpoch || _activeCallMatching(callId) == null) {
      return false;
    }
    if (deniedPermission != null) {
      await _pageManager?.handleNoPermissionAndEndCall(type: deniedPermission);
      return false;
    }
    return true;
  }

  /// 设备准备跟随当前通话代次和 callId，保留等待期间的主动选择，拒绝旧权限结果。
  Future<bool> _openDevices(CallMediaType mediaType,
      {bool preserveSelections = true}) async {
    final epoch = _deviceEpoch;
    final callId = CallStore.shared.state.activeCall.value.callId;
    if (!(preserveSelections && _selectedDevices.contains('microphone')) &&
        !await openLocalMicrophone()) {
      return false;
    }
    if (epoch != _deviceEpoch || _activeCallMatching(callId) == null) {
      return false;
    }
    if (!(preserveSelections && _selectedDevices.contains('speaker'))) {
      await setAudioRoute(mediaType == CallMediaType.audio
          ? AudioRoute.earpiece
          : AudioRoute.speakerphone);
    }
    if (mediaType == CallMediaType.video) {
      if (preserveSelections && _selectedDevices.contains('camera')) {
        return true;
      }
      return _checkResult(await DeviceStore.shared.openLocalCamera(true));
    }
    await closeLocalCamera();
    return true;
  }

  /// 设备和接听结果不能静默丢弃；已知错误使用项目文案，其他错误提供可重试提示。
  bool _checkResult(CompletionHandler result) {
    if (result.errorCode == 0) return true;
    final context = Global.appContext();
    final text = AppLocalization.of(context);
    if (result.errorCode == -1319) {
      AppDialog.showAlert(
        title: text.resolve('chat.uikit.callMicrophoneOccupiedTitle', '麦克风被占用'),
        content: text.resolve('chat.uikit.callMicrophoneOccupiedContent',
            '麦克风正被其他应用占用，无法发起通话，请关闭占用麦克风的程序后重试。'),
        confirmText: text.resolve('chat.uikit.callUnderstood', '我知道了'),
        showCancelButton: false,
        theme: Theme.of(context),
        semanticsIdentifier: 'call.microphoneOccupied',
      );
    } else {
      AppToast.show(
          ErrorParser.getErrorMessage(result.errorCode, text) ??
              text.callFailedToInitiateOrJoinCall,
          duration: const Duration(seconds: 3));
    }
    return false;
  }

  /// 按麦克风、摄像头顺序检查，只向界面返回实际缺失的一项权限。
  Future<PermissionType?> _deniedMediaPermission(
      CallMediaType mediaType) async {
    if (!await _ensurePermission(PermissionType.microphone)) {
      return PermissionType.microphone;
    }
    if (mediaType == CallMediaType.video &&
        !await _ensurePermission(PermissionType.camera)) {
      return PermissionType.camera;
    }
    return null;
  }

  Future<bool> _ensurePermission(PermissionType type) async {
    final status = await Permission.check(type);
    if (_isUsable(status)) {
      return true;
    }
    if (status == PermissionStatus.permanentlyDenied) {
      return false;
    }
    final result = await Permission.request([type]);
    return _isUsable(result[type] ?? PermissionStatus.denied);
  }

  bool _isUsable(PermissionStatus status) =>
      status == PermissionStatus.granted || status == PermissionStatus.limited;
}
