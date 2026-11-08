import 'package:app_ui/app_ui.dart' show AppColorBuildContext, AppIcons;
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'inline_video_player.dart';
import 'video_player.dart';

/// 将本地视频画面、封面和控制条组合为全屏播放器，可为搜索预览预留操作区。
class VideoPlayerWidget extends StatefulWidget {
  final VideoData video;
  final VoidCallback? onClose;

  /// Whether to show the close button (default: true)
  ///
  /// 是否显示关闭按钮（默认：true）
  final bool showCloseButton;

  /// 在搜索预览中将播放进度放在快捷操作栏上方，点击画面关闭预览。
  final bool compactControls;

  const VideoPlayerWidget({
    super.key,
    required this.video,
    this.onClose,
    this.showCloseButton = true,
    this.compactControls = false,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

/// 持有视频控制器，并在页面销毁时释放播放器。
class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late InlineVideoPlayerController _controller;
  bool _showControls = true;
  bool _showThumbnail = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _controller = InlineVideoPlayerController(
      videoPath: widget.video.localPath!,
      width: widget.video.width,
      height: widget.video.height,
    );
    _controller.addListener(_onPlayerUpdate);
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller.removeListener(_onPlayerUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _onPlayerUpdate() {
    if (!mounted) return;

    setState(() {
      // Hide thumbnail when playing, show when paused/completed
      //
      // 播放时隐藏缩略图，暂停/播放完成时显示
      if (_controller.isPlaying) {
        _showThumbnail = false;
      } else if (_controller.position == Duration.zero &&
          !_controller.isPlaying) {
        // Show thumbnail when at start and not playing (completed or initial state)
        //
        // 在开始且未播放时显示缩略图（完成或初始状态）
        _showThumbnail = true;
      }
    });
  }

  void _togglePlayPause() {
    _controller.togglePlayPause();
    if (!widget.compactControls) _showControlsTemporarily();
  }

  void _showControlsTemporarily() {
    setState(() {
      _showControls = true;
    });

    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _onTap() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls && _controller.isPlaying) {
      _hideControlsTimer?.cancel();
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _controller.isPlaying) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _onClose() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).pop();
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compactControls) return _buildCompactPlayer();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Video player - centered with padding for controls
          //
          // 视频播放器 - 居中并为控件留有内边距
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top +
                    50, // Space for close button
                bottom: 80, // Space for progress bar
              ),
              child: InlineVideoPlayer(controller: _controller),
            ),
          ),

          // Thumbnail overlay (shown before playing and after completion)
          //
          // 缩略图覆盖层（播放前和播放完成后显示）
          if (_showThumbnail)
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 50,
                  bottom: 80,
                ),
                child: _buildThumbnail(),
              ),
            ),

          // Controls overlay - handles its own tap events
          //
          // 控件覆盖层 - 自行处理点击事件
          if (_showControls) Positioned.fill(child: _buildControlsOverlay()),

          // Tap area when controls are hidden
          //
          // 控件隐藏时的点击区域
          if (!_showControls)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _onTap,
                child: Container(color: Colors.transparent),
              ),
            ),

          // Close button overlay (conditionally visible)
          //
          // 关闭按钮覆盖层（有条件显示）
          if (widget.showCloseButton)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: GestureDetector(
                onTap: _onClose,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 搜索版复用播放控制器，控制条和右下快捷操作分别命中手势。
  Widget _buildCompactPlayer() => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 封面和播放画面共享显示区，进度条固定在下方。
            Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.sizeOf(context).height * .246),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  InlineVideoPlayer(controller: _controller),
                  if (_showThumbnail) _buildThumbnail(),
                ],
              ),
            ),
            // 关闭手势置于原生画面上层，实播暂停后也不会被 PlatformView 拦截。
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onClose,
              ),
            ),
            // 紧凑控制条与右下角操作栏分别接收触控。
            Positioned(
              left: 16,
              right: 16,
              bottom: 112,
              child: Row(
                children: [
                  Semantics(
                    identifier: 'tim.history.preview.playPause',
                    child: IconButton(
                      onPressed: _togglePlayPause,
                      tooltip: _controller.isPlaying ? '暂停' : '播放',
                      icon: Icon(
                        _controller.isPlaying ? Icons.pause : AppIcons.play,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_formatDuration(_controller.position)} / ${_formatDuration(_controller.duration)}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                        SizedBox(
                            height: 20,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 6,
                                padding: EdgeInsets.zero,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 8),
                              ),
                              child: Semantics(
                                identifier: 'tim.history.preview.progress',
                                child: Slider(
                                  value: _controller.progress.clamp(0.0, 1.0),
                                  onChanged: (value) =>
                                      _controller.seekToProgress(value),
                                  thumbColor: Colors.white,
                                  inactiveColor:
                                      context.appColors.mediaPreviewControl,
                                ),
                              ),
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildThumbnail() {
    // Prefer snapshot file if available
    //
    // 优先使用快照文件（如果可用）
    if (widget.video.hasSnapshotFile) {
      return Image.file(
        File(widget.video.snapshotLocalPath!),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Icon(
          Icons.videocam,
          color: Colors.grey,
          size: 80,
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _onTap,
      child: Container(
        color: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(height: 50),

            // Center play/pause button
            //
            // 播放/暂停按钮居中
            GestureDetector(
              onTap: _togglePlayPause,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _controller.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),

            // Bottom controls
            //
            // 底部控件
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      color: Colors.black.withOpacity(0.5),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Play/Pause button
              //
              // 播放/暂停按钮
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _controller.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Current time
              //
              // 当前时间
              Text(
                _formatDuration(_controller.position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 8),

              // Progress bar
              //
              // 进度条
              Expanded(
                child: _buildProgressBar(),
              ),
              const SizedBox(width: 8),

              // Total time
              //
              // 总时间
              Text(
                _formatDuration(_controller.duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final thumbPosition = (_controller.progress * width).clamp(0.0, width);

        return GestureDetector(
          onTapDown: (details) {
            final progress = (details.localPosition.dx / width).clamp(0.0, 1.0);
            _controller.seekToProgress(progress);
            _showControlsTemporarily();
          },
          onHorizontalDragUpdate: (details) {
            final progress = (details.localPosition.dx / width).clamp(0.0, 1.0);
            _controller.seekToProgress(progress);
          },
          child: Container(
            height: 40,
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Background track
                //
                // 背景轨道
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Progress track
                //
                // 进度轨道
                Container(
                  height: 4,
                  width: thumbPosition,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Thumb
                Positioned(
                  left: (thumbPosition - 6).clamp(0.0, width - 12),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
