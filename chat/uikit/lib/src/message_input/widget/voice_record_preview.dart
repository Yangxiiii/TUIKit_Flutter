import 'dart:async';
import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart' show MessageType, ChatUtil;
import 'package:flutter/material.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart' show Toast;

import '../../ai/ai_media_process_manager.dart';
import '../../audio_recoder/audio_recorder.dart';
import '../../audio_recoder/audio_recording_draft.dart';
import '../../emoji_picker/emoji_picker.dart';
import '../message_text.dart';
import '../input_keyboard_panel.dart';
import '../../third_party/extended_text_field/extended_text_field.dart';
import '../src/chat_special_text_span_builder.dart';
import 'package:tuikit_atomic_x/base_component/theme/color_scheme.dart';

enum _VoicePhase { recording, recognizing, preview }

/// 单条语音的录音与识别预览浮层；只在用户确认时交给宿主发送，草稿拥有临时文件。
class VoiceRecordPreview extends StatefulWidget {
  const VoiceRecordPreview({
    super.key,
    required this.guard,
    required this.onSendAudio,
    required this.onSendText,
    required this.onClose,
    this.recorder,
    this.mediaProcessManager,
  });

  /// 与聊天其他发送入口共用的防重复实例。
  final ActionGuard guard;

  /// 返回真实发送结果；失败时浮层与完整录音继续保留。
  final Future<bool> Function(RecordInfo) onSendAudio;

  /// 发送当前编辑值，不以识别完成事件自动发送。
  final Future<bool> Function(String) onSendText;

  /// 草稿取消或发送成功后移除浮层。
  final VoidCallback onClose;

  /// 默认复用原生录音器，测试可替换采音以验证手势及迟到回调。
  final AudioRecorder? recorder;

  /// 默认使用已有腾讯识别链路，不引入新的上传协议。
  final AiMediaProcessManager? mediaProcessManager;

  @override
  State<VoiceRecordPreview> createState() => VoiceRecordPreviewState();
}

/// 管理浮层局部手势、焦点和识别时序，音频替换与清理由单一草稿维护。
class VoiceRecordPreviewState extends State<VoiceRecordPreview>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _recorder = widget.recorder ?? AudioRecorder();
  late final _draft = AudioRecordingDraft(guard: widget.guard);
  late final _manager =
      widget.mediaProcessManager ?? AiMediaProcessManager.shared;

  /// 新音量到达后用100毫秒原地形变，不移动音量柱或循环固定波形。
  late final _wave = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 100))
    ..value = 1;
  final _text = TextEditingController();
  final _focus = FocusNode();

  /// 与普通聊天输入区共用键盘/表情交接与高度保留，随当前浮层释放。
  InputKeyboardPanel? _keyboardPanel;

  /// 原生自动结束与手势抬起共用当前阶段，终态不会重复追加或识别。
  _VoicePhase _phase = _VoicePhase.recording;

  /// 关闭后所有原生及识别回调只可清理资源，不能更新界面或发送。
  bool _closed = false;
  bool _cancelHover = false;
  bool _editing = false;
  bool _emoji = false;
  bool _sending = false;
  bool _poorNetwork = false;

  /// 仅让各柱外形独立变化，真实音量仍决定所有柱的振幅上限。
  final _waveRandom = math.Random();

  /// 当前形变的起点，保留被新采音打断时的可见高度，避免突跳。
  List<double> _waveFrom = List.filled(22, 0);

  /// 固定位置各柱的目标振幅，范围0至1；静音时全部归零。
  List<double> _waveTo = List.filled(22, 0);

  /// 仅在系统键盘实际出现后响应收起，避免初次进入编辑或切换表情时误退出。
  bool _keyboardWasVisible = false;

  /// 按下的全局逻辑坐标；向上移动72逻辑像素进入取消悬停。
  Offset _pressOrigin = Offset.zero;

  /// 识别请求代次；续录、取消及关闭会使旧结果失效。
  int _recognition = 0;

  /// 8秒后只显示等待提示，终止当前草稿或识别结束时取消。
  Timer? _networkHint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recorder.initialize(onPowerLevel: (value) {
      if (mounted && !_closed && _phase == _VoicePhase.recording) {
        final double power = ((value + 60) / 60).clamp(0, 1);
        final peak = _waveRandom.nextInt(22);
        // 每条柱在原位置独立起伏，随机峰值位置不形成传播方向；至少一柱保留真实音量上限。
        setState(() {
          _waveFrom = List.generate(22,
              (i) => _waveFrom[i] + (_waveTo[i] - _waveFrom[i]) * _wave.value);
          _waveTo = List.generate(
              22,
              (i) =>
                  power * (i == peak ? 1.0 : .15 + .8 * _waveRandom.nextDouble()));
        });
        _wave.forward(from: 0);
      }
    });
    _text.addListener(_refresh);
    _focus.addListener(_refresh);
  }

  void _refresh() {
    if (mounted && !_closed) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboardPanel ??=
        InputKeyboardPanel(view: View.of(context), onChanged: _refresh);
  }

  @override
  void didChangeMetrics() {
    final view = View.of(context);
    final inset = view.viewInsets.bottom / view.devicePixelRatio;
    final visible = inset > 0;
    final hidden = _keyboardWasVisible && !visible;
    _keyboardWasVisible = visible;
    if (!hidden ||
        _closed ||
        !_editing ||
        _emoji ||
        _keyboardPanel?.returningToSystem == true) {
      return;
    }
    // 输入法的收起按钮只隐藏IME，不会替Flutter清焦点；回到预览并保留编辑正文。
    _keyboardPanel?.clear();
    _focus.unfocus();
    setState(() => _editing = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 来电、系统中断或切后台时丢弃正在采集的草稿，不允许恢复后自动发送。
    if (state != AppLifecycleState.resumed && _phase == _VoicePhase.recording) {
      cancel();
    }
  }

  /// 输入栏按下后启动首段；续录也使用同一入口，并只使用整条语音的剩余额度。
  Future<void> startRecord({required Offset origin}) async {
    if (_closed || _draft.remainingDurationMs < 1000) return;
    _recognition++;
    _networkHint?.cancel();
    _keyboardPanel?.clear();
    _focus.unfocus();
    setState(() {
      _pressOrigin = origin;
      _cancelHover = false;
      _editing = false;
      _emoji = false;
      _phase = _VoicePhase.recording;
      _waveFrom = List.filled(22, 0);
      _waveTo = List.filled(22, 0);
      _wave.stop();
      _wave.value = 1;
    });
    final path = ChatUtil.generateMediaPath(
        messageType: MessageType.audio,
        prefix: '',
        withExtension: 'm4a',
        isCache: true);
    final started = await _recorder.startRecord(
      filePath: path,
      maxDurationMs: _draft.remainingDurationMs,
      onComplete: (info) => unawaited(_complete(info)),
    );
    if (!started && mounted && !_closed) {
      Toast.error(context, '语音录制失败');
      cancel();
    }
  }

  /// 记录指针相对按下位置的上移；连续移动不套用点击防抖。
  void updatePointerPosition(Offset position) {
    if (_phase != _VoicePhase.recording || _closed) return;
    final cancel = position.dy < _pressOrigin.dy - 72;
    if (cancel != _cancelHover) setState(() => _cancelHover = cancel);
  }

  /// 松手只停止采音或取消，正常终态交由识别预览处理，不直接发送消息。
  void stopRecord() {
    if (_closed || _phase != _VoicePhase.recording) return;
    if (_cancelHover) {
      cancel();
    } else {
      _recorder.stopRecord();
    }
  }

  /// 先关闭当前会话，再停止原生采音，迟到回调不能重新打开预览。
  void cancel() {
    if (_closed || _sending) return;
    _closed = true;
    _recognition++;
    _networkHint?.cancel();
    unawaited(_recorder.cancelRecord());
    widget.onClose();
  }

  /// 有效片段先合并到草稿，再识别新片段；追加识别文本不会覆盖用户此前的编辑。
  Future<void> _complete(RecordInfo? info) async {
    if (_closed || !mounted || _phase != _VoicePhase.recording) return;
    if (_cancelHover) {
      cancel();
      return;
    }
    if (info == null ||
        (info.errorCode != AudioRecordResultCode.success &&
            info.errorCode != AudioRecordResultCode.successExceedMaxDuration)) {
      Toast.simple(
          context,
          info?.errorCode == AudioRecordResultCode.errorLessThanMinDuration
              ? '说话时长太短'
              : '语音录制失败');
      if (_draft.current == null) {
        cancel();
      } else {
        setState(() => _phase = _VoicePhase.preview);
      }
      return;
    }
    setState(() => _phase = _VoicePhase.recognizing);
    try {
      await _draft.append(info);
    } catch (_) {
      if (!mounted || _closed) return;
      Toast.error(context, '语音追加失败，请重试');
      if (_draft.current == null) {
        cancel();
      } else {
        setState(() => _phase = _VoicePhase.preview);
      }
      return;
    }
    if (!mounted || _closed) return;
    final generation = ++_recognition;
    final prefix = _text.text;
    _poorNetwork = false;
    // 只提示当前任务等待较久，绝不另起一次上传或识别。
    _networkHint = Timer(const Duration(seconds: 8), () {
      if (mounted && !_closed && generation == _recognition) {
        setState(() => _poorNetwork = true);
      }
    });
    final result = await _manager.convert(info.path);
    if (!mounted || _closed || generation != _recognition) return;
    _networkHint?.cancel();
    final recognized = result is AiAsrSuccess ? result.text.trim() : '';
    setState(() {
      _phase = _VoicePhase.preview;
      _poorNetwork = false;
      if (recognized.isNotEmpty) {
        _text.text = prefix.isEmpty ? recognized : '$prefix\n$recognized';
      }
    });
    if (recognized.isEmpty && prefix.isNotEmpty) {
      Toast.error(context, '未识别出文字');
    }
  }

  /// 两种确认动作共用一次发送边界；SDK调用前移交音频读取权，只有真实成功才关闭。
  Future<void> _send(bool audio) =>
      widget.guard.singleFlight<void>(('chat.voice.confirm', this), () async {
        final recording = _draft.current;
        if (_closed ||
            recording == null ||
            (!audio && _text.text.trim().isEmpty)) {
          return;
        }
        setState(() => _sending = true);
        try {
          // SDK接管后保留路径，即使页面退出或上传失败也可由SDK后台任务及重试继续读取。
          if (audio) _draft.retainSentAudio();
          final sent = audio
              ? await widget.onSendAudio(recording)
              : await widget.onSendText(_text.text);
          if (!mounted || _closed) return;
          if (sent) {
            _sending = false;
            cancel();
          }
        } finally {
          if (mounted && !_closed) setState(() => _sending = false);
        }
      });

  /// 系统键盘和表情面板编辑同一个控制器，选择和退格沿用项目的完整表情边界。
  void _insert(String value) {
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : start;
    _text.value = TextEditingValue(
        text: _text.text.replaceRange(start, end, value),
        selection: TextSelection.collapsed(offset: start + value.length));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final editing = _editing && _phase == _VoicePhase.preview;
    final panel = _keyboardPanel!;
    final keyboard =
        panel.hasReservedSpace ? panel.height : media.viewInsets.bottom;
    // 只读切换和IME首帧之间保持预览锚点；所有区域共用系统Insets的同一过渡进度。
    final editProgress =
        editing ? (keyboard / panel.height).clamp(0.0, 1.0) : 0.0;
    final contentBottom = editing ? keyboard + 44 * editProgress : 0.0;
    final available = media.size.height - contentBottom;
    final recording = _phase == _VoicePhase.recording;
    final recognizing = _phase == _VoicePhase.recognizing;
    final noText = !recording && !recognizing && _text.text.trim().isEmpty;
    final textBubble = !recording && !recognizing && !noText;

    // 遮罩保留聊天底图；气泡、操作区和编辑工具栏分别按设计锚点承载。
    return Listener(
        // 续录开始后确认按钮会切换成录音区域，根监听器持续接管同一指针的结束事件。
        onPointerMove: (event) => updatePointerPosition(event.position),
        onPointerUp: (_) {
          if (_phase == _VoicePhase.recording) stopRecord();
        },
        onPointerCancel: (_) {
          if (_phase == _VoicePhase.recording) cancel();
        },
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (popped, _) {
            if (!popped) cancel();
          },
          child: Material(
              type: MaterialType.transparency,
              child: Stack(children: [
                Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: editing ? available : media.size.height,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [
                          0,
                          .87
                        ],
                                colors: [
                          colors.scrim,
                          colors.voiceBackdropEnd
                        ])))),
                Positioned(
                  top: textBubble
                      ? null
                      : math.max(
                          24,
                          media.size.height -
                              470 +
                              214 * editProgress -
                              (editing ? keyboard : 0)),
                  // 单行气泡高68，换算原顶部偏移后固定尾角下沿；换行向上展开，仍跟随同一键盘进度。
                  bottom: textBubble
                      ? 402 - 214 * editProgress + (editing ? keyboard : 0)
                      : null,
                  // 取消态外层仍居中，红色气泡固定102宽，不随设备宽度拉伸。
                  left: _cancelHover && recording
                      ? (media.size.width - 102) / 2
                      : 24,
                  right: _cancelHover && recording
                      ? (media.size.width - 102) / 2
                      : 24,
                  child: _bubble(colors, recording, recognizing, noText),
                ),
                if (!recording && !noText && editProgress < 1)
                  Positioned(
                      top: media.size.height - (recognizing ? 354 : 380),
                      left: 24,
                      right: 24,
                      child: Opacity(
                          opacity: 1 - editProgress,
                          child: Text('轻触文字区域可编辑',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: colors.onScrimSecondary,
                                  fontSize: 14,
                                  height: 20 / 14)))),
                if (recording)
                  ..._recordingArea(colors)
                else
                  ..._previewActions(colors, media, editing ? keyboard : 0,
                      editProgress, recognizing, noText),
                if (editing) _editingPanel(colors, keyboard, editProgress),
              ])),
        ));
  }

  /// 提示和底部弧形承载同一个取消手势，原有聊天内容仍透过遮罩可见。
  List<Widget> _recordingArea(AppColorScheme colors) => [
        Positioned(
            // 取消说明跟随气泡下方24像素，普通录音说明仍锚定底部弧形上方。
            top: _cancelHover ? MediaQuery.sizeOf(context).height - 352 : null,
            bottom: _cancelHover ? null : 152,
            left: 0,
            right: 0,
            child: Text(_cancelHover ? '松开 取消' : '松开预览，上滑取消',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    height: 20 / 14,
                    color: colors.onScrimSecondary))),
        Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 128,
            child: CustomPaint(
                painter: _VoiceArc(colors, _cancelHover),
                child: Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Align(
                        alignment: Alignment.topCenter,
                        child: Icon(AppIcons.mic,
                            color: colors.textTertiary, size: 24))))),
      ];

  /// 两种发送出口共享当前草稿，键盘展开时保持确认按钮与工具栏的相对位置。
  List<Widget> _previewActions(
          AppColorScheme colors,
          MediaQueryData media,
          double keyboard,
          double editProgress,
          bool recognizing,
          bool noText) =>
      [
        Positioned(
            top: media.size.height - 267 + 105 * editProgress - keyboard,
            left: 76 - 36 * editProgress,
            child: _action('chat.voice.cancel', '取消', AppIcons.recall,
                _sending ? null : cancel)),
        Positioned(
            top: media.size.height - 267 + 105 * editProgress - keyboard,
            right: 76 - 36 * editProgress,
            child: _action('chat.voice.audio_only', '仅发语音', AppIcons.voice11,
                _sending ? null : () => unawaited(_send(true)))),
        Positioned(
            bottom: 66 + keyboard + 8 * editProgress,
            left: (media.size.width - 88) / 2,
            child: _confirm(colors, recognizing, noText)),
        if (!recognizing && !noText && editProgress < 1)
          Positioned(
              bottom: 38,
              left: 0,
              right: 0,
              child: Opacity(
                  opacity: 1 - editProgress,
                  child: Text('按住 继续说话',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: colors.onScrimSecondary,
                          fontSize: 12,
                          height: 17 / 12)))),
        if (_poorNetwork)
          Positioned(
              top: media.size.height - 563,
              left: 0,
              right: 0,
              child: Center(
                  child: Container(
                      width: 214,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: colors.textPrimary,
                          borderRadius: BorderRadius.circular(21)),
                      child: Text('网络不佳，正在识别，请稍后',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: colors.onScrim))))),
      ];

  /// 气泡只展示当前录音或文本状态；未识别不移除原音发送入口。
  Widget _bubble(
      AppColorScheme colors, bool recording, bool recognizing, bool noText) {
    final color =
        noText || _cancelHover ? colors.danger : colors.voicePreviewBackground;
    final Widget content;
    if (recording) {
      content = SizedBox(
          height: 86,
          child: Center(
              child: AnimatedBuilder(
                  animation: _wave,
                  builder: (_, __) => CustomPaint(
                      size: Size(_cancelHover ? 54 : 108, 24),
                      painter: _VoiceWave(
                          _cancelHover
                              ? Color.alphaBlend(
                                  colors.scrim.withValues(alpha: .4),
                                  colors.danger)
                              : colors.primary,
                          _wave.value,
                          _waveFrom,
                          _waveTo)))));
    } else if (recognizing) {
      content = SizedBox(
          height: 86,
          child: Center(
              child: Text('•••',
                  style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 18,
                      letterSpacing: 2))));
    } else if (noText) {
      content = SizedBox(
          height: 60,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(AppIcons.info, size: 20, color: colors.onPrimary),
            const SizedBox(width: 8),
            Text('未识别出文字',
                style: TextStyle(color: colors.onPrimary, fontSize: 16))
          ]));
    } else {
      content = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 19),
          child: ExtendedTextField(
            specialTextSpanBuilder: ChatSpecialTextSpanBuilder(
              onTapUrl: (_) {},
              colorScheme: SemanticColorScheme.of(context),
              mapMarkdownMarkers: true,
            ),
            controller: _text,
            focusNode: _focus,
            maxLines: 5,
            minLines: 1,
            readOnly: !_editing,
            keyboardType: TextInputType.multiline,
            keyboardMode: _emoji
                ? ExtendedKeyboardMode.custom
                : _keyboardPanel!.returningToSystem
                    ? ExtendedKeyboardMode.returningToSystem
                    : ExtendedKeyboardMode.system,
            onTap: () {
              if (!_sending) {
                setState(() {
                  _editing = true;
                  _emoji = false;
                });
                _keyboardPanel!.showSystem(_focus);
              }
            },
            style: TextStyle(
                color: colors.textPrimary, fontSize: 16, height: 22 / 16),
            decoration: const InputDecoration(
                // 气泡承载编辑背景，不能继承全局输入框的白底和聚焦描边。
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none),
          ));
    }
    return Semantics(
        identifier: 'chat.voice.preview_text',
        child: CustomPaint(
            painter: _VoiceBubble(color),
            child: Padding(
                padding: const EdgeInsets.only(bottom: 8), child: content)));
  }

  /// 独立点击区域承载设计中的24像素图标及12像素标签，不采用默认IconButton间距。
  Widget _action(String id, String text, IconData icon, VoidCallback? onTap) =>
      Semantics(
          identifier: id,
          button: true,
          enabled: onTap != null,
          child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                  width: 74,
                  height: 56,
                  child: Column(children: [
                    Icon(icon, size: 24, color: context.appColors.onScrim),
                    const SizedBox(height: 8),
                    Text(text,
                        style: TextStyle(
                            fontSize: 12,
                            height: 17 / 12,
                            color: context.appColors.onScrim))
                  ]))));

  /// 点击确认文字，长按继续录音；Flutter手势竞争保证长按结束不会顺带触发文字发送。
  Widget _confirm(AppColorScheme colors, bool recognizing, bool noText) =>
      Semantics(
          identifier: 'chat.voice.confirm',
          button: true,
          enabled: !recognizing &&
              !_sending &&
              (!noText || _draft.remainingDurationMs >= 1000),
          label: '发送文字，长按继续说话',
          child: GestureDetector(
            onTap: recognizing || noText || _sending
                ? null
                : () => unawaited(_send(false)),
            onLongPressStart:
                recognizing || _sending || _draft.remainingDurationMs < 1000
                    ? null
                    : (details) =>
                        unawaited(startRecord(origin: details.globalPosition)),
            child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                    color: noText
                        ? colors.onScrim.withValues(alpha: .12)
                        : colors.onScrim,
                    shape: BoxShape.circle),
                alignment: Alignment.center,
                child: recognizing || _sending
                    ? SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                            strokeWidth: 4,
                            color: colors.primary,
                            backgroundColor:
                                colors.primary.withValues(alpha: .3)))
                    : Icon(AppIcons.check,
                        size: 36,
                        color: noText
                            ? colors.onScrim.withValues(alpha: .3)
                            : colors.primary)),
          ));

  /// 编辑面板跟随真实键盘Insets，表情使用已有目录，禁止使用设计键盘截图。
  Widget _editingPanel(
          AppColorScheme colors, double keyboard, double editProgress) =>
      Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRect(
                child: Align(
                    heightFactor: editProgress,
                    child: Container(
                        height: 44,
                        color: colors.surface,
                        child: Row(children: [
                          Semantics(
                              identifier: 'chat.voice.emoji',
                              button: true,
                              label: _emoji ? '显示键盘' : '表情',
                              child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    setState(() => _emoji = !_emoji);
                                    if (_emoji) {
                                      _keyboardPanel!.showEmoji(_focus);
                                    } else {
                                      _keyboardPanel!.showSystem(_focus);
                                    }
                                  },
                                  child: SizedBox(
                                      width: 52,
                                      height: 44,
                                      child: Icon(
                                          _emoji
                                              ? AppIcons.inputKeyboard
                                              : AppIcons.emoji1,
                                          size: 24,
                                          color: colors.textPrimary)))),
                          Semantics(
                              identifier: 'chat.voice.at',
                              button: true,
                              label: '输入@',
                              child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _insert('@'),
                                  child: SizedBox(
                                      width: 52,
                                      height: 44,
                                      child: Center(
                                          child: Icon(AppIcons.a,
                                              size: 24,
                                              color: colors.textPrimary))))),
                        ])))),
            if (_emoji || _keyboardPanel!.returningToSystem)
              SizedBox(
                  height: keyboard,
                  child: EmojiPicker(
                      voicePreview: true,
                      onEmojiClick: (data) => _insert(data['name'] as String),
                      onDeleteClick: _text.text.isEmpty
                          ? null
                          : () {
                              final selection = _text.selection;
                              if (selection.isValid && !selection.isCollapsed) {
                                _insert('');
                              } else {
                                _text.value =
                                    deleteMessageCharacterBefore(_text.value);
                              }
                            })),
            if (!_emoji && !_keyboardPanel!.returningToSystem)
              SizedBox(height: keyboard),
          ]));

  @override
  void dispose() {
    _closed = true;
    _recognition++;
    _networkHint?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _keyboardPanel?.dispose();
    unawaited(_recorder.cancelRecord().whenComplete(_recorder.dispose));
    unawaited(_draft.dispose());
    _text.dispose();
    _focus.dispose();
    _wave.dispose();
    super.dispose();
  }
}

/// 气泡背景与尾角属于同一容器，文字和波形不使用截图拼接。
class _VoiceBubble extends CustomPainter {
  const _VoiceBubble(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height - 8),
          const Radius.circular(12)))
      ..moveTo(size.width / 2 - 8, size.height - 8)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width / 2 + 8, size.height - 8)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_VoiceBubble old) => old.color != color;
}

/// 固定22条音量柱的位置，在真实音量约束的不规则目标之间原地插值，不横向推进。
class _VoiceWave extends CustomPainter {
  const _VoiceWave(this.color, this.phase, this.from, this.to);
  final Color color;

  /// 当前原地形变的进度，0至1；没有新音量时不循环变化。
  final double phase;

  /// 每条固定位置音量柱的起点，值在0至1内，不搬移历史样本。
  final List<double> from;

  /// 每条固定位置音量柱的目标，均不超过当前真实音量映射值。
  final List<double> to;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (var i = 0; i < 22; i++) {
      final height = 3 + 20 * (from[i] + (to[i] - from[i]) * phase);
      final x = i * size.width / 22 + 2;
      canvas.drawLine(Offset(x, (size.height - height) / 2),
          Offset(x, (size.height + height) / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_VoiceWave old) =>
      old.phase != phase ||
      old.from != from ||
      old.to != to ||
      old.color != color;
}

/// 底部弧形只表示当前按住区域，与波形气泡共用取消状态。
class _VoiceArc extends CustomPainter {
  const _VoiceArc(this.colors, this.cancel);
  final AppColorScheme colors;
  final bool cancel;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 44)
      ..quadraticBezierTo(size.width / 2, -40, size.width, 44)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: cancel
                      ? [
                          Color.alphaBlend(colors.scrim.withValues(alpha: .2),
                              colors.voiceBackdropEnd),
                          Color.alphaBlend(colors.scrim.withValues(alpha: .2),
                              colors.voiceBackdropEnd),
                        ]
                      : [
                          colors.onScrim.withValues(alpha: .6),
                          colors.onScrim.withValues(alpha: .8)
                        ])
              .createShader(Offset.zero & size));
    // 取消态为纯暗色弧形，设计中没有普通录音的浅色描边。
    if (cancel) return;
    final arc = Path()
      ..moveTo(0, 44)
      ..quadraticBezierTo(size.width / 2, -40, size.width, 44);
    canvas.drawPath(
        arc,
        Paint()
          ..color = colors.onScrim.withValues(alpha: .5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);
  }

  @override
  bool shouldRepaint(_VoiceArc old) =>
      old.colors != colors || old.cancel != cancel;
}
