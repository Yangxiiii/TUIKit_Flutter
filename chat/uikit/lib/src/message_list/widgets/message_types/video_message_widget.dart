import 'package:atomic_x_core/api/message/message_action_store.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/image_viewer/image_viewer.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/image_viewer_manager.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_status_mixin.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';

class VideoMessageWidget extends StatefulWidget {
  final MessageInfo message;
  final String conversationID;
  final bool isSelf;
  final double maxWidth;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final MessageListStore? messageListStore;
  final GlobalKey? bubbleKey;
  final MessageListConfigProtocol config;
  final bool isInMergedDetailView;

  /// See [ImageMessageWidget.mergedMediaMessages].
  final List<MessageInfo>? mergedMediaMessages;

  static const double kVideoFixedHeight = 160.0;

  const VideoMessageWidget({
    super.key,
    required this.message,
    required this.conversationID,
    required this.isSelf,
    required this.maxWidth,
    required this.config,
    this.onTap,
    this.onLongPress,
    this.messageListStore,
    this.bubbleKey,
    this.isInMergedDetailView = false,
    this.mergedMediaMessages,
  });

  @override
  State<VideoMessageWidget> createState() => _VideoMessageWidgetState();
}

class _VideoMessageWidgetState extends State<VideoMessageWidget>
    with MessageStatusMixin {
  ImageViewerManager? _imageViewerManager;

  /// Raw pixel dimensions of the local snapshot file, once decoded.
  /// We trust this over `payload.videoSnapshotWidth/Height` because the
  /// SDK-reported width/height come from the video's metadata (with
  /// rotation transform applied), while the on-disk thumbnail may have
  /// been written in the video's native sensor orientation — leading
  /// to a "thumbnail jumps from landscape to portrait" jolt the moment
  /// the send completes. Reading the thumbnail file itself guarantees
  /// the rendered aspect ratio matches the actual image bytes, so the
  /// sending bubble looks identical to the sent bubble.
  Size? _localSnapshotSize;
  String? _resolvedSnapshotPath;

  // Tracks the msgID we have already asked the store to download the
  // snapshot for during this State's lifetime. The widget's `build`
  // can run many times for the same message (parent list rebuilds,
  // scroll, payload mutation events, status changes, …); without
  // dedup we'd call `MessageActionStore.downloadMedia` on every
  // build, racing the SDK against itself and dramatically widening
  // the partial-write window during which `Image.file` can read a
  // half-flushed snapshot file.
  String? _downloadRequestedForMsgID;

  // Image.file decode failures are cached by Flutter's app-wide
  // ImageCache, keyed by FileImage(path). When a partial-write race
  // poisons the cache for a snapshot path, every subsequent rebuild
  // — even after the file becomes whole on disk — would hit the
  // cached failure forever, leaving the cover blank until app
  // restart. We track which paths we've already retried so we can
  // evict-and-retry exactly once per path: the now-complete file
  // gets a fresh decode, and we avoid an evict ↔ rebuild loop if
  // the file is genuinely corrupt.
  final Set<String> _retriedFailedFilePaths = {};

  // Bumped after we evict a failed cache entry so the Image.file
  // widget below gets a new ValueKey and Flutter re-creates it.
  // Without that, the existing Image widget holds onto its prior
  // failed ImageStream and never re-resolves the (now evicted)
  // cache entry.
  int _imageGeneration = 0;

  @override
  void initState() {
    super.initState();
    _initializeImageViewerManager();
    _loadLocalSnapshotSize();
  }

  @override
  void didUpdateWidget(covariant VideoMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A widget instance can be recycled across messages by Flutter's
    // element reuse (most commonly when the list reorders or the
    // same slot is bound to a different message). Reset the per-
    // message dedup/retry bookkeeping so the new message is treated
    // as fresh.
    if (oldWidget.message.msgID != widget.message.msgID) {
      _downloadRequestedForMsgID = null;
      _retriedFailedFilePaths.clear();
      _imageGeneration = 0;
    }
    // The snapshot path may change as the SDK downloads a remote
    // thumbnail or replaces a sending placeholder; re-decode when it
    // does.
    _loadLocalSnapshotSize();
  }

  void _initializeImageViewerManager() {
    _imageViewerManager = ImageViewerManager(
      conversationID: widget.conversationID,
      currentMessage: widget.message,
      context: context,
      presetMediaMessages: widget.mergedMediaMessages,
    );
  }

  Future<void> _loadLocalSnapshotSize() async {
    final payload = widget.message.messagePayload as VideoMessagePayload?;
    final path = payload?.videoSnapshotPath;
    if (path == null || path.isEmpty) return;
    if (path == _resolvedSnapshotPath) return;
    // Only handle on-disk paths; remote URLs are left to the network
    // image renderer's intrinsic sizing.
    if (path.startsWith('http')) return;

    _resolvedSnapshotPath = path;
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, completer.complete);
      final image = await completer.future;
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      if (mounted) {
        setState(() {
          _localSnapshotSize = size;
        });
      }
    } catch (e) {
      debugPrint('Failed to read snapshot dimensions: $e');
    }
  }

  @override
  void dispose() {
    _imageViewerManager?.dispose();
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
            _buildVideoContent(colorsTheme),
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
    _showImageViewer();
  }

  Widget _buildVideoContent(SemanticColorScheme colorsTheme) {
    final payload = widget.message.messagePayload as VideoMessagePayload?;
    final String? videoSnapshotPath = payload?.videoSnapshotPath;

    // Fire the snapshot download exactly once per (State, msgID): the
    // SDK serializes thumbnail downloads under the hood, so retrying
    // from every rebuild only widens the window during which a half-
    // written file can be read by `Image.file`. We mark the msgID
    // synchronously (before the post-frame callback runs) so that
    // back-to-back rebuilds inside the same frame can't queue
    // duplicate triggers either.
    final needsDownload =
        (videoSnapshotPath == null || videoSnapshotPath.isEmpty) &&
            widget.messageListStore != null &&
            _downloadRequestedForMsgID != widget.message.msgID;
    if (needsDownload) {
      _downloadRequestedForMsgID = widget.message.msgID;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        MessageActionStore.create(widget.message)
            .downloadMedia(quality: MediaQuality.thumbnail);
      });
    }

    double displayHeight = VideoMessageWidget.kVideoFixedHeight;
    double displayWidth = 240;

    // Pick the most authoritative source for the snapshot's aspect ratio:
    //   1) the locally-decoded thumbnail pixels (matches what the user
    //      actually sees rendered, so sending → sent is seamless), then
    //   2) the SDK-reported snapshot dimensions on the payload, then
    //   3) the fixed 240x160 fallback.
    double? snapWidth;
    double? snapHeight;
    if (_localSnapshotSize != null && _localSnapshotSize!.height > 0) {
      snapWidth = _localSnapshotSize!.width;
      snapHeight = _localSnapshotSize!.height;
    } else if (payload != null &&
        payload.videoSnapshotHeight > 0 &&
        payload.videoSnapshotWidth > 0) {
      snapWidth = payload.videoSnapshotWidth.toDouble();
      snapHeight = payload.videoSnapshotHeight.toDouble();
    }

    if (snapWidth != null && snapHeight != null) {
      final double aspectRatio = snapWidth / snapHeight;
      displayWidth = displayHeight * aspectRatio;
      if (displayWidth > widget.maxWidth) {
        displayWidth = widget.maxWidth;
      }
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: _buildImageWithFallback(
              context,
              videoSnapshotPath,
              displayWidth,
              displayHeight,
              Icon(Icons.video_library,
                  color: colorsTheme.textColorSecondary, size: 40),
            ),
          ),
        ),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorsTheme.bgColorDefault,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.play_arrow,
            color: colorsTheme.textColorAntiPrimary,
            size: 24,
          ),
        ),
      ],
    );
  }

  Future<void> _showImageViewer() async {
    if (_imageViewerManager == null) return;

    await _imageViewerManager!.showImageViewerIfAvailable();

    if (_imageViewerManager!.initialImageElements.isNotEmpty && mounted) {
      ImageViewer.view(
        context,
        imageElements: _imageViewerManager!.initialImageElements,
        initialIndex: _imageViewerManager!.initialImageIndex,
        onEventTriggered: _imageViewerManager!.handleImageViewerEvent,
      );
    }
  }

  Widget _buildImageWithFallback(BuildContext context, String? imagePath,
      double width, double height, Widget fallback) {
    final colorsTheme = SemanticColorScheme.of(context);
    final remoteURL = (widget.message.messagePayload as VideoMessagePayload?)
        ?.videoSnapshotURL;

    // No local path yet: render directly from the CDN URL while the
    // Store-side download is in flight. Without this, the cover stays
    // blank for the entire download window — particularly painful for
    // large covers (e.g. iOS-sender 1MB native-resolution snapshots),
    // and dangerous because once a partial-write race poisons the
    // ImageCache for the local path the cover never recovers.
    if (imagePath == null || imagePath.isEmpty) {
      if (remoteURL != null && remoteURL.isNotEmpty) {
        return _buildNetworkImage(
            remoteURL, width, height, fallback, colorsTheme);
      }
      return _buildPlaceholder(width, height, fallback, colorsTheme);
    }

    if (imagePath.startsWith('http')) {
      return _buildNetworkImage(
          imagePath, width, height, fallback, colorsTheme);
    }

    return Image.file(
      File(imagePath),
      // Force a fresh Image element after we evict a poisoned cache
      // entry. Without a changing key, Flutter would reuse the
      // existing Image's already-failed ImageStream and never
      // re-resolve through ImageCache, defeating the evict.
      key: ValueKey('$imagePath#$_imageGeneration'),
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        // Two failure modes here, distinguished by whether we've
        // already retried this exact path on this State:
        //
        //   1) First failure: most likely the partial-write race
        //      described in the issue — Image.file decoded the file
        //      while the SDK was still writing it. Evict the
        //      poisoned cache entry, bump _imageGeneration to force
        //      a fresh Image element, and let the next build try
        //      again. By the time that build runs the SDK download
        //      has typically already completed.
        //
        //   2) Second failure: the file is genuinely bad (truncated,
        //      wrong format, gone). Stop retrying so we don't loop,
        //      and render from the CDN URL if available.
        if (!_retriedFailedFilePaths.contains(imagePath)) {
          _retriedFailedFilePaths.add(imagePath);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            PaintingBinding.instance.imageCache
                .evict(FileImage(File(imagePath)));
            if (mounted) {
              setState(() {
                _imageGeneration += 1;
              });
            }
          });
        }
        if (remoteURL != null && remoteURL.isNotEmpty) {
          return _buildNetworkImage(
              remoteURL, width, height, fallback, colorsTheme);
        }
        return _buildPlaceholder(width, height, fallback, colorsTheme);
      },
    );
  }

  Widget _buildNetworkImage(
    String url,
    double width,
    double height,
    Widget fallback,
    SemanticColorScheme colorsTheme,
  ) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          _buildPlaceholder(width, height, fallback, colorsTheme),
    );
  }

  Widget _buildPlaceholder(
    double width,
    double height,
    Widget fallback,
    SemanticColorScheme colorsTheme,
  ) {
    return Container(
      width: width,
      height: height,
      color: colorsTheme.bgColorTopBar,
      child: Center(child: fallback),
    );
  }
}
