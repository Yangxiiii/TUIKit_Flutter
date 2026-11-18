import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_calls_uikit/src/state/global_state.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/float/call_float_widget.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/call_grid_widget.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/pip/call_pip_widget.dart';

/// 依据真实通话形态选择单聊、群聊或系统画中画。
class CallView extends StatefulWidget {
  /// 系统画中画复用 SDK 布局。
  final bool isPipMode;

  /// 宿主转写配置，不改变媒体生命周期。
  final bool enableAITranscriber;

  /// 将当前通话浮层身份透传给群管理，避免等待阶段的空 ID 混淆场次。
  final bool Function()? isCurrentPresentation;

  const CallView({
    super.key,
    this.enableAITranscriber = false,
    this.isPipMode = false,
    this.isCurrentPresentation,
  });

  @override
  State<CallView> createState() => _CallViewState();
}

/// 路由存续期间持有 SDK 布局控制器，结束快照仅影响页面选择。
class _CallViewState extends State<CallView> {
  late final CallCoreController controller;

  @override
  void initState() {
    controller = CallCoreController.create();
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            CallStore.shared.state.activeCall,
            GlobalState.instance.groupCall
          ]),
          builder: (context, child) {
            final activeCall = CallStore.shared.state.activeCall.value;
            if (widget.isPipMode) {
              controller.setLayoutTemplate(CallLayoutTemplate.pip);
              return CallPipWidget(controller: controller);
            }

            if (GlobalState.instance.groupCall.value != null ||
                activeCall.chatGroupId.isNotEmpty ||
                activeCall.inviteeIds.length > 1) {
              controller.setLayoutTemplate(CallLayoutTemplate.grid);
              return CallGridWidget(
                controller: controller,
                enableAITranscriber: widget.enableAITranscriber,
                isCurrentPresentation: widget.isCurrentPresentation,
              );
            }

            controller.setLayoutTemplate(CallLayoutTemplate.float);
            return CallFloatWidget(
              controller: controller,
              enableAITranscriber: widget.enableAITranscriber,
            );
          },
        ),
      ),
    );
  }
}
