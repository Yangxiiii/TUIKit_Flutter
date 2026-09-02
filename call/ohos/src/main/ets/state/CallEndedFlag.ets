// Process-wide flag for "the local user just hung up / rejected".
//
// Workaround for the HarmonyOS engine sometimes reporting the *peer* id as
// `onCallEnded(userId:)` even when we ended the call ourselves — which would
// otherwise misclassify a self-end as a remote-end and fire the wrong
// "the other party hung up" toast. View buttons set the flag *before*
// invoking hangup/reject; `TUICallKitImpl.handleCallEnded` consumes it.
//
// 全局标志，表示“本地用户刚挂断/拒接”。
//
// 解决 HarmonyOS 引擎有时会把 *对方* 的 id 报告为 `onCallEnded(userId:)` 的问题，即使是我们自己挂断 ——
// 否则会把自己挂断误判为对方挂断，并触发错误的“对方已挂断”提示。界面按钮在调用挂断/拒接之前先设置这个标志；`TUICallKitImpl.handleCallEnded` 会处理它。

class CallEndedFlagImpl {
  private flag: boolean = false;

  markSelfEnded(): void {
    this.flag = true;
  }

  consumeAndClear(): boolean {
    const v = this.flag;
    this.flag = false;
    return v;
  }

  clear(): void {
    this.flag = false;
  }
}

let _instance: CallEndedFlagImpl | null = null;

export function CallEndedFlag(): CallEndedFlagImpl {
  if (_instance === null) {
    _instance = new CallEndedFlagImpl();
  }
  return _instance;
}
