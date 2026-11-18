import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:app_service/app_service.dart';
import 'package:app_ui/app_ui.dart';
import 'manager/call_duration_limit.dart';
import 'manager/group_member_subtitle_cache.dart';
import 'manager/group_control_lifecycle.dart';
import 'control/group_control_transport.dart';
import 'manager/group_call_result_tracker.dart';
import 'state/group_call_metadata.dart';

import 'package:tencent_calls_uikit/src/common/metrics/key_metrics.dart';
import 'package:tuikit_atomic_x/atomicx.dart';
import 'package:tencent_calls_uikit/src/common/widget/global.dart';
import 'package:tencent_calls_uikit/src/common/utils/app_lifecycle.dart';
import 'package:tencent_calls_uikit/src/common/utils/foreground_service.dart';
import 'package:tencent_calls_uikit/src/feature/calling_bell_feature.dart';
import 'package:tencent_calls_uikit/src/manager/call_manager.dart';
import 'package:tencent_calls_uikit/src/state/global_state.dart';
import 'package:tencent_calls_uikit/src/tui_call_kit.dart';
import 'package:tencent_cloud_uikit_core/tencent_cloud_uikit_core.dart';
import 'package:tencent_calls_uikit/src/manager/call_page_router.dart';
import 'bridge/bootloader/bootloader.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart' hide CallEndReason;
import 'bridge/voip/fcm_data_sync_handler.dart';
import 'bridge/voip/voip_data_sync_handler.dart';
import 'common/utils/error_parser.dart';
import 'feature/ios_pip_feature.dart';

/// 协调通话界面与 IM 登录状态，并向上层传递 SDK 操作结果。
class TUICallKitImpl implements TUICallKit {
  static final TUICallKitImpl _instance = TUICallKitImpl();
  static TUICallKitImpl get instance => _instance;
  late final CallPageRouter pageRouter;
  IosPipFeature? pictureInPictureFeature;
  late final VoIPDataSyncHandler voIPDataSyncHandler;
  late final FcmDataSyncHandler fcmDataSyncHandler;
  final contactStore = ContactStore.shared;
  bool isNotificationPreparing = false;

  /// 宿主机构岗位资料只缓存当前账号和当前群场次，登出时清理待返回查询。
  late final GroupMemberSubtitleCache _memberSubtitleCache;

  /// 以真实 SDK 接通、成员及结束事件管理本次入会的控制 session。
  late final GroupControlLifecycle _groupControlLifecycle;

  /// 本人真实参与区间独立于房间计时，结束后通过宿主发布个人结果。
  late final GroupCallResultTracker _groupCallResultTracker;

  /// 时长限制独立于页面；群场次消费可信统一截止，SDK 时长仅作补充。
  late final _durationLimit = CallDurationLimit(onLimit: () async {
    if (!await CallManager.instance.hangup(transferHost: false)) {
      throw StateError('Call duration limit hangup failed');
    }
    AppToast.show(
        AppLocalization.of(Global.appContext())
            .resolve('chat.uikit.callDurationLimit', '已达通话最长时长，通话结束'),
        duration: const Duration(seconds: 3));
  });

  /// 成员回调补齐 Store 会移除的邀请结果，不传输自定义会控协议。
  late final TUICallObserver _groupObserver = TUICallObserver(
    onUserInviting: (id) => _onGroupMember(id, GroupCallMemberStatus.waiting),
    onUserJoin: (id) => _onGroupMember(id, GroupCallMemberStatus.joined),
    onUserReject: (id) => _onGroupMember(id, GroupCallMemberStatus.rejected),
    onUserNoResponse: (id) =>
        _onGroupMember(id, GroupCallMemberStatus.noResponse),
    onUserLineBusy: (id) => _onGroupMember(id, GroupCallMemberStatus.busy),
    onUserLeave: (id) => _onGroupMember(id, GroupCallMemberStatus.left),
    onCallBegin: (callId, mediaType, info) {
      _syncGroupCall();
      GlobalState.instance.groupCallSession.updateMember(
          CallStore.shared.state.selfInfo.value.id,
          GroupCallMemberStatus.joined);
      unawaited(CallManager.instance.refreshGroupCallTitle());
      // join 的早期 Store 事件尚无准确媒体类型，真实接通后补齐本端设备准备。
      unawaited(CallManager.instance.prepareJoinedCallDevices(callId));
    },
  );

  /// 应用层仅保留本场成员展示；底层事件未提供 callId 时以当前有效场次为边界。
  void _onGroupMember(String userId, GroupCallMemberStatus status) {
    _syncGroupCall();
    GlobalState.instance.groupCallSession.updateMember(userId, status);
  }

  /// 从 SDK 补齐群标识和资料，空状态及已结束旧场次不会重新打开结果。
  void _syncGroupCall() {
    final call = CallStore.shared.state.activeCall.value;
    if (call.mediaType == null) return;
    final session = GlobalState.instance.groupCallSession;
    final previous = session.value;
    if (previous?.ended == true && previous?.callId == call.callId) return;
    // 只在 SDK 已给出群或多人事实时创建快照；两人临时多人由明确展示元数据创建。
    final participants = CallStore.shared.state.allParticipants.value;
    final group = call.chatGroupId.isNotEmpty ||
        call.inviteeIds.length > 1 ||
        participants.length > 2;
    if (previous == null ||
        (previous.ended && previous.callId != call.callId)) {
      if (!group) return;
      session.begin(
          callId: call.callId,
          groupId: call.chatGroupId,
          groupName: GlobalState.instance.groupCallTitle(call.chatGroupId),
          inviterId: call.inviterId,
          mediaType: call.mediaType!,
          memberIds: {
            call.inviterId,
            ...call.inviteeIds,
            CallStore.shared.state.selfInfo.value.id,
            ...participants.map((member) => member.id),
          });
    }
    // 资料补齐不会删除已拒绝或超时成员，也不会重新激活已结束的场次。
    session.sync(call, participants);
  }

  /// 共享 Store 的场次回调，负责界面路由、设备准备及结束后的展示清理。
  late CallEventListener callEventListener = CallEventListener(
    onCallStarted: (callId, mediaType) async {
      await CallManager.instance.prepareCallDevices(
        callId: callId,
        mediaType: mediaType,
        isCalled: false,
      );
      if (GlobalState.instance.enableAITranscriber) {
        aiTranscriberConfigManager.start();
      }
    },
    onCallReceived:
        (String callId, CallMediaType mediaType, String userData) async {
      CallManager.instance.invalidateDevicePreparation();
      CallManager.instance.clearGroupRequest();
      // 腾讯真实群来源优先；展示标识只能补充独立多人，不能改写群关系或权限。
      final call = CallStore.shared.state.activeCall.value;
      if (call.chatGroupId.isEmpty &&
          GroupCallMetadata.isTemporaryMulti(userData)) {
        GlobalState.instance.groupCallSession.begin(
            callId: callId,
            groupId: '',
            groupName: '',
            inviterId: call.inviterId,
            mediaType: mediaType,
            memberIds: {
              call.inviterId,
              ...call.inviteeIds,
              CallStore.shared.state.selfInfo.value.id
            });
      }
      _syncGroupCall();
      unawaited(CallManager.instance.refreshGroupCallTitle());
      // SDK 先通知待接听状态，再补充多人元数据；补齐资料不能把来电横幅强制展开。
      _showPage();
      KeyMetrics.instance.countUV(EventId.received);
      if (mediaType == CallMediaType.video) {
        await CallManager.instance.openLocalCameraIfPermitted();
      }
    },
    onCallEnded: (callId, mediaType, reason, userId) {
      _groupControlLifecycle.clear();
      CallManager.instance.invalidateDevicePreparation();
      unawaited(CallManager.instance
          .closeLocalMicrophone()
          .catchError((Object error, StackTrace stack) {
        // SDK 结束仍继续原生资源回收，补充关闭失败不能中断结果记录与界面清理。
        appLogger.error('通话结束补充关闭麦克风失败', error: error, stackTrace: stack);
      }));
      aiTranscriberConfigManager.reset(preserveSettings: false);
      final session = GlobalState.instance.groupCallSession;
      session.end(callId, reason,
          isCaller: session.value?.inviterId ==
              LoginStore.shared.loginState.loginUserInfo?.userID);
      // 个人记录发送失败不能阻断 SDK 清理；迟到异常不显示到另一个登录账号。
      final reporter = LoginStore.shared.loginState.loginUserInfo?.userID;
      unawaited(_groupCallResultTracker
          .onEnded(callId, reason)
          .catchError((Object error, StackTrace stack) {
        appLogger.error('通话结果记录失败', error: error, stackTrace: stack);
        if (reporter == LoginStore.shared.loginState.loginUserInfo?.userID) {
          AppToast.show('通话已结束，结果记录保存失败');
        }
      }));
      if (session.value?.canRetry == true) {
        // 只留下结果页；SDK 继续执行结束及设备回收，重呼会生成新场次。
        pageRouter.showCallingPage();
      } else {
        _closePage();
      }
      ForegroundService.stop();
      if (_durationLimit.isEnding(callId)) return;
      final call = CallStore.shared.state.activeCall.value;
      if (call.inviteeIds.length > 1 || call.chatGroupId.isNotEmpty) return;
      final local = CallStore.shared.state.selfInfo.value.id == userId;
      final text = AppLocalization.of(Global.appContext());
      final String? message = switch (reason) {
        CallEndReason.hangup =>
          text.resolve('chat.uikit.callEndedToast', '通话结束'),
        CallEndReason.canceled =>
          local ? text.resolve('chat.uikit.callCancelledToast', '呼叫已取消') : null,
        CallEndReason.reject =>
          local ? null : text.callOtherPartyDeclinedCallRequest,
        CallEndReason.noResponse || CallEndReason.offline => local
            ? null
            : text.resolve('chat.uikit.callUnavailableToast', '暂时无法接通，建议稍后尝试'),
        CallEndReason.lineBusy => text.callOtherPartyBusy,
        _ => null,
      };
      if (message != null) {
        AppToast.show(message, duration: const Duration(seconds: 3));
      }
    },
  );

  TUICallKitImpl() {
    CallStore.shared;
    _groupControlLifecycle = GroupControlLifecycle();
    _groupCallResultTracker = GroupCallResultTracker(
        session: GlobalState.instance.groupCallSession,
        accountId: () =>
            LoginStore.shared.loginState.loginUserInfo?.userID ?? '');
    _memberSubtitleCache = GroupMemberSubtitleCache(
        session: GlobalState.instance.groupCallSession,
        accountId: () =>
            LoginStore.shared.loginState.loginUserInfo?.userID ?? '');
    voIPDataSyncHandler = VoIPDataSyncHandler();
    fcmDataSyncHandler = FcmDataSyncHandler();
    pageRouter = CallPageRouter(
      navigatorGetter: () => Bootloader.instance.navigator,
    );
    CallManager.instance.bindPageManager(pageRouter);
    _subscribeState();
  }

  @override
  Future<CompletionHandler> login(
    int sdkAppId,
    String userId,
    String userSig,
  ) async {
    final completer = Completer<CompletionHandler>();
    TUILogin.instance.login(
      sdkAppId,
      userId,
      userSig,
      TUICallback(
        onSuccess: () {
          CompletionHandler handler = CompletionHandler();
          handler.errorCode = 0;
          handler.errorMessage = "success";
          completer.complete(handler);
        },
        onError: (code, message) {
          handleErrorCode(code);
          CompletionHandler handler = CompletionHandler();
          handler.errorCode = code;
          handler.errorMessage = message;
          completer.complete(handler);
        },
      ),
    );
    return completer.future;
  }

  @override
  Future<void> logout() => logoutIm();

  /// 等待 IM SDK 登出完成；失败时把错误交给会话清理调用方。
  static Future<void> logoutIm() async {
    await TUILogin.instance.logout(
      TUICallback(
        onSuccess: () {},
        onError: (code, message) =>
            throw StateError('腾讯云 IM 登出失败：$code $message'),
      ),
    );
  }

  @override
  Future<CompletionHandler> setSelfInfo(String nickname, String avatar) async {
    UserProfile userInfo = UserProfile(
      userID: LoginStore.shared.loginState.loginUserInfo!.userID,
      nickname: nickname,
      avatarURL: avatar,
      selfSignature: LoginStore.shared.loginState.loginUserInfo!.selfSignature,
      gender: LoginStore.shared.loginState.loginUserInfo!.gender,
      role: LoginStore.shared.loginState.loginUserInfo!.role,
      level: LoginStore.shared.loginState.loginUserInfo!.level,
      birthday: LoginStore.shared.loginState.loginUserInfo!.birthday,
      allowType: LoginStore.shared.loginState.loginUserInfo!.allowType,
      customInfo: LoginStore.shared.loginState.loginUserInfo!.customInfo,
    );
    return CallManager.instance.setSelfInfo(userInfo);
  }

  @override
  Future<CompletionHandler> calls(
    List<String> userIdList,
    callMediaType, [
    CallParams? params,
  ]) async {
    // 普通入口与消息回拨共享宿主守卫，错误提示也留在同一 action 内只执行一次。
    return AppServiceLocator.get<ActionGuard>().singleFlight('tim.call.start',
        () async {
      final handler =
          await CallManager.instance.calls(userIdList, callMediaType, params);
      _showAdmissionError(handler);
      return handler;
    });
  }

  @override
  Future<void> join(String callId) => AppServiceLocator.get<ActionGuard>()
          .singleFlight('tim.call.join', () async {
        // 同场已接通只恢复；提示与路由必须留在防重过程内，避免多个调用者重复提示。
        if (callId.isNotEmpty &&
            CallStore.shared.state.activeCall.value.callId == callId &&
            CallStore.shared.state.selfInfo.value.status ==
                CallParticipantStatus.accept) {
          pageRouter.showCallingPage();
          return;
        }
        final handler = await CallManager.instance.join(callId);
        _showAdmissionError(handler);
      });

  /// 发起和加入共用错误提示，未知 SDK 错误也给出失败反馈。
  void _showAdmissionError(CompletionHandler handler) {
    if (handler.errorCode == 0 || handler.errorCode == -1101) return;
    final text = AppLocalization.of(Global.appContext());
    AppToast.show(
        ErrorParser.getErrorMessage(handler.errorCode, text) ??
            text.callFailedToInitiateOrJoinCall,
        duration: const Duration(seconds: 3));
  }

  @override
  Future<void> enableFloatWindow(bool enable) async {
    GlobalState.instance.setEnableFloatWindow(enable);
  }

  @override
  void enableIncomingBanner(bool enable) {
    GlobalState.instance.setEnableIncomingBanner(enable);
  }

  @override
  void setGroupMemberPicker(GroupMemberPicker? picker) {
    GlobalState.instance.groupMemberPicker = picker;
  }

  @override
  void setGroupMemberSubtitleLoader(GroupMemberSubtitleLoader? loader) {
    _memberSubtitleCache.setLoader(loader);
  }

  @override
  void setGroupControlTransport(GroupControlTransport? transport) {
    _groupControlLifecycle.setTransport(transport);
  }

  @override
  void syncGroupControlPolicy() => _groupControlLifecycle.syncPolicy();

  @override
  void setGroupCallResultHandler(GroupCallResultHandler? handler) {
    _groupCallResultTracker.setHandler(handler);
  }

  @override
  void setGroupCallTitle(String groupId, String title) {
    GlobalState.instance.setGroupCallTitle(groupId, title);
  }

  @override
  Future<void> enableMuteMode(bool enable) async {
    GlobalState.instance.setEnableMuteMode(enable);
  }

  @override
  Future<void> enableVirtualBackground(bool enable) async {
    GlobalState.instance.setEnableBlurBackground(enable);
  }

  @override
  Future<void> enableAITranscriber(bool enable) async {
    GlobalState.instance.setEnableAITranscriber(enable);
  }

  @override
  Future<void> setCallingBell(String assetName) {
    GlobalState.instance.setCallingBellAssetName(assetName);
    return Future.value();
  }

  @override
  Future<void> callExperimentalAPI(String json) {
    return Future.value();
  }

  /// 登录后绑定本端通话和成员观察者，重复登录先移除旧注册以避免重复通知。
  void handleLoginSuccess(int sdkAppID, String userId, String userSig) {
    TUICallEngine.instance.init(sdkAppID, userId, userSig);
    LoginStore.shared.login(
      sdkAppID: sdkAppID,
      userID: userId,
      userSig: userSig,
    );
    CallStore.shared.removeListener(callEventListener);
    CallStore.shared.addListener(callEventListener);
    TUICallEngine.instance.removeObserver(_groupObserver);
    TUICallEngine.instance.addObserver(_groupObserver);
    CallingBellFeature.instance.init();
    CallStore.shared.state.activeCall.removeListener(_checkDurationLimit);
    CallStore.shared.state.activeCall.addListener(_checkDurationLimit);
    GlobalState.instance.groupControl.removeListener(_checkDurationLimit);
    GlobalState.instance.groupControl.addListener(_checkDurationLimit);
    AppLifecycle.instance.currentState.removeListener(_onDurationLifecycle);
    AppLifecycle.instance.currentState.addListener(_onDurationLifecycle);
    if (Platform.isIOS) {
      pictureInPictureFeature = IosPipFeature();
    }
  }

  /// 先使异步操作失效并清理展示资料，再释放 SDK 与平台资源。
  void handleLogoutSuccess() async {
    _groupControlLifecycle.clear(clearAuthority: true);
    _groupCallResultTracker.clear();
    CallManager.instance.invalidateDevicePreparation();
    CallManager.instance.clearGroupRequest();
    _memberSubtitleCache.clear();
    GlobalState.instance.clearGroupCall();
    _closePage();
    TUICallEngine.instance.removeObserver(_groupObserver);
    CallStore.shared.state.activeCall.removeListener(_checkDurationLimit);
    GlobalState.instance.groupControl.removeListener(_checkDurationLimit);
    AppLifecycle.instance.currentState.removeListener(_onDurationLifecycle);
    _durationLimit.reset();
    TUICallEngine.instance.unInit();
    CallStore.shared.removeListener(callEventListener);
    CallingBellFeature.instance.dispose();
    LoginStore.shared.logout();
    if (Platform.isIOS && pictureInPictureFeature != null) {
      pictureInPictureFeature!.dispose();
      pictureInPictureFeature = null;
    }
  }

  /// SDK 每次更新时长时检查限制，挂断失败记录日志并等待下一次状态更新重试。
  void _checkDurationLimit() {
    final call = CallStore.shared.state.activeCall.value;
    final control = GlobalState.instance.groupControl.value;
    unawaited(_durationLimit
        .update(
      callId: call.callId,
      seconds: call.duration.toInt(),
      connected: CallStore.shared.state.selfInfo.value.status ==
          CallParticipantStatus.accept,
      deadlineMs: control?.callId == call.callId ? control?.deadlineMs : null,
      sessionId: control?.callId == call.callId ? control?.sessionId : null,
    )
        .catchError((Object error, StackTrace stack) {
      appLogger.error('达到通话时长上限后结束失败', error: error, stackTrace: stack);
    }));
  }

  /// 系统暂停 Dart 计时回调时仍保留绝对截止，恢复前台后立即复核，不补一轮新会期。
  void _onDurationLifecycle() {
    if (AppLifecycle.instance.isForeground) _checkDurationLimit();
  }

  /// 随共享 Store 更新界面与成员展示，SDK 清理状态时仅保留允许重呼的独立结果页。
  void _subscribeState() {
    CallStore.shared.state.activeCall.addListener(_syncGroupCall);
    CallStore.shared.state.allParticipants.addListener(_syncGroupCall);
    CallStore.shared.state.selfInfo.addListener(() async {
      final activeCall = CallStore.shared.state.activeCall.value;
      if (activeCall.mediaType == null) {
        return;
      }

      final callStatus = CallStore.shared.state.selfInfo.value.status;

      if (callStatus == CallParticipantStatus.waiting) {
        _showPage();
      } else if (callStatus == CallParticipantStatus.accept) {
        _showPage();
      } else if (callStatus == CallParticipantStatus.none &&
          GlobalState.instance.groupCall.value?.canRetry != true) {
        _closePage();
      }
    });
  }

  /// 首次展示遵循统一来电横幅配置，异步资料迟到不能恢复已经结束的来电。
  void _showPage() async {
    if (pageRouter.getCurrentPageRoute() != CallPageType.none) return;

    final activeCall = CallStore.shared.state.activeCall.value;
    final self = CallStore.shared.state.selfInfo.value;
    if (activeCall.mediaType == null ||
        self.status == CallParticipantStatus.none) {
      return;
    }
    final incoming = activeCall.inviterId != self.id &&
        self.status == CallParticipantStatus.waiting;
    final epoch = CallManager.instance.sessionEpoch;
    bool isCurrent() =>
        epoch == CallManager.instance.sessionEpoch &&
        CallStore.shared.state.activeCall.value.callId == activeCall.callId &&
        CallStore.shared.state.selfInfo.value.id == self.id &&
        CallStore.shared.state.selfInfo.value.status !=
            CallParticipantStatus.none;

    // 只有后台被叫需要通知资料；等待期间可能拒绝、接听或收到另一场来电。
    if (AppLifecycle.instance.isBackground &&
        incoming &&
        activeCall.inviterId.isNotEmpty) {
      final handler = await contactStore.getContactInfo(
        userIDList: [activeCall.inviterId],
      );
      if (!isCurrent() ||
          CallStore.shared.state.selfInfo.value.status !=
              CallParticipantStatus.waiting) {
        return;
      }
      if (handler.isSuccess && handler.contactInfoList.isNotEmpty) {
        final selfInfo = CallStore.shared.state.selfInfo.value;
        final contactInfo = handler.contactInfoList.first;
        if (activeCall.inviterId != selfInfo.id &&
            activeCall.mediaType != null) {
          fcmDataSyncHandler.openNotificationView(
            contactInfo.nickname ?? "",
            contactInfo.avatarURL ?? "",
            activeCall.mediaType!,
          );
        }
      }
      isNotificationPreparing = true;
    }

    // 群与临时多人共用 G21 横幅；已由用户展开的界面不会被资料更新覆盖。
    if (!isCurrent() || pageRouter.getCurrentPageRoute() != CallPageType.none) {
      return;
    }
    if (GlobalState.instance.enableIncomingBanner &&
        incoming &&
        CallStore.shared.state.selfInfo.value.status ==
            CallParticipantStatus.waiting) {
      pageRouter.showIncomingBanner();
    } else {
      pageRouter.showCallingPage();
    }
  }

  void _closePage() async {
    if (pageRouter.getCurrentPageRoute() == CallPageType.none) return;

    isNotificationPreparing = false;
    fcmDataSyncHandler.closeNotificationView();
    pageRouter.closeAllPage();
  }

  void handleErrorCode(int errorCode) {
    final errorMessage = ErrorParser.getErrorMessage(
      errorCode,
      AppLocalization.of(Global.appContext()),
    );
    if (errorMessage != null) {
      TUIToast.show(content: errorMessage);
    }
  }
}
