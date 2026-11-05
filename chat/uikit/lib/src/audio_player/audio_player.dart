import 'dart:async';
import 'package:app_core/app_core.dart';
import 'audio_player_platform.dart';

/// 接收原生播放状态，暂停和结束分别通知，切换消息不能伪装为播放完成。
abstract class AudioPlayerListener {
  void onPlay() {}
  void onPause() {}
  void onResume() {}
  void onProgressUpdate(int currentPosition, int duration) {}
  void onCompletion() {}
  void onError(String errorMessage) {}
}

/// 协调共享原生播放器的唯一所有者，各消息保留暂停位置，非当前实例不能释放其他语音。
class AudioPlayer {
  AudioPlayer._();

  /// 当前占用原生播放器的实例，切换前必须暂停旧实例。
  static AudioPlayer? _active;
  static final _guard = ActionGuard();

  /// 不同消息的命令串行交给唯一硬件，失败后队列仍可继续。
  static Future<void> _operations = Future<void>.value();
  String? _currentPath;
  AudioPlayerListener? _listener;
  bool _isPaused = false;
  bool _isPlaying = false;

  /// 当前实例的暂停毫秒位置，切换其他消息时保留，播放结束时清零。
  int _currentPosition = 0;

  /// 最近一次原生事件提供的总毫秒数，停止时清零。
  int _duration = 0;
  bool _disposed = false;

  /// 是否收到原生开始播放状态，发起请求本身不代表已经播放。
  bool get isPlaying => _isPlaying;

  /// 当前消息是否保留可恢复的暂停位置。
  bool get isPaused => _isPaused;

  /// 为消息创建局部播放状态，硬件所有权仍由本类统一协调。
  static AudioPlayer createInstance() => AudioPlayer._();

  /// 更换界面监听，不重建或停止原生播放器。
  AudioPlayer setListener(AudioPlayerListener? listener) {
    _listener = listener;
    return this;
  }

  static Future<void> _enqueue(Future<void> Function() action) {
    final next = _operations.then((_) => action());
    // 调用方仍收到异常，队列吸收失败以免阻断下一条消息。
    _operations = next.catchError((Object _) {});
    return next;
  }

  /// 同一消息切换暂停/续播，切换源时从各消息保存的毫秒位置装载。
  Future<void> play(String path) => _guard.singleFlight<void>(
        ('chat.audio.play', this),
        () => _enqueue(() => _play(path)),
      );

  /// 在硬件交接完成后绑定新监听；暂停进度不能被旧消息的结束回调抹掉。
  Future<void> _play(String path) async {
    if (_disposed) return;
    if (identical(_active, this) && _currentPath == path) {
      if (_isPlaying) {
        await _pause();
      } else if (_isPaused) {
        await AudioPlayerPlatform.resume();
      }
      return;
    }
    if (_active case final AudioPlayer previous) {
      await previous._pause();
    }
    if (_currentPath != path) _currentPosition = 0;
    _currentPath = path;
    _active = this;
    try {
      await AudioPlayerPlatform.play(
        filePath: path,
        startPositionMs: _currentPosition,
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
        onProgressUpdate: (position, duration) {
          _currentPosition = position;
          _duration = duration;
          _listener?.onProgressUpdate(position, duration);
        },
        onComplete: () {
          _isPlaying = false;
          _isPaused = false;
          _currentPosition = 0;
          if (identical(_active, this)) _active = null;
          _listener?.onCompletion();
        },
        onError: (error) {
          _isPlaying = false;
          _isPaused = false;
          if (identical(_active, this)) _active = null;
          _listener?.onError(error);
        },
      );
    } catch (_) {
      if (identical(_active, this)) _active = null;
      _isPlaying = false;
      rethrow;
    }
  }

  /// 暂停前保存原生位置，不以界面最后一次进度估算恢复点。
  Future<void> _pause() async {
    if (!identical(_active, this)) return;
    _currentPosition = await AudioPlayerPlatform.getCurrentPosition();
    await AudioPlayerPlatform.pause();
    _isPlaying = false;
    _isPaused = true;
    _listener?.onPause();
  }

  /// 只暂停本实例当前拥有的原生播放器。
  Future<void> pause() => _enqueue(_pause);

  /// 原源仍在硬件中时恢复，否则重新装载并定位到本消息的暂停位置。
  Future<void> resume() => _enqueue(() async {
        if (_isPaused && _currentPath != null) await _play(_currentPath!);
      });

  /// 只停止本实例拥有的硬件，非当前实例仅清除自己的状态。
  Future<void> stop() => _enqueue(() async {
        if (identical(_active, this)) {
          await AudioPlayerPlatform.stop();
          _active = null;
        }
        _currentPath = null;
        _currentPosition = 0;
        _duration = 0;
        _isPlaying = false;
        _isPaused = false;
      });

  /// 录音或会话退出前串行停止共享播放，等待中的旧命令不能晚于录音启动。
  static Future<void> stopAll() => _enqueue(() async {
        await AudioPlayerPlatform.stop();
        _active = null;
      });

  /// 当前消息最后一次原生位置，单位为毫秒。
  int getCurrentPosition() => _currentPosition;

  /// 当前消息原生总时长，单位为毫秒。
  int getDuration() => _duration;

  /// 使本实例排队请求失效，非当前气泡销毁不注销其他消息的事件通道。
  Future<void> dispose() async {
    _disposed = true;
    await stop();
    _listener = null;
  }
}
