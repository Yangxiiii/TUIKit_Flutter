import 'package:flutter/foundation.dart';

import '../../audio_player/audio_player_platform.dart';
import '../ai_media_process_manager.dart';

/// Injectable player start signature. Defaults to [AudioPlayerPlatform.play],
/// which (after the remote-URL change) accepts both local paths and http(s)
/// URLs.
typedef TtsPlayFn = Future<void> Function({
  required String url,
  required VoidCallback onComplete,
  required void Function(String error) onError,
});

/// Injectable player stop signature. Defaults to [AudioPlayerPlatform.stop].
typedef TtsStopFn = Future<void> Function();

/// Turns text into speech via [AiMediaProcessManager.convertTextToVoice] and
/// plays the resulting audio URL. Used by record-translation "read aloud" and
/// the "listen from here" feature.
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
  int _generation = 0;

  /// Convert [text] to speech using [voiceId] and play it.
  ///
  /// [onStart] fires once playback begins; [onComplete] fires when the audio
  /// finishes (or is stopped externally); [onError] fires on conversion or
  /// playback failure.
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
