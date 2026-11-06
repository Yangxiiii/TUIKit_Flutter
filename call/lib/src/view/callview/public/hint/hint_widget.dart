import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'call_hint_messages.dart';

/// 从 SDK 连接时长及双方网络状态生成提示，不在 build 中启动计时器。
class HintWidget extends StatelessWidget {
  const HintWidget({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([
          CallStore.shared.state.activeCall,
          CallStore.shared.state.selfInfo,
          CallStore.shared.state.networkQualities
        ]),
        builder: (context, _) {
          final state = CallStore.shared.state;
          final call = state.activeCall.value;
          final self = state.selfInfo.value;
          final text = AppLocalization.of(context);
          final List<String> hints = [];
          if (self.status == CallParticipantStatus.waiting) {
            hints.add(self.id == call.inviterId
                ? text.callWaitingForInvitationAcceptance
                : call.mediaType == CallMediaType.video
                    ? text.callInvitedToVideoCall
                    : text.callInvitedToAudioCall);
          } else if (self.status == CallParticipantStatus.accept) {
            // 已接通展示 3 秒；恢复通话页面时仍沿用 SDK 时长，不重新倒数。
            if (call.duration < 3) hints.add(text.callConnected);
            final qualities = state.networkQualities.value;
            if (_badNetwork(qualities[self.id])) {
              hints.add(text.callSelfNetworkLowQuality);
            }
            if (qualities.entries.any(
                (entry) => entry.key != self.id && _badNetwork(entry.value))) {
              hints.add(text.callOtherPartyNetworkLowQuality);
            }
          }
          return CallHintMessages(
              messages: hints,
              waiting: self.status == CallParticipantStatus.waiting);
        },
      );

  bool _badNetwork(NetworkQuality? quality) =>
      quality == NetworkQuality.bad ||
      quality == NetworkQuality.veryBad ||
      quality == NetworkQuality.down;
}
