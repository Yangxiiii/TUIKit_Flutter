import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';

import '../hint/timer_widget.dart';
import '../participant/call_participant_pane.dart';
import '../participant/call_video_view.dart';

/// 应用内单聊悬浮窗，接通后固定两路画面的位置，音频展示头像和时长。
class CallCompactWidget extends StatefulWidget {
  const CallCompactWidget({super.key});

  @override
  State<CallCompactWidget> createState() => _CallCompactWidgetState();
}

/// 持有应用内悬浮窗的 SDK 布局控制器，随悬浮窗路由释放。
class _CallCompactWidgetState extends State<CallCompactWidget> {
  final _controller = CallCoreController.create();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([
          CallStore.shared.state.activeCall,
          CallStore.shared.state.selfInfo,
          CallStore.shared.state.allParticipants,
          DeviceStore.shared.state.cameraStatus
        ]),
        builder: (context, _) {
          final state = CallStore.shared.state;
          final self = state.selfInfo.value;
          final call = state.activeCall.value;
          final remote = state.allParticipants.value
              .where((p) => p.id != self.id)
              .firstOrNull;
          final connected = self.status == CallParticipantStatus.accept;
          final name = remote == null
              ? ''
              : remote.remark.isNotEmpty
                  ? remote.remark
                  : remote.name.isNotEmpty
                      ? remote.name
                      : remote.id;
          if (call.mediaType == CallMediaType.video) {
            return _buildVideo(context, call, self, remote, name);
          }
          return CallCompactAudioContent(
            id: remote?.id,
            name: name,
            avatarUrl: remote?.avatarURL,
            duration: connected ? call.duration.toInt() : null,
          );
        },
      );

  /// 按全屏尺寸布局腾讯视图后再缩小，保留右上角小画面。
  Widget _buildVideo(
    BuildContext context,
    CallInfo call,
    CallParticipantInfo self,
    CallParticipantInfo? remote,
    String name,
  ) {
    // 邀请资料还未齐全时沿用头像，避免 SDK 使用空的受邀者列表。
    final canRenderVideo = self.id.isNotEmpty &&
        call.inviterId.isNotEmpty &&
        call.inviteeIds.isNotEmpty &&
        self.status != CallParticipantStatus.none;
    final accepted = self.status == CallParticipantStatus.accept;
    final localCameraOn = canRenderVideo &&
        DeviceStore.shared.state.cameraStatus.value == DeviceStatus.on;
    final remoteCameraOn = canRenderVideo && remote?.isCameraOpened == true;
    // 接通后的悬浮窗固定主次位置，关闭摄像头只隐藏对应的纹理。
    if (accepted || !localCameraOn) {
      return CallCompactVideoContent(
        main: _pane(remote, name,
            cameraOn: accepted && remoteCameraOn,
            bindVideo: accepted && canRenderVideo),
        small: _pane(self, self.name,
            cameraOn: localCameraOn,
            bindVideo: accepted && canRenderVideo,
            local: true),
      );
    }

    // 组合布局按全屏排好后缩小。点击和拖动由悬浮窗外层接收。
    final size = MediaQuery.sizeOf(context);
    return IgnorePointer(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.topRight,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: CallCoreView(
            key: ValueKey(call.callId),
            controller: _controller,
          ),
        ),
      ),
    );
  }

  /// 每个画面只根据自己的摄像头决定显示头像还是视频。
  Widget _pane(CallParticipantInfo? info, String name,
          {required bool cameraOn,
          required bool bindVideo,
          bool local = false}) =>
      CallParticipantPane(
        userId: info?.id ?? '',
        name: name,
        avatarUrl: info?.avatarURL ?? '',
        hasVideo: cameraOn,
        isMainView: false,
        video: bindVideo && info != null && info.id.isNotEmpty
            ? CallVideoView(
                key: ValueKey(info.id), userId: info.id, local: local)
            : const SizedBox.shrink(),
      );
}

/// 共享应用内小窗的主次画面布局，两个位置可分别显示头像或视频。
class CallCompactVideoContent extends StatelessWidget {
  const CallCompactVideoContent(
      {super.key, required this.main, required this.small});

  /// 对端画面填充主区域。
  final Widget main;

  /// 本端画面显示在右上角。
  final Widget small;

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        main,
        Positioned(
          right: 4,
          top: 4,
          width: 25,
          height: 54,
          child:
              ClipRRect(borderRadius: BorderRadius.circular(4), child: small),
        ),
      ]);
}

/// 单聊音频小窗的共享内容，保留消息列表同源头像和通话时长。
class CallCompactAudioContent extends StatelessWidget {
  const CallCompactAudioContent({
    super.key,
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.duration,
  });

  /// 参与者标识用于共享头像缓存。
  final String? id;
  final String name;
  final String? avatarUrl;

  /// 接通时为已通话秒数，等待时为空。
  final int? duration;

  @override
  Widget build(BuildContext context) => Material(
        color: context.appColors.surface,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AppUserAvatar(name: name, userId: id, url: avatarUrl, size: 36),
          const SizedBox(height: 8),
          Text(
            duration != null
                ? const TimerWidget().formatDuration(duration!)
                : AppLocalization.of(context)
                    .resolve('chat.uikit.callWaitingAnswer', '待接听'),
            style: TextStyle(
                fontSize: 12, height: 1.5, color: context.appColors.primary),
          ),
        ]),
      );
}
