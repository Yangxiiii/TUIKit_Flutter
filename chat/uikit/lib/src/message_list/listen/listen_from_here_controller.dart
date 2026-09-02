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
///
/// 驱动“从这里开始听”的顺序播放队列。
///
/// 单例模式，这样长按菜单（用于开始播放）和聊天页面的播放条（用于显示/停止播放）共享一个信息来源。
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
  ///
  /// 在实际播放之前准备当前项目时为 true（例如文本转语音生成/音频缓冲）。驱动加载动画。
  bool get isLoading => _loading;
  String get currentText => _currentText;

  /// Start playing from [fromMessageId] downward (to the newest message).
  ///
  /// 从 [fromMessageId] 开始向下播放（到最新消息）。
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
    //
    // [消息] 已经按照 AtomicXCore 排序（从最旧到最新）——群聊按顺序排，C2C 按自己的顺序排——所以只需找到点击的消息，从那里播放到结束。
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
    //
    // 只有第一个项目显示加载动画；连续播放的后续项目不会显示。
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
    //
    // 相同发送者的音频项目没有语音前缀 → 直接播放音频。
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
          //
          // 语音消息：在前缀之后播放原始音频。
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
