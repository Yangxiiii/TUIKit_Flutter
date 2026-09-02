import 'package:flutter/foundation.dart';

/// Manages the display state of ASR (Automatic Speech Recognition) text bubbles.
///
/// Core features:
/// - Hidden set mode: Uses an in-memory Set<String> to store message IDs that are hidden in this session
/// - Shown by default: When asrText has value, the ASR text bubble is shown by default
/// - Session-only: Hidden state only affects current session, lost when exiting message list
/// - Re-entering chat: If asrText has value, it will be shown again
///
/// 管理 ASR（自动语音识别）文本气泡的显示状态。
///
/// 核心功能: - 隐藏设置模式: 使用内存中的 Set<String> 来存储本次会话中隐藏的消息 ID - 默认显示: 当 asrText 有值时，ASR 文本气泡默认显示 - 仅限本会话:
/// 隐藏状态仅影响当前会话，退出消息列表后消失 - 重新进入聊天: 如果 asrText 有值，会再次显示
class AsrDisplayManager extends ChangeNotifier {
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

  /// Mark message as converting
  ///
  /// 标记消息为正在转换
  void setConverting(String messageID, bool converting) {
    bool changed = false;
    if (converting) {
      changed = _convertingMessageIDs.add(messageID);
      // When starting conversion, remove from hidden set so it shows
      //
      // 开始转换时，从隐藏集合中移除以便显示
      _hiddenMessageIDs.remove(messageID);
    } else {
      changed = _convertingMessageIDs.remove(messageID);
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// Clear all display states
  ///
  /// 清除所有显示状态
  void clear() {
    if (_hiddenMessageIDs.isNotEmpty || _convertingMessageIDs.isNotEmpty) {
      _hiddenMessageIDs.clear();
      _convertingMessageIDs.clear();
      notifyListeners();
    }
  }
}
