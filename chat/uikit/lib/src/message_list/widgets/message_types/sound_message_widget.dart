import 'dart:async';
import 'dart:math' as math;
import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart'
    show AppIcons, AppColorBuildContext, AppColorScheme;

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/audio_player/audio_player.dart';
import 'package:tuikit_atomic_x/base_component/base_component.dart';
import 'package:tencent_chat_uikit/src/message_list/message_list_config.dart';
import 'package:tencent_chat_uikit/src/message_list/widgets/message_status_mixin.dart';
import '../../utils/asr_display_manager.dart';
import '../../utils/voice_message_media.dart';
import '../message_actions_scope.dart';

/// 展示语音气泡及单聊识别入口，播放状态由共享播放器协调。
class SoundMessageWidget extends StatefulWidget {
  /// 腾讯消息模型，音频时长按秒读取，ASR沿用SDK缓存。
  final MessageInfo message;

  /// 己方语音不展示未播放红点及接收方转换提示。
  final bool isSelf;

  /// 宿主消息行可用逻辑宽度，供旧气泡与大字体布局约束。
  final double maxWidth;

  /// 播放操作前通知宿主收起输入等临时界面。
  final VoidCallback? onTap;

  /// 沿用气泡统一菜单入口。
  final VoidCallback? onLongPress;

  /// 当前会话的SDK列表，作为同消息异步请求的作用域。
  final MessageListStore? messageListStore;

  /// 只标记主气泡边界，不能包含识别附件以免回执和菜单锚点偏移。
  final GlobalKey? bubbleKey;

  /// 沿用宿主的回执、时间与合并转发展示配置。
  final MessageListConfigProtocol config;

  /// 单聊按MasterGo展示，其他场景保留既有气泡布局。
  final String? conversationID;

  /// 与文字附件和消息菜单共用状态，避免重复维护转换及过期事实。
  final AsrDisplayManager? asrDisplayManager;

  /// 点击转换时交给气泡统一动作入口，不在展示组件另起识别请求。
  final VoidCallback? onConvertToText;

  /// 合并转发详情沿用原展示，不添加单聊动作入口。
  final bool isInMergedDetailView;

  /// Optional override for bubble background color (used for highlight animation)
  ///
  /// 气泡背景颜色的可选覆盖（用于高亮动画）
  final Color? bubbleColor;

  const SoundMessageWidget({
    super.key,
    required this.message,
    required this.isSelf,
    required this.maxWidth,
    required this.config,
    this.onTap,
    this.onLongPress,
    this.messageListStore,
    this.bubbleKey,
    this.isInMergedDetailView = false,
    this.bubbleColor,
    this.conversationID,
    this.asrDisplayManager,
    this.onConvertToText,
  });

  @override
  State<SoundMessageWidget> createState() => _SoundMessageWidgetState();
}

/// 下载只驱动局部忙碌态，播放与暂停位置由AudioPlayer保持唯一事实来源。
class _SoundMessageWidgetState extends State<SoundMessageWidget>
    with MessageStatusMixin, WidgetsBindingObserver {
  late AudioPlayer _audioPlayer;
  final _fallbackGuard = ActionGuard();

  /// 仅驱动加载图标，实际重复操作由ActionGuard保护。
  bool _isDownloading = false;

  /// 仅供无列表管理器的独立气泡使用，有管理器时不维护第二份状态。
  bool _localPlayed = false;

  /// 独立气泡没有列表管理器时保留已确认的资源过期状态。
  bool _localExpired = false;
  bool get _isC2C =>
      widget.conversationID?.startsWith('c2c_') == true ||
      widget.message.conversationType == ConversationType.c2c;
  bool get _isPlaying => _audioPlayer.isPlaying;
  Duration get _currentPosition =>
      Duration(milliseconds: _audioPlayer.getCurrentPosition());
  bool get _expired =>
      widget.asrDisplayManager?.isExpired(widget.message.msgID) ??
      _localExpired;
  bool get _played =>
      widget.asrDisplayManager?.wasPlayed(widget.message.msgID) ?? _localPlayed;
  ActionGuard get _guard =>
      MessageActionsScope.maybeOf(context)?.actionGuard ?? _fallbackGuard;
  Object get _requestScope =>
      widget.asrDisplayManager ?? widget.messageListStore ?? this;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.asrDisplayManager?.addListener(_refreshVoiceState);
    _audioPlayer =
        AudioPlayer.createInstance().setListener(_AudioPlayerListenerImpl(
      refresh: () {
        if (mounted) setState(() {});
      },
      started: () {
        if (mounted && !widget.isSelf) _markPlayed();
      },
      failure: (_) {
        if (mounted) {
          setState(() {});
          Toast.error(context, '语音播放失败，请重试');
        }
      },
    ));
    // 确定性预览不触发SDK；在线会话从腾讯本地消息恢复播放标记。
    if (_isC2C &&
        !widget.isSelf &&
        LoginStore.shared.loginState.loginStatus == LoginStatus.logined) {
      final id = widget.message.msgID;
      unawaited(VoiceMessageMedia(widget.message).wasPlayed().then((played) {
        if (mounted && played && widget.message.msgID == id) {
          if (widget.asrDisplayManager case final AsrDisplayManager manager) {
            manager.markPlayed(id);
          } else {
            setState(() => _localPlayed = true);
          }
        }
      }).catchError((Object _) {}));
    }
  }

  void _refreshVoiceState() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(SoundMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asrDisplayManager != widget.asrDisplayManager) {
      oldWidget.asrDisplayManager?.removeListener(_refreshVoiceState);
      widget.asrDisplayManager?.addListener(_refreshVoiceState);
    }
  }

  /// 原生已经开始播放或资源明确过期后才清除红点，元数据写入不覆盖ASR缓存。
  void _markPlayed() {
    if (widget.asrDisplayManager case final AsrDisplayManager manager) {
      manager.markPlayed(widget.message.msgID);
    } else {
      _localPlayed = true;
    }
    if (LoginStore.shared.loginState.loginStatus == LoginStatus.logined) {
      unawaited(VoiceMessageMedia(widget.message)
          .markPlayed()
          .catchError((Object _) {}));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_audioPlayer.pause().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    widget.asrDisplayManager?.removeListener(_refreshVoiceState);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_audioPlayer.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isC2C && !widget.isInMergedDetailView) {
      return _buildVoiceMessage(context);
    }
    final colors = SemanticColorScheme.of(context);

    final statusAndTimeWidgets = buildStatusAndTimeWidgets(
      message: widget.message,
      isSelf: widget.isSelf,
      colors: colors,
      isShowTimeInBubble: widget.config.isShowTimeInBubble,
      enableReadReceipt: widget.config.enableReadReceipt,
      isInMergedDetailView: widget.isInMergedDetailView,
    );

    // The ASR (voice → text) bubble used to be rendered here as a sibling
    // of the voice bubble inside a Column. That made the read-receipt
    // and status-icon (placed by MessageItem with
    // CrossAxisAlignment.end) drift to the bottom of the column whenever
    // the ASR bubble was present, see Bug-956459. The ASR bubble is now
    // built by `MessageAttachmentBuilder` and rendered by `MessageItem`
    // *outside* the row that holds the receipt — see
    // `lib/src/message_list/widgets/message_attachments.dart`.
    //
    // ASR（语音→文字）气泡以前是在 Column 内作为语音气泡的兄弟元素渲染的。那样的话，每当 ASR 气泡出现时，由 MessageItem 使用 CrossAxisAlignment.end
    // 放置的已读回执和状态图标会漂移到列的底部，见 Bug-956459。ASR 气泡现在由 `MessageAttachmentBuilder` 构建，并由 `MessageItem` 渲染在放置回执的行
    // *外部* —— 参见 `lib/src/message_list/widgets/message_attachments.dart`。
    return GestureDetector(
      onTap: _handleTap,
      onLongPress: widget.onLongPress,
      child: Container(
        key: widget.bubbleKey,
        constraints: BoxConstraints(
          maxWidth: widget.maxWidth * 0.7,
        ),
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: _getBubbleColor(colors),
          borderRadius: _getBubbleBorderRadius(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment:
              widget.isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            _buildSoundContent(colors),
            if (statusAndTimeWidgets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: statusAndTimeWidgets,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _handleTap() => unawaited(_playSoundMessage());

  /// 气泡与侧边标记分属不同容器，回执仍锚定主气泡而非识别附件底部。
  Widget _buildVoiceMessage(BuildContext context) {
    final colors = context.appColors;
    final payload = widget.message.messagePayload as AudioMessagePayload?;
    final duration = (payload?.audioDuration ?? 0).clamp(0, 60);
    // 设计2秒参考气泡宽80，60秒上限182；短音频留足字形空间。
    final labelStyle = DefaultTextStyle.of(context)
        .style
        .copyWith(fontSize: 16, height: 22 / 16, color: colors.textPrimary);
    final label = TextPainter(
        text: TextSpan(text: '$duration″', style: labelStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context))
      ..layout();
    final width =
        math.max(80 + (duration - 2).clamp(0, 58) * 102 / 58, 60 + label.width);
    final height = math.max(40.0, label.height + 16);
    final converting =
        widget.asrDisplayManager?.isConverting(widget.message.msgID) ?? false;
    final showConvert = !widget.isSelf &&
        !_expired &&
        !converting &&
        (payload?.asrText?.isEmpty ?? true) &&
        widget.onConvertToText != null;
    // 主气泡保持回执锚点，红点和转换入口属于气泡右侧的独立状态区。
    final bubble = _voiceBubble(colors, duration, width, height, labelStyle);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      bubble,
      if (!widget.isSelf && !_played)
        Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Semantics(
                identifier: 'chat.voice.unheard.${widget.message.msgID}',
                label: '未播放',
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: colors.danger, shape: BoxShape.circle),
                    child: const SizedBox(width: 8, height: 8)))),
      if (_expired || showConvert)
        Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Semantics(
                identifier:
                    'chat.voice.${_expired ? 'expired' : 'convert'}.${widget.message.msgID}',
                button: showConvert,
                child: GestureDetector(
                  onTap: showConvert ? widget.onConvertToText : null,
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: colors.outline.withValues(alpha: .5),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(_expired ? '已过期' : '转文字',
                          style: TextStyle(
                              fontSize: 10,
                              height: 14 / 10,
                              color: colors.textTertiary))),
                ))),
    ]);
  }

  /// 主气泡宽度按时长与实际字体测量，播放动画只改变图标，不移动时长或回执。
  Widget _voiceBubble(AppColorScheme colors, int duration, double width,
      double height, TextStyle labelStyle) {
    return Semantics(
        identifier: 'chat.voice.bubble.${widget.message.msgID}',
        button: true,
        label: '$duration秒语音',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onLongPress: widget.onLongPress,
          child: Container(
            key: widget.bubbleKey,
            width: width,
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
                color: widget.bubbleColor ??
                    (widget.isSelf
                        ? colors.chatOutgoingBubble
                        : colors.chatIncomingBubble),
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              if (_isDownloading)
                SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: colors.primary))
              else
                AnimatedOpacity(
                    opacity: _isPlaying &&
                            (_audioPlayer.getCurrentPosition() ~/ 250).isOdd
                        ? .45
                        : 1,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(AppIcons.voice,
                        size: 20, color: colors.textPrimary)),
              const SizedBox(width: 8),
              Text('$duration″', style: labelStyle),
            ]),
          ),
        ));
  }

  Widget _buildSoundContent(SemanticColorScheme colorsTheme) {
    final int soundDuration =
        (widget.message.messagePayload as AudioMessagePayload?)
                ?.audioDuration ??
            0;

    return SizedBox(
      width: 160,
      child: Row(
        children: [
          Icon(
            widget.isSelf ? Icons.volume_up : Icons.volume_down,
            color: widget.isSelf
                ? colorsTheme.textColorAntiPrimary
                : colorsTheme.textColorPrimary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                8,
                (index) {
                  final height = 4.0 + (index % 3) * 4.0;
                  final isActive = _isPlaying && (index % 2 == 0);

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 2,
                    height: isActive ? height * 1.5 : height,
                    decoration: BoxDecoration(
                      color: widget.isSelf
                          ? colorsTheme.textColorAntiPrimary
                          : colorsTheme.textColorPrimary,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _isPlaying
                ? _formatDuration(_currentPosition.inSeconds)
                : _formatDuration(soundDuration),
            style: FontScheme.caption3Medium.copyWith(
              color: widget.isSelf
                  ? colorsTheme.textColorAntiPrimary
                  : colorsTheme.textColorPrimary,
            ),
          ),
          if (_isDownloading)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    widget.isSelf
                        ? colorsTheme.textColorAntiPrimary
                        : colorsTheme.textColorPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 下载、播放和错误提示共用同消息守卫，退出后的结果不再启动播放。
  Future<void> _playSoundMessage() => _guard.singleFlight<void>(
          ('chat.voice.play', _requestScope, widget.message.msgID), () async {
        final userId = LoginStore.shared.loginState.loginUserInfo?.userID;
        widget.onTap?.call();
        if (_expired) {
          Toast.error(context, '语音已过期');
          _markPlayed();
          setState(() {});
          return;
        }
        setState(() => _isDownloading = true);
        try {
          final path = await _guard.singleFlight<String>(
              ('chat.voice.download', _requestScope, widget.message.msgID),
              () => VoiceMessageMedia(widget.message).load());
          // 下载完成后再次核对账号，避免旧会话在账号切换的下一帧启动播放。
          if (!mounted ||
              LoginStore.shared.loginState.loginUserInfo?.userID != userId) {
            return;
          }
          if (!_isC2C && _audioPlayer.isPlaying) {
            await _audioPlayer.stop();
          } else {
            await _audioPlayer.play(path);
          }
        } on VoiceMediaFailure catch (error) {
          if (!mounted) return;
          if (error.expired) {
            if (widget.asrDisplayManager case final AsrDisplayManager manager) {
              manager.setExpired(widget.message.msgID);
            } else {
              _localExpired = true;
            }
            _markPlayed();
          }
          Toast.error(context, error.expired ? '语音已过期' : '语音播放失败，请重试');
        } catch (_) {
          if (mounted) Toast.error(context, '语音播放失败，请重试');
        } finally {
          if (mounted) setState(() => _isDownloading = false);
        }
      });

  String _formatDuration(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Color _getBubbleColor(SemanticColorScheme colorsTheme) {
    if (widget.bubbleColor != null) return widget.bubbleColor!;
    if (widget.isSelf) {
      return colorsTheme.bgColorBubbleOwn;
    } else {
      return colorsTheme.bgColorBubbleReciprocal;
    }
  }

  BorderRadius _getBubbleBorderRadius() {
    if (widget.isSelf) {
      return const BorderRadius.only(
        topLeft: Radius.circular(18),
        topRight: Radius.circular(18),
        bottomLeft: Radius.circular(18),
        bottomRight: Radius.circular(0),
      );
    } else {
      return const BorderRadius.only(
        topLeft: Radius.circular(18),
        topRight: Radius.circular(18),
        bottomLeft: Radius.circular(0),
        bottomRight: Radius.circular(18),
      );
    }
  }
}

/// 把原生状态变化转为界面重建，不在气泡中再保存一份播放位置。
class _AudioPlayerListenerImpl extends AudioPlayerListener {
  _AudioPlayerListenerImpl(
      {required this.refresh, required this.started, required this.failure});

  /// 组件仍存活时重建图标及状态，位置始终由播放器维护。
  final VoidCallback refresh;

  /// 只在原生开始或恢复时标记已播放，进度回调不重复写缓存。
  final VoidCallback started;

  /// 将原生失败交给当前组件反馈，不把失败当作播放完成。
  final ValueChanged<String> failure;
  @override
  void onPlay() {
    started();
    refresh();
  }

  @override
  void onPause() => refresh();
  @override
  void onResume() {
    started();
    refresh();
  }

  @override
  void onProgressUpdate(int position, int duration) => refresh();
  @override
  void onCompletion() => refresh();
  @override
  void onError(String error) => failure(error);
}
