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
import '../chat_media_placeholder.dart';

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
      return Center(
          child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: event.operatorName,
                    style: TextStyle(color: colors.primary)),
                TextSpan(
                    text: ' ${event.actionText}',
                    style: TextStyle(color: colors.textSecondary)),
              ]),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, height: 19 / 12)));
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
                RichFileBlock(
                  :final url,
                  :final mimeType,
                  :final thumbnailUrl,
                  :final width,
                  :final height,
                )
                    when mimeType.startsWith('video/') =>
                  _buildVideo(
                    context,
                    url,
                    thumbnailUrl,
                    width,
                    height,
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
    final size = width != null && height != null
        ? _mediaDisplaySize(width, height)
        : null;
    final displayWidth = size?.width ?? math.max(1.0, maxWidth * 0.7 - 24);
    // 无尺寸消息交由图片解码确定比例，仍限制最大高度，避免长图撑满聊天窗口。
    final displayHeight = size?.height;
    return Semantics(
      identifier: 'tim.rich.image.${message.msgID}.${url.hashCode}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPreview,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: displayWidth, maxHeight: 240),
            child: Image(
              image: _resizeMediaImage(
                context,
                localPreview && Uri.tryParse(url)?.scheme == 'file'
                    ? FileImage(File.fromUri(Uri.parse(url)))
                    : CachedNetworkImageProvider(url),
                Size(displayWidth, displayHeight ?? 240),
              ),
              width: displayWidth,
              height: displayHeight,
              fit: BoxFit.contain,
              frameBuilder: (_, child, frame, synchronous) =>
                  synchronous || frame != null
                      ? child
                      : _buildImagePlaceholder(displayWidth, displayHeight),
              errorBuilder: (_, __, ___) => SizedBox(
                width: displayWidth,
                height: displayHeight ?? 120,
                child: Icon(Icons.broken_image_outlined,
                    color: colors.textColorTertiary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 消息携带尺寸时，加载占位和资源共用同一个盒子，避免加载完成后气泡跳动。
  Widget _buildImagePlaceholder(double width, double? height) => SizedBox(
        width: width,
        height: height ?? 120,
        child: ChatMediaPlaceholder(image: config.imageLoadingPlaceholder),
      );

  /// 宽高只用于比例，在气泡的宽高上限内等比缩放，避免长图或竖屏视频被裁剪。
  Size _mediaDisplaySize(int width, int height) => applyBoxFit(
        BoxFit.contain,
        Size(width.toDouble(), height.toDouble()),
        Size(math.max(1.0, maxWidth * 0.7 - 24), 240),
      ).destination;

  /// 与编辑器一致，按展示物理像素的 1.5 倍解码；保持比例且不放大小图。
  ResizeImage _resizeMediaImage(
      BuildContext context, ImageProvider original, Size size) {
    final scale = MediaQuery.devicePixelRatioOf(context) * 1.5;
    return ResizeImage(
      original,
      width: math.max(1, (size.width * scale).ceil()),
      height: math.max(1, (size.height * scale).ceil()),
      policy: ResizeImagePolicy.fit,
    );
  }

  /// 视频气泡点击进入共用媒体预览器，编辑器中的封面仍不提供播放交互。
  Widget _buildVideo(BuildContext context, String url, String? thumbnailUrl,
      int? width, int? height, VoidCallback? onPreview,
      {bool localPreview = false}) {
    // 历史视频没有尺寸时沿用横屏占位，新消息在解码封面前即可确定真实比例。
    final size = width != null && height != null
        ? _mediaDisplaySize(width, height)
        : _mediaDisplaySize(16, 9);
    // 消息与资源共同区分点击入口，资源地址只保留散列，避免把签名URL写入语义树。
    return Semantics(
      identifier: 'tim.rich.video.${message.msgID}.${url.hashCode}',
      child: GestureDetector(
        // 封面自身忽略指针以兼容编辑器，气泡需要由外层显式接管点击命中。
        behavior: HitTestBehavior.opaque,
        onTap: onPreview,
        child: RichContentVideoPreview(
          playIcon: config.videoPlayIcon,
          loadingPlaceholder: config.videoLoadingPlaceholder,
          image: thumbnailUrl == null
              ? null
              : _resizeMediaImage(
                  context,
                  localPreview && Uri.tryParse(thumbnailUrl)?.scheme == 'file'
                      ? FileImage(File.fromUri(Uri.parse(thumbnailUrl)))
                      : CachedNetworkImageProvider(thumbnailUrl),
                  size,
                ),
          size: size,
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
