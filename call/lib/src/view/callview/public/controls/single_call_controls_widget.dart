import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_calls_uikit/src/manager/call_manager.dart';
import 'single_call_controls.dart';

/// 按 SDK 的媒体、主被叫与设备事实绘制单聊操作区，不维护另一份开关状态。
class SingleCallControlsWidget extends StatelessWidget {
  const SingleCallControlsWidget({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([
          CallStore.shared.state.activeCall,
          CallStore.shared.state.selfInfo,
          DeviceStore.shared.state.microphoneStatus,
          DeviceStore.shared.state.currentAudioRoute,
          DeviceStore.shared.state.cameraStatus,
        ]),
        builder: (context, _) {
          final call = CallStore.shared.state.activeCall.value;
          final self = CallStore.shared.state.selfInfo.value;
          if (call.mediaType == null ||
              self.status == CallParticipantStatus.none) {
            return const SizedBox.shrink();
          }
          final accepted = self.status == CallParticipantStatus.accept;
          final incoming = !accepted && self.id != call.inviterId;
          final video = call.mediaType == CallMediaType.video;
          return SingleCallControls(
            video: video,
            incoming: incoming,
            accepted: accepted,
            microphoneOn: DeviceStore.shared.state.microphoneStatus.value ==
                DeviceStatus.on,
            speakerOn: DeviceStore.shared.state.currentAudioRoute.value ==
                AudioRoute.speakerphone,
            cameraOn:
                DeviceStore.shared.state.cameraStatus.value == DeviceStatus.on,
            onEnd: incoming
                ? CallManager.instance.reject
                : CallManager.instance.hangup,
            onAccept: CallManager.instance.accept,
            onMicrophone: CallManager.instance.toggleMicrophone,
            onSpeaker: CallManager.instance.toggleSpeaker,
            onCamera: CallManager.instance.toggleCamera,
            onFlip: () => CallManager.instance
                .switchCamera(!DeviceStore.shared.state.isFrontCamera.value),
          );
        },
      );
}
