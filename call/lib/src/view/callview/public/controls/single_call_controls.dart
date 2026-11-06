import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import '../../core/common/widget/controls_button.dart';

/// 只呈现单聊控件；生产和预览传入相同事实及动作，按钮不自行订阅 SDK。
class SingleCallControls extends StatelessWidget {
  const SingleCallControls(
      {super.key,
      required this.video,
      required this.incoming,
      required this.accepted,
      required this.microphoneOn,
      required this.speakerOn,
      required this.cameraOn,
      required this.onEnd,
      required this.onAccept,
      required this.onMicrophone,
      required this.onSpeaker,
      required this.onCamera,
      required this.onFlip});

  /// 当前媒体是否为视频。
  final bool video;

  /// 当前是否为尚未接听的被叫。
  final bool incoming;

  /// 当前是否已经连接。
  final bool accepted;

  /// 本端麦克风事实。
  final bool microphoneOn;

  /// 当前路由是否为扬声器。
  final bool speakerOn;

  /// 本端摄像头事实。
  final bool cameraOn;

  /// 拒绝、取消或挂断入口。
  final VoidCallback onEnd;

  /// 接听当前邀请。
  final VoidCallback onAccept;

  /// 切换本端麦克风。
  final VoidCallback onMicrophone;

  /// 切换声音路由。
  final VoidCallback onSpeaker;

  /// 切换本端摄像头。
  final VoidCallback onCamera;

  /// 翻转本端镜头。
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalization.of(context);
    final end = _button(
        context,
        'end',
        AppIcons.phone2,
        incoming
            ? l10n.callRejectAction
            : accepted
                ? l10n.callHangUp
                : l10n.callCancel,
        onEnd,
        background: context.appColors.danger,
        iconSize: 42);
    final accept = _button(
        context, 'accept', AppIcons.phone3, l10n.callAcceptAction, onAccept,
        background: context.appColors.success);
    // 语音被叫只提供接听和拒绝，视频被叫保留上排设备开关。
    if (!video) {
      return _row(
          incoming
              ? [end, accept]
              : [_microphone(context), end, _speaker(context)],
          horizontalPadding: incoming ? 0 : 22);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _row([_microphone(context), _speaker(context), _camera(context)]),
      const SizedBox(height: 32),
      _row(incoming
          ? [end, const SizedBox(width: 72), accept]
          : [
              const SizedBox(width: 72),
              end,
              // shortcut: 字体库缺少双循环箭头，沿用 SDK 翻转图标，补齐 AppIcons 后替换。
              _button(context, 'flip', null, l10n.callSwitchCamera,
                  cameraOn ? onFlip : null,
                  imagePath: 'call_assets/switch_camera.png'),
            ]),
    ]);
  }

  Widget _row(List<Widget> children, {double horizontalPadding = 22}) =>
      Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children.map((child) => Expanded(child: child)).toList()),
      );

  Widget _microphone(BuildContext context) {
    final on = microphoneOn;
    final text = AppLocalization.of(context);
    return _button(context, 'microphone', on ? AppIcons.mic : AppIcons.micOff,
        on ? text.callMicrophoneIsOn : text.callMicrophoneIsOff, onMicrophone,
        active: on);
  }

  Widget _speaker(BuildContext context) {
    final on = speakerOn;
    final text = AppLocalization.of(context);
    return _button(
        context,
        'speaker',
        on ? AppIcons.voiceOn : AppIcons.voiceOff,
        on ? text.callSpeakerIsOn : text.callSpeakerIsOff,
        onSpeaker,
        active: on,
        iconSize: 36);
  }

  Widget _camera(BuildContext context) {
    final on = cameraOn;
    final text = AppLocalization.of(context);
    return _button(
        context,
        'camera',
        on ? AppIcons.cameraOn : AppIcons.videoOff,
        on ? text.callCameraIsOn : text.callCameraIsOff,
        onCamera,
        active: on);
  }

  /// 开启设备使用白底深色图标，关闭设备使用半透明深底，始终取 SDK 实际状态。
  Widget _button(BuildContext context, String id, IconData? icon, String label,
      VoidCallback? onTap,
      {bool active = false,
      Color? background,
      String imagePath = '',
      double iconSize = 40}) {
    final colors = context.appColors;
    return ControlsButton(
      icon: icon,
      imgUrl: imagePath,
      iconSize: iconSize,
      tips: label,
      semanticsIdentifier: 'call.$id',
      backgroundColor: background ??
          (active ? colors.onScrim : colors.scrim.withValues(alpha: .3)),
      imgColor: icon == null
          ? null
          : active
              ? colors.textPrimary
              : colors.onScrim,
      textColor: colors.onScrim,
      onTap: onTap,
    );
  }
}
