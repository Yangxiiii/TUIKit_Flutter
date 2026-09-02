import { DeviceStore, AudioRoute } from '@tencentcloud/atomicxcore';
import { Logger } from '../common/utils/Logger';

// One-off lookup helper for non-component code. ArkUI components observe
// `DeviceStore.state.currentAudioRoute` directly via @ObjectLink instead.
//
// 非组件代码的一次性查找助手。ArkUI 组件通过 @ObjectLink 直接观察 `DeviceStore.state.currentAudioRoute`。

export class TRTCAudioRouteObserver {
  static currentRoute(): AudioRoute {
    return DeviceStore.shared().state.currentAudioRoute;
  }

  static dump(): void {
    Logger.info('TRTCAudioRouteObserver currentRoute=', TRTCAudioRouteObserver.currentRoute());
  }
}
