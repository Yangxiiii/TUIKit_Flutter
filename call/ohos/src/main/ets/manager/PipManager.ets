// System-level Picture-in-Picture controller wrapper.
//
// Drag-close behaviour (PiPState.ABOUT_TO_STOP from the recents/system UI):
// ends the entire call via `CallStore.shared().hangup()` regardless of
// caller/callee role (per product decision; CallStore exposes no `leave()`).
//
// 系统级画中画控制器包装器。
//
// 拖拽关闭行为（来自最近使用/系统 UI 的 PiPState.ABOUT_TO_STOP）：无论是拨出方还是接听方，都会通过 `CallStore.shared().hangup()`
// 结束整个通话（按照产品决策；CallStore 没有提供 `leave()` 方法）。

import { common } from '@kit.AbilityKit';
import { PiPWindow } from '@kit.ArkUI';
import { CallStore } from '@tencentcloud/atomicxcore';
import { Logger } from '../common/utils/Logger';
import { CallEndedFlag } from '../state/CallEndedFlag';

const PIP_DISABLED: boolean = true;

export enum PipState {
  stopped = 0,
  starting = 1,
  started = 2,
  aboutToStop = 3,
  error = 99,
}

type StateChangeCallback = (state: PipState) => void;

class PipManagerImpl {
  private context: common.UIAbilityContext | null = null;
  private xcomponentController: XComponentController | null = null;
  private controller: PiPWindow.PiPController | null = null;
  private currentState: PipState = PipState.stopped;
  private stateCallbacks: Set<StateChangeCallback> = new Set();
  private isCreating: boolean = false;

  init(context: common.UIAbilityContext, xcomponentController?: XComponentController): void {
    if (PIP_DISABLED) {
      return;
    }
    this.context = context;
    this.xcomponentController = xcomponentController ?? null;
  }

  /**
   * Capability gate. Hosts MUST use this to decide whether to show the
   * "minimize" button — no in-app fallback overlay is provided. PiP is gated
   * by Window SessionManager and only available on phones (not tablet 2-in-1
   * / TV / car).
   *
   * 能力门控。主机必须使用它来决定是否显示“最小化”按钮——应用内不提供备用覆盖层。PiP 受窗口 SessionManager 控制，仅在手机上可用（不支持平板 2 合 1 / 电视 / 车载设备）。
   */
  isSupported(): boolean {
    if (PIP_DISABLED) {
      return false;
    }
    try {
      return canIUse('SystemCapability.Window.SessionManager');
    } catch (e) {
      Logger.warn('PipManager.isSupported: canIUse threw, treating as unsupported', e);
      return false;
    }
  }

  onStateChange(cb: StateChangeCallback): () => void {
    this.stateCallbacks.add(cb);
    // Replay current state so latecomers can sync immediately.
    //
    // 重放当前状态，让后来的用户可以立即同步。
    cb(this.currentState);
    return (): void => {
      this.stateCallbacks.delete(cb);
    };
  }

  getState(): PipState {
    return this.currentState;
  }

  /** Returns true when the system has accepted the request (not necessarily already in `started`). */

  /* 当系统接受请求时返回 true（不一定表示已经进入 `started` 状态）。 */
  async enter(): Promise<boolean> {
    if (PIP_DISABLED) {
      return false;
    }
    if (!this.isSupported()) {
      Logger.warn('PipManager.enter: PiP not supported on this device');
      return false;
    }
    if (!this.context) {
      Logger.error('PipManager.enter: context not initialized; call init() first');
      return false;
    }
    if (this.currentState === PipState.started || this.currentState === PipState.starting) {
      Logger.info('PipManager.enter: already starting/started, skip');
      return true;
    }
    if (this.isCreating) {
      Logger.info('PipManager.enter: creation in flight, skip');
      return false;
    }

    try {
      if (!this.controller) {
        this.isCreating = true;
        // `componentController` is required on PiPConfiguration. We have no
        // dedicated video XComponent (the in-app video is rendered by
        // CallCoreView), so when the host has not provided one, fall back
        // to a placeholder — VIDEO_CALL template will then show the system
        // default placeholder UI inside the PiP window.
        //
        // 在 PiPConfiguration 上需要 `componentController`。我们没有专用的视频 XComponent（应用内视频由 CallCoreView
        // 渲染），所以当宿主没有提供时，会回退到占位符 —— VIDEO_CALL 模板会在 PiP 窗口中显示系统默认的占位符 UI。
        if (this.xcomponentController === null) {
          this.xcomponentController = new XComponentController();
        }
        const config: PiPWindow.PiPConfiguration = {
          context: this.context,
          componentController: this.xcomponentController,
          templateType: PiPWindow.PiPTemplateType.VIDEO_CALL,
          contentWidth: 360,
          contentHeight: 640,
        };
        this.controller = await PiPWindow.create(config);
        this.bindControllerListeners();
        this.isCreating = false;
      }

      this.setState(PipState.starting);
      await this.controller.startPiP();
      // startPiP resolves when the request is accepted; the visible
      // transition is reported via the stateChange listener (-> started).
      //
      // 当请求被接受时，startPiP 会被解决；可见的过渡效果通过 stateChange 监听器（-> started）报告。
      return true;
    } catch (e) {
      this.isCreating = false;
      Logger.error('PipManager.enter failed', e);
      this.setState(PipState.error);
      return false;
    }
  }

  async exit(): Promise<void> {
    if (!this.controller || this.currentState === PipState.stopped) {
      return;
    }
    try {
      await this.controller.stopPiP();
    } catch (e) {
      Logger.warn('PipManager.exit failed', e);
    }
  }

  async destroy(): Promise<void> {
    this.stateCallbacks.clear();
    if (!this.controller) {
      return;
    }
    const ctrl = this.controller;
    this.controller = null;
    this.setState(PipState.stopped);
    try {
      await ctrl.stopPiP();
    } catch {
      // tearing down anyway
      //
      // 无论如何都在拆除。
    }
  }

  private bindControllerListeners(): void {
    if (!this.controller) {
      return;
    }
    this.controller.on('stateChange', (state: PiPWindow.PiPState, reason: string): void => {
      Logger.info('PipManager state change:', state, reason);
      switch (state) {
        case PiPWindow.PiPState.ABOUT_TO_START:
          this.setState(PipState.starting);
          break;
        case PiPWindow.PiPState.STARTED:
          this.setState(PipState.started);
          break;
        case PiPWindow.PiPState.ABOUT_TO_STOP:
          this.setState(PipState.aboutToStop);
          this.handleAboutToStop();
          break;
        case PiPWindow.PiPState.STOPPED:
        case PiPWindow.PiPState.ABOUT_TO_RESTORE:
          this.setState(PipState.stopped);
          break;
        case PiPWindow.PiPState.ERROR:
          this.setState(PipState.error);
          break;
        default:
          break;
      }
    });
  }

  /**
   * ABOUT_TO_STOP fires both on user drag-close AND on programmatic
   * `stopPiP()` from our own `exit()`. Guard with `activeCall.callId` so we
   * don't try to hang up a call that has already ended through other paths.
   *
   * ABOUT_TO_STOP 会在用户拖动关闭和我们自己通过 `exit()` 调用的程序性 `stopPiP()` 时触发。用 `activeCall.callId`
   * 做保护，这样我们就不会尝试挂断已经通过其他路径结束的通话。
   */
  private handleAboutToStop(): void {
    const activeCallId = CallStore.shared().state.activeCall.callId;
    if (!activeCallId) {
      return;
    }
    Logger.info('PipManager: PiP about to stop, hanging up call', activeCallId);
    // Self-initiated end → mark before hangup() so handleCallEnded suppresses
    // the "the other party hung up" toast (the engine sometimes echoes the
    // peer id back as `userId` on HarmonyOS, see CallEndedFlag).
    //
    // 自行结束 → 在 hangup() 前标记，这样 handleCallEnded 会抑制“对方挂断”提示（引擎有时会在 HarmonyOS 上将对端id回显为 `userId`，见
    // CallEndedFlag）。
    CallEndedFlag().markSelfEnded();
    CallStore.shared().hangup().catch((e: Error): void => {
      Logger.warn('PipManager: hangup on PiP close failed', e);
    });
  }

  private setState(state: PipState): void {
    if (this.currentState === state) {
      return;
    }
    this.currentState = state;
    this.stateCallbacks.forEach((cb): void => {
      try {
        cb(state);
      } catch (e) {
        Logger.warn('PipManager.stateCallback threw', e);
      }
    });
  }
}

const _instance: PipManagerImpl = new PipManagerImpl();

export function PipManager(): PipManagerImpl {
  return _instance;
}
