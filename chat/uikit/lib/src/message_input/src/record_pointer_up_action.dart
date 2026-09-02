/// Action to take when the recording gesture ends (PointerUp / PointerCancel).
///
/// The action is determined by the finger's position at release time:
/// - On the cancel button → [cancel]
/// - On the convert-to-text button → [convert]
/// - Anywhere else → [send] (release-to-send original voice)
///
/// 录制手势结束时要采取的动作（PointerUp / PointerCancel）
///
/// 动作由手指释放时的位置决定：- 在取消按钮上 → [取消] - 在转换为文本按钮上 → [转换] - 在其他任何地方 → [发送]（释放即发送原始语音）
enum RecordPointerUpAction { send, cancel, convert }

/// Pure dispatch helper used by [MessageInput] to translate hover flags into
/// the resulting action. Extracted to a top-level function so it can be unit
/// tested without standing up the full widget tree.
///
/// Defensive precedence: when both flags are accidentally true (which the
/// state machine in [AudioRecordOverlay] should prevent), [cancel] wins to
/// favor the safer "drop the recording" outcome over silently sending.
///
/// 纯派发助手，由 [MessageInput] 用来把悬停标志转换成最终动作。提取为顶层函数，这样可以单独单元测试，而不需要搭建完整的组件树。
///
/// 防御性优先：当两个标志意外同时为真时（[AudioRecordOverlay] 的状态机本应防止这种情况），[取消] 优先，以偏向更安全的“丢弃录音”结果，而不是悄悄发送。
RecordPointerUpAction recordPointerUpAction({
  required bool overCancel,
  required bool overConvert,
}) {
  if (overCancel) return RecordPointerUpAction.cancel;
  if (overConvert) return RecordPointerUpAction.convert;
  return RecordPointerUpAction.send;
}
