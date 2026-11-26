import { ComponentContent, UIContext } from '@kit.ArkUI';

/// 持有原生窗口内唯一一条提示的文案和动效状态，窗口关闭时终止计时。
@Observed
export class NativeToastState {
  /// 当前文案保留到淡出结束，期间还能原位替换。
  message: string = '';
  /// 只由入场和退场更新，替换文案不重复动画。
  opacity: number = 0;
  /// 首次入场从目标位置下方 8 vp 上移。
  offset: number = 8;

  /// 从当前提示展示起计算停留时长，替换和隐藏时作废旧任务。
  private expiry: number = -1;
  /// 淡出完成后清空内容，非负值也用于识别退场中收到的新提示。
  private removal: number = -1;

  /// 新文案重新计时，首次展示从常驻节点的透明状态开始。
  show(context: UIContext, message: string, durationMs: number = 2000): void {
    if (message.trim().length === 0 || this.message === message) return;
    const entering = this.message.length === 0;
    const exiting = this.removal !== -1;
    clearTimeout(this.expiry);
    clearTimeout(this.removal);
    this.removal = -1;
    this.message = message;
    if (entering) {
      this.opacity = 0;
      this.offset = 8;
      context.animateTo({ duration: 200 }, () => {
        this.opacity = 1;
        this.offset = 0;
      });
    } else if (exiting) {
      this.opacity = 1;
    }
    this.expiry = setTimeout(() => {
      context.animateTo({ duration: 150 }, () => { this.opacity = 0; });
      this.removal = setTimeout(() => this.clear(), 150);
    }, durationMs);
  }

  /// 窗口销毁或提示淡出后释放状态。
  clear(): void {
    clearTimeout(this.expiry);
    clearTimeout(this.removal);
    this.expiry = -1;
    this.removal = -1;
    this.message = '';
    this.opacity = 0;
    this.offset = 8;
  }
}

/// 原生窗口内的底部提示，绘制时把触摸交回下层操作区域。
@Component
export struct NativeToast {
  /// 由当前原生窗口或弹层共享的提示状态。
  @ObjectLink state: NativeToastState;
  /// 所在容器已经扣除的系统底边距，单位为 vp。
  @Prop bottomInset: number = 0;
  /// 键盘从整屏底部占用的 vp，原生没有文本输入的弹层使用默认值。
  @Prop keyboardInset: number = 0;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Text(this.state.message)
          .fontSize(14)
          .fontColor(Color.White)
          .textAlign(TextAlign.Start)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 242 })
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .backgroundColor('#1A1F26')
          .borderRadius(999)
          .opacity(this.state.opacity)
          .translate({ y: this.state.offset })
          .accessibilityText(this.state.message)
          .accessibilityLevel(this.state.message.length > 0 ? 'yes' : 'no')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, bottom: Math.max(0, (this.keyboardInset > 0 ? this.keyboardInset + 16 : 80) - this.bottomInset) })
    .animation({ duration: 200, curve: Curve.EaseOut })
    .hitTestBehavior(HitTestMode.None)
  }
}


interface NativeToastOverlayConfig {
  state: NativeToastState;
  keyboardInset: number;
}

@Component
struct NativeToastOverlayContent {
  /// @State 使通过 ComponentContent 创建的浮层也观察共享的提示模型。
  @State state: NativeToastState = new NativeToastState();
  /// 窗口尺寸变化后由 Overlay 更新，Toast 自身继续做平滑过渡。
  @Prop keyboardInset: number = 0;

  build() {
    NativeToast({ state: this.state, keyboardInset: this.keyboardInset })
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.KEYBOARD], [SafeAreaEdge.BOTTOM])
  }
}

@Builder
function buildToastOverlay(config: NativeToastOverlayConfig) {
  NativeToastOverlayContent({ state: config.state, keyboardInset: config.keyboardInset })
}

/// 供独立原生通话窗口使用，浮层常驻于主窗口，覆盖层不接管触摸。
export class NativeToastOverlay {
  private readonly state: NativeToastState = new NativeToastState();
  /// 由当前窗口的 OverlayManager 持有，切换窗口前移除并释放。
  private content: ComponentContent<NativeToastOverlayConfig> | null = null;
  private context: UIContext | null = null;

  /// 把提示插入当前窗口，后续消息更新同一个原生节点。
  show(context: UIContext, message: string, durationMs: number, keyboardInset: number): void {
    if (this.context !== context) this.clear();
    if (this.content === null) {
      const config: NativeToastOverlayConfig = {
        state: this.state,
        keyboardInset: keyboardInset,
      };
      const content = new ComponentContent(context, wrapBuilder(buildToastOverlay), config);
      context.getOverlayManager().addComponentContent(content);
      this.context = context;
      this.content = content;
    }
    this.setKeyboardInset(keyboardInset);
    this.state.show(context, message, durationMs);
  }

  /// 原生窗口的键盘区域变化后重新计算位置。
  setKeyboardInset(keyboardInset: number): void {
    this.content?.update({ state: this.state, keyboardInset: keyboardInset });
  }

  /// 结束窗口生命周期时清空计时，移除对应原生节点。
  clear(): void {
    this.state.clear();
    const content = this.content;
    const context = this.context;
    this.content = null;
    this.context = null;
    if (content !== null && context !== null) {
      try {
        context.getOverlayManager().removeComponentContent(content);
      } finally {
        content.dispose();
      }
    }
  }
}
