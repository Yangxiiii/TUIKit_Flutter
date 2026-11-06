import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/widgets.dart';

/// 当前消息窗口派生的引用与直接回复索引，供列表同一帧复用。
typedef ChatMessageReplyView = ({
  Map<String, MessageQuoteInfo> quotes,
  Map<String, List<String>> replies,
});

/// 宿主提供跨端回复协议和页面跳转，UIKit 继续持有原消息窗口与定位逻辑。
final class ChatMessageReplyConfig {
  const ChatMessageReplyConfig({
    required this.project,
    required this.openDetails,
    required this.sendError,
    required this.canStart,
    required this.contentTooLongMessage,
  });

  /// 每次窗口变化按可见消息派生引用与计数。
  final ChatMessageReplyView Function(
    List<MessageInfo> window,
    bool Function(String id) isRevoked,
  ) project;

  /// 使用源消息和已知直接回复打开详情，转发复用原会话列表。
  final void Function(
    BuildContext context,
    MessageInfo source,
    List<String> replies,
    MessageListStore store,
  ) openDetails;

  /// 将本地发送失败转成可见提示；撤回失败可要求清空旧草稿。
  final ({String message, bool reset}) Function(int code) sendError;

  /// 输入超限时的提示；此时发送按钮已禁用，不会进入 SDK 回调。
  final String contentTooLongMessage;

  /// 进入输入区前检查当前已知的回复资格；提交时由宿主再次校验。
  final bool Function(BuildContext context, MessageInfo source, int count)
      canStart;

  /// SDK 原始扩展字段只在 UIKit 边界取出，宿主无需读取可变的内部消息对象。
  static String? cloudDataOf(MessageInfo message) =>
      message.rawMessage?.cloudCustomData;
}
