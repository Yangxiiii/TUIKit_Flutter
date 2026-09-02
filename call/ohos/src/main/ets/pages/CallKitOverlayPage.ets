// SubWindow root Entry for the call-kit.
//
// Registered as a NamedRoute via the `@Entry({ routeName })` decorator —
// HarmonyOS' global named-route registry is populated at module-load time
// (this file is import-ed by SubWindowManager so the decorator runs once
// during SDK init). The SDK's child Window then loads it via
// `subWindow.loadContentByName(TUI_CALLKIT_OVERLAY_ROUTE_NAME)`.
//
// Router state (banner / fullView / none) drives both the visible content
// here AND the child Window's own geometry (managed by SubWindowManager).
//
// 通话套件的 SubWindow 根入口。
//
// 通过 `@Entry({ routeName })` 装饰器注册为 NamedRoute —— HarmonyOS 全局命名路由注册在模块加载时完成（这个文件被 SubWindowManager
// 导入，所以装饰器在 SDK 初始化时运行一次）。随后 SDK 的子窗口通过 `subWindow.loadContentByName(TUI_CALLKIT_OVERLAY_ROUTE_NAME)`
// 加载它。
//
// 路由状态（横幅 / 全屏 / 无）决定这里显示的内容，同时也控制子窗口自己的几何尺寸（由 SubWindowManager 管理）。

import {
  CallStore, DeviceStore, CallInfo, CallParticipantInfo, CallParticipantStatus, DeviceState,
} from '@tencentcloud/atomicxcore';
import { ViewState, ViewStateClass, CallRoute } from '../state/ViewState';
import { CallMainPage } from '../view/CallMainPage';
import { IncomingBannerView } from '../view/component/IncomingBanner/IncomingBannerView';
import { Logger } from '../common/utils/Logger';
import { CallStatusObserver } from '../feature/CallStatusObserver';
import { RouterManager } from '../manager/RouterManager';

export const TUI_CALLKIT_OVERLAY_ROUTE_NAME: string = 'TUICallKitOverlayPage';

@Entry({ routeName: 'TUICallKitOverlayPage' })
@Component
export struct TUICallKitOverlayPage {
  @State viewState: ViewStateClass = ViewState();
  @State callState_activeCall: CallInfo = CallStore.shared().state.activeCall;
  @State callState_selfInfo: CallParticipantInfo = CallStore.shared().state.selfInfo;
  @State callState_allParticipants: CallParticipantInfo[] = CallStore.shared().state.allParticipants;
  @State deviceState: DeviceState = DeviceStore.shared().state as DeviceState;

  build() {
    // @Entry requires a single container root; OverlayRouter is a custom
    // @Component (not a built-in container), so wrap it in a Stack.
    //
    // @Entry 只要求一个容器根；OverlayRouter 是自定义 @Component（不是内置容器），所以用 Stack 包裹一下。
    Stack() {
      OverlayRouter({
        viewState: this.viewState,
        callState_activeCall: this.callState_activeCall,
        callState_selfInfo: this.callState_selfInfo,
        callState_allParticipants: this.callState_allParticipants,
        deviceState: this.deviceState,
      });
    }
    .width('100%')
    .height('100%');
  }
}

@Component
struct OverlayRouter {
  @ObjectLink viewState: ViewStateClass;
  @ObjectLink callState_activeCall: CallInfo;
  @ObjectLink @Watch('onSelfInfoChanged') callState_selfInfo: CallParticipantInfo;
  @ObjectLink callState_allParticipants: CallParticipantInfo[];
  @ObjectLink deviceState: DeviceState;

  /**
   * Status-watcher hook. `@ObjectLink + @Watch` is the canonical ArkUI
   * pattern for observing field changes on an @Observed class — fires
   * whenever ANY tracked field changes. We dedupe by status inside
   * CallStatusObserver itself (`lastStatus` cache), so spurious fires
   * (e.g. avatarURL changes) are no-ops.
   *
   * 状态观察器钩子。`@ObjectLink + @Watch` 是 ArkUI 观察 @Observed 类字段变化的标准用法 —— 只要任何被跟踪的字段变化，它就会触发。我们在
   * CallStatusObserver 内部按状态去重（`lastStatus` 缓存），所以一些无关触发（比如 avatarURL 变化）不会有实际效果。
   */
  onSelfInfoChanged(): void {
    const status = this.callState_selfInfo.status;
    CallStatusObserver().notify(status);

    if (status === CallParticipantStatus.accept
        && this.viewState.router === CallRoute.banner) {
      Logger.info('TUICallKitOverlayPage: selfInfo.status -> accept, banner -> fullView');
      RouterManager.showCallingView();
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.viewState.router === CallRoute.fullView) {
        CallMainPage({
          viewState: this.viewState,
          callState_activeCall: this.callState_activeCall,
          callState_selfInfo: this.callState_selfInfo,
          callState_allParticipants: this.callState_allParticipants,
          deviceState: this.deviceState,
        });
      } else if (this.viewState.router === CallRoute.banner) {
        IncomingBannerView({
          viewState: this.viewState,
          activeCall: this.callState_activeCall,
          selfInfo: this.callState_selfInfo,
          allParticipants: this.callState_allParticipants,
        });
      }
    }
    .width('100%')
    .height('100%');
  }
}
