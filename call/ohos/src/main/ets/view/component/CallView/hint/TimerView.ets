// Shows either the "Waiting" hint or the HMS-formatted call duration.
//
// Visibility rules:
//   status == accept                    → show HMS duration
//   1:1 waiting                         → hide
//   multi-party callee waiting          → hide
//   multi-party caller waiting          → show "Waiting"
//
// Why a local clock (not `activeCall.duration`): atomicxcore's
// `CallInfo.duration` is documented to auto-increment per second, but on
// HarmonyOS that is not implemented — the field stays at 0 from accept
// through hangup. We capture `Date.now()` on the first `accept` transition
// and recompute every 1Hz tick. The 1Hz pulse is delivered by mutating
// `@State refreshTick`, which marks this component dirty and re-runs build()
// → displayText().
//
// 显示“等待”提示或 HMS 格式的通话时长。
//
// 可见性规则：
//
// 1:1 等待 → 隐藏，多方被叫等待 → 隐藏，多方主叫等待 → 显示“等待”
//
// 为什么用本地时钟（而不是 `activeCall.duration`）：atomicxcore 的 `CallInfo.duration` 文档里说会每秒自增，但在 HarmonyOS 上没有实现
// —— 这个字段从接听到挂断一直是 0。我们在第一次 `accept` 转换时捕获 `Date.now()`，并每秒重新计算一次。每秒脉冲是通过修改 `@State refreshTick`
// 触发的，它会标记这个组件为脏并重新运行 build() → displayText()。

import { CallParticipantInfo, CallInfo, CallParticipantStatus } from '@tencentcloud/atomicxcore';
import { TimerUtil } from '../../../../common/utils/TimerUtil';
import { TUICallKitLocalize } from '../../../../common/Localized';
import { CallConstants } from '../../../../common/CallConstants';

@Component
export struct TimerView {
  @ObjectLink selfInfo: CallParticipantInfo;
  @ObjectLink activeCall: CallInfo;

  /** Numeric value is irrelevant — only the mutation matters for ArkUI's @State change-tracking. */

  /* 数值本身无关紧要 —— 关键是 ArkUI 的 @State 变更追踪机制会根据变化来处理。 */
  @State private refreshTick: number = 0;

  /** 0 = "not started yet". Never reset once set; the next call gets a fresh component instance. */
  private startTimeMs: number = 0;

  private intervalId: number = -1;

  aboutToAppear(): void {
    this.intervalId = setInterval((): void => {
      this.refreshTick = this.refreshTick + 1;
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.intervalId !== -1) {
      clearInterval(this.intervalId);
      this.intervalId = -1;
    }
  }

  build() {
    // ArkUI's @Component build() requires exactly one root *container* node
    // and disallows free statements alongside it; the ensureStartTime()
    // side-effect lives inside displayText() instead.
    //
    // ArkUI 的 @Component build() 需要恰好一个根 *容器* 节点，并且不允许在旁边写自由语句；ensureStartTime() 的副作用改放在 displayText() 里面。
    Column() {
      Text(this.displayText())
        .fontColor(CallConstants.Color_White)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .visibility(this.shouldShow() ? Visibility.Visible : Visibility.Hidden);
    };
  }

  private ensureStartTime(): void {
    if (this.startTimeMs !== 0) {
      return;
    }
    if (this.selfInfo.status === CallParticipantStatus.accept) {
      this.startTimeMs = Date.now();
    }
  }

  private displayText(): string {
    this.ensureStartTime();

    // Read refreshTick so this method's call-site (build()) registers a
    // dependency on it — ArkUI's tracker only counts *reads* during build,
    // not writes.
    //
    // 读取 refreshTick，这样这个方法的调用点 (build()) 会注册对它的依赖 — ArkUI 的追踪器只在构建期间统计 *读取*，不统计写入。
    const _tick: number = this.refreshTick;
    void _tick;

    if (this.selfInfo.status === CallParticipantStatus.accept) {
      if (this.startTimeMs === 0) {
        return TimerUtil.secondToHMSString(0);
      }
      const elapsedMs: number = Date.now() - this.startTimeMs;
      const seconds: number = Math.max(0, Math.floor(elapsedMs / 1000));
      return TimerUtil.secondToHMSString(seconds);
    }
    return TUICallKitLocalize('TUICallKit.waitAccept');
  }

  private shouldShow(): boolean {
    if (this.selfInfo.status === CallParticipantStatus.accept) {
      return true;
    }

    const isOneToOne = (this.activeCall.chatGroupId?.length ?? 0) === 0
      && (this.activeCall.inviteeIds?.length ?? 0) <= 1;
    if (isOneToOne) {
      return false;
    }

    if (this.selfInfo.status === CallParticipantStatus.waiting) {
      const isCaller = this.activeCall.inviterId === this.selfInfo.id;
      return isCaller;
    }

    return true;
  }
}
