import 'package:app_ui/app_ui.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tencent_chat_uikit/src/audio_recoder/audio_recorder.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/ai/ai_media_process_manager.dart';
import 'package:tencent_chat_uikit/src/ai/tts/tts_playback_helper.dart';
import 'package:tencent_chat_uikit/src/ai/tts/tts_text_sanitizer.dart';
import 'package:tencent_chat_uikit/src/ai/tts/voice_message_config.dart';

/// State machine of [AudioRecordOverlay].
///
/// - [recording]: default state on overlay show. Waveform + cancel (and optional
///   convert) buttons + release-to-* hint.
/// - [converting]: voice-to-text in progress. Three-dot animation in a blue
///   bubble. Bottom buttons stay visible but ignore taps.
/// - [editing]: conversion succeeded. Editable TextField with converted text +
///   three buttons (cancel / send original / send text).
/// - [error]: conversion failed (or returned empty / timed out). Red bubble
///   with localized error text. Any tap on the overlay closes it.
///
/// [AudioRecordOverlay] 的状态机。
///
/// - [recording]：覆盖层显示时的默认状态。显示波形 + 取消按钮（可选转换按钮）+ 释放执行提示。-
/// [converting]：语音转文字中。蓝色气泡中的三个点动画。底部按钮保持可见，但点击无效。- [editing]：转换成功。可编辑的文本框显示转换后的文字 + 三个按钮（取消 / 发送原始语音 /
/// 发送文字）。- [error]：转换失败（或返回空 / 超时）。红色气泡显示本地化错误信息。点按覆盖层的任何位置都会关闭它。
enum _OverlayState { recording, converting, editing, error }

/// Audio recording overlay widget that follows WeChat-style recording UI.
///
/// Design states (from Figma):
/// 1. Recording: gradient overlay + waveform + releaseToSend hint + centered
///    cancel button (and optional convert button when [enableVoiceToText] is
///    true).
/// 2. Cancel hover: cancel button highlights (red), hint becomes
///    releaseToCancel, waveform turns red.
/// 3. Convert hover: convert button highlights (blue), hint becomes
///    releaseToConvert.
/// 4. Countdown: last 10s shows recordCountdownTips hint.
/// 5. Converting / Editing / Error: see [_OverlayState].
///
/// 音频录音覆盖控件，跟随微信风格的录音 UI。
///
/// 设计状态（来自 Figma）：1. 录音：渐变覆盖 + 波形 + 释放发送提示 + 居中取消按钮（以及可选的转换按钮，当 [enableVoiceToText] 启用时）。
///
/// 2. 取消悬停：取消按钮高亮（红色），提示变为释放取消，波形变红。3. 转换悬停：转换按钮高亮（蓝色），提示变为...
///
/// 4. 倒计时：最后 10 秒显示 recordCountdownTips 提示。5. 转换 / 编辑 / 错误：见 [_OverlayState]。
class AudioRecordOverlay extends StatefulWidget {
  /// Fired when recording finishes successfully and the original audio is to
  /// be sent (default release-to-send, OR user pressed "send original voice"
  /// in editing state).
  ///
  /// 当录音成功完成并且原始音频要发送时触发（默认释放发送，或用户在编辑状态下按了“发送原始语音”）。
  final ValueChanged<RecordInfo> onRecordFinish;

  /// Fired when the recording is cancelled (user dragged to cancel button,
  /// pressed cancel in editing state, or tapped the error bubble).
  ///
  /// 当录音被取消时触发（用户拖到取消按钮，在编辑状态下按取消，或点击错误气泡）。
  final VoidCallback onRecordCancelled;

  /// Fired when the user accepts the converted text (and optionally edits it)
  /// and presses "send" in editing state. Required when [enableVoiceToText]
  /// is true and the user reaches the editing state.
  ///
  /// 当用户在编辑状态下接受转换后的文本（并可选择编辑）后按下“发送”时触发。当[enableVoiceToText]为真且用户进入编辑状态时必需。
  final ValueChanged<String>? onSendText;

  /// When true, recording state shows an additional convert-to-text button
  /// next to cancel; releasing on it triggers voice-to-text conversion.
  ///
  /// 为真时，录音状态会在取消按钮旁显示一个额外的转换为文本按钮；松手时会触发语音转文本。
  final bool enableVoiceToText;

  /// Manager that performs upload + voice-to-text conversion. Defaults to a
  /// real [AiMediaProcessManager] backed by SDK experimental APIs; tests can
  /// inject a fake.
  ///
  /// 管理器，用于执行上传 + 语音转文本转换。默认使用由 SDK 实验 API 支持的真实[AiMediaProcessManager]；测试时可以注入假的。
  final AiMediaProcessManager? mediaProcessManager;

  /// Optional: provide these when the overlay lives inside an [OverlayEntry],
  /// where the normal InheritedWidget lookup would fail.
  ///
  /// 可选：当覆盖层位于［OverlayEntry］内时提供这些，因为普通的 InheritedWidget 查找会失败。
  final SemanticColorScheme? colorScheme;
  final AppLocalizedText? atomicLocalizations;

  const AudioRecordOverlay({
    super.key,
    required this.onRecordFinish,
    required this.onRecordCancelled,
    this.onSendText,
    this.enableVoiceToText = false,
    this.mediaProcessManager,
    this.colorScheme,
    this.atomicLocalizations,
  });

  @override
  State<AudioRecordOverlay> createState() => AudioRecordOverlayState();
}

class AudioRecordOverlayState extends State<AudioRecordOverlay>
    with TickerProviderStateMixin {
  late AudioRecorder _audioRecorder;
  late AnimationController _waveAnimationController;
  late AnimationController _dotsAnimationController;
  late AiMediaProcessManager _mediaProcessManager;

  _OverlayState _state = _OverlayState.recording;
  bool _isRecording = false;
  bool _isFingerOverCancel = false;
  bool _isFingerOverConvert = false;
  int _recordingDurationMs = 0;

  /// File path of the recorded audio file. Captured when [stopRecordAndConvert]
  /// finishes the recording so we can later "send original voice" from the
  /// editing state without re-recording.
  ///
  /// 录音音频文件的文件路径。在[stopRecordAndConvert]完成录音时捕获，这样我们以后可以在编辑状态下“不重新录音”发送原始语音。
  String? _capturedRecordPath;
  int _capturedRecordDurationSec = 0;

  /// Editing-state text controller. Created lazily when entering editing.
  ///
  /// 编辑状态文本控制器。进入编辑时会懒加载创建。
  TextEditingController? _editingController;

  /// Editing-state focus node. Initially does NOT request focus (so the
  /// keyboard stays hidden in the preview sub-state). When the user taps
  /// the text bubble, focus is requested and the bubble switches to its
  /// "active editing" appearance (blue bg + white text + waveform hidden).
  ///
  /// 编辑状态焦点节点。初始时不会请求焦点（所以在预览子状态下键盘保持隐藏）。当用户点击文本气泡时，会请求焦点，气泡切换到“活跃编辑”状态（蓝色背景 + 白色文字 + 隐藏波形）。
  FocusNode? _editingFocusNode;

  /// First ASR transcription text — the immutable source for translation.
  /// Switching languages always translates from this, never from a prior
  /// translation, to avoid cumulative information loss.
  ///
  /// 第一次 ASR 转录文本——翻译的不可变来源。切换语言总是以此为基础翻译，从不使用之前的翻译，以避免信息累积损失。
  String _asrOriginalText = '';

  /// Current translated text; null when not translated (or translation undone).
  ///
  /// 当前翻译文本；未翻译（或撤销翻译）时为 null。
  String? _translatedText;

  /// True while a translate request is in flight.
  ///
  /// 如果翻译请求正在进行中，则为 true。
  bool _isTranslating = false;

  /// True while the editing-state "read aloud" TTS playback is active.
  ///
  /// 如果编辑状态下“朗读” TTS 播放处于激活状态，则为 true。
  bool _isPlayingTts = false;

  /// Lazily-created TTS helper, reusing [_mediaProcessManager].
  ///
  /// 懒加载创建的 TTS 辅助工具，复用 [_mediaProcessManager]。
  TtsPlaybackHelper? _ttsHelper;

  /// Translate target languages offered in the record-translation selector.
  /// Codes must match the IMSDK text-translation backend contract. Notably
  /// Traditional Chinese is `zh-TR`, NOT the more common BCP-47 `zh-TW` —
  /// the latter is rejected by the backend.
  ///
  /// 翻译记录选择器中提供的目标语言。代码必须与IMSDK文本翻译后台的契约匹配。特别注意，繁体中文是`zh-TR`，而不是更常见的BCP-47 `zh-TW` —— 后者会被后台拒绝。
  static const List<Map<String, String>> _translateLanguageOptions = [
    {"code": "zh", "name": "简体中文"},
    {"code": "zh-TR", "name": "繁體中文"},
    {"code": "en", "name": "English"},
    {"code": "ja", "name": "日本語"},
    {"code": "ko", "name": "한국어"},
    {"code": "fr", "name": "Français"},
    {"code": "es", "name": "Español"},
    {"code": "it", "name": "Italiano"},
    {"code": "de", "name": "Deutsch"},
    {"code": "tr", "name": "Türkçe"},
    {"code": "ru", "name": "Русский"},
    {"code": "pt", "name": "Português"},
    {"code": "vi", "name": "Tiếng Việt"},
    {"code": "id", "name": "Bahasa Indonesia"},
    {"code": "th", "name": "ภาษาไทย"},
    {"code": "ms", "name": "Bahasa Melayu"},
  ];

  /// Max recording duration in seconds
  ///
  /// 最大录音时长（秒）
  static const int _maxDurationSec = 60;

  /// Countdown threshold in seconds (show countdown in last N seconds)
  ///
  /// 倒计时阈值（秒）（在最后N秒显示倒计时）
  static const int _countdownThresholdSec = 10;

  /// Horizontal padding for the converting / editing / error panel content.
  /// Larger than the recording-state padding to give the bubble + buttons
  /// some breathing room near the screen edges.
  ///
  /// 转换/编辑/错误面板内容的水平内边距。比录音状态的内边距大，为气泡+按钮在屏幕边缘留出一些空间。
  static const double _kPanelHPadding = 40.0;

  /// Vertical gap between the bubble (text/dots/error) and the three-button
  /// row in the converting / editing / error states.
  ///
  /// 转换/编辑/错误状态下，气泡（文本/点/错误）与三按钮行之间的垂直间隙。
  static const double _kBubbleToButtonsGap = 40.0;

  /// Distance from the right edge of the panel content (i.e., from the
  /// right edge of the bubble — they align by virtue of using the same
  /// horizontal padding) to the horizontal CENTER of the "send" button.
  /// Used to position the bubble's downward arrow so it points at the
  /// send button's circle. Send circle is 70 wide → its center sits at
  /// 35px from the row's right edge.
  ///
  /// 从面板内容的右边缘（即气泡的右边缘——由于使用相同的水平内边距，所以它们对齐）到“发送”按钮水平中心的距离。用于定位气泡向下的箭头，使其指向发送按钮的圆。发送按钮圆宽度为70 →
  /// 其中心位于行的右边缘35px处。
  static const double _kSendButtonCenterFromRight = 35.0;

  final GlobalKey _cancelButtonKey = GlobalKey();
  final GlobalKey _convertButtonKey = GlobalKey();

  // Random wave heights for animation
  //
  // 动画用的随机波高
  final List<double> _waveHeights = List.generate(20, (_) => 0.5);
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _waveAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    )..addListener(_updateWaveHeights);

    // Three-dot pulse: 1.2s loop is comfortable.
    //
    // 三点脉冲：1.2秒循环比较舒适。
    _dotsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _audioRecorder = AudioRecorder();
    _audioRecorder.initialize(
      onProgressUpdate: _onProgressUpdate,
      onStateChanged: _onStateChanged,
    );

    _mediaProcessManager =
        widget.mediaProcessManager ?? AiMediaProcessManager();
  }

  @override
  void dispose() {
    _waveAnimationController.removeListener(_updateWaveHeights);
    _waveAnimationController.dispose();
    _dotsAnimationController.dispose();
    _audioRecorder.cancelRecord();
    _audioRecorder.dispose();
    _ttsHelper?.stop();
    _editingController?.dispose();
    _editingFocusNode?.dispose();
    super.dispose();
  }

  void _updateWaveHeights() {
    if (!_isRecording || !mounted) return;
    setState(() {
      for (int i = 0; i < _waveHeights.length; i++) {
        // Smoothly interpolate toward new random target
        //
        // 平滑地插值到新的随机目标
        final target = 0.2 + _random.nextDouble() * 0.8;
        _waveHeights[i] = _waveHeights[i] + (target - _waveHeights[i]) * 0.3;
      }
    });
  }

  void _onProgressUpdate(int durationMs, double progress) {
    if (mounted) {
      setState(() {
        _recordingDurationMs = durationMs;
      });
    }
  }

  void _onStateChanged(bool isRecording) {
    if (mounted) {
      setState(() {
        _isRecording = isRecording;
      });

      if (isRecording) {
        _waveAnimationController.repeat();
      } else {
        _waveAnimationController.stop();
        _waveAnimationController.reset();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Public API consumed by the parent MessageInput
  // ---------------------------------------------------------------------------
  //
  // 父级 MessageInput 使用的公共 API

  Future<void> startRecord({required String filePath}) async {
    await _audioRecorder.startRecord(
      filePath: filePath,
      onComplete: (recordInfo) {
        if (recordInfo != null) {
          if (recordInfo.errorCode ==
                  AudioRecordResultCode.errorLessThanMinDuration &&
              mounted) {
            final atomicLocalizations =
                widget.atomicLocalizations ?? AppLocalization.of(context);
            Toast.warning(context, atomicLocalizations.sayTimeShort);
          }
          if (recordInfo.errorCode ==
                  AudioRecordResultCode.successExceedMaxDuration &&
              mounted) {
            final atomicLocalizations =
                widget.atomicLocalizations ?? AppLocalization.of(context);
            Toast.warning(context, atomicLocalizations.recordLimitTips);
          }
          widget.onRecordFinish(recordInfo);
        }
      },
    );
  }

  /// Stop recording and send the audio as a voice message (legacy
  /// release-to-send path).
  ///
  /// 停止录音并将音频作为语音消息发送（旧版释放发送路径）。
  void stopRecord() {
    _audioRecorder.stopRecord();
  }

  /// Production entry point: parent intercepts the record-finish callback
  /// and calls this with the captured file path + duration to drive the
  /// converting state machine. Implementation detail (see design.md):
  /// the parent `MessageInput` shows the overlay with `enableVoiceToText:
  /// true`, and when the user releases on the convert button, calls
  /// `_audioRecorder.stopRecord` then routes the resulting [RecordInfo] here
  /// instead of sending it as a voice message.
  ///
  /// 生产入口点：父组件拦截记录完成的回调，并调用这个方法，把抓取到的文件路径和时长传进去，以驱动转换状态机。实现细节（见 design.md）：父组件 `MessageInput` 会显示带
  /// `enableVoiceToText: true` 的覆盖层，当用户松开转换按钮时，会调用 `_audioRecorder.stopRecord`，然后把生成的 [RecordInfo]
  /// 传到这里，而不是作为语音消息发送。
  void enterConverting(String filePath, int durationSec) {
    if (!mounted) return;
    _capturedRecordPath = filePath;
    _capturedRecordDurationSec = durationSec;
    setState(() {
      _state = _OverlayState.converting;
    });
    _dotsAnimationController.repeat();
    _runConversion(filePath);
  }

  /// Test-only convenience: same as [enterConverting] but with a default
  /// duration. Tests use this to skip the actual recording lifecycle.
  ///
  /// 仅测试用便捷方法：功能和 [enterConverting] 一样，但有默认时长。测试使用它来跳过实际的录音生命周期。
  @visibleForTesting
  void enterConvertingForTest(String filePath) {
    enterConverting(filePath, 1);
  }

  Future<void> _runConversion(String filePath) async {
    final result = await _mediaProcessManager.convert(filePath);
    if (!mounted) return;

    if (result is AiAsrSuccess && result.text.isNotEmpty) {
      // Cache the original transcription and reset translation/TTS state for
      // this new editing session.
      //
      // 缓存原始转录内容，并为这个新的编辑会话重置翻译/TTS 状态。
      _asrOriginalText = result.text;
      _translatedText = null;
      _isTranslating = false;
      _isPlayingTts = false;
      final controller = TextEditingController(text: result.text);
      controller.selection =
          TextSelection.collapsed(offset: result.text.length);
      _editingController?.dispose();
      _editingController = controller;
      // FocusNode is initially NOT focused: editing state opens in
      // "preview" sub-state (gray bubble, no keyboard, waveform visible).
      // The user must tap the text bubble to start editing.
      //
      // FocusNode 初始不聚焦：编辑状态会在“预览”子状态下打开（灰色气泡，无键盘，可见波形）。用户必须点击文本气泡才能开始编辑。
      _editingFocusNode?.dispose();
      final focusNode = FocusNode()..addListener(_onEditingFocusChanged);
      _editingFocusNode = focusNode;
      setState(() {
        _state = _OverlayState.editing;
      });
      _dotsAnimationController.stop();
      _dotsAnimationController.reset();
      // Force a rebuild so listeners on the controller update the
      // send-button enabled state.
      //
      // 强制重建，这样控制器上的监听器会更新发送按钮的可用状态。
      controller.addListener(_onEditingTextChanged);
    } else {
      setState(() {
        _state = _OverlayState.error;
      });
      _dotsAnimationController.stop();
      _dotsAnimationController.reset();
    }
  }

  void _onEditingTextChanged() {
    if (mounted) setState(() {});
  }

  /// Triggered whenever the editing TextField gains/loses focus. We listen
  /// to it so the parent panel can re-layout (`AnimatedPadding`) when the
  /// keyboard pops up / is dismissed.
  ///
  /// 每当编辑的文本框获得/失去焦点时触发。我们监听它，以便父面板可以在键盘弹出/收起时重新布局（`AnimatedPadding`）。
  void _onEditingFocusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> cancelRecord() async {
    await _audioRecorder.cancelRecord();
    widget.onRecordCancelled();
  }

  /// Reset recording state to initial values
  ///
  /// 将录音状态重置为初始值。
  void resetRecordingState() {
    if (mounted) {
      setState(() {
        _recordingDurationMs = 0;
        _isFingerOverCancel = false;
        _isFingerOverConvert = false;
        _state = _OverlayState.recording;
        _capturedRecordPath = null;
        _capturedRecordDurationSec = 0;
        _editingController?.removeListener(_onEditingTextChanged);
        _editingController?.dispose();
        _editingController = null;
        _editingFocusNode?.removeListener(_onEditingFocusChanged);
        _editingFocusNode?.dispose();
        _editingFocusNode = null;
        _asrOriginalText = '';
        _translatedText = null;
        _isTranslating = false;
        _isPlayingTts = false;
        _ttsHelper?.stop();
      });
    }
  }

  /// Check if a global position is over the cancel button
  ///
  /// 检查一个全局位置是否在取消按钮上。
  bool isPointerOverCancelButton(Offset globalPosition) {
    return _isPointerOverButton(_cancelButtonKey, globalPosition);
  }

  /// Check if a global position is over the convert-to-text button.
  /// Always returns false when [AudioRecordOverlay.enableVoiceToText] is false
  /// or the convert button hasn't been laid out yet.
  ///
  /// 检查一个全局位置是否在转换为文本按钮上。当 [AudioRecordOverlay.enableVoiceToText] 为 false 或转换按钮还没有布局时，总是返回 false。
  bool isPointerOverConvertButton(Offset globalPosition) {
    if (!widget.enableVoiceToText) return false;
    return _isPointerOverButton(_convertButtonKey, globalPosition);
  }

  bool _isPointerOverButton(GlobalKey key, Offset globalPosition) {
    final RenderBox? renderBox =
        key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return false;
    final localPos = renderBox.globalToLocal(globalPosition);
    final size = renderBox.size;
    // Expand hit area a bit for easier targeting
    //
    // 略微扩大命中区域，更容易点击。
    const expandPx = 20.0;
    return localPos.dx >= -expandPx &&
        localPos.dx <= size.width + expandPx &&
        localPos.dy >= -expandPx &&
        localPos.dy <= size.height + expandPx;
  }

  /// Update finger position (called from parent's pointer move handler).
  /// Updates both cancel and convert hover flags. Only effective in the
  /// recording state (after recording finishes, the gesture is over).
  ///
  /// 更新手指位置（由父级的指针移动处理器调用）。会更新取消和转换按钮的悬停标志。只在录音状态下有效（录音结束后，手势结束）。
  void updatePointerPosition(Offset globalPosition) {
    if (!_isRecording || _state != _OverlayState.recording) return;
    final isOverCancel = isPointerOverCancelButton(globalPosition);
    // Cancel and convert are mutually exclusive (can't be on both at once),
    // and cancel takes precedence if buttons accidentally overlap.
    //
    // 取消和转换是互斥的（不能同时选择），如果按钮意外重叠，取消优先。
    final isOverConvert =
        !isOverCancel && isPointerOverConvertButton(globalPosition);
    if (isOverCancel != _isFingerOverCancel ||
        isOverConvert != _isFingerOverConvert) {
      setState(() {
        _isFingerOverCancel = isOverCancel;
        _isFingerOverConvert = isOverConvert;
      });
    }
  }

  int get _remainingSeconds {
    final elapsed = (_recordingDurationMs / 1000).floor();
    return _maxDurationSec - elapsed;
  }

  bool get _showCountdown =>
      _remainingSeconds <= _countdownThresholdSec && _isRecording;

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme ?? SemanticColorScheme.of(context);
    final atomicLocale =
        widget.atomicLocalizations ?? AppLocalization.of(context);

    return Stack(
      children: [
        // Semi-transparent top area: tap-through gradient that fades into
        // the solid bottom panel, allowing the message list to remain visible.
        //
        // 半透明顶部区域：可点击穿透的渐变，渐变到实心底部面板，使消息列表保持可见。
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colorScheme.bgColorOperate.withValues(alpha: 0.0),
                    colorScheme.bgColorOperate.withValues(alpha: 0.6),
                    colorScheme.bgColorOperate,
                  ],
                  stops: const [0.0, 0.55, 0.7],
                ),
              ),
            ),
          ),
        ),

        // Bottom-aligned content panel — content varies by state.
        //
        // 底部对齐的内容面板——内容根据状态变化。
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildBottomPanel(colorScheme, atomicLocale),
        ),

        // Error state overlays a tap-anywhere catcher across the full screen.
        //
        // 错误状态在整个屏幕上覆盖一个点击捕捉层。
        if (_state == _OverlayState.error) _buildErrorTapCatcher(),
      ],
    );
  }

  Widget _buildBottomPanel(
      SemanticColorScheme colorScheme, AppLocalizedText atomicLocale) {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;
    // viewInsets.bottom > 0 means the soft keyboard is up. Lift the entire
    // overlay panel above the keyboard so the bubble + buttons remain
    // visible while the user edits the converted text.
    //
    // viewInsets.bottom > 0 表示软键盘已弹出。将整个覆盖面板抬到键盘上方，这样在用户编辑转换文本时，气泡和按钮仍然可见。
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final liftedAboveKeyboard = keyboardInset > 0;
    Widget content;
    switch (_state) {
      case _OverlayState.recording:
        content = _buildRecording(colorScheme, atomicLocale);
        break;
      case _OverlayState.converting:
        content = _buildConverting(colorScheme, atomicLocale);
        break;
      case _OverlayState.editing:
        content = _buildEditing(colorScheme, atomicLocale);
        break;
      case _OverlayState.error:
        content = _buildError(colorScheme, atomicLocale);
        break;
    }
    // NOTE: Do NOT wrap with AnimatedPadding — `viewInsets.bottom` is already
    // updated continuously by the framework in sync with the system keyboard
    // animation (iOS in particular). Layering an AnimatedPadding on top adds
    // a second easing curve, making the panel visibly lag behind the keyboard.
    //
    // 注意：不要使用 AnimatedPadding 包裹——`viewInsets.bottom` 已经会随着系统键盘动画（尤其是 iOS）由框架持续更新。在上面再套一层 AnimatedPadding
    // 会增加第二个缓动曲线，使面板明显落后于键盘。
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Container(
        color: colorScheme.bgColorOperate,
        padding: EdgeInsets.only(
          // When keyboard is up the safe-area is irrelevant (keyboard already
          // covers it), so collapse padding to 0 to avoid extra empty space.
          //
          // 当键盘弹出时，安全区域无关紧要（键盘已经覆盖了它），所以将内边距缩到 0，避免额外的空白。
          bottom: liftedAboveKeyboard ? 0 : bottomPadding,
        ),
        child: content,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // recording state
  // ---------------------------------------------------------------------------
  //
  // 录制状态

  Widget _buildRecording(
      SemanticColorScheme colorScheme, AppLocalizedText atomicLocale) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        _buildHintText(colorScheme, atomicLocale),
        const SizedBox(height: 16),
        _buildRecordingButtonsRow(colorScheme, atomicLocale),
        const SizedBox(height: 16),
        _buildWaveformBar(colorScheme),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildRecordingButtonsRow(
      SemanticColorScheme colorScheme, AppLocalizedText atomicLocale) {
    final cancelBtn = _buildCancelButton(colorScheme, atomicLocale);
    if (!widget.enableVoiceToText) {
      // Single button centered (legacy behavior).
      //
      // 单个按钮居中（旧版行为）。
      return Center(child: cancelBtn);
    }
    final convertBtn = _buildConvertButton(colorScheme, atomicLocale);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [cancelBtn, convertBtn],
    );
  }

  /// Full-width rounded waveform bar at the bottom of the overlay.
  /// Normal: blue/primary background. Cancel hover: red background.
  ///
  /// 覆盖层底部的全宽圆角波形条。正常：蓝色/主色背景。取消悬停：红色背景。
  Widget _buildWaveformBar(SemanticColorScheme colorScheme) {
    final barColor = _isFingerOverCancel
        ? colorScheme.textColorError
        : colorScheme.buttonColorPrimaryDefault;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: barColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(_waveHeights.length, (index) {
            // Varied base heights for visual rhythm
            //
            // 不同的基础高度以维持视觉节奏
            const baseHeights = [
              6.0,
              8.0,
              14.0,
              10.0,
              18.0,
              8.0,
              12.0,
              6.0,
              14.0,
              18.0
            ];
            final baseHeight = baseHeights[index % baseHeights.length];
            final animatedHeight = _isRecording
                ? baseHeight * _waveHeights[index]
                : baseHeight * 0.3;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 3,
                height: animatedHeight.clamp(3.0, 24.0),
                decoration: BoxDecoration(
                  color: colorScheme.switchColorButton,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildHintText(
      SemanticColorScheme colorScheme, AppLocalizedText atomicLocale) {
    String hintText;

    if (_showCountdown) {
      hintText = atomicLocale.recordCountdownTips(_remainingSeconds);
    } else if (_isFingerOverCancel) {
      hintText = atomicLocale.releaseToCancel;
    } else if (_isFingerOverConvert) {
      hintText = atomicLocale.releaseToConvert;
    } else {
      hintText = atomicLocale.releaseToSend;
    }

    return Text(
      hintText,
      style: FontScheme.caption2Regular.copyWith(
        color: colorScheme.textColorSecondary,
        decoration: TextDecoration.none,
      ),
    );
  }

  /// Circular cancel button.
  /// Normal: light gray bg + dark text, no border.
  /// Cancel hover: red bg + white text.
  ///
  /// 圆形取消按钮。正常：浅灰色背景 + 深色文字，无边框。取消悬停：红色背景 + 白色文字。
  Widget _buildCancelButton(
      SemanticColorScheme colorScheme, AppLocalizedText atomicLocale) {
    final isHover = _isFingerOverCancel;
    final bgColor = isHover
        ? colorScheme.textColorError
        : colorScheme.buttonColorSecondaryDefault;
    final textColor =
        isHover ? colorScheme.textColorButton : colorScheme.textColorPrimary;

    return AnimatedContainer(
      key: _cancelButtonKey,
      duration: const Duration(milliseconds: 200),
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          atomicLocale.cancel,
          key: const Key('vtt_cancel_button'),
          style: FontScheme.caption1Medium.copyWith(
            color: textColor,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  /// Circular convert-to-text button.
  /// Normal: light gray bg + dark text.
  /// Hover: primary bg + white text.
  ///
  /// 循环转换为文本按钮。正常：浅灰色背景 + 深色文字。悬停：主色背景 + 白色文字。
  Widget _buildConvertButton(
      SemanticColorScheme colorScheme, AppLocalizedText atomicLocale) {
    final isHover = _isFingerOverConvert;
    final bgColor = isHover
        ? colorScheme.buttonColorPrimaryDefault
        : colorScheme.buttonColorSecondaryDefault;
    final textColor =
        isHover ? colorScheme.textColorButton : colorScheme.textColorPrimary;

    return AnimatedContainer(
      key: _convertButtonKey,
      duration: const Duration(milliseconds: 200),
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          atomicLocale.convertToText,
          key: const Key('vtt_convert_button'),
          textAlign: TextAlign.center,
          style: FontScheme.caption1Medium.copyWith(
            color: textColor,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // converting state
  // ---------------------------------------------------------------------------
  //
  // 转换中状态

  Widget _buildConverting(
      SemanticColorScheme colorScheme, AppLocalizedText atomicLocale) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kPanelHPadding),
          child: _BubbleWithArrow(
            color: colorScheme.buttonColorPrimaryDefault,
            arrowRightOffset: _kSendButtonCenterFromRight,
            child: _ConvertingBubbleContent(
              key: const Key('vtt_converting_dots'),
              controller: _dotsAnimationController,
              dotColor: colorScheme.textColorButton,
            ),
          ),
        ),
        const SizedBox(height: _kBubbleToButtonsGap),
        // Buttons remain visible (Figma 1826-5936) but ignore taps.
        //
        // 按钮保持可见（Figma 1826-5936），但忽略点击。
        IgnorePointer(
          child: _buildEditingButtonsRow(
            colorScheme,
            atomicLocale,
            disabled: true,
          ),
        ),
        const SizedBox(height: 16),
        // The static gray waveform bar is shown from the moment conversion
        // starts and stays through the editing state, providing visual
        // continuity with the recording state.
        //
        // 从转换开始就显示静态灰色波形条，并在编辑状态中保持，提供与录音状态的视觉连续性。
        _buildPreviewWaveformBar(colorScheme),
        const SizedBox(height: 8),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // editing state
  // ---------------------------------------------------------------------------
  //
  // 编辑状态

  Widget _buildEditing(
      SemanticColorScheme colorScheme, AppLocalizedText atomicLocale) {
    final controller = _editingController!;
    final focusNode = _editingFocusNode!;
    // Per Figma: bubble is ALWAYS blue with white text (independent of focus
    // state). The only thing focus changes is whether the keyboard is up.
    //
    // 根据 Figma：气泡始终是蓝色，文字白色（与焦点状态无关）。焦点唯一改变的是键盘是否弹出。
    final bubbleColor = colorScheme.buttonColorPrimaryDefault;
    final textColor = colorScheme.textColorButton;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kPanelHPadding),
          child: _BubbleWithArrow(
            color: bubbleColor,
            arrowRightOffset: _kSendButtonCenterFromRight,
            child: Container(
              constraints: const BoxConstraints(minHeight: 70, maxHeight: 220),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              // Tapping anywhere on the bubble (including padding) requests
              // focus, which raises the keyboard.
              //
              // 点击气泡的任何地方（包括内边距）都会请求焦点，从而弹出键盘。
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (!focusNode.hasFocus) {
                    focusNode.requestFocus();
                  }
                },
                // Override the inherited TextSelectionTheme so the cursor,
                // the iOS-style water-drop selection handle, and the
                // selection highlight all stay visible on the blue bubble
                // background (default handle color comes from the app's
                // primary color, which is the same blue as the bubble).
                //
                // 覆盖继承的TextSelectionTheme，使光标、iOS风格的水滴选择手柄和选择高亮都保持在蓝色气泡背景上（默认手柄颜色来自应用的主色，与气泡相同）。
                child: Theme(
                  data: Theme.of(context).copyWith(
                    textSelectionTheme: TextSelectionThemeData(
                      cursorColor: textColor,
                      selectionHandleColor: textColor,
                      selectionColor: textColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: TextField(
                    key: const Key('vtt_editing_textfield'),
                    controller: controller,
                    focusNode: focusNode,
                    // Do NOT autofocus: editing opens with the keyboard hidden.
                    // User taps the bubble to start editing.
                    //
                    // 请勿自动对焦：编辑在键盘隐藏状态下打开。用户点击气泡即可开始编辑。
                    autofocus: false,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    cursorColor: textColor,
                    // Suppress the collapsed-state handle entirely.
                    // Material draws a 45°-rotated square (looks like a
                    // water-drop / diamond) directly below the caret on
                    // tap, and iOS draws an actual oval water-drop — both
                    // are visually distracting on the blue bubble. Custom
                    // controls return SizedBox.shrink() for collapsed so
                    // only the white caret line stays. Long-press text
                    // selection still draws normal left/right handles.
                    //
                    // 完全抑制折叠状态手柄。Material 在水源头下方画一个旋转45°的方形（看起来像水滴/菱形），iOS 画出一个真正的椭圆形水滴——这两点在蓝色气泡中视觉上都很分散注意力。自定义控件返回
                    // SsizeBox.shrink（） 表示折叠，所以只有白色插入线保持。长按文本选择仍然显示正常的左右手柄。
                    selectionControls:
                        _NoCollapsedHandleSelectionControls.instance,
                    // Disable the iOS-style magnifier (floating lens that
                    // appears under the finger while tapping/dragging the
                    // caret). It also looks like a "water-drop" on the
                    // bubble, and the user wants the editing area to show
                    // only a plain caret line.
                    //
                    // 禁用 iOS 风格的放大镜（在点击/拖动光标时出现在手指下方的浮动镜头）。它在气泡上看起来像“水滴”，用户希望编辑区只显示普通的光标线。
                    magnifierConfiguration: TextMagnifierConfiguration.disabled,
                    style: FontScheme.caption1Regular.copyWith(
                      color: textColor,
                      decoration: TextDecoration.none,
                    ),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildTranslateChipRow(colorScheme),
        const SizedBox(height: 16),
        _buildEditingButtonsRow(colorScheme, atomicLocale, disabled: false),
        const SizedBox(height: 16),
        // Static gray waveform bar is shown both before AND after the
        // keyboard pops up — the parent's AnimatedPadding lifts the entire
        // panel above the keyboard, so the bar stays visible at the bottom
        // of the panel rather than being hidden.
        //
        // 在键盘弹出前后都会显示静态灰色波形条——父层的 AnimatedPadding 会将整个面板抬高到键盘上方，所以波形条会保持在面板底部可见，而不会被隐藏。
        _buildPreviewWaveformBar(colorScheme),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Static, evenly-sized waveform bar shown in the editing-preview
  /// sub-state. Per Figma: equal-height short vertical bars in a neutral
  /// gray color on a light gray rounded-rectangle background. Not animated
  /// since recording is over.
  ///
  /// 编辑预览子状态下显示静态、大小一致的波形条。根据 Figma：浅灰色圆角矩形背景上的等高短垂直条，颜色为中性灰。录制结束后不再动画。
  Widget _buildPreviewWaveformBar(SemanticColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: colorScheme.bgColorInput,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(_waveHeights.length, (_) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Container(
                width: 3,
                // Equal-height bars per Figma 1783-12707 design.
                //
                // 根据 Figma 1783-12707 设计显示等高条。
                height: 5,
                decoration: BoxDecoration(
                  color: colorScheme.textColorTertiary,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // editing state — translate / read-aloud chip row
  // ---------------------------------------------------------------------------
  //
  // 编辑状态——翻译/朗读功能的芯片行

  /// Row of action chips shown between the text bubble and the three buttons.
  /// Before translation: a single "Translate" chip. After translation:
  /// "Undo Translation" / "Switch Language" / "Read Aloud" (or "Stop").
  ///
  /// 在文字气泡和三个按钮之间显示一排操作芯片。翻译前：单个“翻译”芯片。翻译后：“撤销翻译”/“切换语言”/“朗读”（或“停止”）。
  Widget _buildTranslateChipRow(SemanticColorScheme colorScheme) {
    final chatLocale = AppLocalization.of(context);
    final List<Widget> children;
    if (_translatedText == null) {
      children = [
        _buildActionChip(
          colorScheme,
          label: chatLocale.voiceTranslate,
          onTap: _isTranslating ? null : _onTranslateTapped,
        ),
      ];
    } else {
      children = [
        _buildActionChip(
          colorScheme,
          label: chatLocale.voiceCancelTranslation,
          onTap: _onCancelTranslationTapped,
        ),
        const SizedBox(width: 8),
        _buildActionChip(
          colorScheme,
          label: chatLocale.voiceSwitchLanguage,
          onTap: _isTranslating ? null : _onSwitchLanguageTapped,
        ),
        const SizedBox(width: 8),
        _buildActionChip(
          colorScheme,
          label: _isPlayingTts
              ? chatLocale.voiceStopReadAloud
              : chatLocale.voiceReadAloud,
          onTap: _onReadAloudTapped,
        ),
      ];
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kPanelHPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildActionChip(
    SemanticColorScheme colorScheme, {
    required String label,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.buttonColorSecondaryDefault,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: FontScheme.caption2Regular.copyWith(
            color: disabled
                ? colorScheme.textColorDisable
                : colorScheme.textColorPrimary,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  Future<void> _onTranslateTapped() async {
    final config = VoiceMessageConfig.instance;
    // Refresh from local storage so a previously saved language survives an
    // app restart (the singleton's in-memory cache starts empty).
    //
    // 从本地存储刷新，以便之前保存的语言在应用重启后仍然存在（单例的内存缓存初始为空）。
    await config.load();
    var lang = config.recordTranslateTargetLanguage;
    if (lang.isEmpty) {
      final picked = await _showLanguageSelector();
      if (picked == null) return;
      await config.setRecordTranslateTargetLanguage(picked);
      lang = picked;
    }
    await _translateTo(lang);
  }

  Future<void> _onSwitchLanguageTapped() async {
    final picked = await _showLanguageSelector();
    if (picked == null) return;
    await VoiceMessageConfig.instance.setRecordTranslateTargetLanguage(picked);
    await _translateTo(picked);
  }

  /// Always translates from [_asrOriginalText] (never from a prior translation).
  ///
  /// 始终从 [_asrOriginalText] 翻译（从不使用之前的翻译）。
  Future<void> _translateTo(String languageCode) async {
    if (!mounted) return;
    setState(() => _isTranslating = true);
    final result = await _mediaProcessManager.translateSingleText(
      text: _asrOriginalText,
      targetLanguage: languageCode,
    );
    if (!mounted) return;
    setState(() => _isTranslating = false);
    if (result.success && result.text != null && result.text!.isNotEmpty) {
      _translatedText = result.text;
      _setControllerText(result.text!);
      setState(() {});
    } else {
      Toast.error(context, AppLocalization.of(context).voiceTranslateFailed);
    }
  }

  void _onCancelTranslationTapped() {
    _translatedText = null;
    _setControllerText(_asrOriginalText);
    setState(() {});
  }

  void _setControllerText(String text) {
    final controller = _editingController;
    if (controller == null) return;
    controller.text = text;
    controller.selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _onReadAloudTapped() async {
    if (_isPlayingTts) {
      await _ttsHelper?.stop();
      if (mounted) setState(() => _isPlayingTts = false);
      return;
    }
    // Strip emoji so they aren't spoken.
    //
    // 去掉表情符号，这样它们不会被朗读。
    final text = sanitizeTextForTts(_editingController?.text ?? '');
    if (text.isEmpty) return;
    // Refresh selected voice from local storage (survives app restart).
    //
    // 从本地存储刷新所选语音（重启应用后仍然有效）。
    await VoiceMessageConfig.instance.load();
    _ttsHelper ??= TtsPlaybackHelper(service: _mediaProcessManager);
    setState(() => _isPlayingTts = true);
    await _ttsHelper!.speak(
      text: text,
      voiceId: VoiceMessageConfig.instance.selectedVoiceId,
      onComplete: () {
        if (mounted) setState(() => _isPlayingTts = false);
      },
      onError: (e) {
        if (mounted) {
          setState(() => _isPlayingTts = false);
          Toast.error(context, AppLocalization.of(context).voiceTtsFailed);
        }
      },
    );
  }

  /// Language picker shown as an [OverlayEntry] so it renders ABOVE the audio
  /// record overlay (which itself lives in an OverlayEntry). A modal bottom
  /// sheet would be a Navigator route and appear behind the record panel.
  /// Returns the selected language code, or null when dismissed.
  ///
  /// 语言选择器显示为 [OverlayEntry]，因此可以渲染在音频录制覆盖层之上（录音面板本身也在 OverlayEntry 中）。模态底部表单会作为 Navigator
  /// 路由出现，并显示在录音面板后面。返回所选语言代码，或在取消时返回 null。
  Future<String?> _showLanguageSelector() async {
    final overlay = Overlay.of(context);
    final colorScheme = widget.colorScheme ?? SemanticColorScheme.of(context);
    final chatLocale = AppLocalization.of(context);
    final currentLang =
        VoiceMessageConfig.instance.recordTranslateTargetLanguage;

    final completer = Completer<String?>();
    late OverlayEntry entry;

    void close(String? result) {
      if (entry.mounted) entry.remove();
      if (!completer.isCompleted) completer.complete(result);
    }

    entry = OverlayEntry(
      builder: (overlayContext) {
        final mediaQuery = MediaQuery.of(overlayContext);
        return Stack(
          children: [
            // Dimming barrier; tap to dismiss.
            //
            // 调暗遮罩；点击即可关闭。
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => close(null),
                child: const ColoredBox(color: Colors.black54),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: colorScheme.bgColorOperate,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: SafeArea(
                  top: false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: mediaQuery.size.height * 0.6,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            chatLocale.voiceSwitchLanguageSheetTitle,
                            style: FontScheme.caption2Regular.copyWith(
                              color: colorScheme.textColorSecondary,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _translateLanguageOptions.length,
                            itemBuilder: (context, index) {
                              final option = _translateLanguageOptions[index];
                              final selected = currentLang == option['code'];
                              return InkWell(
                                onTap: () => close(option['code']),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  child: Text(
                                    option['name'] ?? '',
                                    style: FontScheme.caption1Regular.copyWith(
                                      color: selected
                                          ? colorScheme.textColorLink
                                          : colorScheme.textColorPrimary,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(entry);
    return completer.future;
  }

  Widget _buildEditingButtonsRow(
    SemanticColorScheme colorScheme,
    AppLocalizedText atomicLocale, {
    required bool disabled,
  }) {
    // Layout:
    // - Outer horizontal padding `_kPanelHPadding` keeps the row away from
    //   screen edges.
    // - The three buttons are spaced evenly via `MainAxisAlignment.spaceBetween`,
    //   so the gap between cancel↔sendOriginal matches sendOriginal↔send.
    // - Send button stays anchored to the right edge (same horizontal padding
    //   as the bubble), which keeps the bubble's downward arrow aligned with
    //   its center (`_kSendButtonCenterFromRight`).
    // - The send button's vertical center aligns with the small icon-circles'
    //   vertical centers (24px from the row top): 70/2 - 48/2 = 11px upward
    //   translation.
    //
    // - 外部水平内边距 `_kPanelHPadding` 保持行距离屏幕边缘一定距离。- 三个按钮通过 `MainAxisAlignment.spaceBetween`
    // 均匀分布，所以取消↔发送原文的间距和发送原文↔发送的间距相同。- 发送按钮固定在右边缘（与气泡相同的水平内边距），保持气泡下箭头与其中心对齐
    // (`_kSendButtonCenterFromRight`)。- 发送按钮的垂直中心与小图标圈对齐。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kPanelHPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SmallActionButton(
            key: const Key('vtt_btn_cancel'),
            label: atomicLocale.cancel,
            iconAsset: 'chat_assets/icon/close_audio_record.svg',
            colorScheme: colorScheme,
            onTap: disabled ? null : _onEditingCancelTapped,
          ),
          _SmallActionButton(
            key: const Key('vtt_btn_send_original'),
            label: atomicLocale.sendOriginalVoice,
            iconAsset: 'chat_assets/icon/send_origin_audio.svg',
            colorScheme: colorScheme,
            onTap: disabled ? null : _onSendOriginalTapped,
          ),
          Transform.translate(
            offset: const Offset(0, -11),
            child: _SendTextButton(
              key: const Key('vtt_btn_send_text'),
              label: atomicLocale.send,
              colorScheme: colorScheme,
              enabled: !disabled &&
                  (_editingController?.text.trim().isNotEmpty ?? false),
              onTap: _onSendTextTapped,
            ),
          ),
        ],
      ),
    );
  }

  void _onEditingCancelTapped() {
    widget.onRecordCancelled();
  }

  void _onSendOriginalTapped() {
    final path = _capturedRecordPath;
    if (path == null) {
      widget.onRecordCancelled();
      return;
    }
    final info = RecordInfo(duration: _capturedRecordDurationSec, path: path)
      ..errorCode = AudioRecordResultCode.success;
    widget.onRecordFinish(info);
  }

  void _onSendTextTapped() {
    final controller = _editingController;
    if (controller == null) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    widget.onSendText?.call(text);
  }

  // ---------------------------------------------------------------------------
  // error state
  // ---------------------------------------------------------------------------
  //
  // 错误状态

  Widget _buildError(
      SemanticColorScheme colorScheme, AppLocalizedText atomicLocale) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kPanelHPadding),
          child: _BubbleWithArrow(
            key: const Key('vtt_error_bubble'),
            color: colorScheme.textColorError,
            arrowRightOffset: _kSendButtonCenterFromRight,
            child: Container(
              constraints: const BoxConstraints(minHeight: 70),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              alignment: Alignment.center,
              child: Text(
                atomicLocale.voiceToTextFailed,
                style: FontScheme.caption1Regular.copyWith(
                  color: colorScheme.textColorButton,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: _kBubbleToButtonsGap),
        // Buttons present but inert.
        //
        // 按钮存在但无反应。
        IgnorePointer(
          child: _buildEditingButtonsRow(
            colorScheme,
            atomicLocale,
            disabled: true,
          ),
        ),
        const SizedBox(height: 16),
        // Match editing/converting: keep the gray waveform visible so the
        // overall layout remains consistent across the three end-states.
        //
        // 匹配编辑/转换：保持灰色波形可见，以便在三种最终状态下整体布局保持一致。
        _buildPreviewWaveformBar(colorScheme),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Full-screen tap catcher in error state. Any tap closes the overlay.
  ///
  /// 错误状态下的全屏点击捕获器。任何点击都会关闭覆盖层。
  Widget _buildErrorTapCatcher() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onRecordCancelled,
      ),
    );
  }
}

// =============================================================================
// Sub-widgets
// =============================================================================

/// Rounded rectangle "bubble" with a downward-pointing triangle tail at
/// the bottom edge. The tail is positioned via [arrowRightOffset] which
/// measures the distance from the bubble's RIGHT edge to the tail's
/// horizontal center — used to make the tail point at the send button.
///
/// 带有向下三角形尾巴的圆角矩形“气泡”，尾巴位于底边。尾巴的位置通过 [arrowRightOffset] 来控制，它测量从气泡右边缘到尾巴水平中心的距离——用于让尾巴指向发送按钮。
class _BubbleWithArrow extends StatelessWidget {
  const _BubbleWithArrow({
    super.key,
    required this.color,
    required this.arrowRightOffset,
    required this.child,
  });

  final Color color;
  final double arrowRightOffset;
  final Widget child;

  static const double _kArrowWidth = 14.0;
  static const double _kArrowHeight = 8.0;
  static const double _kRadius = 12.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Bubble body.
        //
        // 气泡主体。
        Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(_kRadius),
          ),
          child: child,
        ),
        // Downward triangle tail. `bottom: -arrowHeight` makes the tail
        // protrude below the bubble. `right` positions its center along
        // the bubble's bottom edge.
        //
        // 向下的三角形尾巴。`bottom: -arrowHeight` 让尾巴伸出气泡底部。`right` 设置其在气泡底边的中心位置。
        Positioned(
          right: arrowRightOffset - _kArrowWidth / 2,
          bottom: -_kArrowHeight + 0.5, // 0.5px overlap to avoid hairline gap
          child: CustomPaint(
            size: const Size(_kArrowWidth, _kArrowHeight),
            painter: _BubbleArrowPainter(color: color),
          ),
        ),
      ],
    );
  }
}

class _BubbleArrowPainter extends CustomPainter {
  _BubbleArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Animated three-dot content used in the converting state. Each dot
/// pulses out of phase, producing a smooth left-to-right shimmer.
/// Wrapped in a [_BubbleWithArrow] by the caller so the bubble shape +
/// downward arrow are consistent with the editing/error bubbles.
///
/// 用于转换状态的三点动画内容。每个点错开脉冲，产生平滑的从左到右闪烁效果。主叫方会用 [_BubbleWithArrow] 将其包装起来，使气泡形状和向下箭头与编辑/错误气泡保持一致。
class _ConvertingBubbleContent extends StatelessWidget {
  const _ConvertingBubbleContent({
    super.key,
    required this.controller,
    required this.dotColor,
  });

  final AnimationController controller;

  /// Base color for the three pulsing dots. Each dot's alpha is multiplied
  /// by a staggered brightness value to produce the shimmer effect.
  /// Caller passes `colorScheme.textColorButton` (white) so the dots stay
  /// theme-aware on the bubble's primary background.
  ///
  /// 三个跳动点的基础颜色。每个点的透明度都会乘以一个错开的亮度值来产生闪烁效果。调用方传入 `colorScheme.textColorButton`（白色），这样点在气泡的主背景上仍然会保持主题感。
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      alignment: Alignment.centerLeft,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              // Stagger each dot's brightness by 1/3 cycle.
              //
              // 让每个点的亮度错开 1/3 个周期。
              final phase = (controller.value + i / 3) % 1.0;
              final brightness = 0.3 + 0.7 * (1 - (phase * 2 - 1).abs());
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: dotColor.withValues(alpha: brightness),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// Small circular button used for cancel / send-original in editing state.
/// 48x48 light-gray background with a centered SVG icon (20x20) and a
/// caption label rendered below the circle. Disabled when [onTap] is null.
///
/// 编辑状态下用于取消/发送原始内容的小圆按钮。48x48 的浅灰色背景，中心有一个 20x20 的 SVG 图标，下方渲染有标题标签。[onTap] 为 null 时禁用。
class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    super.key,
    required this.label,
    required this.iconAsset,
    required this.colorScheme,
    required this.onTap,
  });

  final String label;
  final String iconAsset;
  final SemanticColorScheme colorScheme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final iconColor =
        disabled ? colorScheme.textColorDisable : colorScheme.textColorPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: disabled
                  ? colorScheme.buttonColorSecondaryDisabled
                  : colorScheme.buttonColorSecondaryDefault,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: SvgPicture.asset(
              iconAsset,
              package: 'tencent_chat_uikit',
              width: 20,
              height: 20,
              // Force-tint the icon so it's always visible regardless of
              // the SVG's intrinsic fill color (works around cases where
              // some SVG fills don't render reliably under OverlayEntry).
              //
              // 强制给图标着色，使其始终可见，无论 SVG 的内在填充颜色如何（解决某些 SVG 填充在 OverlayEntry 下渲染不可靠的问题）。
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: FontScheme.caption2Regular.copyWith(
              color: disabled
                  ? colorScheme.textColorDisable
                  : colorScheme.textColorSecondary,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

/// Primary "send" button used in editing state. Sized so its bottom edge
/// aligns with the bottom of the small-action buttons' label text — i.e.,
/// total height matches `48 (circle) + 5 (gap) + ~17 (label) = 70`.
///
/// 编辑状态下的主要“发送”按钮。大小设计使其下边缘与小动作按钮标签文字的下边缘对齐，也就是
class _SendTextButton extends StatelessWidget {
  const _SendTextButton({
    super.key,
    required this.label,
    required this.colorScheme,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final SemanticColorScheme colorScheme;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: enabled
              ? colorScheme.buttonColorPrimaryDefault
              : colorScheme.buttonColorPrimaryDisabled,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: FontScheme.caption1Medium.copyWith(
            color: colorScheme.textColorButton,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

/// Selection controls that behave like [MaterialTextSelectionControls] for
/// the left/right (active selection) handles but draw NOTHING for the
/// collapsed (no-selection) handle — i.e., when the caret is just blinking
/// after a tap, no diamond/water-drop is shown below it.
///
/// Background:
/// - On iOS, [CupertinoTextSelectionControls] paints an oval "water-drop"
///   handle below the caret in collapsed state.
/// - On Android (Material), the collapsed handle is a 45°-rotated square
///   that visually reads as a diamond / water-drop too.
/// Both look distracting on top of the editing bubble's blue background,
/// so we suppress them while keeping long-press selection fully usable.
///
/// 选择控件，左/右（活动选择）手柄的行为像
/// [MaterialTextSelectionControls]，但在折叠（无选择）手柄时什么都不显示——也就是说，当光标只是点击后闪烁时，不会在下面显示钻石/水滴形状。
///
/// - 在 iOS 上，[CupertinoTextSelectionControls] 会在折叠状态下在光标下画一个椭圆形“水滴”手柄。- 在
/// Android（Material）上，折叠手柄是一个旋转45°的方形，从视觉上也像钻石/水滴。两者放在编辑气泡的蓝色背景上都很显眼，所以我们隐藏它们，同时保持长按选择功能可用。
class _NoCollapsedHandleSelectionControls
    extends MaterialTextSelectionControls {
  _NoCollapsedHandleSelectionControls._();

  static final _NoCollapsedHandleSelectionControls instance =
      _NoCollapsedHandleSelectionControls._();

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textHeight, [
    VoidCallback? onTap,
  ]) {
    if (type == TextSelectionHandleType.collapsed) {
      return const SizedBox.shrink();
    }
    return super.buildHandle(context, type, textHeight, onTap);
  }

  @override
  Offset getHandleAnchor(
    TextSelectionHandleType type,
    double textLineHeight,
  ) {
    if (type == TextSelectionHandleType.collapsed) {
      return Offset.zero;
    }
    return super.getHandleAnchor(type, textLineHeight);
  }
}
