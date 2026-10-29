import '../../utils/sticky_message_event.dart';
import 'dart:io';
import '../../../message_input/pending_rich_content_message.dart';
import 'package:app_ui/app_ui.dart' as app;
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/utils/rich_content_message.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_types/rich_content_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/big_file_message.dart';
import 'file_message_widget.dart';
import 'rich_content_video_preview.dart';
import '../../utils/rich_content_media_viewer.dart';

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
    final event = StickyMessageEvent.fromMessage(message);
    if (event != null) {
      if (event.isControl) return const SizedBox.shrink();
      final colors = app.AppColorBuildContext(context).appColors;
      // 系统提示只展示姓名和动作，不增加头像、普通气泡或编辑入口。
      return Center(child: Text.rich(TextSpan(children: [
        TextSpan(text: event.operatorName, style: TextStyle(color: colors.primary)),
        TextSpan(text: ' ${event.actionText}', style: TextStyle(color: colors.textSecondary)),
      ]), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, height: 19 / 12)));
    }
    final colors = SemanticColorScheme.of(context);
    final atomicLocale = AppLocalization.of(context);
    final customMessage = (message.messagePayload as CustomMessagePayload?);
    // 发送中的本地气泡直接读取内存草稿，不放宽远端消息协议对 URL 的校验。
    if (customMessage is PendingRichContentMessage) {
      return _buildRichContentMessage(
          context, colors, customMessage.draft.localPreview,
          localPreview: true);
    }
    final file = BigFileMessage.tryParse(customMessage?.customData);
    if (file != null) {
      return FileMessageWidget(
          message: message,
          isSelf: isSelf,
          maxWidth: maxWidth,
          config: config,
          onLongPress: onLongPress,
          messageListStore: messageListStore,
          bigFile: file);
    }

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

  /// 按正文顺序展示文字、图片、视频及普通文件，媒体点击定位到共用预览器。
  Widget _buildRichContentMessage(
    BuildContext context,
    SemanticColorScheme colors,
    RichContentMessage content, {
    bool localPreview = false,
  }) {
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
                    textStyle: FontScheme.caption1Regular.copyWith(
                      color: foreground,
                    ),
                  ),
                RichImageBlock(:final url, :final width, :final height) =>
                  _buildImage(
                    context,
                    url,
                    width,
                    height,
                    colors,
                    localPreview
                        ? null
                        : () => showRichContentMediaViewer(
                              context,
                              content,
                              index,
                              downloadVideo: config.fileDownloader,
                            ),
                    localPreview: localPreview,
                  ),
                RichFileBlock(:final url, :final mimeType, :final thumbnailUrl)
                    when mimeType.startsWith('video/') =>
                  _buildVideo(
                    context,
                    url,
                    thumbnailUrl,
                    localPreview
                        ? null
                        : () => showRichContentMediaViewer(
                              context,
                              content,
                              index,
                              downloadVideo: config.fileDownloader,
                            ),
                    localPreview: localPreview,
                  ),
                RichFileBlock(:final url, :final name, :final size) =>
                  _buildFile(url, name, size, foreground, colors,
                      localPreview: localPreview),
              },
            ],
          ],
        ),
      ),
    );
  }

  /// 按原图比例约束气泡尺寸，点击进入媒体预览，加载失败时保留可识别占位。
  Widget _buildImage(
    BuildContext context,
    String url,
    int? width,
    int? height,
    SemanticColorScheme colors,
    VoidCallback? onPreview, {
    bool localPreview = false,
  }) {
    final displayWidth = math.max(1.0, maxWidth * 0.7 - 24);
    // 无尺寸消息交由图片解码确定比例，仍限制最大高度，避免长图撑满聊天窗口。
    final displayHeight = width != null && height != null
        ? math.max(1.0, math.min(240.0, displayWidth * height / width))
        : null;
    return Semantics(
      identifier: 'tim.rich.image.${message.msgID}.${url.hashCode}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPreview,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: displayWidth, maxHeight: 240),
            child: localPreview && Uri.tryParse(url)?.scheme == 'file'
                ? Image(
                    image: ResizeImage(FileImage(File.fromUri(Uri.parse(url))),
                        width: (displayWidth *
                                MediaQuery.devicePixelRatioOf(context) *
                                1.5)
                            .ceil(),
                        height:
                            (240 * MediaQuery.devicePixelRatioOf(context) * 1.5)
                                .ceil(),
                        policy: ResizeImagePolicy.fit),
                    width: displayWidth,
                    height: displayHeight,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                        Icons.broken_image_outlined,
                        color: colors.textColorTertiary),
                  )
                : CachedNetworkImage(
                    imageUrl: url,
                    width: displayWidth,
                    height: displayHeight,
                    fit: displayHeight == null ? BoxFit.contain : BoxFit.cover,
                    errorWidget: (_, __, ___) => SizedBox(
                      width: displayWidth,
                      height: displayHeight ?? 120,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: colors.textColorTertiary,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// 视频气泡点击进入共用媒体预览器，编辑器中的封面仍不提供播放交互。
  Widget _buildVideo(BuildContext context, String url, String? thumbnailUrl,
      VoidCallback? onPreview,
      {bool localPreview = false}) {
    final width = math.max(1.0, maxWidth * 0.7 - 24);
    // 消息与资源共同区分点击入口，资源地址只保留散列，避免把签名URL写入语义树。
    return Semantics(
      identifier: 'tim.rich.video.${message.msgID}.${url.hashCode}',
      child: GestureDetector(
        // 封面自身忽略指针以兼容编辑器，气泡需要由外层显式接管点击命中。
        behavior: HitTestBehavior.opaque,
        onTap: onPreview,
        child: RichContentVideoPreview(
          playIcon: config.videoPlayIcon,
          image: thumbnailUrl == null
              ? null
              : localPreview && Uri.tryParse(thumbnailUrl)?.scheme == 'file'
                  ? ResizeImage(
                      FileImage(File.fromUri(Uri.parse(thumbnailUrl))),
                      width:
                          (width * MediaQuery.devicePixelRatioOf(context) * 1.5)
                              .ceil(),
                      height: (math.min(240, width * 9 / 16) *
                              MediaQuery.devicePixelRatioOf(context) *
                              1.5)
                          .ceil(),
                      policy: ResizeImagePolicy.fit)
                  : CachedNetworkImageProvider(thumbnailUrl),
          size: Size(width, math.min(240, width * 9 / 16)),
        ),
      ),
    );
  }

  /// 普通文件沿用附件卡片，视频由共用封面组件展示，点击时打开协议 URL。
  Widget _buildFile(
    String url,
    String name,
    int size,
    Color foreground,
    SemanticColorScheme colors, {
    bool localPreview = false,
  }) {
    return InkWell(
      onTap: localPreview
          ? null
          : () =>
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
