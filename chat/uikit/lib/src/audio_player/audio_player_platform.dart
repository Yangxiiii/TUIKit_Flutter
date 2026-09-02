import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class AudioPlayerPlatform {
  static const MethodChannel _methodChannel =
      MethodChannel('tencent_chat_uikit/audio_player');
  static const EventChannel _eventChannel =
      EventChannel('tencent_chat_uikit/audio_player_events');

  /// HarmonyOS detection. `Platform.isOhos` only exists in the Flutter-OH SDK,
  /// so we compare the OS string to stay compilable under standard Flutter.
  ///
  /// 检测 HarmonyOS。`Platform.isOhos` 只存在于 Flutter-OH SDK 中，所以我们通过比较操作系统字符串来保证在标准 Flutter 下能编译。
  static bool get _isOhos => Platform.operatingSystem == 'ohos';

  static StreamSubscription? _eventSubscription;
  static Function()? _onComplete;
  static Function(int currentPosition, int duration)? _onProgressUpdate;
  static Function()? _onPlay;
  static Function()? _onPause;
  static Function()? _onResume;
  static Function(String errorMessage)? _onError;

  /// Track the current playing file path to detect switching between different audio files.
  ///
  /// 跟踪当前播放的文件路径，以检测不同音频文件之间的切换。
  static String? _currentPlayingPath;

  /// Store the previous onComplete callback so we can notify the old widget when switching.
  ///
  /// 保存之前的 onComplete 回调，这样在切换时就可以通知旧的 widget。
  static Function()? _previousOnComplete;

  /// Play audio file
  ///
  /// 播放音频文件
  static Future<void> play({
    required String filePath,
    Function()? onComplete,
    Function(int currentPosition, int duration)? onProgressUpdate,
    Function()? onPlay,
    Function()? onPause,
    Function()? onResume,
    Function(String errorMessage)? onError,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS && !_isOhos) {
      throw UnsupportedError(
          'Native AudioPlayer is only supported on Android, iOS and HarmonyOS');
    }

    try {
      // If switching to a different audio file, notify the previous widget via its onComplete callback
      // so it can reset its playing state and progress.
      //
      // 这样它就能重置播放状态和进度。
      if (_currentPlayingPath != null && _currentPlayingPath != filePath) {
        _previousOnComplete?.call();
      }

      // Remember current path and callback for next switch detection
      //
      // 记住当前路径和回调，以便下一次切换检测
      _currentPlayingPath = filePath;
      _previousOnComplete = onComplete;

      // Setup callbacks
      //
      // 设置回调
      _onComplete = onComplete;
      _onProgressUpdate = onProgressUpdate;
      _onPlay = onPlay;
      _onPause = onPause;
      _onResume = onResume;
      _onError = onError;

      // Setup event channel for callbacks
      //
      // 为回调设置事件通道
      await _eventSubscription?.cancel();

      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is Map) {
            final eventType = event['type'] as String?;

            switch (eventType) {
              case 'onComplete':
                // Clear state BEFORE invoking the callback. The callback may
                // synchronously start playing another file (e.g. the
                // "listen from here" queue), and play() inspects
                // _currentPlayingPath / _previousOnComplete; leaving them set
                // would re-fire this callback and recurse infinitely.
                //
                // 在调用回调之前清理状态。回调可能会同步开始播放另一个文件（例如“从这里开始听”的队列），play() 会检查 _currentPlayingPath /
                // _previousOnComplete；如果它们没有被清理，将会重新触发这个回调并无限递归。
                final onComplete = _onComplete;
                _onComplete = null;
                _currentPlayingPath = null;
                _previousOnComplete = null;
                onComplete?.call();
                break;
              case 'onProgressUpdate':
                final currentPosition = event['currentPosition'] as int? ?? 0;
                final duration = event['duration'] as int? ?? 0;
                _onProgressUpdate?.call(currentPosition, duration);
                break;
              case 'onPlay':
                _onPlay?.call();
                break;
              case 'onPause':
                _onPause?.call();
                break;
              case 'onResume':
                _onResume?.call();
                break;
              case 'onError':
                final errorMessage =
                    event['errorMessage'] as String? ?? 'Unknown error';
                _onError?.call(errorMessage);
                break;
            }
          }
        },
        onError: (error) {
          print('AudioPlayerPlatform event error: $error');
          _onError?.call('Event stream error: $error');
        },
      );

      // Call native method to play
      //
      // 调用本地方法播放
      await _methodChannel.invokeMethod('play', {
        'filePath': filePath,
      });
    } catch (e) {
      print('AudioPlayerPlatform.play error: $e');
      rethrow;
    }
  }

  /// Pause playback
  ///
  /// 暂停播放
  static Future<void> pause() async {
    try {
      await _methodChannel.invokeMethod('pause');
    } catch (e) {
      print('AudioPlayerPlatform.pause error: $e');
    }
  }

  /// Resume playback
  ///
  /// 恢复播放
  static Future<void> resume() async {
    try {
      await _methodChannel.invokeMethod('resume');
    } catch (e) {
      print('AudioPlayerPlatform.resume error: $e');
    }
  }

  /// Stop playback
  ///
  /// 停止播放
  static Future<void> stop() async {
    try {
      // Notify the current listener before disposing, so the playing widget
      // (e.g. SoundMessageWidget) can reset its UI state properly.
      //
      // 在释放前通知当前监听器，以便正在播放的Widget（例如 SoundMessageWidget）可以正确重置 UI 状态。
      final onComplete = _onComplete;
      _onComplete = null;
      onComplete?.call();

      await _methodChannel.invokeMethod('stop');
      await dispose();
    } catch (e) {
      print('AudioPlayerPlatform.stop error: $e');
    }
  }

  /// Get current position in milliseconds
  ///
  /// 获取当前播放位置（毫秒）
  static Future<int> getCurrentPosition() async {
    try {
      final position = await _methodChannel.invokeMethod('getCurrentPosition');
      return position as int? ?? 0;
    } catch (e) {
      print('AudioPlayerPlatform.getCurrentPosition error: $e');
      return 0;
    }
  }

  /// Get duration in milliseconds
  ///
  /// 获取时长（毫秒）
  static Future<int> getDuration() async {
    try {
      final duration = await _methodChannel.invokeMethod('getDuration');
      return duration as int? ?? 0;
    } catch (e) {
      print('AudioPlayerPlatform.getDuration error: $e');
      return 0;
    }
  }

  /// Check if playing
  ///
  /// 检查是否正在播放
  static Future<bool> isPlaying() async {
    try {
      final playing = await _methodChannel.invokeMethod('isPlaying');
      return playing as bool? ?? false;
    } catch (e) {
      print('AudioPlayerPlatform.isPlaying error: $e');
      return false;
    }
  }

  /// Check if paused
  ///
  /// 检查是否已暂停
  static Future<bool> isPaused() async {
    try {
      final paused = await _methodChannel.invokeMethod('isPaused');
      return paused as bool? ?? false;
    } catch (e) {
      print('AudioPlayerPlatform.isPaused error: $e');
      return false;
    }
  }

  /// Dispose resources
  ///
  /// 释放资源
  static Future<void> dispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _onComplete = null;
    _onProgressUpdate = null;
    _onPlay = null;
    _onPause = null;
    _onResume = null;
    _onError = null;
    _currentPlayingPath = null;
    _previousOnComplete = null;
  }
}
