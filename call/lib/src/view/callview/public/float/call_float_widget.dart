import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';

import '../controls/single_call_controls_widget.dart';
import '../hint/hint_widget.dart';
import '../hint/timer_widget.dart';
import '../participant/call_video_view.dart';
import 'call_scene.dart';

/// 在共享通话界面中嵌入腾讯视频，保持接通后主次画面的位置。
class CallFloatWidget extends StatefulWidget {
  const CallFloatWidget(
      {super.key, required this.controller, this.enableAITranscriber = false});

  /// SDK 布局控制器仍由上层创建和释放，群聊及系统画中画继续复用。
  final CallCoreController controller;

  /// 保留既有配置兼容；本次单聊设计不显示 AI 入口。
  final bool enableAITranscriber;

  @override
  State<CallFloatWidget> createState() => _CallFloatWidgetState();
}

/// 映射 SDK 状态，保存独立布局下的主次位置。
class _CallFloatWidgetState extends State<CallFloatWidget> {
  /// 每个参与者独占一个渲染视图，交换大小画面时移动现有纹理。
  final _localVideoKey = GlobalKey();
  final _remoteVideoKey = GlobalKey();

  /// 只在用户点击小画面时交换主次位置。
  bool _localInMainView = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([
          CallStore.shared.state.activeCall,
          CallStore.shared.state.selfInfo,
          CallStore.shared.state.allParticipants,
          DeviceStore.shared.state.cameraStatus,
        ]),
        builder: (context, _) {
          final state = CallStore.shared.state;
          final self = state.selfInfo.value;
          final call = state.activeCall.value;
          final remote = state.allParticipants.value
              .where((p) => p.id != self.id)
              .firstOrNull;
          final video = call.mediaType == CallMediaType.video;
          final accepted = self.status == CallParticipantStatus.accept;
          // 腾讯单聊模板通过邀请资料查找远端，等参与者标识齐全后再挂载。
          final canRenderVideo = video &&
              self.id.isNotEmpty &&
              call.inviterId.isNotEmpty &&
              call.inviteeIds.isNotEmpty &&
              self.status != CallParticipantStatus.none;
          final selfUser = _user(
            self,
            cameraOn: canRenderVideo &&
                DeviceStore.shared.state.cameraStatus.value == DeviceStatus.on,
          );
          final remoteUser = remote == null
              ? null
              : _user(remote,
                  cameraOn: canRenderVideo && remote.isCameraOpened);
          return CallScene(
            key: ValueKey(call.callId),
            self: selfUser,
            remote: remoteUser,
            video: video,
            accepted: accepted,
            localInMainView: _localInMainView,
            onSwap: () => setState(() => _localInMainView = !_localInMainView),
            // 接通后固定使用双槽布局。开关摄像头时由画面组件切换头像和视频。
            combinedVideo: !accepted && selfUser.cameraOn
                ? CallCoreView(
                    key: ValueKey(call.callId), controller: widget.controller)
                : null,
            videoBuilder: (id) => accepted && canRenderVideo
                ? CallVideoView(
                    key: id == self.id ? _localVideoKey : _remoteVideoKey,
                    userId: id,
                    local: id == self.id)
                : const SizedBox.shrink(),
            controls: const SingleCallControlsWidget(),
            hint: const HintWidget(),
            timer: const TimerWidget(fontSize: 16, fontWeight: FontWeight.w600),
          );
        },
      );

  /// 映射 SDK 资料，画面尚不可渲染时按头像状态展示。
  CallSceneUser _user(CallParticipantInfo info, {required bool cameraOn}) => (
        id: info.id,
        name: info.remark.isNotEmpty
            ? info.remark
            : info.name.isNotEmpty
                ? info.name
                : info.id,
        avatarUrl: info.avatarURL,
        // 腾讯基础资料没有可核实的机构职务字段，不映射猜测的自定义键。
        subtitle: '',
        cameraOn: cameraOn,
      );
}
