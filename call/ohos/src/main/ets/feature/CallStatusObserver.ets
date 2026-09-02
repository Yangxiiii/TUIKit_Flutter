// Bridges `CallParticipantInfo.status` (an @Observed field on atomicxcore's
// shared state) to non-@Component subscribers (Bell / Vibrator features).
//
// atomicxcore's `CallEventListener` only fires onCallStarted / onCallReceived /
// onCallEnded — there is no callback for the waiting → accept transition. On
// HarmonyOS @Observed fields can only be subscribed via ArkUI's @ObjectLink
// from an @Component, so `OverlayRoot` does the @ObjectLink work and forwards
// status changes here via `notify(...)`.
//
// 桥接 `CallParticipantInfo.status`（atomicxcore 共享状态中的 @Observed 字段）到非 @Component 订阅者（铃声 / 震动功能）。
//
// atomicxcore 的 `CallEventListener` 只会在 onCallStarted / onCallReceived / onCallEnded 触发——对于等待 →
// 接听的状态转换没有回调。在 HarmonyOS 上，@Observed 的字段只能通过 @Component 里的 ArkUI @ObjectLink 订阅，所以 `OverlayRoot` 处理
// @ObjectLink 并通过 `notify(...)` 把状态变化转发过来。

import { CallParticipantStatus } from '@tencentcloud/atomicxcore';

type Listener = (status: CallParticipantStatus) => void;

class CallStatusObserverImpl {
  private listeners: Listener[] = [];
  private lastStatus: CallParticipantStatus = CallParticipantStatus.none;

  addListener(cb: Listener): () => void {
    this.listeners.push(cb);
    return (): void => {
      const idx = this.listeners.indexOf(cb);
      if (idx >= 0) {
        this.listeners.splice(idx, 1);
      }
    };
  }

  /** Deduplicated against `lastStatus` so spurious rebuilds do not fan out. */

  /* 与 `lastStatus` 去重，所以不会因为虚假的重建而大规模触发。 */
  notify(status: CallParticipantStatus): void {
    if (status === this.lastStatus) {
      return;
    }
    this.lastStatus = status;
    // Snapshot to be safe against re-entrant unsubscribe() inside a callback.
    //
    // 做快照以防回调内部 re-enter 的 unsubscribe()。
    const snapshot = this.listeners.slice();
    for (const cb of snapshot) {
      cb(status);
    }
  }
}

let _instance: CallStatusObserverImpl | null = null;

export function CallStatusObserver(): CallStatusObserverImpl {
  if (_instance === null) {
    _instance = new CallStatusObserverImpl();
  }
  return _instance;
}
