// Public facade for the call-kit SDK.
//
// Integration model: the SDK owns its top-level renderer. Hosts call
// `attach(windowStage)` once from EntryAbility.onWindowStageCreate; business
// pages do NOT embed any SDK @Component. Tear-down via `detach()` from
// onWindowStageDestroy.
//
// call-kit SDK 的公共外观。
//
// 集成模式：SDK 拥有其顶层渲染器。宿主在 EntryAbility.onWindowStageCreate 中调用一次 attach(windowStage)；业务页面不嵌入任何 SDK
// @Component。通过 detach() 进行拆卸。

import { common } from '@kit.AbilityKit';
import window from '@ohos.window';
import {
  CallStore, LoginStore, DeviceStore, CallMediaType, CallParams, CallEventListener,
  CallEndReason, UserProfile, CallParticipantStatus, ErrorInfo,
} from '@tencentcloud/atomicxcore';
import { GlobalState, CallOrientation } from './state/GlobalState';
import { ViewState } from './state/ViewState';
import { RouterManager } from './manager/RouterManager';
import { SubWindowManager } from './manager/SubWindowManager';
import { CallingBellFeature } from './feature/CallingBellFeature';
import { CallingVibratorFeature } from './feature/CallingVibratorFeature';
import {
  IncomingNotificationFeature,
  NOTIFICATION_CALL_ACTION_ACCEPT,
  NOTIFICATION_CALL_ACTION_REJECT,
} from './feature/IncomingNotificationFeature';
import { NetworkQualityToastManager } from './manager/NetworkQualityToastManager';
import { PipManager } from './manager/PipManager';
import { ScreenStateManager } from './manager/ScreenStateManager';
import { AVSessionManager } from './manager/AVSessionManager';
import { Permission } from './common/utils/Permission';
import { Preferences } from './common/utils/Preferences';
import { Logger } from './common/utils/Logger';
import { Toast } from './common/widgets/Toast';
import { TUICallKitLocalize, setLocalizedContext } from './common/Localized';
import { Constants, FrameworkConstants } from './common/Constants';
import { AppStateObserver } from './feature/AppStateObserver';
import { CallEndedFlag } from './state/CallEndedFlag';

export abstract class TUICallKit {
  private static _instance: TUICallKit | null = null;

  static createInstance(context: common.Context): TUICallKit {
    if (!TUICallKit._instance) {
      TUICallKit._instance = new TUICallKitImpl(context as common.UIAbilityContext);
    }
    return TUICallKit._instance;
  }

  /**
   * Mount the call-kit overlay onto the given WindowStage's main Window.
   * Idempotent. Requires API 12+.
   *
   * 将 call-kit 覆盖层挂载到给定 WindowStage 的主窗口。幂等。要求 API 12 及以上。
   */
  abstract attach(windowStage: window.WindowStage): void;

  abstract detach(): void;

  abstract setSelfInfo(nickname: string, avatar: string): Promise<void>;

  abstract calls(
    userIdList: string[],
    mediaType: CallMediaType,
    params?: CallParams,
  ): Promise<void>;

  abstract join(callId: string): Promise<void>;

  abstract setCallingBell(filePath: string): void;

  abstract enableMuteMode(enable: boolean): void;

  /** v1 TODO: virtual background out of scope. */
  /** v1 待办：虚拟背景超出范围。 */
  // abstract enableFloatWindow(enable: boolean): void;

  abstract enableIncomingBanner(enable: boolean): void;

  /** 处理系统来电通知动作；callId 不匹配时不会操作当前通话。 */
  abstract handleNotificationAction(action: string, callId: string): void;

  /** v1 TODO: virtual background out of scope. */
  /** v1 待办：虚拟背景超出范围。 */
  // abstract enableVirtualBackground(enable: boolean): void;

  abstract callExperimentalAPI(jsonStr: string): void;

  /** 0 = portrait, 1 = landscapeLeft, 2 = landscapeRight. */
  abstract setScreenOrientation(orientation: number): Promise<void>;
}

/**
 * Render an exception thrown by the atomicxcore engine into a single readable
 * line. `Logger.error('...', e)` on a JSON-serialised `ErrorInfo` only shows
 * `{"code":...,"name":"ErrorInfo"}` because Error.message is non-enumerable
 * (skipped by JSON.stringify).
 *
 * 将 atomicxcore 引擎抛出的异常渲染成一行可读文本。对 JSON 序列化的 `ErrorInfo` 调用 `Logger.error('...', e)` 时，
 * 只会显示 `{"code":...,"name":"ErrorInfo"}`，因为 `Error.message` 不可枚举，会被 `JSON.stringify` 跳过。
 */
function formatError(e: object | Error | ErrorInfo | null | undefined): string {
  if (!e) {
    return 'unknown error';
  }
  if (e instanceof Error) {
    const code = (e as ErrorInfo).code;
    const codeStr = (code !== undefined && code !== null) ? `code=${code}, ` : '';
    return `${codeStr}message=${e.message}`;
  }
  try {
    return JSON.stringify(e);
  } catch (_) {
    return String(e);
  }
}

class PendingNotificationAction {
  action: string;
  callId: string;

  constructor(action: string, callId: string) {
    this.action = action;
    this.callId = callId;
  }
}

class TUICallKitImpl extends TUICallKit {
  private context: common.UIAbilityContext;
  private listener: CallEventListener | null = null;
  /**
   * Reused across calls — lifecycle is bound to start/end of each call,
   * not the SDK lifetime.
   *
   * 跨调用重用 — 生命周期绑定到每次调用的开始/结束，而不是 SDK 的生命周期。
   */
  private avSessionManager: AVSessionManager = new AVSessionManager();
  private pendingNotificationAction: PendingNotificationAction | null = null;

  constructor(context: common.UIAbilityContext) {
    super();
    this.context = context;
    setLocalizedContext(context);
    void Preferences.init(context);
    AppStateObserver().init(context);
    ScreenStateManager().init(context);
    CallingBellFeature.shared().init(context);
    CallingVibratorFeature.shared().init();
    PipManager().init(context);
    IncomingNotificationFeature.shared().init(context);
    this.installCallEventListener();
    Logger.info('TUICallKitImpl initialized, version=', Constants.TUICALL_VERSION);
  }

  attach(windowStage: window.WindowStage): void {
    Toast.bindHost(windowStage);
    SubWindowManager.shared().attach(windowStage);
  }

  detach(): void {
    SubWindowManager.shared().detach();
    Toast.unbindHost();
  }

  async setSelfInfo(nickname: string, avatar: string): Promise<void> {
    const profile = new UserProfile();
    const current = LoginStore.shared().state.loginUserInfo;
    profile.userID = current?.userID ?? '';
    profile.nickname = nickname;
    profile.avatarURL = avatar;
    await LoginStore.shared().setSelfInfo(profile);
  }

  async calls(userIdList: string[], mediaType: CallMediaType, params?: CallParams): Promise<void> {
    const selfId = LoginStore.shared().state.loginUserInfo?.userID ?? '';
    if (userIdList.length === 1 && userIdList[0] === selfId) {
      Toast.showError(TUICallKitLocalize('TUICallKit.calNotCallYourself'));
      return;
    }
    if (userIdList.length + 1 > Constants.MAX_USER) {
      Toast.showError(TUICallKitLocalize('TUICallKit.User.Exceed.Limit'));
      return;
    }
    if (CallStore.shared().state.activeCall.callId.length > 0
        && CallStore.shared().state.selfInfo.status !== CallParticipantStatus.none) {
      Toast.showError(TUICallKitLocalize('TUICallKit.youHaveMissedCalls'));
      return;
    }
    const ok = await Permission.hasPermission(this.context, mediaType);
    if (!ok) {
      return;
    }
    try {
      await CallStore.shared().calls(userIdList, mediaType, params);
    } catch (e) {
      Logger.error('TUICallKitImpl.calls failed,', formatError(e));
    }
  }

  async join(callId: string): Promise<void> {
    try {
      await CallStore.shared().join(callId);
    } catch (e) {
      Logger.error('TUICallKitImpl.join failed,', formatError(e));
    }
  }

  setCallingBell(filePath: string): void {
    CallingBellFeature.shared().setCustomRingFilePath(filePath);
  }

  enableMuteMode(enable: boolean): void {
    GlobalState().enableMuteMode = enable;
    void Preferences.setMuteMode(enable);
    if (enable) {
      CallingBellFeature.shared().stopAll();
      CallingVibratorFeature.shared().stop();
    }
  }

  enableFloatWindow(enable: boolean): void {
    GlobalState().enableFloatWindow = enable;
  }

  enableIncomingBanner(enable: boolean): void {
    GlobalState().enableIncomingBanner = enable;
  }

  handleNotificationAction(action: string, callId: string): void {
    if ((action !== NOTIFICATION_CALL_ACTION_ACCEPT && action !== NOTIFICATION_CALL_ACTION_REJECT)
        || callId.length === 0) {
      Logger.warn('handleNotificationAction: invalid parameters');
      return;
    }

    const activeCallId = CallStore.shared().state.activeCall.callId;
    if (activeCallId.length === 0) {
      // 冷启动时 CallStore 可能尚未恢复邀请，暂存动作并在同一 callId 到达后执行。
      this.pendingNotificationAction = new PendingNotificationAction(action, callId);
      return;
    }
    if (activeCallId !== callId) {
      Logger.warn('handleNotificationAction: stale call action ignored', callId);
      return;
    }
    this.executeNotificationAction(action, callId);
  }

  enableVirtualBackground(enable: boolean): void {
    // TODO: not implemented in v1.
    //
    // 待办：v1 中未实现。
    GlobalState().enableVirtualBackground = enable;
    Logger.warn('enableVirtualBackground is a TODO in call_v2 v1.');
  }

  callExperimentalAPI(jsonStr: string): void {
    CallStore.shared().callExperimentalAPI(jsonStr).catch((e: Object): void => {
      Logger.warn('callExperimentalAPI failed', e);
    });
  }

  async setScreenOrientation(orientation: number): Promise<void> {
    let target = window.Orientation.PORTRAIT;
    switch (orientation) {
      case CallOrientation.landscapeLeft: target = window.Orientation.LANDSCAPE; break;
      case CallOrientation.landscapeRight: target = window.Orientation.LANDSCAPE_INVERTED; break;
      default: target = window.Orientation.PORTRAIT;
    }
    GlobalState().orientation = orientation as CallOrientation;
    try {
      const win = await window.getLastWindow(this.context);
      await win.setPreferredOrientation(target);
    } catch (e) {
      Logger.warn('setScreenOrientation failed', e);
    }
  }

  private setFramework(): void {
    const params: Record<string, Object> = {
      'framework': FrameworkConstants.framework,
      'component': FrameworkConstants.component,
      'language': FrameworkConstants.language,
    };
    const jsonObj: Record<string, Object> = {
      'api': 'setFramework',
      'params': params,
    };
    const jsonStr = JSON.stringify(jsonObj);
    CallStore.shared().callExperimentalAPI(jsonStr).catch((e: Object): void => {
      Logger.error('setFramework failed', e);
    });
  }

  private installCallEventListener(): void {
    this.listener = new CallEventListener(
      (callId: string, mediaType: CallMediaType): void => {
        this.handleCallStarted(callId, mediaType);
      },
      (callId: string, mediaType: CallMediaType, userData: string): void => {
        this.handleCallReceived(callId, mediaType, userData);
      },
      (callId: string, mediaType: CallMediaType, reason: CallEndReason, userId: string): void => {
        this.handleCallEnded(callId, mediaType, reason, userId);
      },
    );
    CallStore.shared().addListener(this.listener);
  }

  private handleCallStarted(callId: string, _mediaType: CallMediaType): void {
    Logger.info('onCallStarted', callId);
    CallEndedFlag().clear();
    void ScreenStateManager().beginCall();
    // Without AVSession + background task, the OS may mute mic / speaker once
    // the call is backgrounded.
    //
    // 如果没有 AVSession + 后台任务，操作系统在通话后台运行时可能会静音麦克风/扬声器。
    void this.avSessionManager.start();
    CallingBellFeature.shared().startDialing();
    NetworkQualityToastManager.start();
    RouterManager.showCallingView();
    this.setFramework();
  }

  private handleCallReceived(callId: string, _mediaType: CallMediaType, _userData: string): void {
    Logger.info('onCallReceived', callId);
    CallEndedFlag().clear();
    void ScreenStateManager().beginCall();
    void this.avSessionManager.start();
    CallingBellFeature.shared().startRinging();
    CallingVibratorFeature.shared().start();
    NetworkQualityToastManager.start();
    // Foreground vs background decision is made inside the feature.
    //
    // 前台 vs 后台的决定在功能内部做。
    void IncomingNotificationFeature.shared().publish();
    if (GlobalState().enableIncomingBanner) {
      RouterManager.showBannerView();
    } else {
      RouterManager.showCallingView();
    }
    this.setFramework();

    const pending = this.pendingNotificationAction;
    this.pendingNotificationAction = null;
    if (pending && pending.callId === callId) {
      this.executeNotificationAction(pending.action, pending.callId);
    }
  }

  private handleCallEnded(
    callId: string,
    _mediaType: CallMediaType,
    reason: CallEndReason,
    userId: string,
  ): void {
    Logger.info('onCallEnded', callId, reason);
    CallingBellFeature.shared().stopAll();
    CallingVibratorFeature.shared().stop();
    NetworkQualityToastManager.stop();
    void PipManager().destroy();
    void IncomingNotificationFeature.shared().cancel();
    void ScreenStateManager().endCall();
    void this.avSessionManager.stop();
    if (this.pendingNotificationAction?.callId === callId) {
      this.pendingNotificationAction = null;
    }


    const selfId = CallStore.shared().state.selfInfo.id;
    const activeCall = CallStore.shared().state.activeCall;
    const flagWasSelfEnded = CallEndedFlag().consumeAndClear();
    const isSelfEnded = flagWasSelfEnded
        || selfId.length === 0
        || userId === selfId;
    const isGroupCall = (activeCall.chatGroupId?.length ?? 0) > 0
        || activeCall.inviteeIds.length > 1;
    if (!isSelfEnded && !isGroupCall) {
      const msgKey = TUICallKitImpl.endReasonToastKey(reason);
      if (msgKey.length > 0) {
        Toast.show(TUICallKitLocalize(msgKey));
      }
    }
    RouterManager.closeView();
  }

  /** 校验已由统一入口完成；动作失败只记录日志，不阻塞 Ability 恢复。 */
  private executeNotificationAction(action: string, callId: string): void {
    this.pendingNotificationAction = null;
    void IncomingNotificationFeature.shared().cancel();
    const operation = action === NOTIFICATION_CALL_ACTION_ACCEPT
      ? CallStore.shared().accept()
      : CallStore.shared().reject();
    operation.catch((e: Object): void => {
      Logger.warn('handleNotificationAction failed', callId, e);
    });
  }

  private static endReasonToastKey(reason: CallEndReason): string {
    switch (reason) {
      case CallEndReason.hangup: return 'TUICallKit.otherPartyHangup';
      case CallEndReason.reject: return 'TUICallKit.otherPartyReject';
      case CallEndReason.noResponse: return 'TUICallKit.otherPartyNoResponse';
      case CallEndReason.canceled: return 'TUICallKit.otherPartyCanceled';
      case CallEndReason.lineBusy: return 'TUICallKit.lineBusy';
      default: return '';
    }
  }
}
