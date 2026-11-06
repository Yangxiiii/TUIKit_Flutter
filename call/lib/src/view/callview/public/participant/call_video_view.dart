import 'package:flutter/widgets.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';

/// 将单个参与者绑定到腾讯原生视频视图，由外层根据摄像头状态切换可见性。
class CallVideoView extends StatelessWidget {
  const CallVideoView({super.key, required this.userId, required this.local});

  /// 纹理对应的参与者，关闭摄像头期间仍保留该绑定。
  final String userId;

  /// 本端绑定现有预览，远端绑定已接通的订阅。
  final bool local;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: VideoView(
          key: ValueKey(userId),
          onViewCreated: (viewId) {
            if (viewId == 0) return;
            // 沿用腾讯组合视图的绑定入口，沿用当前通话及设备状态。
            if (local) {
              TUICallEngine.instance.callExperimentalAPI({
                'api': 'setLocalView',
                'params': {'videoView': viewId},
              });
            } else {
              TUICallEngine.instance.startRemoteView(userId, viewId);
            }
          },
        ),
      );
}
