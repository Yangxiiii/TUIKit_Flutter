export class CallConstants {
  static readonly MAX_PARTICIPANT: number = 9;

  static readonly groupFunctionViewHeight: number = 210;
  static readonly groupSmallFunctionViewHeight: number = 115;
  /** Bottom safe-area inset fallback for the multi-call controls panel. */

  /* 多人通话控制面板的底部安全区域下边距备选方案。 */
  static readonly groupFunctionBottomHeight: number = 16;

  /**
   * Legacy multi-call absolute-layout offset. New layouts should use
   * `justifyContent: SpaceBetween` + `Constants.CONTROLS_CONTAINER_MAX_WIDTH`
   * instead of hard-coded offsets.
   *
   * 旧版多人通话绝对布局偏移。新布局应使用 `justifyContent: SpaceBetween` +
   * `Constants.CONTROLS_CONTAINER_MAX_WIDTH`，而不是硬编码偏移。
   */
  static readonly horizontalOffset: number = 80;

  static readonly groupFunctionAnimationDuration: number = 300;
  static readonly smartCellularAnimationDuration: number = 250;

  static readonly Color_White: string = '#FFFFFF';
  static readonly Color_OweWhite: string = '#CCFFFFFF';
  static readonly Color_Black: string = '#000000';
  static readonly Color_HangupRed: string = '#FF584C';
  static readonly Color_AnswerGreen: string = '#29CC85';
  static readonly Color_BgMask: string = '#33000000';
  /** Dark mask overlaid on the blurred self-avatar background (~50% black). */

  /* 模糊自我头像背景上覆盖暗色蒙版（约 50% 黑色）。 */
  static readonly Color_BlurMask: string = '#80000000';
  static readonly Color_TextPrimary: string = '#333333';
  static readonly Color_TextSecondary: string = '#999999';

  static readonly mainAvatarSize: number = 100;
  static readonly waitingCellAvatarSize: number = 32;

  static readonly hintTopMargin: number = 12;
}
