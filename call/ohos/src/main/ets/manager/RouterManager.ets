import { ViewState, CallRoute } from '../state/ViewState';
import { GlobalState } from '../state/GlobalState';
import { Logger } from '../common/utils/Logger';

type RouteListener = (next: CallRoute) => void;

let _routeListener: RouteListener | null = null;
let flutterPresenter: ((route: CallRoute) => boolean) | null = null;

/** 统一分发通话路由，由宿主选择 Flutter 或原生窗口承载。 */
export class RouterManager {
  /** Flutter 宿主就绪后注册单聊接管回调，销毁时解除绑定。 */
  static bindFlutterPresenter(presenter: ((route: CallRoute) => boolean) | null): void {
    flutterPresenter = presenter;
    const route = ViewState().router;
    if (route !== CallRoute.none) _routeListener?.(route);
  }

  /** 只在 Flutter 确认接管时跳过原生窗口。 */
  static presentInFlutter(route: CallRoute): boolean {
    return flutterPresenter?.(route) ?? false;
  }

  /** 单聊可使用 Flutter 横幅，群聊继续遵循原生配置。 */
  static hasFlutterPresenter(): boolean {
    return flutterPresenter !== null;
  }

  static showCallingView(): void {
    ViewState().router = CallRoute.fullView;
    Logger.info('RouterManager: -> fullView');
    if (_routeListener !== null) {
      _routeListener(CallRoute.fullView);
    }
  }

  /** Flutter 单聊使用共享横幅，原生路径在横幅被禁用时直接进入全屏。 */
  static showBannerView(useFlutterBanner: boolean = false): void {
    if (!useFlutterBanner && !GlobalState().enableIncomingBanner) {
      RouterManager.showCallingView();
      return;
    }
    ViewState().router = CallRoute.banner;
    Logger.info('RouterManager: -> banner');
    if (_routeListener !== null) {
      _routeListener(CallRoute.banner);
    }
  }

  static closeView(): void {
    ViewState().reset();
    Logger.info('RouterManager: -> none');
    if (_routeListener !== null) {
      _routeListener(CallRoute.none);
    }
  }

  /**
   * Subscribe (or unsubscribe with `null`) to route transitions. Owned by
   * SubWindowManager so the SubWindow can be created / resized / destroyed
   * in lockstep with the route — same pattern as iOS WindowManager.
   *
   * 订阅（或用 `null` 取消订阅）路由转换。由 SubWindowManager 拥有，所以 SubWindow 可以与路由同步创建/调整大小/销毁——和 iOS 的 WindowManager
   * 模式一样。
   */
  static bindRouteListener(listener: RouteListener | null): void {
    _routeListener = listener;
  }
}
