import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:app_service/app_service.dart';
import 'package:app_ui/app_ui.dart';
import 'manager/call_duration_limit.dart';

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

  /// 时长限制独立于页面生命周期；最小化和恢复继续使用同一 SDK 时长。
  late final _durationLimit = CallDurationLimit(onLimit: () async {
    if (!await CallManager.instance.hangup()) {
      throw StateError('Call duration limit hangup failed');
    }
    AppToast.show(
        AppLocalization.of(Global.appContext())
            .resolve('chat.uikit.callDurationLimit', '已达通话最长时长，通话结束'),
        duration: const Duration(seconds: 3));
  });
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
      KeyMetrics.instance.countUV(EventId.received);
      if (mediaType == CallMediaType.video) {
        await CallManager.instance.openLocalCameraIfPermitted();
      }
    },
    onCallEnded: (callId, mediaType, reason, userId) {
      CallManager.instance.invalidateDevicePreparation();
      CallManager.instance.closeLocalMicrophone();
      aiTranscriberConfigManager.reset(preserveSettings: false);
      _closePage();
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
      if (handler.errorCode != -1101) handleErrorCode(handler.errorCode);
      if (handler.errorCode != 0 &&
          handler.errorCode != -1101 &&
          ErrorParser.getErrorMessage(
                  handler.errorCode, AppLocalization.of(Global.appContext())) ==
              null) {
        AppToast.show(
            AppLocalization.of(Global.appContext())
                .callFailedToInitiateOrJoinCall,
            duration: const Duration(seconds: 3));
      }
      return handler;
    });
  }

  @override
  Future<void> join(String callId) async {
    final handler = await CallManager.instance.join(callId);
    handleErrorCode(handler.errorCode);
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

  void handleLoginSuccess(int sdkAppID, String userId, String userSig) {
    TUICallEngine.instance.init(sdkAppID, userId, userSig);
    LoginStore.shared.login(
      sdkAppID: sdkAppID,
      userID: userId,
      userSig: userSig,
    );
    CallStore.shared.addListener(callEventListener);
    CallingBellFeature.instance.init();
    CallStore.shared.state.activeCall.removeListener(_checkDurationLimit);
    CallStore.shared.state.activeCall.addListener(_checkDurationLimit);
    if (Platform.isIOS) {
      pictureInPictureFeature = IosPipFeature();
    }
  }

  void handleLogoutSuccess() async {
    CallManager.instance.invalidateDevicePreparation();
    CallStore.shared.state.activeCall.removeListener(_checkDurationLimit);
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
    unawaited(_durationLimit
        .update(
      callId: call.callId,
      seconds: call.duration.toInt(),
      connected: CallStore.shared.state.selfInfo.value.status ==
          CallParticipantStatus.accept,
      singleCall: call.chatGroupId.isEmpty && call.inviteeIds.length == 1,
    )
        .catchError((Object error, StackTrace stack) {
      appLogger.error('达到通话时长上限后结束失败', error: error, stackTrace: stack);
    }));
  }

  void _subscribeState() {
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
      } else if (callStatus == CallParticipantStatus.none) {
        _closePage();
      }
    });
  }

  void _showPage() async {
    if (pageRouter.getCurrentPageRoute() != CallPageType.none) return;

    final activeCall = CallStore.shared.state.activeCall.value;
    if (AppLifecycle.instance.isBackground && activeCall.inviterId.isNotEmpty) {
      final handler = await contactStore.getContactInfo(
        userIDList: [activeCall.inviterId],
      );
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

    if (GlobalState.instance.enableIncomingBanner &&
        CallStore.shared.state.selfInfo.value.id !=
            CallStore.shared.state.activeCall.value.inviterId &&
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
