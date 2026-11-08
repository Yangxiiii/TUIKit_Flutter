import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_calls_uikit/src/manager/call_manager.dart';

import '../hint/timer_widget.dart';
import '../participant/call_participant_pane.dart';
import '../participant/call_video_view.dart';

/// 浮窗操作只在原浮层有效。单聊语音主叫允许使用尚未分配标识的当前通话。
bool matchesFloatingCall({
  required String expectedId,
  required CallInfo call,
  required CallParticipantInfo self,
  required bool isCurrentPresentation,
}) {
  if (!isCurrentPresentation || self.status == CallParticipantStatus.none) {
    return false;
  }
  if (expectedId.isNotEmpty) return call.callId == expectedId;
  // SDK 可能在对方接听时才填充 callId，主叫在此之前也能收起或取消。
  return call.mediaType == CallMediaType.audio &&
      call.chatGroupId.isEmpty &&
      call.inviteeIds.length == 1 &&
      self.id.isNotEmpty &&
      call.inviterId == self.id;
}

/// 应用内单聊悬浮窗，接通后固定两路画面的位置，音频展示头像和时长。
class CallCompactWidget extends StatefulWidget {
  const CallCompactWidget({
    super.key,
    required this.onRestore,
    required this.isCurrentPresentation,
  });

  /// 被叫从小窗接听成功时恢复同一通话的全屏界面。
  final VoidCallback onRestore;

  /// 当前卡片是否仍属于原通话浮层。
  final bool Function() isCurrentPresentation;

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
            id: remote?.id ??
                (call.inviterId == self.id
                    ? call.inviteeIds.firstOrNull
                    : call.inviterId),
            name: name,
            avatarUrl: remote?.avatarURL,
            incoming: call.inviterId != self.id,
            duration: connected ? call.duration.toInt() : null,
            onWaitingAction: () => _handleWaitingAction(call.callId),
          );
        },
      );

  /// 只操作卡片绑定的原通话。接听成功后展开，取消由 SDK 结束事件关闭浮层。
  Future<void> _handleWaitingAction(String callId) async {
    final state = CallStore.shared.state;
    final call = state.activeCall.value;
    final self = state.selfInfo.value;
    if (call.mediaType != CallMediaType.audio ||
        self.status != CallParticipantStatus.waiting ||
        !matchesFloatingCall(
          expectedId: callId,
          call: call,
          self: self,
          isCurrentPresentation: widget.isCurrentPresentation(),
        )) {
      return;
    }
    if (call.inviterId == self.id) {
      await CallManager.instance.hangup();
      return;
    }
    if (await CallManager.instance.accept() &&
        mounted &&
        widget.isCurrentPresentation() &&
        state.activeCall.value.callId == callId) {
      widget.onRestore();
    }
  }

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

/// 绘制单聊语音小窗的卡片外壳，裁剪圆角内的画面并保留外侧阴影。
class CallCompactAudioSurface extends StatelessWidget {
  const CallCompactAudioSurface({super.key, required this.child});

  /// 小窗正文或承载正文的通话路由，均限制在卡片圆角内。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(12);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: colors.scrim.withValues(alpha: .16),
            offset: const Offset(0, 8),
            blurRadius: 36,
          ),
        ],
      ),
      // 阴影位于裁剪外层，旧通话页或原生纹理无法画到圆角外。
      child: ClipRRect(
        borderRadius: radius,
        child: ColoredBox(color: colors.surface, child: child),
      ),
    );
  }
}

/// 单聊语音浮窗展示同源头像，以及主叫取消、被叫接听或已接通时长。
class CallCompactAudioContent extends StatelessWidget {
  const CallCompactAudioContent({
    super.key,
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.incoming,
    required this.duration,
    required this.onWaitingAction,
  });

  /// 语音卡片的边长，单位为逻辑像素。
  static const dimension = 80.0;

  /// 设计稿的顶部坐标 118 减去状态栏高度 45.76。
  static const topGap = 72.24;

  /// 参与者标识用于共享头像缓存。
  final String? id;
  final String name;
  final String? avatarUrl;

  /// 等待接听时决定底部是接听还是取消操作。
  final bool incoming;

  /// 接通时为已通话秒数，等待时为空。
  final int? duration;

  /// 操作当前等待中的呼叫，接通后只展示时长。
  final VoidCallback onWaitingAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elapsed = duration;
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 等待标记只覆盖头像，接通后显示原头像。
          ClipOval(
            child: Stack(
              alignment: Alignment.center,
              children: [
                AppUserAvatar(name: name, userId: id, url: avatarUrl, size: 36),
                if (elapsed == null) ...[
                  Positioned.fill(child: ColoredBox(color: colors.scrim)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 3,
                    children: List.filled(
                      3,
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.callWaitingIndicator,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(dimension: 4),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (elapsed != null)
            Text(
              const TimerWidget().formatDuration(elapsed),
              style: TextStyle(
                  fontSize: 12, height: 16 / 12, color: colors.primary),
            )
          else
            _buildWaitingAction(context),
        ],
      ),
    );
  }

  /// 操作行与浮窗外层的恢复手势分开，读屏可分别触发。
  Widget _buildWaitingAction(BuildContext context) {
    final text = AppLocalization.of(context);
    final colors = context.appColors;
    final color = incoming ? colors.primary : colors.danger;
    return Semantics(
      identifier: incoming ? 'call.compact.accept' : 'call.compact.cancel',
      container: true,
      button: true,
      label: incoming ? text.callAcceptAction : text.callCancel,
      onTap: onWaitingAction,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onWaitingAction,
        excludeFromSemantics: true,
        child: ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 字体图标自身带留白，放大字形而保持设计的 16 像素占位。
              Transform.scale(
                scale: 1.25,
                child: Icon(incoming ? AppIcons.phone3 : AppIcons.phone2,
                    size: 16, color: color),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  incoming
                      ? text.resolve('chat.uikit.callWaitingAnswer', '待接听')
                      : text.callCancel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, height: 16 / 12, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
