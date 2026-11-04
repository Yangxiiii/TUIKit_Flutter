import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/widgets.dart';

/// 将已有消息、来源Store与转发方式交给宿主，UIKit不依赖宿主业务包。
final class ChatForwardRequest {
  ChatForwardRequest({
    required List<MessageInfo> messages,
    required this.type,
    required this.source,
    required this.conversationID,
    required this.single,
    required this.needReadReceipt,
    this.recordTitle,
  }) : messages = List.unmodifiable(messages);

  /// 按来源时间升序排列的原消息，不修改SDK当前列表。
  final List<MessageInfo> messages;

  /// 用户明确选择的逐条或合并方式。
  final MessageForwardType type;

  /// 来源消息列表Store，继续使用其公开转发接口。
  final MessageListStore source;

  /// 来源会话ID；合并包内的独立消息预览可能没有外层会话ID。
  final String conversationID;

  /// 单条菜单入口与多选一条消息的入口保持不同确认文案。
  final bool single;

  /// 沿用来源页面的已读回执配置。
  final bool needReadReceipt;

  /// 合并详情内层消息保留原记录标题；普通聊天为空时由宿主使用当前会话资料生成。
  final String? recordTitle;
}

/// 宿主接管选择与发送流程，true仅表示所有目标和留言均发送成功。
typedef ChatForwardHandler = Future<bool> Function(
    BuildContext context, ChatForwardRequest request);

/// 宿主执行本地删除；返回已确认删除的消息，部分失败不得虚报整个批次成功。
typedef ChatLocalDeleteHandler = Future<List<String>> Function(
    List<MessageInfo> messages);
