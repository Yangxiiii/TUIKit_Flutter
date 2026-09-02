import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'audio_player_platform.dart';

/// Audio player listener interface
///
/// 音频播放器监听器接口。
abstract class AudioPlayerListener {
  void onPlay() {}
  void onPause() {}
  void onResume() {}
  void onProgressUpdate(int currentPosition, int duration) {}
  void onCompletion() {}
  void onError(String errorMessage) {}
}

class AudioPlayer {
  String? _currentPath;
  AudioPlayerListener? _listener;
  bool _isPaused = false;
  bool _isPlaying = false;
  int _currentPosition = 0;
  int _duration = 0;

  bool get isPlaying => _isPlaying;
  bool get isPaused => _isPaused;

  /// HarmonyOS detection. `Platform.isOhos` only exists in the Flutter-OH SDK,
  /// so we compare the OS string to stay compilable under standard Flutter.
  ///
  /// HarmonyOS 检测。`Platform.isOhos` 仅存在于 Flutter-OH SDK 中，因此我们通过比较操作系统字符串来保持在标准 Flutter 下可编译。
  static bool get _isOhos => Platform.operatingSystem == 'ohos';

  AudioPlayer._();

  static AudioPlayer createInstance() {
    return AudioPlayer._();
  }

  /// Set listener for audio player events
  ///
  /// 设置音频播放器事件的监听器
  AudioPlayer setListener(AudioPlayerListener? listener) {
    _listener = listener;
    return this;
  }

  Future<void> play(String filePath) async {
    try {
      _isPaused = false;
      if (_currentPath == filePath && _isPlaying) {
        await stop();
        return;
      }

      if (_isPlaying) {
        await stop();
      }

      _currentPath = filePath;

      // Use native implementation on mobile platforms
      //
      // 在移动平台上使用原生实现
      if (Platform.isAndroid || Platform.isIOS || _isOhos) {
        await AudioPlayerPlatform.play(
          filePath: filePath,
          onComplete: () {
            _isPlaying = false;
            _isPaused = false;
            _listener?.onCompletion();
          },
          onProgressUpdate: (currentPosition, duration) {
            _currentPosition = currentPosition;
            _duration = duration;
            _listener?.onProgressUpdate(currentPosition, duration);
          },
          onPlay: () {
            _isPlaying = true;
            _isPaused = false;
            _listener?.onPlay();
          },
          onPause: () {
            _isPlaying = false;
            _isPaused = true;
            _listener?.onPause();
          },
          onResume: () {
            _isPlaying = true;
            _isPaused = false;
            _listener?.onResume();
          },
          onError: (errorMessage) {
            debugPrint('AudioPlayer error: $errorMessage');
            _isPlaying = false;
            _isPaused = false;
            _listener?.onError(errorMessage);
          },
        );
      } else {
        throw UnsupportedError(
            'AudioPlayer only supports Android, iOS and HarmonyOS');
      }
    } catch (e) {
      debugPrint('play failed: $e');
      rethrow;
    }
  }

  Future<void> pause() async {
    if (!_isPlaying) return;
    _isPaused = true;
    _isPlaying = false;
    await AudioPlayerPlatform.pause();
  }

  Future<void> resume() async {
    if (!_isPaused) return;
    _isPaused = false;
    _isPlaying = true;
    await AudioPlayerPlatform.resume();
  }

  Future<void> stop() async {
    await AudioPlayerPlatform.stop();
    _currentPath = null;
    _isPlaying = false;
    _isPaused = false;
    _currentPosition = 0;
    _duration = 0;
  }

  int getCurrentPosition() {
    return _currentPosition;
  }

  int getDuration() {
    return _duration;
  }

  Future<void> dispose() async {
    await AudioPlayerPlatform.dispose();
    _listener = null;
  }
}
