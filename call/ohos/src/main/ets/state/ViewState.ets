export enum CallRoute {
  none = 0,
  banner = 1,
  fullView = 2,
}

@Observed
export class ViewStateClass {
  router: CallRoute = CallRoute.none;
  /** Status-bar height in vp, injected by SubWindowManager via getWindowAvoidArea(TYPE_SYSTEM). */

  /* 状态栏高度（vp），通过 SubWindowManager 的 getWindowAvoidArea(TYPE_SYSTEM) 注入。 */
  statusBarHeight: number = 0;
  /** Navigation-indicator height in vp, injected via TYPE_NAVIGATION_INDICATOR. */

  /* 导航指示器高度（vp），通过 TYPE_NAVIGATION_INDICATOR 注入。 */
  navBarHeight: number = 0;

  reset(): void {
    this.router = CallRoute.none;
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
