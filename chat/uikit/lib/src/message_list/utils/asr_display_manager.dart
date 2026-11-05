import 'package:flutter/foundation.dart';

/// 维护当前列表的识别显示、失败、过期及已播放状态；账号切换或列表销毁后不复用。
/// 已识别正文及持久化标记由腾讯SDK保存，此处只协调界面状态。
class AsrDisplayManager extends ChangeNotifier {
  /// 失败与过期分别保存，失败可重试，真实过期隐藏转换入口。
  final Set<String> _failed = {};
  final Set<String> _expired = {};

  /// 已实际开始播放或确认过期的本会话标记，不与会话未读条数混用。
  final Set<String> _played = {};

  /// 当前消息最近一次识别失败，供附件展示与重新识别使用。
  bool hasFailed(String id) => _failed.contains(id);

  /// 资源已由刷新后的腾讯地址明确确认不存在。
  bool isExpired(String id) => _expired.contains(id);

  /// 本会话已经播放过，持久化事实另由腾讯localCustomInt提供。
  bool wasPlayed(String id) => _played.contains(id);

  /// 只有状态实际变化才通知列表，不重复重建所有气泡。
  void setFailed(String id, bool value) {
    final changed = value ? _failed.add(id) : _failed.remove(id);
    if (changed) notifyListeners();
  }

  /// 真实过期同时移除未播放标记，不能由普通下载失败调用。
  void setExpired(String id) {
    _expired.add(id);
    _played.add(id);
    _failed.remove(id);
    _convertingMessageIDs.remove(id);
    notifyListeners();
  }

  /// 真实播放开始后隐藏红点，不把请求播放本身当作听过。
  void markPlayed(String id) {
    if (_played.add(id)) notifyListeners();
  }

  /// Set of message IDs that are hidden in this session
  ///
  /// 本次会话中隐藏的消息 ID 集合
  final Set<String> _hiddenMessageIDs = {};

  /// Set of message IDs that are currently converting
  ///
  /// 当前正在转换的消息 ID 集合
  final Set<String> _convertingMessageIDs = {};

  /// Check if the message's ASR text bubble is hidden (collapsed) in this session
  ///
  /// 检查消息的 ASR 文本气泡在本次会话中是否隐藏（折叠）
  bool isHidden(String messageID) {
    return _hiddenMessageIDs.contains(messageID);
  }

  /// Check if the message is currently converting
  ///
  /// 检查消息是否正在转换
  bool isConverting(String messageID) {
    return _convertingMessageIDs.contains(messageID);
  }

  /// Hide the ASR text bubble for this session
  ///
  /// 隐藏本次会话的 ASR 文本气泡
  void hide(String messageID) {
    if (_hiddenMessageIDs.add(messageID)) {
      notifyListeners();
    }
  }

  /// Show the ASR text bubble (remove from hidden set)
  ///
  /// 显示 ASR 文本气泡（从隐藏集合中移除）
  void show(String messageID) {
    if (_hiddenMessageIDs.remove(messageID)) {
      notifyListeners();
    }
  }

  /// 开始识别时清除失败和隐藏状态；结束请求只清理进行中标记，不删除SDK正文。
  void setConverting(String messageID, bool converting) {
    bool changed = false;
    if (converting) {
      changed = _convertingMessageIDs.add(messageID);
      _failed.remove(messageID);
      // 重试必须重新展示附件，不能沿用上次隐藏结果造成无反馈。
      _hiddenMessageIDs.remove(messageID);
    } else {
      changed = _convertingMessageIDs.remove(messageID);
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// 列表销毁或账号切换时清除界面状态，SDK持久化正文仍由SDK维护。
  void clear() {
    final voiceChanged =
        _failed.isNotEmpty || _expired.isNotEmpty || _played.isNotEmpty;
    _failed.clear();
    _expired.clear();
    _played.clear();
    if (_hiddenMessageIDs.isNotEmpty || _convertingMessageIDs.isNotEmpty) {
      _hiddenMessageIDs.clear();
      _convertingMessageIDs.clear();
      notifyListeners();
    } else if (voiceChanged) {
      notifyListeners();
    }
  }
}
