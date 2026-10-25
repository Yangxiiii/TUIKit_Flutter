import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/foundation.dart';

/// 宿主提供编辑权限与SDK保存能力，UIKit仅协调输入和展示，不自行维护成功次数。
class ChatMessageEditConfig {
  const ChatMessageEditConfig({
    required this.canEdit,
    required this.prepare,
    required this.save,
    required this.onMessageWindowChanged,
    this.editedMessageIds = const {},
  });

  /// 同步决定菜单资格；提交前宿主仍须从SDK复核所有权、时限与次数。
  final bool Function(MessageInfo message) canEdit;

  /// 返回最新原文或失败文案，失败时不进入编辑状态。
  final Future<({String? text, String? error})> Function(String messageId)
      prepare;

  /// null代表保存成功，否则返回需求约定的失败文案，失败时保留输入。
  final Future<String?> Function(String messageId, String text) save;

  /// 当前窗口的稳定消息标识，用于宿主批量派生SDK附加数据。
  final ValueChanged<List<String>> onMessageWindowChanged;

  /// SDK已确认编辑成功的消息集合；仅控制标签，不写入正文。
  final Set<String> editedMessageIds;
}
