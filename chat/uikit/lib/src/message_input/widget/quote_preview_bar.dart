import 'package:tencent_chat_uikit/src/message_list/utils/big_file_message.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:app_ui/app_ui.dart' show AppIcons, AppColorBuildContext;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_input/src/chat_special_text_span_builder.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text/extended_text.dart';
import '../../message_list/utils/message_utils.dart';

/// 引用预览栏。单聊回复在输入行上方展示单行摘要，原生引用保留媒体预览。
class QuotePreviewBar extends StatelessWidget {
  final MessageInfo quotedMessage;
  final VoidCallback onClose;

  /// 单聊回复的摘要位于共享输入卡片内，旧引用仍展示对应媒体预览。
  final bool compactReply;

  const QuotePreviewBar({
    super.key,
    required this.quotedMessage,
    required this.onClose,
    this.compactReply = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    final locale = AppLocalization.of(context);
    final senderName = ChatUtil.getMessageSenderName(quotedMessage);

    if (compactReply) {
      final appColors = context.appColors;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        height: 32,
        decoration: BoxDecoration(
          color: appColors.referenceBackground,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            // 关闭动作固定在左侧，任意消息类型的摘要都只占一行。
            Semantics(
              identifier: 'tim.reply.cancel',
              label: '取消回复',
              button: true,
              child: InkWell(
                onTap: onClose,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(AppIcons.close,
                      size: 14, color: appColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '$senderName：${MessageUtil.getMessageAbstract(quotedMessage, context)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: appColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.bgColorDefault,
        border: Border(
          top: BorderSide(
              color: colors.strokeColorPrimary.withValues(alpha: 0.2),
              width: 0.5),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          // Content area - single line: "sender: content"
          //
          // 内容区 - 单行：“发送者：内容”
          Expanded(
            child: _buildSingleLineContent(colors, locale, senderName),
          ),
          // Thumbnail (for image/video)
          //
          // 缩略图（针对图片/视频）
          _buildThumbnail(colors),
          const SizedBox(width: 8),
          // Close button
          //
          // 关闭按钮
          GestureDetector(
            onTap: onClose,
            child: Icon(
              Icons.close,
              size: 18,
              color: colors.textColorSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleLineContent(
      SemanticColorScheme colors, AppLocalizedText locale, String senderName) {
    final payload = quotedMessage.messagePayload;
    final textStyle = FontScheme.caption2Regular.copyWith(
      color: colors.textColorSecondary,
    );
    final prefix = senderName.isNotEmpty ? '$senderName：' : '';

    // Audio and file use Icon prefix
    //
    // 音频和文件使用图标前缀
    if (payload is AudioMessagePayload) {
      final duration = payload.audioDuration;
      final minutes = duration ~/ 60;
      final seconds = duration % 60;
      final timeText =
          '${minutes > 0 ? "$minutes:" : ""}${seconds.toString().padLeft(2, '0')}"';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prefix.isNotEmpty)
            Text(prefix,
                style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          Icon(Icons.volume_up, size: 14, color: colors.textColorSecondary),
          const SizedBox(width: 2),
          Flexible(
              child: Text(timeText,
                  style: textStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
        ],
      );
    }
    if (payload is FileMessagePayload) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prefix.isNotEmpty)
            Text(prefix,
                style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          Icon(Icons.insert_drive_file,
              size: 14, color: colors.textColorSecondary),
          const SizedBox(width: 2),
          Flexible(
              child: Text(payload.fileName ?? locale.messageTypeFile,
                  style: textStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
        ],
      );
    }

    final contentText = _getContentSummary(locale);
    final displayText = '$prefix$contentText';
    // 使用共用解析器将ZDEmoji令牌显示为行内图片，原文用于引用与发送。
    return ExtendedText(
      displayText,
      specialTextSpanBuilder: ChatSpecialTextSpanBuilder(
        colorScheme: colors,
        onTapUrl: (_) {},
      ),
      style: textStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _getContentSummary(AppLocalizedText locale) {
    final payload = quotedMessage.messagePayload;

    switch (payload) {
      case TextMessagePayload p:
        return p.text;
      case ImageMessagePayload _:
        return locale.messageTypeImage;
      case VideoMessagePayload _:
        return locale.messageTypeVideo;
      case AudioMessagePayload _:
        return '';
      case FileMessagePayload _:
        return '';
      case FaceMessagePayload _:
        return locale.messageTypeSticker;
      case CustomMessagePayload p:
        return BigFileMessage.tryParse(p.customData)?.name ??
            p.description ??
            locale.messageTypeCustom;
      case MergedMessagePayload p:
        return p.title.isNotEmpty ? p.title : locale.messageTypeMerged;
      default:
        return locale.messageTypeUnknown;
    }
  }

  Widget _buildThumbnail(SemanticColorScheme colors) {
    final payload = quotedMessage.messagePayload;

    String? imageUrl;
    bool isVideo = false;

    if (payload is ImageMessagePayload) {
      imageUrl = payload.thumbImageURL ?? payload.originalImageURL;
    } else if (payload is VideoMessagePayload) {
      imageUrl = payload.videoSnapshotURL;
      isVideo = true;
    }

    if (imageUrl == null || imageUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 32,
        height: 32,
        child: Stack(
          children: [
            CachedNetworkImage(
              imageUrl: imageUrl,
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                color: colors.bgColorBubbleReciprocal,
                child: Icon(
                  isVideo ? Icons.videocam : Icons.image,
                  size: 16,
                  color: colors.textColorSecondary,
                ),
              ),
            ),
            if (isVideo)
              Positioned.fill(
                child: Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
