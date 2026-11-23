import 'package:app_core/app_core.dart' show maxCallDurationSeconds;

/// 本端执行已验证的房间绝对截止点，SDK 时长作为补充；不替代服务端强制结束。
class CallDurationLimit {
  CallDurationLimit({
    required this.onLimit,
    DateTime Function()? now,
    Duration Function()? elapsed,
  })  : _now = now ?? DateTime.now,
        _elapsed = elapsed {
    _clock.start();
  }

  /// 达到上限时结束当前通话；失败继续向调用方传播，下一次状态更新可重试。
  final Future<void> Function() onLimit;

  /// 本场最长连接时长，单位为秒，不包含等待接听。
  static const maxSeconds = maxCallDurationSeconds;

  /// 墙钟用于跨端统一 UTC 截止，Stopwatch 防止本端墙钟回退延长预算。
  final DateTime Function() _now;
  final Duration Function()? _elapsed;
  final Stopwatch _clock = Stopwatch();

  /// 同一账号同场重入保留原单调截止，直到登出清理；最多保存最近 64 场。
  final Map<String, _LocalDeadline> _deadlines = {};

  /// 已触发结束的通话；保留到清理或新通话，防止相同时长多次通知。
  String? _endingCallId;

  /// 同场重新入会必须重新执行到期退出，不能复用上一次入会已经挂断的标记。
  String? _endingSessionId;

  /// 判断某次结束事件是否来自本地时长限制，用于避免重复结束提示。
  bool isEnding(String callId) => callId.isNotEmpty && _endingCallId == callId;

  /// 消费可信主持的绝对截止；晚加入、重入、交接和时钟回退都不能扩大既有预算。
  Future<void> update({
    required String callId,
    required int seconds,
    required bool connected,
    int? deadlineMs,
    String? sessionId,
  }) async {
    if (!connected || callId.isEmpty) return;
    if (isEnding(callId) &&
        (sessionId == null || sessionId == _endingSessionId)) {
      return;
    }
    final nowMs = _now().millisecondsSinceEpoch;
    final elapsedMs = (_elapsed?.call() ?? _clock.elapsed).inMilliseconds;

    // 首次接收把跨端墙钟换算为本端剩余预算；以后只收紧，绝不因同步或重入延长。
    if (deadlineMs != null && deadlineMs > 0) {
      final remaining = (deadlineMs - nowMs).clamp(0, maxSeconds * 1000);
      final monotonicDeadline = elapsedMs + remaining;
      final previous = _deadlines[callId];
      if (previous == null) {
        if (_deadlines.length >= 64) _deadlines.remove(_deadlines.keys.first);
        _deadlines[callId] = _LocalDeadline(deadlineMs, monotonicDeadline);
      } else {
        if (deadlineMs < previous.wallMs) previous.wallMs = deadlineMs;
        if (monotonicDeadline < previous.elapsedMs) {
          previous.elapsedMs = monotonicDeadline;
        }
      }
    }
    final deadline = _deadlines[callId];
    final expired = seconds >= maxSeconds ||
        (deadline != null &&
            (nowMs >= deadline.wallMs || elapsedMs >= deadline.elapsedMs));
    if (!expired) return;

    // 结束入口自行防重且复核场次；失败释放标记，SDK 更新或后台恢复可继续重试。
    _endingCallId = callId;
    _endingSessionId = sessionId;
    try {
      await onLimit();
    } catch (_) {
      if (_endingCallId == callId) _endingCallId = null;
      rethrow;
    }
  }

  /// 登出时清理账号绑定的截止缓存，不把上一账号的同名场次带入新登录。
  void reset() {
    _endingCallId = null;
    _endingSessionId = null;
    _deadlines.clear();
  }
}

/// 同一可信截止的墙钟与单调时钟表达，任一到期即可结束，更新只能缩短。
class _LocalDeadline {
  _LocalDeadline(this.wallMs, this.elapsedMs);

  /// 原始 UTC 毫秒截止点，跨端通过可信会控同步。
  int wallMs;

  /// 本端 Stopwatch 毫秒截止点，防止系统时间回退延长会期。
  int elapsedMs;
}
