import 'package:flutter/foundation.dart';

import '../../audio_player/audio_player_platform.dart';
import '../ai_media_process_manager.dart';

/// Injectable player start signature. Defaults to [AudioPlayerPlatform.play],
/// which (after the remote-URL change) accepts both local paths and http(s)
/// URLs.
///
/// 可注入播放器启动签名。默认是 [AudioPlayerPlatform.play]，它（在远程 URL 改变后）可接受本地路径和 http(s) 链接
typedef TtsPlayFn = Future<void> Function({
  required String url,
  required VoidCallback onComplete,
  required void Function(String error) onError,
});

/// Injectable player stop signature. Defaults to [AudioPlayerPlatform.stop].
///
/// 可注入播放器停止签名。默认是 [AudioPlayerPlatform.stop]。
typedef TtsStopFn = Future<void> Function();

/// Turns text into speech via [AiMediaProcessManager.convertTextToVoice] and
/// plays the resulting audio URL. Used by record-translation "read aloud" and
/// the "listen from here" feature.
///
/// 通过 [AiMediaProcessManager.convertTextToVoice] 将文本转换为语音，并播放生成的音频 URL。用于记录翻译的“朗读”和“从这里听”功能。
class TtsPlaybackHelper {
  TtsPlaybackHelper({
    AiMediaProcessManager? service,
    TtsPlayFn? play,
    TtsStopFn? stop,
  })  : _service = service ?? AiMediaProcessManager.shared,
        _play = play ?? _defaultPlay,
        _stop = stop ?? _defaultStop;

  final AiMediaProcessManager _service;
  final TtsPlayFn _play;
  final TtsStopFn _stop;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  /// Bumped on every [speak] and [stop]. An in-flight [speak] whose token no
  /// longer matches (because the user stopped, or a newer speak started during
  /// the async text-to-speech request) must NOT start playback.
  ///
  /// 在每次 [speak] 和 [stop] 时都会触发。如果正在进行的 [speak] 令牌不再匹配（因为用户停止了，或者在异步文本转语音请求期间启动了新的 speak），则绝不能开始播放。
  int _generation = 0;

  /// Convert [text] to speech using [voiceId] and play it.
  ///
  /// [onStart] fires once playback begins; [onComplete] fires when the audio
  /// finishes (or is stopped externally); [onError] fires on conversion or
  /// playback failure.
  ///
  /// 使用 [voiceId] 将 [text] 转换为语音并播放。
  ///
  /// [onStart] 在播放开始时触发；[onComplete] 在音频播放完成（或被外部停止）时触发；[onError] 在转换或播放失败时触发。
  Future<void> speak({
    required String text,
    String voiceId = '',
    String language = '',
    VoidCallback? onStart,
    VoidCallback? onComplete,
    void Function(String error)? onError,
  }) async {
    final myGeneration = ++_generation;
    final result = await _service.convertTextToVoice(
      text: text,
      voiceId: voiceId,
      language: language,
    );
    // Aborted while the (async) TTS request was in flight — don't start
    // playing (e.g. user tapped "X" / stop during the loading window).
    //
    // 在（异步）TTS 请求进行中被中止——不要开始播放（例如用户点击了“X”或在加载期间点击停止）。
    if (myGeneration != _generation) return;
    if (!result.success ||
        result.audioUrl == null ||
        result.audioUrl!.isEmpty) {
      _isPlaying = false;
      onError?.call(result.message ?? 'tts failed');
      return;
    }

    _isPlaying = true;
    onStart?.call();
    await _play(
      url: result.audioUrl!,
      onComplete: () {
        _isPlaying = false;
        onComplete?.call();
      },
      onError: (e) {
        _isPlaying = false;
        onError?.call(e);
      },
    );
  }

  Future<void> stop() async {
    // Invalidate any in-flight speak so it won't start playing after stop.
    //
    // 使任何正在进行的 speak 失效，以免在停止后开始播放。
    _generation++;
    _isPlaying = false;
    await _stop();
  }
}

Future<void> _defaultPlay({
  required String url,
  required VoidCallback onComplete,
  required void Function(String error) onError,
}) {
  return AudioPlayerPlatform.play(
    filePath: url,
    onComplete: onComplete,
    onError: onError,
  );
}

Future<void> _defaultStop() => AudioPlayerPlatform.stop();
