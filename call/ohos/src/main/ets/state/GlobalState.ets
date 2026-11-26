export enum CallOrientation {
  portrait = 0,
  landscapeLeft = 1,
  landscapeRight = 2,
}

/** 保存鸿蒙通话组件共用的显示与设备设置。 */
@Observed
export class GlobalStateClass {
  enableMuteMode: boolean = false;
  enableFloatWindow: boolean = true;
  enableIncomingBanner: boolean = false;
  /** v1 TODO: virtual background out of scope. */

  /* v1 待办事项：虚拟背景超出当前范围。 */
  enableVirtualBackground: boolean = false;
  orientation: CallOrientation = CallOrientation.portrait;
}

let _instance: GlobalStateClass | null = null;

export function GlobalState(): GlobalStateClass {
  if (!_instance) {
    _instance = new GlobalStateClass();
  }
  return _instance;
}
