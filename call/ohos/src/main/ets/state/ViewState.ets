export enum CallRoute {
  none = 0,
  banner = 1,
  fullView = 2,
}

/** 当前通话窗口的路由和展示来源，设备安全区可跨通话保留。 */
@Observed
export class ViewStateClass {
  /** 当前显示横幅、全屏或关闭，原生和 Flutter 通过同一个路由协调。 */
  router: CallRoute = CallRoute.none;
  /** 独立多人只选一人时仍用多人界面，接听和会控权限由 SDK 决定。 */
  temporaryMulti: boolean = false;
  /** Status-bar height in vp, injected by SubWindowManager via getWindowAvoidArea(TYPE_SYSTEM). */

  /* 状态栏高度（vp），通过 SubWindowManager 的 getWindowAvoidArea(TYPE_SYSTEM) 注入。 */
  statusBarHeight: number = 0;
  /** Navigation-indicator height in vp, injected via TYPE_NAVIGATION_INDICATOR. */

  /* 导航指示器高度（vp），通过 TYPE_NAVIGATION_INDICATOR 注入。 */
  navBarHeight: number = 0;

  reset(): void {
    this.router = CallRoute.none;
    this.temporaryMulti = false;
    // Safe-area heights are device hardware properties; preserved across calls.
    //
    // 安全区高度是设备硬件属性；在调用间保持不变。
  }
}

let _instance: ViewStateClass | null = null;

export function ViewState(): ViewStateClass {
  if (!_instance) {
    _instance = new ViewStateClass();
  }
  return _instance;
}
