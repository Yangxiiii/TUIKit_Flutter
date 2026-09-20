import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/rich_content_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

/// 按业务标识展示自定义消息，并为未知协议保留通用气泡兜底。
class CustomMessageWidget extends StatelessWidget {
  /// 待展示的消息，图文协议从其自定义数据字段中解析。
  final MessageInfo message;
  final bool isSelf;

  /// 气泡可用的最大宽度，单位为逻辑像素。
  final double maxWidth;

  /// 复用消息列表的对齐和圆角配置，使图文消息与普通聊天气泡一致。
  final MessageListConfigProtocol config;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final MessageListStore? messageListStore;

  const CustomMessageWidget({
    super.key,
    required this.message,
    required this.isSelf,
    required this.maxWidth,
    this.config = const ChatMessageListConfig(),
    this.onTap,
    this.onLongPress,
    this.messageListStore,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SemanticColorScheme.of(context);
    final atomicLocale = AppLocalization.of(context);
    final customMessage = (message.messagePayload as CustomMessagePayload?);

    final customContent =
        ChatUtil.jsonData2Dictionary(customMessage?.customData);
    if (customContent != null &&
        customContent['businessID'] == 'group_create') {
      return _buildSystemMessage(context, colors, atomicLocale, customContent);
    }

    if (customContent?['businessID'] == RichContentMessage.businessID) {
      final richContent =
          RichContentMessage.tryParse(customMessage?.customData);
      if (richContent != null) {
        return _buildRichContentMessage(context, colors, richContent);
      }
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: _buildDefaultCustomMessagePayload(context, colors, atomicLocale),
    );
  }

  /// 在同一气泡中按协议顺序展示文字、图片和文件。
  Widget _buildRichContentMessage(
    BuildContext context,
    SemanticColorScheme colors,
    RichContentMessage content,
  ) {
    final foreground =
        isSelf ? colors.textColorAntiPrimary : colors.textColorPrimary;
    // 文字气泡在不同对齐方式下的尾角方向必须保持一致。
    final tailOnRight =
        config.alignment == 'right' || (config.alignment != 'left' && isSelf);
    final radius = config.textBubbleCornerRadius;
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth * 0.7),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
          color:
              isSelf ? colors.bgColorBubbleOwn : colors.bgColorBubbleReciprocal,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(radius),
            topRight: Radius.circular(radius),
            bottomLeft: Radius.circular(tailOnRight ? radius : 0),
            bottomRight: Radius.circular(tailOnRight ? 0 : radius),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 每个块保留原始位置，避免把附件统一挪到文字之后。
            for (final (index, block) in content.blocks.indexed) ...[
              if (index > 0) const SizedBox(height: 8),
              switch (block) {
                RichTextBlock(:final text) => RichContentMarkdown(
                    data: text,
                    textStyle:
                        FontScheme.caption1Regular.copyWith(color: foreground),
                  ),
                RichImageBlock(:final url, :final width, :final height) =>
                  _buildImage(url, width, height, colors),
                RichFileBlock(:final url, :final name, :final size) =>
                  _buildFile(url, name, size, foreground, colors),
              },
            ],
          ],
        ),
      ),
    );
  }

  /// 根据原图比例约束预览大小，图片加载失败时仍保留可识别的占位内容。
  Widget _buildImage(
    String url,
    int width,
    int height,
    SemanticColorScheme colors,
  ) {
    final displayWidth = math.max(1.0, maxWidth * 0.7 - 24);
    final displayHeight = math.max(
      1.0,
      math.min(240.0, displayWidth * height / width),
    );
    return GestureDetector(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: url,
          width: displayWidth,
          height: displayHeight,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: Icon(Icons.broken_image_outlined,
                color: colors.textColorTertiary),
          ),
        ),
      ),
    );
  }

  /// 文件块沿用普通文件消息的附件卡片层级，点击时使用协议 URL 打开。
  Widget _buildFile(
    String url,
    String name,
    int size,
    Color foreground,
    SemanticColorScheme colors,
  ) {
    return InkWell(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelf
              ? colors.buttonColorPrimaryDefault.withAlpha(26)
              : colors.bgColorDefault.withAlpha(128),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.buttonColorSecondaryHover,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.attach_file,
                color: colors.textColorAntiPrimary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        FontScheme.caption2Medium.copyWith(color: foreground),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatFileSize(size),
                    style: FontScheme.caption3Regular.copyWith(
                      color: isSelf
                          ? colors.textColorAntiSecondary
                          : colors.textColorSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 与普通文件气泡保持相同的文件大小展示单位。
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildSystemMessage(
      BuildContext context,
      SemanticColorScheme colorsTheme,
      AppLocalizedText atomicLocale,
      Map<String, dynamic> customContent) {
    String content = '';

    switch (customContent['businessID']) {
      case 'group_create':
        final sender = customContent['opUser'];
        final cmd = customContent['cmd'] as int? ?? 0;
        if (cmd >= 0) {
          if (cmd == 1) {
            content = '$sender ${atomicLocale.createCommunity}';
          } else {
            content = '$sender ${atomicLocale.createGroupTips}';
          }
        }
        break;
      default:
        content = customContent['content']?.toString() ??
            atomicLocale.messageTypeCustom;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorsTheme.strokeColorPrimary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            content,
            style: FontScheme.caption3Regular.copyWith(
              color: colorsTheme.textColorTertiary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultCustomMessagePayload(
    BuildContext context,
    SemanticColorScheme colorsTheme,
    AppLocalizedText atomicLocale,
  ) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: maxWidth * 0.7,
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: isSelf
            ? colorsTheme.buttonColorPrimaryDefault
            : colorsTheme.bgColorDefault,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        atomicLocale.messageTypeCustom,
        style: FontScheme.caption2Medium.copyWith(
          color: isSelf
              ? colorsTheme.textColorAntiPrimary
              : colorsTheme.textColorPrimary,
        ),
      ),
    );
  }
}
