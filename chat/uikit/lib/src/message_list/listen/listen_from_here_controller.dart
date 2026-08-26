import 'package:app_ui/app_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:tuikit_atomic_x/atomicx.dart';

import '../../ai/tts/tts_playback_helper.dart';
import '../../ai/tts/voice_message_config.dart';
import '../../audio_player/audio_player_platform.dart';
import 'listen_from_here.dart';

/// Drives the "listen from here" sequential playback queue.
///
/// Singleton so the long-press menu (which starts playback) and the chat-page
/// playback bar (which displays/stops it) share one source of truth.
class ListenFromHereController extends ChangeNotifier {
  ListenFromHereController({TtsPlaybackHelper? tts})
      : _tts = tts ?? TtsPlaybackHelper();

  static final ListenFromHereController instance = ListenFromHereController();

  final TtsPlaybackHelper _tts;

  List<ListenItem> _queue = [];
  int _index = -1;
  bool _active = false;
  bool _loading = false;
  String _currentText = '';
  String _voiceId = '';

  bool get isActive => _active;

  /// True while preparing the current item (e.g. text-to-speech generation /
  /// audio buffering) before playback actually starts. Drives the spinner.
  bool get isLoading => _loading;
  String get currentText => _currentText;

  /// Start playing from [fromMessageId] downward (to the newest message).
  Future<void> start({
    required List<MessageInfo> messages,
    required String fromMessageId,
    required AppLocalizedText l,
  }) async {
    stop();
    await VoiceMessageConfig.instance.load();
    _voiceId = VoiceMessageConfig.instance.selectedVoiceId;

    // [messages] is already ordered (oldest→newest) by AtomicXCore — group
    // chats by sequence, C2C by its own order — so just locate the tapped
    // message and play from there to the end.
    final startIdx = messages.indexWhere((m) => m.msgID == fromMessageId);
    final slice = startIdx >= 0 ? messages.sublist(startIdx) : messages;

    _queue = buildListenPlan(messages: slice, l: l);
    if (_queue.isEmpty) return;

    _active = true;
    _loading = true;
    _index = 0;
    notifyListeners();
    // Only the first item shows the loading spinner; subsequent items in the
    // continuous playback don't.
    _playCurrent(showLoading: true);
  }

  void _playCurrent({bool showLoading = false}) {
    if (!_active || _index < 0 || _index >= _queue.length) {
      stop();
      return;
    }
    final item = _queue[_index];
    _currentText = item.speechText;
    if (showLoading) _loading = true;
    notifyListeners();

    final audioPath = item.audioPath;

    // Same-sender audio items carry no spoken prefix → play the audio directly.
    if (item.speechText.isEmpty && audioPath != null && audioPath.isNotEmpty) {
      _playAudio(audioPath);
      return;
    }

    _tts.speak(
      text: item.speechText,
      voiceId: _voiceId,
      onStart: () {
        if (_active && _loading) {
          _loading = false;
          notifyListeners();
        }
      },
      onComplete: () {
        if (!_active) return;
        if (audioPath != null && audioPath.isNotEmpty) {
          // Voice message: play the original audio right after the prefix.
          _playAudio(audioPath);
        } else {
          _advance();
        }
      },
      onError: (_) {
        if (_active) _advance();
      },
    );
  }

  void _playAudio(String audioPath) {
    AudioPlayerPlatform.play(
      filePath: audioPath,
      onPlay: () {
        if (_active && _loading) {
          _loading = false;
          notifyListeners();
        }
      },
      onComplete: _advance,
      onError: (_) => _advance(),
    );
  }

  void _advance() {
    if (!_active) return;
    _index++;
    if (_index >= _queue.length) {
      stop();
    } else {
      _playCurrent();
    }
  }

  void stop() {
    final wasActive = _active;
    _active = false;
    _loading = false;
    _index = -1;
    _queue = [];
    _currentText = '';
    _tts.stop();
    AudioPlayerPlatform.stop();
    if (wasActive) notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
