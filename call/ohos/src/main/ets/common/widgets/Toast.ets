import window from '@ohos.window';
import { UIContext } from '@kit.ArkUI';
import { NativeToastOverlay } from 'tuikit_atomic_x';
import { Logger } from '../utils/Logger';

/** 通话反馈优先进入应用浮层，独立原生通话使用主窗口保留挂断提示。 */
export class Toast {
  /** 主窗口独立于通话子窗口的生命周期，挂断后仍可展示提示。 */
  private static hostWindow: window.Window | null = null;
  private static hostContext: UIContext | null = null;
  private static readonly overlay: NativeToastOverlay = new NativeToastOverlay();

  /** Flutter 接管通话时，原生信令提示也交给宿主的统一浮层。 */
  private static presenter: ((message: string, durationMs: number) => void) | null = null;

  /** 更新原生提示的键盘避让位置，同一回调随 WindowStage 释放。 */
  private static readonly keyboardChanged = (change: window.AvoidAreaOptions): void => {
    const context = Toast.hostContext;
    if (context !== null && change.type === window.AvoidAreaType.TYPE_KEYBOARD) {
      Toast.overlay.setKeyboardInset(context.px2vp(change.area.bottomRect.height));
    }
  };

  /** 通话展示的连接和卸载与 Flutter 引擎生命周期保持一致。 */
  static bindPresenter(presenter: ((message: string, durationMs: number) => void) | null): void {
    Toast.presenter = presenter;
    if (presenter !== null) Toast.overlay.clear();
  }

  /** 在通话接入 WindowStage 时保留主窗口与键盘避让信息。 */
  static bindHost(windowStage: window.WindowStage): void {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      if (mainWindow === Toast.hostWindow) return;
      Toast.unbindHost();
      Toast.hostWindow = mainWindow;
      Toast.hostContext = mainWindow.getUIContext();
      mainWindow.on('avoidAreaChange', Toast.keyboardChanged);
    } catch (error) {
      Logger.warn('Toast.bindHost failed', error);
    }
  }

  /** 通话组件卸载时同时注销窗口回调并清空提示。 */
  static unbindHost(): void {
    try {
      Toast.hostWindow?.off('avoidAreaChange', Toast.keyboardChanged);
      Toast.overlay.clear();
    } catch (error) {
      Logger.warn('Toast.unbindHost failed', error);
    } finally {
      Toast.hostWindow = null;
      Toast.hostContext = null;
    }
  }

  /** 向宿主派发文字反馈；Flutter 未接管时仍复用原生底部浮层。 */
  static show(message: string, durationMs: number = 2000): void {
    if (!message) return;
    try {
      if (Toast.presenter !== null) {
        Toast.presenter(message, durationMs);
        return;
      }
      const host = Toast.hostWindow;
      const context = Toast.hostContext;
      if (host === null || context === null) return;
      const keyboard = host.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
      Toast.overlay.show(context, message, durationMs, context.px2vp(keyboard.bottomRect.height));
    } catch (error) {
      Logger.warn('Toast.show failed', error);
    }
  }

  static showError(message: string): void {
    Toast.show(message);
  }
}
