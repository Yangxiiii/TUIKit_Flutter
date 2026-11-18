import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/widgets.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';
import '../../../../state/global_state.dart';

/// 将单个参与者绑定到腾讯原生视频视图，由外层根据摄像头状态切换可见性。
class CallVideoView extends StatelessWidget {
  const CallVideoView(
      {super.key, required this.userId, required this.local, this.groupCallId});

  /// 纹理对应的参与者，关闭摄像头期间仍保留该绑定。
  final String userId;

  /// 本端绑定现有预览，远端绑定已接通的订阅。
  final bool local;

  /// 群通话的本端视图绑定真实场次，可用作开启摄像头的原生参数。
  final String? groupCallId;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: VideoView(
          // 同一账号换场时重建原生视图，避免复用已有视图却拿不到新场次的创建回调。
          key: ValueKey((groupCallId, userId)),
          onViewCreated: (viewId) {
            if (viewId == 0) return;
            // 沿用腾讯组合视图的绑定入口，沿用当前通话及设备状态。
            if (local) {
              final callId = groupCallId;
              if (callId != null) {
                final state = CallStore.shared.state;
                if (state.activeCall.value.callId != callId ||
                    state.selfInfo.value.id != userId) {
                  return;
                }
                GlobalState.instance.groupLocalVideoView.value =
                    (callId: callId, userId: userId, viewId: viewId);
              }
              TUICallEngine.instance.callExperimentalAPI({
                'api': 'setLocalView',
                'params': {'videoView': viewId},
              });
            } else {
              TUICallEngine.instance.startRemoteView(userId, viewId);
            }
          },
          onViewDisposed: (viewId) {
            // 旧视图迟到销毁不能清除同一场次刚创建的新纹理。
            final global = GlobalState.instance;
            if (global.groupLocalVideoView.value ==
                (callId: groupCallId, userId: userId, viewId: viewId)) {
              global.groupLocalVideoView.value = null;
            }
          },
        ),
      );
}
