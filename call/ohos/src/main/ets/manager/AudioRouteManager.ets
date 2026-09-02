import { DeviceStore, AudioRoute } from '@tencentcloud/atomicxcore';
import { Logger } from '../common/utils/Logger';

// v1 STUB: only "speakerphone <-> earpiece" two-state switching is supported.
// Bluetooth / wired-headset detection is out of scope for v1.
//
// v1 版本占位：只支持“扬声器 <-> 听筒”两态切换。蓝牙/有线耳机检测在 v1 范围之外。

export class AudioRouteManager {
  /** v1 stub. TODO: integrate @ohos.bluetooth / @ohos.multimedia.audio device routing. */

  /* v1 存根。TODO：整合 @ohos.bluetooth / @ohos.multimedia.audio 设备路由。 */
  static isBluetoothHeadsetConnected(): boolean {
    return false;
  }

  /** v1 stub. */

  /* v1 存根。 */
  static isWiredHeadsetConnected(): boolean {
    return false;
  }

  static syncAudioRouteFromSystem(): AudioRoute {
    return DeviceStore.shared().state.currentAudioRoute;
  }

  static toggle(): void {
    const current = DeviceStore.shared().state.currentAudioRoute;
    const next = current === AudioRoute.speakerphone
      ? AudioRoute.earpiece
      : AudioRoute.speakerphone;
    DeviceStore.shared().setAudioRoute(next);
    Logger.info('AudioRouteManager.toggle ->', next);
  }

  /** v1 stub: HarmonyOS has no AVRoutePickerView equivalent. */

  /* v1 存根：HarmonyOS 没有 AVRoutePickerView 对应组件。 */
  static enableAvRoutePickerMode(): void {
    Logger.info('AudioRouteManager.enableAvRoutePickerMode: not supported on HarmonyOS (TODO)');
  }
}
