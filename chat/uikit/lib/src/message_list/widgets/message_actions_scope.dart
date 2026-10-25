import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/widgets.dart';
import '../../emoji_picker/emoji_picker_model.dart';
import '../message_edit_config.dart';
import 'message_tooltip.dart';

/// 把聊天页的编辑配置和面板编排交给气泡，避免让展示组件直接调用业务服务。
class MessageActionsScope extends InheritedWidget {
  const MessageActionsScope({
    super.key,
    required this.config,
    required this.showActions,
    required this.onMessagesChanged,
    required super.child,
  });

  /// 当前宿主允许的编辑能力及SDK派生标识。
  final ChatMessageEditConfig config;

  /// 由聊天页展示底部面板并协调目标气泡避让；回应沿用原有SDK回调。
  final void Function(MessageInfo, GlobalKey, List<MessageMenuItem>,
      void Function(EmojiPickerModelItem)?) showActions;

  /// SDK列表完成更新后检查当前编辑目标并批量派生附加数据。
  final ValueChanged<List<MessageInfo>> onMessagesChanged;

  /// 气泡订阅当前编辑标识；未配置能力时继续使用原有消息菜单。
  static MessageActionsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MessageActionsScope>();

  @override
  bool updateShouldNotify(MessageActionsScope oldWidget) =>
      oldWidget.config != config;
}
