import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';
import 'package:app_service/app_service.dart';
import 'package:app_ui/app_ui.dart';
import '../common/widget/global.dart';
import '../common/utils/error_parser.dart';
import 'package:tuikit_atomic_x/atomicx.dart';
import 'package:tencent_calls_uikit/src/manager/call_page_router.dart';
import '../state/global_state.dart';
import '../state/group_call_metadata.dart';
import '../state/group_control_state.dart';
import 'group_control_controller.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart' show TUICallEngine;

/// 统一校验通话入口、权限及设备操作，SDK 负责信令与通话状态。
class CallManager {
  CallManager._();

  /// 测试通过显式依赖验证权限等待、账号切换及 SDK 失败，不连接真实媒体。
  @visibleForTesting
  CallManager.testing(
      {required CallStore store,
      required String Function() accountId,
      required Future<PermissionType?> Function(CallMediaType)
          requestPermission,
      Future<String?> Function(String)? queryGroupTitle,
      Future<void> Function()? suspendGroupDevices})
      : _storeOverride = store,
        _accountOverride = accountId,
        _permissionOverride = requestPermission,
        _groupTitleOverride = queryGroupTitle,
        _suspendGroupDevicesOverride = suspendGroupDevices ?? (() async {});

  /// 当前真实入会的会控入口；无策略时仍允许关闭设备，但不得自行开启。
  GroupControlController? get groupControl =>
      GlobalState.instance.groupControlController;

  /// 群来源、独立多人展示标识或正在加入的场次都必须先同步当前媒体策略。
  bool get _groupPolicyRequired =>
      _joiningCallId != null ||
      GlobalState.instance.groupCall.value?.ended == false ||
      _store.state.activeCall.value.chatGroupId.isNotEmpty ||
      _store.state.activeCall.value.inviteeIds.length > 1;

  /// 在 SDK accept/join 前实际关闭设备；系统接通是否短暂自动采集仍需跨端实测。
  Future<void> _suspendGroupDevices() async {
    if (_suspendGroupDevicesOverride != null) {
      await _suspendGroupDevicesOverride!();
      return;
    }
    await Future.wait([
      TUICallEngine.instance.closeMicrophone(),
      TUICallEngine.instance.closeCamera(),
    ]);
  }

  static final CallManager _instance = CallManager._();
  static CallManager get instance => _instance;

  CallPageRouter? _pageManager;

  /// 单元测试替身；生产路径始终使用腾讯共享 Store。
  CallStore? _storeOverride;

  /// 测试可改变账号，以验证等待中的操作不会跨账号执行。
  String Function()? _accountOverride;

  /// 测试模拟系统权限弹窗的延迟与拒绝结果。
  Future<PermissionType?> Function(CallMediaType)? _permissionOverride;

  /// 群资料测试入口；正式环境读取腾讯公开 GroupStore。
  Future<String?> Function(String)? _groupTitleOverride;

  /// 测试注入真实关闭动作的延迟或失败，不跳过生产入会前的媒体关闭阶段。
  Future<void> Function()? _suspendGroupDevicesOverride;

  CallStore get _store => _storeOverride ?? CallStore.shared;

  /// 每次读取当前已登录身份，异步操作前后均以此核对账号。
  String get _accountId =>
      _accountOverride?.call() ??
      LoginStore.shared.loginState.loginUserInfo?.userID ??
      '';

  /// 本地选人与提交共用的总人数上限，含本人及等待接听的成员。
  static const maxParticipants = 9;

  /// 仅用于重新发起的参数副本；不保存或恢复已结束的 SDK callId。
  ({
    String accountId,
    List<String> ids,
    CallMediaType mediaType,
    CallParams params
  })? _lastGroupRequest;

  /// 跨发起和加入共用准入锁；不同入口不能把对方的成功结果误当作自己的成功。
  bool _admissionRunning = false;

  /// join 先进入房间再获得媒体类型，仅为当前加入过程补齐设备准备。
  String? _joiningCallId;

  /// 供选人流程核对生命周期；结束、登出及新来电都会使旧代次失效。
  int get sessionEpoch => _deviceEpoch;

  /// 设备准备的异步代次；SDK 在主叫等待时尚未分配 callId，以代次阻止旧结果影响新通话。
  int _deviceEpoch = 0;

  /// 仅记录本次邀请中是否主动操作过设备；开关值始终取 DeviceStore，不复制设备状态。
  final Set<String> _selectedDevices = {};

  /// 新来电、结束及登出使先前尚未完成的设备准备失效。
  void invalidateDevicePreparation() {
    _deviceEpoch++;
    _selectedDevices.clear();
    _joiningCallId = null;
  }

  void bindPageManager(CallPageRouter pageManager) {
    _pageManager = pageManager;
  }

  Future<CompletionHandler> setSelfInfo(UserProfile userInfo) {
    return LoginStore.shared.setSelfInfo(userInfo: userInfo);
  }

  /// 统一入口合并重复发起，群及临时多人同样使用 45 秒首次邀请。
  Future<CompletionHandler> calls(
          List<String> userIdList, CallMediaType callMediaType,
          [CallParams? params]) =>
      AppServiceLocator.get<ActionGuard>().singleFlight((
        'tim.call.admission.start',
        _accountId
      ), () => _withAdmission(() => _calls(userIdList, callMediaType, params)));

  /// 权限前后校验账号和忙线，输入去重后按包含本人的容量提交。
  Future<CompletionHandler> _calls(List<String> userIdList,
      CallMediaType mediaType, CallParams? params) async {
    final accountId = _accountId;
    if (accountId.isEmpty) return _failure(-1201, 'Not logged in');
    final ids = userIdList.toSet().toList();
    if (ids.isEmpty ||
        ids.any(
            (id) => id.trim().isEmpty || id != id.trim() || id == accountId)) {
      return _failure(101002, 'Invalid participants');
    }
    if (ids.length + 1 > maxParticipants) {
      return _failure(101010, 'Too many participants');
    }
    if (_isBusy) return _failure(-1203, 'Already in a call');
    // 在权限弹窗前冻结宿主参数，不能被弹窗期间的外部改写改变通话来源。
    final effectiveParams = _copyParams(params ?? CallParams())..timeout = 45;
    final epoch = _deviceEpoch;
    final denied = await (_permissionOverride?.call(mediaType) ??
        _deniedMediaPermission(mediaType));
    // 权限弹窗期间的新来电、账号切换和结束不能被旧请求覆盖。
    if (accountId != _accountId) return _failure(-1201, 'Login changed');
    if (epoch != _deviceEpoch || _isBusy) {
      return _failure(-1203, 'Call changed');
    }
    if (denied != null) {
      await _pageManager?.handleNoPermissionAndEndCall(type: denied);
      return _failure(-1101, 'Media permission denied');
    }
    // 只有通过准入才开启新代次，展示快照不改变 SDK 有效会话。
    invalidateDevicePreparation();
    final requestEpoch = _deviceEpoch;
    final isGroup = effectiveParams.chatGroupId.isNotEmpty ||
        ids.length > 1 ||
        GroupCallMetadata.isTemporaryMulti(effectiveParams.userData);
    final history = GlobalState.instance.groupCallSession;
    final previousResult = history.value;
    final previousRequest = _lastGroupRequest;
    if (isGroup) {
      _lastGroupRequest = (
        accountId: accountId,
        ids: List.unmodifiable(ids),
        mediaType: mediaType,
        params: effectiveParams
      );
      history.begin(
          callId: '',
          groupId: effectiveParams.chatGroupId,
          groupName:
              GlobalState.instance.groupCallTitle(effectiveParams.chatGroupId),
          inviterId: accountId,
          mediaType: mediaType,
          memberIds: [accountId, ...ids]);
    } else {
      _lastGroupRequest = null;
      history.clear();
    }
    final result =
        await _sdkResult(() => _store.calls(ids, mediaType, effectiveParams));
    if (accountId != _accountId || requestEpoch != _deviceEpoch) {
      return _failure(-1203, 'Call changed');
    }
    if (result.errorCode != 0 && isGroup) {
      // 重呼失败仍可再次尝试；仅恢复只读结束结果，绝不恢复旧 SDK 会话或设备。
      history.value = previousResult?.ended == true ? previousResult : null;
      _lastGroupRequest =
          previousResult?.canRetry == true ? previousRequest : null;
    }
    return result;
  }

  bool get _isBusy =>
      _store.state.activeCall.value.mediaType != null ||
      _store.state.selfInfo.value.status != CallParticipantStatus.none;

  /// 返回当前已加入或邀请中的占位成员，始终包含本人。
  Set<String> get occupiedUserIds => {
        if (_accountId.isNotEmpty) _accountId,
        for (final member in _store.state.allParticipants.value)
          if (member.id.isNotEmpty &&
              member.status != CallParticipantStatus.none)
            member.id,
        // 成员资料异步补齐期间，已知的真实邀请仍占用人数，避免短暂少算容量。
        if (GlobalState.instance.groupCall.value case final snapshot?
            when !snapshot.ended &&
                snapshot.callId == _store.state.activeCall.value.callId)
          for (final member in snapshot.members)
            if (member.status == GroupCallMemberStatus.waiting ||
                member.status == GroupCallMemberStatus.joined)
              member.id,
      };

  /// 追加邀请只作用于触发选人的原场次；SDK 仍负责最终并发准入。
  Future<CompletionHandler> invite(List<String> userIds,
          {required String expectedCallId}) =>
      AppServiceLocator.get<ActionGuard>()
          .singleFlight(('tim.call.invite', expectedCallId), () async {
        final accountId = _accountId;
        final epoch = _deviceEpoch;
        final current = _store.state.activeCall.value;
        if (accountId.isEmpty) return _failure(-1201, 'Not logged in');
        if (expectedCallId.isEmpty ||
            current.callId != expectedCallId ||
            current.mediaType == null ||
            _store.state.selfInfo.value.status !=
                CallParticipantStatus.accept) {
          return _failure(101002, 'Call is not active');
        }
        if (userIds.any((id) => id.trim().isEmpty || id != id.trim())) {
          return _failure(101002, 'Invalid participants');
        }
        // 选人期间其他成员可能加入，提交前以实时占位重新去重并复核九人上限。
        final occupied = occupiedUserIds;
        final ids = userIds.toSet().difference(occupied).toList();
        if (ids.isEmpty) return _failure(101002, 'No new participants');
        if (occupied.length + ids.length > maxParticipants) {
          return _failure(101010, 'Too many participants');
        }
        final result = await _sdkResult(() => _store.invite(ids, CallParams()));
        if (accountId != _accountId ||
            epoch != _deviceEpoch ||
            _store.state.activeCall.value.callId != expectedCallId) {
          return _failure(-1203, 'Call changed');
        }
        // Store 不暴露逐用户失败名单；只按后续真实成员事件改变邀请状态。
        return result;
      });

  /// 加入已有有效 callId，身份、忙线和权限等待沿用发起入口的边界。
  Future<CompletionHandler> join(String callId) =>
      AppServiceLocator.get<ActionGuard>().singleFlight(
          ('tim.call.admission.join', _accountId),
          () => _withAdmission(() async {
                final accountId = _accountId;
                if (accountId.isEmpty) return _failure(-1201, 'Not logged in');
                if (callId.trim().isEmpty || callId != callId.trim()) {
                  return _failure(101002, 'Invalid callId');
                }
                if (_isBusy) return _failure(-1203, 'Already in a call');
                // 先申请音频权限；join 的真实媒体类型由后续 SDK 接通事件补齐。
                final epoch = _deviceEpoch;
                final denied =
                    await (_permissionOverride?.call(CallMediaType.audio) ??
                        _deniedMediaPermission(CallMediaType.audio));
                if (accountId != _accountId) {
                  return _failure(-1201, 'Login changed');
                }
                if (epoch != _deviceEpoch || _isBusy) {
                  return _failure(-1203, 'Call changed');
                }
                if (denied != null) {
                  await _pageManager?.handleNoPermissionAndEndCall(
                      type: denied);
                  return _failure(-1101, 'Media permission denied');
                }
                // 新场次不携带旧重呼结果，迟到的 SDK 返回只能报告场次已变化。
                invalidateDevicePreparation();
                final requestEpoch = _deviceEpoch;
                _lastGroupRequest = null;
                GlobalState.instance.groupCallSession.clear();
                _joiningCallId = callId;
                final result = await _sdkResult(() async {
                  await _suspendGroupDevices();
                  // 关闭本端设备也跨越原生异步边界，不能让旧加入随后进入新场次。
                  if (accountId != _accountId ||
                      requestEpoch != _deviceEpoch ||
                      _joiningCallId != callId) {
                    return _failure(-1203, 'Call changed');
                  }
                  return _store.join(callId);
                });
                if (result.errorCode != 0 && _joiningCallId == callId) {
                  _joiningCallId = null;
                }
                if (accountId != _accountId || requestEpoch != _deviceEpoch) {
                  return _failure(-1203, 'Call changed');
                }
                return result;
              }));

  /// 读取被叫或加入场次的真实群名，迟到结果不能写入其他账号或新场次。
  Future<void> refreshGroupCallTitle() async {
    final call = _store.state.activeCall.value;
    final groupId = call.chatGroupId;
    final callId = call.callId;
    final accountId = _accountId;
    final epoch = _deviceEpoch;
    if (accountId.isEmpty ||
        groupId.isEmpty ||
        callId.isEmpty ||
        GlobalState.instance.groupCallTitle(groupId).isNotEmpty) {
      return;
    }
    await AppServiceLocator.get<ActionGuard>().singleFlight(
        ('tim.call.groupTitle', accountId, epoch, callId, groupId), () async {
      try {
        // 复用腾讯公开群资料查询，不用群 ID 或通话发起人伪造群名称。
        final String? title;
        if (_groupTitleOverride != null) {
          title = await _groupTitleOverride!(groupId);
        } else {
          final result = await GroupStore.shared.getGroupInfo(groupID: groupId);
          title = result.errorCode == 0 && result.groupInfo?.groupID == groupId
              ? result.groupInfo?.groupName
              : null;
        }
        // 查询期间可能结束、登出或进入同群的新通话，缓存和界面必须一起丢弃旧结果。
        if (title == null ||
            title.isEmpty ||
            accountId != _accountId ||
            epoch != _deviceEpoch ||
            _store.state.activeCall.value.callId != callId ||
            _store.state.activeCall.value.chatGroupId != groupId) {
          return;
        }
        GlobalState.instance.setGroupCallTitle(groupId, title);
      } catch (_) {
        // 群资料失败不影响已建立的通话，界面继续使用类型文案。
      }
    });
  }

  /// 全员未接后的重呼重新创建通话，不能对已经结束的 callId 执行 invite。
  Future<CompletionHandler> retryGroupCall() async {
    final request = _lastGroupRequest;
    if (request == null ||
        request.accountId != _accountId ||
        GlobalState.instance.groupCall.value?.canRetry != true) {
      return _failure(101002, 'Nothing to retry');
    }
    return calls(request.ids, request.mediaType,
        _copyParams(request.params)..roomId = '');
  }

  /// 结果页关闭只清理展示快照，已经结束的 SDK 会话无需再次挂断。
  void dismissGroupCallResult() {
    if (GlobalState.instance.groupCall.value?.ended != true) return;
    clearGroupRequest();
    _pageManager?.closeAllPage();
  }

  /// 新账号或新来电不能沿用上一场的重呼参数。
  void clearGroupRequest() {
    _lastGroupRequest = null;
    GlobalState.instance.groupCallSession.clear();
  }

  /// 不改写调用方持有的可变参数，重呼只保留明确公开的 SDK 字段。
  CallParams _copyParams(CallParams params) => CallParams(
      roomId: params.roomId,
      timeout: params.timeout,
      userData: params.userData,
      chatGroupId: params.chatGroupId,
      isEphemeralCall: params.isEphemeralCall,
      cloudRecordPolicy: params.cloudRecordPolicy,
      offlinePushTitle: params.offlinePushTitle,
      offlinePushDescription: params.offlinePushDescription);

  /// 不同入口竞争时返回忙线；所有结束路径都释放锁，异常转换为可展示失败。
  Future<CompletionHandler> _withAdmission(
      Future<CompletionHandler> Function() action) async {
    if (_admissionRunning) return _failure(-1203, 'Call admission in progress');
    _admissionRunning = true;
    try {
      return await _sdkResult(action);
    } finally {
      _admissionRunning = false;
    }
  }

  /// SDK 抛出的异常也转为统一失败结果，调用方才能恢复按钮并展示错误。
  Future<CompletionHandler> _sdkResult(
      Future<CompletionHandler> Function() action) async {
    try {
      return await action();
    } catch (_) {
      return _failure(-3301, 'SDK operation failed');
    }
  }

  /// 本地边界错误沿用 SDK 完成结果契约，统一由调用方展示。
  CompletionHandler _failure(int code, String message) => CompletionHandler()
    ..errorCode = code
    ..errorMessage = message;

  /// 权限校验通过且邀请仍有效时接听，失败不触发展开通话。
  Future<bool> accept() => AppServiceLocator.get<ActionGuard>()
      .singleFlight('tim.call.accept', _accept);

  /// 在权限及设备准备结束后再次核对邀请，SDK 失败不打开已接通页面。
  Future<bool> _accept() async {
    final activeCall = _store.state.activeCall.value;
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
    return _checkResult(await _store.accept());
  }

  /// 拒绝与挂断共享结束守卫，只有 SDK 确认成功才返回 true。
  Future<bool> reject() => AppServiceLocator.get<ActionGuard>().singleFlight(
      'tim.call.end', () async => _checkResult(await _store.reject()));

  /// 普通离开先交接；到期结束直接释放媒体，不能等待网络交接延长会期。
  Future<bool> hangup({bool transferHost = true}) =>
      AppServiceLocator.get<ActionGuard>().singleFlight(
          transferHost ? 'tim.call.end' : 'tim.call.deadline.end', () async {
        final account = _accountId;
        final epoch = _deviceEpoch;
        final callId = _store.state.activeCall.value.callId;
        final controller = groupControl;
        GroupControlResult? transfer;
        if (!transferHost) {
          // 到期使用独立守卫，不能被正在等待 ACK 的普通离开流程阻塞。
          // 并行安全关闭只是补充，原生关闭失败仍必须继续请求 SDK hangup 释放资源。
          unawaited(_suspendGroupDevices()
              .catchError((Object error, StackTrace stack) {
            appLogger.error('通话到期关闭本端设备失败', error: error, stackTrace: stack);
          }));
        } else if (controller?.value.canManage == true) {
          transfer = await controller!.prepareLeave();
        }
        // 交接可能等待网络；期间结束、换账号或新来电时不得挂断新的场次。
        if (account != _accountId ||
            epoch != _deviceEpoch ||
            callId != _store.state.activeCall.value.callId) {
          return false;
        }
        // 主持交接未确认不能困住用户，SDK 挂断始终优先释放本端媒体。
        final success = _checkResult(await _sdkResult(_store.hangup));
        if (success && transfer?.success == false) {
          AppToast.show('已离开通话，主持交接尚未全部确认');
        }
        return success;
      });

  /// 权限及 SDK 返回成功后才视为麦克风开启，失败不更改界面状态。
  Future<bool> openLocalMicrophone() async {
    if (_groupPolicyRequired) {
      final control = groupControl;
      if (control == null) return false;
      return (await control.setSelfDevice(GroupControlDevice.microphone, true))
          .success;
    }
    final epoch = _deviceEpoch;
    final callId = _store.state.activeCall.value.callId;
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
    if (_groupPolicyRequired) {
      final control = groupControl;
      if (control != null) {
        await control.setSelfDevice(
            GroupControlDevice.microphone, !control.value.microphoneOn);
      } else {
        await closeLocalMicrophone();
      }
      return;
    }
    _selectedDevices.add('microphone');
    if (DeviceStore.shared.state.microphoneStatus.value == DeviceStatus.on) {
      await closeLocalMicrophone();
    } else {
      await openLocalMicrophone();
    }
  }

  /// 摄像头选择只影响本端，接听不会覆盖等待期间的关闭操作。
  Future<void> toggleCamera() async {
    if (_groupPolicyRequired) {
      final control = groupControl;
      if (control != null) {
        await control.setSelfDevice(
            GroupControlDevice.camera, !control.value.cameraOn);
      } else {
        await closeLocalCamera();
      }
      return;
    }
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

  /// 关闭无需会控授权，未知策略阶段仍允许停止采集；原生失败由调用方处理。
  Future<void> closeLocalMicrophone() async {
    if (_groupPolicyRequired && _storeOverride == null) {
      await TUICallEngine.instance.closeMicrophone();
      return;
    }
    DeviceStore.shared.closeLocalMicrophone();
  }

  /// 摄像头权限结果只作用于触发操作的当前通话。
  Future<void> openLocalCamera(bool isFront) async {
    if (_groupPolicyRequired) {
      await groupControl?.setSelfDevice(GroupControlDevice.camera, true);
      return;
    }
    final epoch = _deviceEpoch;
    final callId = _store.state.activeCall.value.callId;
    final hasPermission = await _ensurePermission(PermissionType.camera);
    if (epoch != _deviceEpoch || _activeCallMatching(callId) == null) return;
    if (!hasPermission) {
      await _pageManager?.handleNoPermissionAndEndCall(
          type: PermissionType.camera);
      return;
    }
    _checkResult(await DeviceStore.shared.openLocalCamera(isFront));
  }

  /// 关闭摄像头始终允许，不以权限开关或当前主持状态阻止资源释放。
  Future<void> closeLocalCamera() async {
    if (_groupPolicyRequired && _storeOverride == null) {
      await TUICallEngine.instance.closeCamera();
      return;
    }
    DeviceStore.shared.closeLocalCamera();
  }

  /// 该 SDK 的镜头切换为无返回值接口，只能捕获同步异常，不能确认硬件成功。
  Future<void> switchCamera(bool isFront) async {
    try {
      DeviceStore.shared.switchCamera(isFront);
    } catch (_) {
      _checkResult(_failure(-3301, 'Camera switch failed'));
    }
  }

  Future<void> setAudioRoute(AudioRoute route) async {
    DeviceStore.shared.setAudioRoute(route);
  }

  /// 只有本端主动 join 才补齐真实媒体类型，普通接听保留其原权限流程。
  Future<void> prepareJoinedCallDevices(String callId) async {
    final call = _activeCallMatching(callId);
    if (_joiningCallId != callId || call?.mediaType == null) return;
    _joiningCallId = null;
    await prepareCallDevices(
        callId: callId, mediaType: call!.mediaType!, isCalled: true);
  }

  /// 按真实媒体类型准备设备，异步权限和设备返回均受本场代次约束。
  Future<void> prepareCallDevices({
    required String callId,
    required CallMediaType mediaType,
    required bool isCalled,
  }) async {
    final activeCall = _activeCallMatching(callId);
    if (activeCall == null ||
        activeCall.mediaType != mediaType ||
        (!isCalled && activeCall.inviterId != _store.state.selfInfo.value.id)) {
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
    if (_groupPolicyRequired) return;
    final epoch = _deviceEpoch;
    final callId = _store.state.activeCall.value.callId;
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
    final activeCall = _store.state.activeCall.value;
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
    if (_groupPolicyRequired) {
      final epoch = _deviceEpoch;
      final result = await _sdkResult(() async {
        await _suspendGroupDevices();
        return CompletionHandler();
      });
      return epoch == _deviceEpoch && _checkResult(result);
    }
    final epoch = _deviceEpoch;
    final callId = _store.state.activeCall.value.callId;
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
