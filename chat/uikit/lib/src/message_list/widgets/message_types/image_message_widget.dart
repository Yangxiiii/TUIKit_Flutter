import 'package:atomic_x_core/api/message/message_action_store.dart';
import '../../message_history_config.dart';
import 'dart:io';

import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/image_viewer/image_element.dart';
import 'package:tencent_chat_uikit/src/image_viewer/image_viewer.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/image_viewer_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_status_mixin.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import '../chat_media_placeholder.dart';

/// 展示普通图片消息，优先使用本地资源，加载时使用宿主占位图，点击进入共用预览器。
class ImageMessageWidget extends StatefulWidget {
  final MessageInfo message;
  final String conversationID;
  final bool isSelf;
  final double maxWidth;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final MessageListStore? messageListStore;

  /// 离线时只展示及预览本机文件。
  final bool localOnly;
  final GlobalKey? bubbleKey;
  final MessageListConfigProtocol config;
  final bool isInMergedDetailView;

  /// When this widget is rendered inside a merged-message detail page,
  /// the conversation-backed [messageListStore] is empty and the image
  /// viewer cannot page over the live history. Pass the merged bundle's
  /// own message list here so the viewer can render images / videos
  /// from the bundle directly.
  ///
  /// 合并转发、归档及离线窗口传入有序媒体快照，避免对当前来源发起实时历史分页。
  final List<MessageInfo>? mergedMediaMessages;

  /// 在线会话到达 SDK 历史边缘后，沿用宿主的归档查询。
  final ChatOlderMessagesLoader? loadOlderMedia;

  static const double kImageFixedHeight = 160.0;

  const ImageMessageWidget({
    super.key,
    required this.message,
    required this.conversationID,
    required this.isSelf,
    required this.maxWidth,
    required this.config,
    this.onTap,
    this.onLongPress,
    this.messageListStore,
    this.localOnly = false,
    this.bubbleKey,
    this.isInMergedDetailView = false,
    this.mergedMediaMessages,
    this.loadOlderMedia,
  });

  @override
  State<ImageMessageWidget> createState() => _ImageMessageWidgetState();
}

/// 管理图片消息预览入口，加载占位沿用气泡的固定尺寸。
class _ImageMessageWidgetState extends State<ImageMessageWidget>
    with MessageStatusMixin {
  /// 从点击开始到预览关闭只保留一个管理器，避免并发拉取同一会话媒体。
  ImageViewerManager? _imageViewerManager;

  @override
  void dispose() {
    _imageViewerManager?.dispose();
    _imageViewerManager = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorsTheme = SemanticColorScheme.of(context);

    final statusAndTimeWidgets = buildStatusAndTimeWidgets(
      message: widget.message,
      isSelf: widget.isSelf,
      colors: colorsTheme,
      isOverlay: true,
      isShowTimeInBubble: widget.config.isShowTimeInBubble,
      enableReadReceipt: widget.config.enableReadReceipt,
      isInMergedDetailView: widget.isInMergedDetailView,
    );

    return GestureDetector(
      behavior: widget.localOnly ? HitTestBehavior.opaque : null,
      onTap: _handleTap,
      onLongPress: widget.onLongPress,
      child: Container(
        key: widget.bubbleKey,
        constraints: BoxConstraints(
          maxWidth: widget.maxWidth,
        ),
        margin: EdgeInsets.zero,
        child: Stack(
          children: [
            _buildImageContent(colorsTheme),
            if (statusAndTimeWidgets.isNotEmpty)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorsTheme.bgColorDefault,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: statusAndTimeWidgets,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _handleTap() {
    widget.onTap?.call();
    if (widget.localOnly) {
      ImageViewer.viewLocalMessage(context, widget.message,
          mediaMessages: widget.mergedMediaMessages);
      return;
    }
    _showImageViewer();
  }

  Widget _buildImageContent(SemanticColorScheme colorsTheme) {
    final imagePayload = widget.message.messagePayload as ImageMessagePayload?;
    String? originalImagePath = imagePayload?.originalImagePath;
    String? largeImagePath = imagePayload?.largeImagePath;
    String? thumbImagePath = imagePayload?.thumbImagePath;

    // Remote URL fallbacks. In the merged-forward detail view the bundle is
    // re-downloaded on every open and the local thumb files are transient /
    // may be gone the second time, so we must be able to render straight from
    // the server URL instead of getting stuck on the loading spinner
    // (bug#161210776). Local path always wins when present.
    //
    // 远程 URL 回退。在合并转发的详情视图中，每次打开都会重新下载 bundle，本地缩略图文件是临时的／第二次可能已经不存在，所以我们必须能够直接从服务器 URL
    // 渲染，而不是卡在加载动画上（bug#161210776）。本地路径存在时总是优先。
    final thumbImageURL = widget.localOnly ? null : imagePayload?.thumbImageURL;
    final largeImageURL = widget.localOnly ? null : imagePayload?.largeImageURL;
    final originalImageURL =
        widget.localOnly ? null : imagePayload?.originalImageURL;

    final bool hasLocalPath =
        (originalImagePath != null && originalImagePath.isNotEmpty) ||
            (largeImagePath != null && largeImagePath.isNotEmpty) ||
            (thumbImagePath != null && thumbImagePath.isNotEmpty);
    final bool hasRemoteURL =
        (thumbImageURL != null && thumbImageURL.isNotEmpty) ||
            (largeImageURL != null && largeImageURL.isNotEmpty) ||
            (originalImageURL != null && originalImageURL.isNotEmpty);

    if (!hasLocalPath && !hasRemoteURL) {
      if (widget.messageListStore != null &&
          widget.message.rawMessage != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          MessageActionStore.create(widget.message)
              .downloadMedia(quality: MediaQuality.thumbnail);
        });

        return Container(
          width: 200,
          height: ImageMessageWidget.kImageFixedHeight,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: colorsTheme.bgColorTopBar,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ChatMediaPlaceholder(
              image: widget.config.imageLoadingPlaceholder, showLoading: true),
        );
      }
    }

    final double aspectRatio =
        (widget.message.messagePayload as ImageMessagePayload?)
                        ?.originalImageWidth !=
                    null &&
                (widget.message.messagePayload as ImageMessagePayload?)
                        ?.originalImageHeight !=
                    null &&
                (widget.message.messagePayload as ImageMessagePayload)
                        .originalImageHeight >
                    0
            ? (widget.message.messagePayload as ImageMessagePayload)
                    .originalImageWidth /
                (widget.message.messagePayload as ImageMessagePayload)
                    .originalImageHeight
            : 1.0;

    double displayHeight = ImageMessageWidget.kImageFixedHeight;
    double displayWidth = displayHeight * aspectRatio;

    if (displayWidth > widget.maxWidth) {
      displayWidth = widget.maxWidth;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: displayWidth,
        height: displayHeight,
        child: (() {
          // Prefer any available local file, then fall back to a remote URL.
          //
          // 优先使用任何可用的本地文件，然后才回退到远程 URL。
          String? displayPath;
          if (originalImagePath != null && originalImagePath.isNotEmpty) {
            displayPath = originalImagePath;
          } else if (largeImagePath != null && largeImagePath.isNotEmpty) {
            displayPath = largeImagePath;
          } else if (thumbImagePath != null && thumbImagePath.isNotEmpty) {
            displayPath = thumbImagePath;
          } else if (thumbImageURL != null && thumbImageURL.isNotEmpty) {
            displayPath = thumbImageURL;
          } else if (largeImageURL != null && largeImageURL.isNotEmpty) {
            displayPath = largeImageURL;
          } else if (originalImageURL != null && originalImageURL.isNotEmpty) {
            displayPath = originalImageURL;
          }

          if (displayPath != null) {
            if (displayPath.startsWith('http')) {
              return Image.network(
                displayPath,
                width: displayWidth,
                height: displayHeight,
                fit: BoxFit.cover,
                frameBuilder: _buildLoadingFrame,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: colorsTheme.bgColorTopBar,
                    child: Center(
                      child: Icon(Icons.broken_image,
                          color: colorsTheme.textColorSecondary),
                    ),
                  );
                },
              );
            } else {
              return Image.file(
                File(displayPath),
                width: displayWidth,
                height: displayHeight,
                fit: BoxFit.cover,
                frameBuilder: _buildLoadingFrame,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: colorsTheme.bgColorTopBar,
                    child: Center(
                      child: Icon(Icons.broken_image,
                          color: colorsTheme.textColorSecondary),
                    ),
                  );
                },
              );
            }
          } else {
            return Container(
              color: colorsTheme.bgColorTopBar,
              child: Center(
                child: Icon(Icons.broken_image,
                    color: colorsTheme.textColorSecondary),
              ),
            );
          }
        })(),
      ),
    );
  }

  /// 以首帧是否完成判断加载，覆盖网络尚未返回字节及本地文件解码阶段。
  Widget _buildLoadingFrame(
          BuildContext context, Widget child, int? frame, bool synchronous) =>
      synchronous || frame != null
          ? child
          : ChatMediaPlaceholder(
              image: widget.config.imageLoadingPlaceholder, showLoading: true);

  /// 先打开预览，再补全点中的图片与相邻媒体，关闭后释放本次查看器。
  Future<void> _showImageViewer() async {
    if (_imageViewerManager != null) return;
    final preset = widget.mergedMediaMessages ??
        (widget.message.rawMessage == null ? [widget.message] : null);
    final manager = ImageViewerManager(
      conversationID: widget.conversationID,
      currentMessage: widget.message,
      context: context,
      presetMediaMessages: preset,
      hiddenMessageIDs: widget.config.hiddenMessageIDs,
      downloadRichVideo: widget.config.fileDownloader,
      loadOlderMedia: widget.loadOlderMedia,
    );
    _imageViewerManager = manager;
    try {
      await ImageViewer.view(
        context,
        imageElements: [
          ImageElement(type: 0, imagePath: '', mediaId: widget.message.msgID),
        ],
        initialIndex: 0,
        imageUpdates: manager.loadImageWindow(),
        loadMoreOnOverscroll: manager.canPageAtEdge,
        onEventTriggered: manager.handleImageViewerEvent,
      );
    } finally {
      if (_imageViewerManager == manager) {
        manager.dispose();
        _imageViewerManager = null;
      }
    }
  }
}
