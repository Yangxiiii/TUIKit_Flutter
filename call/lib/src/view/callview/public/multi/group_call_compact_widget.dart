import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_calls_uikit/src/manager/call_manager.dart';

import '../float/call_compact_widget.dart';

/// 群和临时多人统一使用 80 像素白卡，等待时提供取消或接听，接通后展示时长。
class GroupCallCompactWidget extends StatelessWidget {
  const GroupCallCompactWidget(
      {super.key,
      required this.onRestore,
      required this.isCurrentPresentation});

  /// 接听成功后恢复同一通话全屏。
  final VoidCallback onRestore;

  /// 防止旧浮层对后续通话执行操作。
  final bool Function() isCurrentPresentation;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([
          CallStore.shared.state.activeCall,
          CallStore.shared.state.selfInfo,
          CallStore.shared.state.allParticipants
        ]),
        builder: (context, _) {
          final state = CallStore.shared.state;
          final call = state.activeCall.value;
          final self = state.selfInfo.value;
          final inviter = state.allParticipants.value
              .where((member) => member.id == call.inviterId)
              .firstOrNull;
          final avatar = inviter ?? self;
          return CallCompactAudioContent(
              id: avatar.id,
              name: avatar.name,
              avatarUrl: avatar.avatarURL,
              incoming: call.inviterId != self.id,
              duration: self.status == CallParticipantStatus.accept
                  ? call.duration
                  : null,
              onWaitingAction: () => _waitingAction(call.callId));
        },
      );

  /// 操作前后都复核原浮层；已接通状态不再执行等待按钮动作。
  Future<void> _waitingAction(String callId) async {
    final state = CallStore.shared.state;
    final self = state.selfInfo.value;
    if (self.status != CallParticipantStatus.waiting ||
        !matchesFloatingCall(
            expectedId: callId,
            call: state.activeCall.value,
            self: self,
            isCurrentPresentation: isCurrentPresentation(),
            isGroup: true)) {
      return;
    }
    if (state.activeCall.value.inviterId == self.id) {
      await CallManager.instance.hangup();
    } else if (await CallManager.instance.accept() &&
        isCurrentPresentation() &&
        state.activeCall.value.callId == callId) {
      onRestore();
    }
  }
}
