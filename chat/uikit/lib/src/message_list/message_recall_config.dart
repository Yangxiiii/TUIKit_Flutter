import 'package:atomic_x_core/atomicxcore.dart';
import '../message_input/rich_content_draft.dart';
import 'utils/rich_content_message.dart';

/// 聊天提示和会话摘要共用身份事实，摘要按设计省去姓名后的空格。
String chatMessageRecallText(MessageInfo message, {bool compact = false}) {
  if (message.isSentBySelf) return '你撤回了一条消息';
  final name = message.from.nickname;
  final displayName =
      name != null && name.isNotEmpty ? name : message.from.userID;
  return '“$displayName”${compact ? '' : ' '}撤回了一条消息';
}

/// 撤回原文回填普通输入框所需的内容；富文本保留完整有序块，不使用纯文本摘要。
class ChatMessageRecallDraft {
  const ChatMessageRecallDraft({this.text, this.richContent});

  /// 普通文本原文；只有非富文本消息使用，保留换行与格式标记。
  final String? text;

  /// 已校验的oa_rich_content v1原文；回填时恢复图片、文件和文字顺序。
  final String? richContent;

  /// 将原文转换为现有输入草稿；未知业务协议返回null，不能覆盖用户草稿。
  RichContentDraft? toRichDraft() {
    final content = RichContentMessage.tryParse(richContent);
    return content == null ? null : RichContentDraft.fromMessage(content);
  }
}

/// 宿主提供撤回校验、原设备资格与短期原文；UIKit只编排确认和展示。
class ChatMessageRecallConfig {
  const ChatMessageRecallConfig({
    required this.canRecall,
    required this.recall,
    required this.editableUntil,
    required this.prepareReedit,
    required this.onLocalMessageSent,
  });

  /// 菜单展示资格；实际提交仍须重查SDK，不能只信任此同步结果。
  final bool Function(MessageInfo) canRecall;

  /// 宿主重查后调用submit；submit返回SDK错误码并保留AtomicX成功通知链。
  final Future<String?> Function(
      String messageId, Future<int> Function() submit) recall;

  /// 已确认的原设备重新编辑截止时间；null代表没有授予资格。
  final DateTime? Function(String messageId) editableUntil;

  /// 点击时重新校验时限并返回原文；失败时不更改输入草稿。
  final ({ChatMessageRecallDraft? draft, String? error}) Function(
      String messageId) prepareReedit;

  /// 只由当前输入流程的本机发送成功事件调用，跨端同步消息不触发。
  final void Function(MessageInfo) onLocalMessageSent;

  /// 当前仅识别项目已有富文本；未定义的名片、通话及其他custom不授予资格。
  static bool supportsCustomMessage(String? data) =>
      RichContentMessage.tryParse(data) != null;

  /// 统一菜单的类型、身份与120秒边界，避免不同展示入口授予不同权限。
  static bool isEligible(MessageInfo message, DateTime now) {
    // 只有项目已识别的自定义富文本进入白名单，未知custom不得推断为名片。
    final supported = switch (message.messageType) {
      MessageType.text ||
      MessageType.image ||
      MessageType.video ||
      MessageType.audio ||
      MessageType.file ||
      MessageType.face =>
        true,
      MessageType.custom => message.messagePayload is CustomMessagePayload &&
          supportsCustomMessage(
              (message.messagePayload as CustomMessagePayload).customData),
      _ => false,
    };
    // SDK消息时间为秒；缺失、未来时间及到120秒的消息都不能授予菜单资格。
    final timestamp = message.timestamp;
    final age = timestamp == null
        ? null
        : now.difference(DateTime.fromMillisecondsSinceEpoch(timestamp * 1000));
    return message.msgID.isNotEmpty &&
        message.isSentBySelf &&
        message.conversationType == ConversationType.c2c &&
        message.status == MessageStatus.sendSuccess &&
        supported &&
        age != null &&
        !age.isNegative &&
        age < const Duration(minutes: 2);
  }
}
