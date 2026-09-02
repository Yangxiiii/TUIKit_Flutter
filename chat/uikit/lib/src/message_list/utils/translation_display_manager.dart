import 'package:flutter/foundation.dart';

/// Manages the display state of translation text bubbles.
///
/// Core features:
/// - Hidden set mode: Uses an in-memory Set<String> to store message IDs that are hidden in this session
/// - Shown by default: When translatedText has value, the translation bubble is shown by default
/// - Session-only: Hidden state only affects current session, lost when exiting message list
/// - Re-entering chat: If translatedText has value, it will be shown again
///
/// 管理翻译文字气泡的显示状态
///
/// 核心功能：- 隐藏设置模式：使用内存中的 Set<String> 来存储本会话中隐藏的消息 ID - 默认显示：当 translatedText 有值时，翻译气泡默认显示 -
/// 仅限会话：隐藏状态只会影响当前会话，退出消息列表后会丢失 - 重新进入聊天：如果 translatedText 有值，会再次显示
class TranslationDisplayManager extends ChangeNotifier {
  /// Set of message IDs that are hidden in this session
  ///
  /// 本会话中隐藏的消息 ID 集合
  final Set<String> _hiddenMessageIDs = {};

  /// Set of message IDs that are currently translating
  ///
  /// 当前正在翻译的消息 ID 集合
  final Set<String> _translatingMessageIDs = {};

  /// Check if the message's translation bubble is hidden (collapsed) in this session
  ///
  /// 检查消息的翻译气泡在本会话中是否被隐藏（折叠）
  bool isHidden(String messageID) {
    return _hiddenMessageIDs.contains(messageID);
  }

  /// Check if the message is currently translating
  ///
  /// 检查消息是否正在翻译中
  bool isTranslating(String messageID) {
    return _translatingMessageIDs.contains(messageID);
  }

  /// Hide the translation bubble for this session
  ///
  /// 隐藏本会话的翻译气泡
  void hide(String messageID) {
    if (_hiddenMessageIDs.add(messageID)) {
      notifyListeners();
    }
  }

  /// Show the translation bubble (remove from hidden set)
  ///
  /// 显示翻译气泡（从隐藏集合中移除）
  void show(String messageID) {
    if (_hiddenMessageIDs.remove(messageID)) {
      notifyListeners();
    }
  }

  /// Mark message as translating
  ///
  /// 标记消息为正在翻译
  void setTranslating(String messageID, bool translating) {
    bool changed = false;
    if (translating) {
      changed = _translatingMessageIDs.add(messageID);
      // When starting translation, remove from hidden set so it shows
      //
      // 开始翻译时，从隐藏集合中移除以便显示
      _hiddenMessageIDs.remove(messageID);
    } else {
      changed = _translatingMessageIDs.remove(messageID);
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// Clear all display states
  ///
  /// 清除所有显示状态
  void clear() {
    if (_hiddenMessageIDs.isNotEmpty || _translatingMessageIDs.isNotEmpty) {
      _hiddenMessageIDs.clear();
      _translatingMessageIDs.clear();
      notifyListeners();
    }
  }
}
