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
      'call_assets/hangup.png',
      incoming
          ? l10n.callRejectAction
          : accepted
              ? l10n.callHangUp
              : l10n.callCancel,
      onEnd,
    );
    final accept = _button(
      context,
      'accept',
      'call_assets/dialing.png',
      l10n.callAcceptAction,
      onAccept,
    );
    // 语音被叫只提供接听和拒绝，视频被叫保留上排设备开关。
    if (!video) {
      return _row(
        incoming
            ? [end, accept]
            : [_microphone(context), end, _speaker(context)],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row([_microphone(context), _speaker(context), _camera(context)]),
        const SizedBox(height: 32),
        _row(
          incoming
              ? [end, const SizedBox.shrink(), accept]
              : [
                  const SizedBox.shrink(),
                  end,
                  // 翻转图只包含字形，沿用现有独立圆底和 32 像素图标尺寸。
                  _button(
                    context,
                    'flip',
                    'call_assets/switch_camera.png',
                    l10n.callSwitchCamera,
                    cameraOn ? onFlip : null,
                    background: context.appColors.scrim.withValues(alpha: .3),
                    imageSize: 32,
                  ),
                ],
        ),
      ],
    );
  }

  /// 视频两排共用 34 逻辑像素边距，语音按来电角色保留原有列位。
  Widget _row(List<Widget> children) => Padding(
        padding: EdgeInsets.symmetric(
            horizontal: video ? 34 : (incoming ? 0 : 22)),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children.map((child) => Expanded(child: child)).toList()),
      );

  Widget _microphone(BuildContext context) {
    final on = microphoneOn;
    final text = AppLocalization.of(context);
    return _button(
      context,
      'microphone',
      on ? 'call_assets/mute.png' : 'call_assets/mute_on.png',
      on ? text.callMicrophoneIsOn : text.callMicrophoneIsOff,
      onMicrophone,
    );
  }

  Widget _speaker(BuildContext context) {
    final on = speakerOn;
    final text = AppLocalization.of(context);
    return _button(
      context,
      'speaker',
      on ? 'call_assets/handsfree_on.png' : 'call_assets/handsfree.png',
      on ? text.callSpeakerIsOn : text.callSpeakerIsOff,
      onSpeaker,
    );
  }

  Widget _camera(BuildContext context) {
    final on = cameraOn;
    final text = AppLocalization.of(context);
    return _button(
      context,
      'camera',
      on ? 'call_assets/camera_on.png' : 'call_assets/camera_off.png',
      on ? text.callCameraIsOn : text.callCameraIsOff,
      onCamera,
    );
  }

  /// 原版实心素材自带圆底，按当前通话页的 60 像素按钮绘制。
  Widget _button(
    BuildContext context,
    String id,
    String imagePath,
    String label,
    VoidCallback? onTap, {
    Color background = Colors.transparent,
    double imageSize = 60,
  }) {
    final colors = context.appColors;
    return ControlsButton(
      imgUrl: imagePath,
      imgHeight: imageSize,
      dimension: 60,
      tips: label,
      semanticsIdentifier: 'call.$id',
      backgroundColor: background,
      textColor: colors.onScrim,
      onTap: onTap,
    );
  }
}
