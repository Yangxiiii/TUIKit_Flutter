// Toast wrapper that always renders on the HOST app's main Window.
//
// `promptAction.showToast` is a static API — without an explicit UIContext
// it picks the currently-focused window. When the SDK's SubWindow is in
// `fullView`, it captures focus, so a toast issued at call-end (e.g.
// "对方拒绝了你的通话请求") would be parented to the SubWindow and silently
// disappear when SubWindowManager.teardown destroys it ~immediately
// afterwards.
//
// Fix: capture the host's main-window UIContext at SDK `attach(windowStage)`
// time and route every toast through it. The host main Window outlives the
// SubWindow, so toasts survive the SubWindow tear-down.
//
// Toast 容器，总是在 HOST 应用的主窗口中渲染。
//
// `promptAction.showToast` 是一个静态 API — 如果没有显式的 UIContext，它会选择当前聚焦的窗口。当 SDK 的子窗口处于 `fullView`
// 时，它会捕获焦点，所以在调用结束时发出的 toast（例如
//
// 当 SubWindowManager.teardown 销毁它时会~立即消失。
//
// 修复：在 SDK `attach(windowStage)` 时捕获主机的主窗口 UIContext，并通过它路由每个 toast。主机主窗口寿命长于子窗口，因此 toast
// 能在子窗口销毁后继续存在。

import window from '@ohos.window';
import { UIContext, promptAction } from '@kit.ArkUI';
import { Logger } from '../utils/Logger';

export class Toast {
  private static _hostUIContext: UIContext | null = null;

  /**
   * Bind the host's main-window UIContext. Called by
   * `TUICallKit.attach(windowStage)`.
   *
   * 绑定主机的主窗口 UIContext。由 `TUICallKit.attach(windowStage)` 调用。
   */
  static bindHost(windowStage: window.WindowStage): void {
    try {
      const mainWin: window.Window = windowStage.getMainWindowSync();
      Toast._hostUIContext = mainWin.getUIContext();
      Logger.info('Toast.bindHost: host UIContext captured');
    } catch (e) {
      Logger.warn('Toast.bindHost failed', e);
    }
  }

  /** Drop the cached UIContext on `TUICallKit.detach()`. */

  /* 在 `TUICallKit.detach()` 时清除缓存的 UIContext。 */
  static unbindHost(): void {
    Toast._hostUIContext = null;
  }

  static show(message: string, durationMs: number = 2000): void {
    if (!message) {
      return;
    }
    const opts: promptAction.ShowToastOptions = {
      message,
      duration: durationMs,
      bottom: '10%',
    };
    try {
      if (Toast._hostUIContext) {
        Toast._hostUIContext.getPromptAction().showToast(opts);
      } else {
        // Fallback: SDK was never bound (e.g. error toast fires before
        // attach). The static API picks whichever window is currently
        // focused — tolerable when the SubWindow isn't up yet.
        //
        // 备用：SDK 从未绑定（例如在 attach 之前触发错误 toast）。静态 API 会选择当前聚焦的窗口——当子窗口还未弹出时，这种情况可以接受。
        promptAction.showToast(opts);
      }
    } catch (e) {
      Logger.warn('Toast.show failed', e);
    }
  }

  static showOnTop(message: string, durationMs: number = 2000): void {
    if (!message) {
      return;
    }
    const opts: promptAction.ShowToastOptions = {
      message,
      duration: durationMs,
      bottom: '10%',
    };
    try {
      promptAction.showToast(opts);
    } catch (e) {
      Logger.warn('Toast.showOnTop failed', e);
    }
  }

  static showError(message: string): void {
    Toast.show(message, 2500);
  }
}
