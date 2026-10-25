import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/widgets.dart';
import '../message_recall_config.dart';

/// 让消息展示订阅宿主的撤回资格，同时把确认、回填编排保留在聊天页。
class MessageRecallScope extends InheritedWidget {
  const MessageRecallScope(
      {super.key,
      required this.config,
      required this.onRecall,
      required this.onReedit,
      required super.child});

  /// 当前账号和会话的撤回能力及限时原文资格。
  final ChatMessageRecallConfig config;

  /// 打开确认并调用宿主统一入口，消息气泡不直接写入SDK。
  final void Function(MessageInfo) onRecall;

  /// 将已校验的原文回填到普通输入区。
  final void Function(String messageId) onReedit;

  /// 仅订阅当前聊天页，未注入能力的群聊沿用原UIKit行为。
  static MessageRecallScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MessageRecallScope>();

  @override
  bool updateShouldNotify(MessageRecallScope oldWidget) =>
      oldWidget.config != config;
}
