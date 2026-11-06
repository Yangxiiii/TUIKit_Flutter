/// 根据 SDK 已连接时长执行单聊上限，窗口恢复和重复回调不会重复结束同一通话。
class CallDurationLimit {
  CallDurationLimit({required this.onLimit});

  /// 达到上限时结束当前通话；失败继续向调用方传播，下一次状态更新可重试。
  final Future<void> Function() onLimit;

  /// 单聊最长连接时长，单位为秒，不包含等待接听。
  static const maxSeconds = 3600;

  /// 已触发结束的通话；保留到清理或新通话，防止相同时长多次通知。
  String? _endingCallId;

  /// 判断某次结束事件是否来自本地时长限制，用于避免重复结束提示。
  bool isEnding(String callId) => callId.isNotEmpty && _endingCallId == callId;

  /// 只接受 SDK 连接时长，不在界面新增与服务端振铃超时竞争的计时器。
  Future<void> update(
      {required String callId,
      required int seconds,
      required bool connected,
      required bool singleCall}) async {
    if (!connected ||
        !singleCall ||
        callId.isEmpty ||
        seconds < maxSeconds ||
        isEnding(callId)) {
      return;
    }
    _endingCallId = callId;
    try {
      await onLimit();
    } catch (_) {
      if (_endingCallId == callId) _endingCallId = null;
      rethrow;
    }
  }

  /// 登出时释放本次会话的限制状态。
  void reset() => _endingCallId = null;
}
