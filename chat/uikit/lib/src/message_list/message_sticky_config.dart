import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/widgets.dart';

import 'utils/big_file_message.dart';
import 'utils/rich_content_message.dart';

/// 宿主提供单聊置顶状态和动作；UIKit只编排菜单、定位和叠放区域。
final class ChatMessageStickyConfig {
  const ChatMessageStickyConfig(
      {required this.pin,
      required this.bannerBuilder,
      required this.onMessagesChanged,
      required this.onMessagesDeleted});

  /// 提交置顶；返回null表示成功，否则由页面显示业务反馈。
  final Future<String?> Function(MessageInfo message) pin;

  /// 宿主提供横幅并使用UIKit提供的定位回调，避免访问私有列表状态。
  final Widget Function(BuildContext context, void Function(MessageInfo) locate)
      bannerBuilder;

  /// 当前SDK窗口变化后交给宿主检查置顶原消息是否失效。
  final ValueChanged<List<MessageInfo>> onMessagesChanged;

  /// SDK明确删除成功的消息ID，与分页窗口缺失分开处理。
  final ValueChanged<List<String>> onMessagesDeleted;
}

/// 从真实SDK内容派生横幅摘要，不以操作人信息代替原发送人。
final class ChatStickyPreview {
  const ChatStickyPreview(
      {required this.text, this.imageUrl, this.isVideo = false});

  /// 只用于横幅的一行摘要，原消息内容保持不变。
  final String text;

  /// 真实消息的缩略图或视频封面，不是设计截图。
  final String? imageUrl;

  /// 视频封面需要叠加播放标识，与图片预览分别表达。
  final bool isVideo;

  /// 按消息自身类型派生，已知自定义内容沿用各自的协议校验器。
  factory ChatStickyPreview.fromMessage(MessageInfo message) {
    final payload = message.messagePayload;
    return switch (payload) {
      TextMessagePayload p => ChatStickyPreview(text: p.text),
      ImageMessagePayload p => ChatStickyPreview(
          text: '[图片]', imageUrl: p.thumbImageURL ?? p.originalImageURL),
      VideoMessagePayload p => ChatStickyPreview(
          text: '[视频]', imageUrl: p.videoSnapshotURL, isVideo: true),
      FileMessagePayload p =>
        ChatStickyPreview(text: '[文件]${p.fileName ?? ''}'),
      FaceMessagePayload p => ChatStickyPreview(text: p.faceData ?? '[表情]'),
      CustomMessagePayload p => _custom(p.customData),
      _ => const ChatStickyPreview(text: '消息不存在'),
    };
  }

  /// 已知自定义附件和图文按各自协议派生，未知内容不猜测为文件。
  static ChatStickyPreview _custom(String data) {
    final file = BigFileMessage.tryParse(data);
    if (file != null) return ChatStickyPreview(text: '[文件]${file.name}');
    final rich = RichContentMessage.tryParse(data);
    if (rich == null) return const ChatStickyPreview(text: '消息不存在');
    // 富文本保留有序内容摘要，附件不被误当作普通文字或操作提示。
    final text = rich.blocks
        .map((block) => switch (block) {
              RichTextBlock b => b.text,
              RichImageBlock _ => '[图片]',
              RichFileBlock b => '[文件]${b.name}',
            })
        .join();
    return ChatStickyPreview(text: text);
  }
}
