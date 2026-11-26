import 'dart:async';

import 'package:flutter/foundation.dart';

/// 保存当前窗口的定位目标，把失效计时与气泡的挂载和滚动解耦。
final class MessageLocationHighlight {
  MessageLocationHighlight(this._onExpired);

  /// 首次用户操作后保留高亮的时间。
  static const _delayAfterInteraction = Duration(seconds: 1);

  /// 计时结束后让所属窗口刷新已有消息行。
  final VoidCallback _onExpired;

  /// 当前实际定位到的消息 ID，随成功的定位一起更新。
  String? _messageId;

  /// 每次定位最多启动一次；重新定位或关闭窗口时取消。
  Timer? _expiry;

  /// 只有成功定位后的实际消息 ID 可以匹配高亮。
  bool shows(String messageId) => _messageId == messageId;

  /// 程序定位后的首轮布局保留当前窗口，直到用户开始操作。
  bool get awaitingInteraction => _messageId != null && _expiry == null;

  /// 随窗口的定位状态一起提交，重复定位到同一条也重新等待操作。
  void show(String messageId) {
    clear();
    if (messageId.isNotEmpty) _messageId = messageId;
  }

  /// 滚动或其他操作只使用首次输入的时间，连续操作不重置计时。
  void onUserInteraction() {
    if (!awaitingInteraction) return;
    _expiry = Timer(_delayAfterInteraction, () {
      clear();
      _onExpired();
    });
  }

  /// 清理窗口的定位状态，并取消可能尚未到期的计时。
  void clear() {
    _expiry?.cancel();
    _expiry = null;
    _messageId = null;
  }
}
