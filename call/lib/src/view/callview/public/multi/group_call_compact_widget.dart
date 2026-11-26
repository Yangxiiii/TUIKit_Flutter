import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_calls_uikit/src/manager/call_manager.dart';
import 'package:tencent_calls_uikit/src/state/global_state.dart';

import '../float/call_compact_widget.dart';

/// 群及临时多人共用小窗，超时结果只展示状态并由外层手势恢复全屏。
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
          CallStore.shared.state.allParticipants,
          GlobalState.instance.groupCall,
        ]),
        builder: (context, _) {
          final result = GlobalState.instance.groupCall.value;
          if (result case final timeout? when timeout.canRetry) {
            return _buildTimeoutCard(context, timeout);
          }
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

  /// 已结束的 SDK 通话不再显示等待动画、接听按钮或计时。
  Widget _buildTimeoutCard(BuildContext context, GroupCallSnapshot result) {
    final caller = result.members
        .where((member) => member.id == result.inviterId)
        .firstOrNull;
    final name = AppUserAvatarScope.personName(
      context,
      result.inviterId,
      fallback: caller?.name,
      groupId: result.groupId,
    );
    return CallCompactAudioSurface(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppUserAvatar(
            userId: result.inviterId,
            name: name,
            url: caller?.avatarURL,
            size: 36,
          ),
          const SizedBox(height: 8),
          Text(
            '呼叫超时',
            style: TextStyle(fontSize: 12, color: context.appColors.textPrimary),
          ),
        ],
      ),
    );
  }

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
