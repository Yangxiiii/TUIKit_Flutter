import 'dart:math';

import 'package:flutter/foundation.dart';

/// 保存云端录制偏移，开始时返回片段 ID，结束时提交同一片段 ID。
typedef GroupCallRecordingHandler = Future<String> Function(
  String callId,
  int seconds,
  String? recordId,
);

/// 按真实通话场次跟踪本端发起的录制片段，跟随通话而非页面销毁。
class GroupCallRecording extends ChangeNotifier {
  GroupCallRecording({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// 以 UTC 当前时间换算相对整场通话起点的视频偏移秒数。
  final DateTime Function() _now;

  /// 与宿主登录会话绑定，清除后不再发出旧请求。
  GroupCallRecordingHandler? _handler;

  /// 每场只保留当前正在提交或尚未结束的片段，旧场次可独立异步收尾。
  final _segments = <String, _RecordingSegment>{};

  /// 只有已登记接口的账号可以开启录制入口。
  bool get available => _handler != null;

  /// 服务器返回片段 ID 后才进入录制中状态。
  bool isRecording(String callId) => _segments[callId]?.recordId != null;

  /// 接口请求未完成时，入口显示等待状态。
  bool isPending(String callId) => _segments[callId]?.pending == true;

  /// 注册当前账号的保存入口，切换账号时释放旧片段状态。
  void setHandler(GroupCallRecordingHandler? handler) {
    if (identical(_handler, handler)) return;
    _handler = handler;
    _segments.clear();
    notifyListeners();
  }

  /// 开始或结束一个片段，调用方通过 ActionGuard 合并同一场次的用户操作。
  Future<bool> toggle({
    required String callId,
    required int? connectedAtMs,
  }) async {
    final handler = _handler;
    if (handler == null || callId.isEmpty) return false;
    if (!_segments.containsKey(callId) &&
        (connectedAtMs == null || connectedAtMs <= 0)) {
      return false;
    }

    final segment = _segments.putIfAbsent(
      callId,
      () => _RecordingSegment(connectedAtMs!),
    );
    if (segment.endSecond != null) return false;
    final recordId = segment.recordId;
    final seconds = _offset(segment);
    segment.pending = true;
    notifyListeners();
    try {
      final id = await handler(callId, seconds, recordId);
      if (!_isCurrent(callId, segment)) return false;
      if (recordId == null) {
        segment.recordId = id;
        segment.startSecond = seconds;
      } else {
        _segments.remove(callId);
      }
    } finally {
      // 挂断可能发生在开始回包前，拿到 ID 后仍用真实结束时刻收尾。
      segment.pending = false;
      if (_isCurrent(callId, segment)) {
        if (segment.recordId == null) {
          _segments.remove(callId);
        } else if (segment.endSecond != null) {
          await _finish(callId, segment);
        }
      }
      if (identical(_handler, handler)) notifyListeners();
    }
    return recordId != null && identical(_handler, handler);
  }

  /// SDK 结束事件锁定最后一秒，等待中的开始请求回包后会继续收尾。
  Future<void> end(String callId) async {
    final segment = _segments[callId];
    if (segment == null || segment.endSecond != null) return;
    segment.endSecond = _offset(segment);
    if (!segment.pending) await _finish(callId, segment);
  }

  /// 结束请求无论结果如何都释放已离场的片段，异常由通话层记录。
  Future<void> _finish(String callId, _RecordingSegment segment) async {
    try {
      await _handler?.call(
        callId,
        max(segment.startSecond, segment.endSecond!),
        segment.recordId!,
      );
    } finally {
      if (_isCurrent(callId, segment)) {
        _segments.remove(callId);
        notifyListeners();
      }
    }
  }

  bool _isCurrent(String callId, _RecordingSegment segment) =>
      identical(_segments[callId], segment);

  /// 本机时钟回拨时仍保证片段结束偏移不早于开始偏移。
  int _offset(_RecordingSegment segment) => max(
        segment.startSecond,
        (_now().millisecondsSinceEpoch - segment.connectedAtMs) ~/ 1000,
      );
}

/// 保存待提交片段的时间锚点及服务器身份，避免换场或缩小浮窗后串用 ID。
class _RecordingSegment {
  _RecordingSegment(this.connectedAtMs);

  /// 同一场最初 SDK 接通的 UTC 毫秒时间，晚加入和重入均使用它。
  final int connectedAtMs;

  /// 服务器开始成功后分配的片段 ID。
  String? recordId;

  /// 开始成功时的偏移秒数，结束时间不能早于它。
  int startSecond = 0;

  /// SDK 结束瞬间对应的偏移秒数，与接口回包时间无关。
  int? endSecond;

  /// 请求未返回时只标记通话已结束，由当前请求负责后续收尾。
  bool pending = false;
}
