import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/widgets.dart';

import '../message_list/utils/rich_content_markdown_parser.dart';
import '../message_list/utils/rich_content_message.dart';
import '../message_list/utils/rich_content_markdown_span.dart';

/// 将有效富文本转为单行样式摘要；撤回及其他消息继续使用原有展示入口。
TextSpan? richContentConversationPreview(
  BuildContext context,
  MessageInfo? message,
  TextStyle style,
) {
  if (message?.status == MessageStatus.revoked ||
      message?.messageType != MessageType.custom) {
    return null;
  }
  final payload = message?.messagePayload;
  if (payload is! CustomMessagePayload) return null;
  final content = RichContentMessage.tryParse(payload.customData);
  if (content == null) return null;

  final locale = AppLocalization.of(context);
  // 保留全部块的发送顺序，媒体仅占文字宽度，不在会话行中加载或播放资源。
  return TextSpan(style: style, children: [
    for (final (index, block) in content.blocks.indexed) ...[
      if (index > 0) const TextSpan(text: ' '),
      switch (block) {
        RichTextBlock(:final text) => TextSpan(children: [
            for (final (index, node)
                in parseRichContentMarkdown(text).indexed) ...[
              if (index > 0) const TextSpan(text: ' '),
              richContentMarkdownSpan(context, node, style, compact: true),
            ],
          ]),
        RichImageBlock() => TextSpan(text: locale.messageTypeImage),
        RichFileBlock(:final mimeType) => TextSpan(
            text: mimeType.startsWith('video/')
                ? locale.messageTypeVideo
                : locale.messageTypeFile,
          ),
      },
    ],
  ]);
}
