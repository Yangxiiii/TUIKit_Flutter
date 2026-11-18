import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../../core/common/widget/controls_button.dart';

/// 群/多人通话的两排操作区；只接收真实设备与生命周期，不模拟录制成功。
class GroupCallControls extends StatelessWidget {
  const GroupCallControls({
    super.key,
    required this.incoming,
    required this.connected,
    required this.ended,
    required this.retryable,
    required this.microphoneOn,
    required this.cameraOn,
    required this.canFlip,
    required this.onEnd,
    required this.onAccept,
    required this.onMicrophone,
    required this.onCamera,
    required this.onFlip,
    required this.onRetry,
    this.speakerOn = false,
    this.onSpeaker,
    this.canOpenMicrophone = true,
    this.canOpenCamera = true,
    this.microphonePending = false,
    this.cameraPending = false,
    this.microphoneHint,
    this.cameraHint,
  });

  /// 尚未接听的被叫只显示拒绝与接听。
  final bool incoming;

  /// 接通后统一显示挂断，不沿用设计样例中冲突的取消文案。
  final bool connected;

  /// 已结束快照不得继续操纵设备。
  final bool ended;

  /// 只有生命周期控制器允许时才能重新发起新场次。
  final bool retryable;

  /// SDK的本端麦克风、摄像头实际状态。
  final bool microphoneOn, cameraOn;

  /// 由 SDK 当前音频路由决定扬声器是否开启。
  final bool speakerOn;

  /// 已知策略只限制开启；成员仍可关闭已经开启的本人设备。
  final bool canOpenMicrophone, canOpenCamera;

  /// 等待真实设备结果时禁止重复提交，不提前翻转实际状态图标。
  final bool microphonePending, cameraPending;

  /// 当前会控给出的限制、等待或失败原因。
  final String? microphoneHint, cameraHint;

  /// 设备确认具备前后摄像头时允许显示翻转入口。
  final bool canFlip;

  /// 拒绝、取消或确认挂断当前场次。
  final VoidCallback onEnd;

  /// 接听当前有效邀请。
  final VoidCallback onAccept;

  /// 本人设备操作复用权限检查和 SDK 错误处理。
  final VoidCallback onMicrophone, onCamera;

  /// 切换本机听筒和免提，与群会控权限无关。
  final VoidCallback? onSpeaker;

  /// 请求 SDK 切换前后摄像头，无媒体执行入口的预览可传空。
  final VoidCallback? onFlip;

  /// 创建新通话，不能恢复旧callId。
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalization.of(context);
    if (incoming && !ended) {
      return Padding(
          padding: const EdgeInsets.only(left: 60, right: 72),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _button(context, 'reject', AppIcons.phone2, '拒绝', onEnd,
                background: context.appColors.danger),
            _button(context, 'accept', AppIcons.phone3, '接听', onAccept,
                background: context.appColors.success),
          ]));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // 上排集中本机设备，扬声器显示当前播放路由。
      _row([
        _button(
            context,
            'microphone',
            microphoneOn ? AppIcons.mic : AppIcons.micOff,
            microphoneOn ? '麦克风已开' : '麦克风已关',
            ended || microphonePending || (!microphoneOn && !canOpenMicrophone)
                ? null
                : onMicrophone,
            active: microphoneOn,
            pending: microphonePending,
            hint: microphoneHint),
        _button(
          context,
          'speaker',
          speakerOn ? AppIcons.voiceOn : AppIcons.voiceOff,
          speakerOn ? l10n.callSpeakerIsOn : l10n.callSpeakerIsOff,
          ended ? null : onSpeaker,
          active: speakerOn && !ended,
        ),
        _button(
            context,
            'camera',
            cameraOn ? AppIcons.cameraOn : AppIcons.videoOff,
            cameraOn ? '摄像头已开' : '摄像头已关',
            ended || cameraPending || (!cameraOn && !canOpenCamera)
                ? null
                : onCamera,
            active: cameraOn,
            pending: cameraPending,
            hint: cameraHint),
      ]),
      const SizedBox(height: 40),
      // 下排保留禁用的云端录制入口，挂断始终居中。
      _row([
        _recordUnavailable(context),
        _button(
          context,
          retryable ? 'retry' : 'end',
          retryable ? AppIcons.phone3 : AppIcons.phone2,
          retryable
              ? '重新呼叫'
              : connected
                  ? '挂断'
                  : ended
                      ? '关闭'
                      : '取消',
          retryable ? onRetry : onEnd,
          background:
              retryable ? context.appColors.success : context.appColors.danger,
        ),
        if (canFlip && connected && cameraOn && !ended)
          ControlsButton(
            dimension: 60,
            labelSpacing: 8,
            labelMaxLines: 1,
            semanticsIdentifier: 'call.group.flip',
            // 字体库缺少双循环翻转字形，复用 SDK 既有同语义资源。
            imgUrl: 'call_assets/switch_camera_group.png',
            tips: '翻转摄像头',
            textColor: context.appColors.onScrim,
            backgroundColor: context.appColors.groupCallControlBackground,
            // 摄像头开关尚未确认时不能同时切换镜头。
            onTap: cameraPending ? null : onFlip,
          )
        else
          const SizedBox(width: 60),
      ]),
    ]);
  }

  Widget _row(List<Widget> children) => Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 322),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: children
                  .map((child) => SizedBox(width: 70, child: child))
                  .toList(),
            )),
      );

  Widget _button(BuildContext context, String id, IconData icon, String label,
      VoidCallback? onTap,
      {bool active = false,
      Color? background,
      bool pending = false,
      String? hint}) {
    final colors = context.appColors;
    final button = Opacity(
      opacity: onTap == null ? .45 : 1,
      child: ControlsButton(
        icon: icon,
        iconSize: 32,
        dimension: 60,
        labelSpacing: incoming ? 22 : 8,
        labelMaxLines: 1,
        tips: label,
        semanticsIdentifier: 'call.group.$id',
        backgroundColor: background ??
            (active ? colors.onScrim : colors.groupCallControlBackground),
        imgColor: active ? colors.textPrimary : colors.onScrim,
        textColor: colors.onScrim,
        onTap: onTap,
      ),
    );
    return Tooltip(
        message: hint ?? (pending ? '正在等待设备确认' : label),
        child: Stack(alignment: Alignment.topCenter, children: [
          button,
          if (pending)
            Positioned(
                top: 18,
                child: Semantics(
                    label: '正在等待设备确认',
                    liveRegion: true,
                    child: SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: colors.onScrim)))),
        ]));
  }

  Widget _recordUnavailable(BuildContext context) => Semantics(
        identifier: 'call.group.record',
        button: true,
        enabled: false,
        label: '录制通话，云端录制接口尚未接入',
        child: Tooltip(
          message: '云端录制接口尚未接入，暂不可用',
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.appColors.groupCallControlBackground),
              child: Text('暂不可用',
                  style: TextStyle(
                      color: context.appColors.onScrimSecondary, fontSize: 10)),
            ),
            const SizedBox(height: 8),
            Text('录制通话',
                style: TextStyle(
                    color: context.appColors.onScrimSecondary,
                    fontSize: 14,
                    height: 20 / 14)),
          ]),
        ),
      );
}
