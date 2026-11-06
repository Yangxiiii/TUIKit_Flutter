import 'dart:math' as math;
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import '../participant/call_participant_pane.dart';

/// 单个画面的展示事实：用户标识、备注优先的名称、头像地址、独立机构职务子标题及对应端摄像头状态。
typedef CallSceneUser = ({
  String id,
  String name,
  String avatarUrl,
  String subtitle,
  bool cameraOn
});

/// 以已解析事实展示单聊画面；不订阅 SDK，使生产和本地预览共用同一布局。
class CallScene extends StatelessWidget {
  const CallScene(
      {super.key,
      required this.self,
      this.remote,
      required this.video,
      required this.accepted,
      required this.localInMainView,
      required this.onSwap,
      required this.videoBuilder,
      this.combinedVideo,
      required this.controls,
      required this.hint,
      required this.timer});

  /// 本端展示资料与摄像头事实。
  final CallSceneUser self;

  /// 对端资料尚未返回时不伪造姓名或机构。
  final CallSceneUser? remote;

  /// 当前通话媒体类型。
  final bool video;

  /// 当前是否已经接通。
  final bool accepted;

  /// 主次互换只影响布局。
  final bool localInMainView;

  /// 通知持有者交换画面。
  final VoidCallback onSwap;

  /// 生产传入腾讯视频视图，预览只传本地画面。
  final Widget Function(String userId) videoBuilder;

  /// 等待接听时可以使用腾讯组合视图显示本端预览。
  /// 接通后的大小画面由本组件固定，摄像头切换只改变对应画面的内容。
  final Widget? combinedVideo;

  /// 由同一媒体与角色事实生成的操作区域。
  final Widget controls;

  /// 当前连接或网络提示。
  final Widget hint;

  /// SDK 时长或本地预览时长。
  final Widget timer;

  @override
  Widget build(BuildContext context) {
    final main = video && (!accepted || localInMainView) ? self : remote;
    final small = localInMainView ? remote : self;
    final padding = MediaQuery.paddingOf(context);
    // 画面位于底层；资料、状态、操作和小窗分别叠加，摄像头关闭不影响另一端。
    return Stack(fit: StackFit.expand, children: [
      if (combinedVideo == null)
        _pane(main, remote,
            video: video, main: true, showAvatar: accepted && video)
      else
        combinedVideo!,
      if (video)
        IgnorePointer(
            child: DecoratedBox(
                decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                context.appColors.scrim.withValues(alpha: .8),
                Colors.transparent,
                Colors.transparent,
                context.appColors.scrim.withValues(alpha: .8)
              ],
              stops: const [
                0,
                .2,
                .4,
                1
              ]),
        ))),
      // 语音始终显示资料，视频接通后让主画面保持完整。
      if (!video || !accepted) _userInfo(context, remote),
      if (video && accepted && combinedVideo == null)
        _CallSmallWindow(
          onSwap: onSwap,
          child:
              _pane(small, remote, video: true, main: false, showAvatar: true),
        ),
      if (!accepted)
        Positioned(
            top: video
                ? (MediaQuery.sizeOf(context).height - 20) / 2
                : MediaQuery.sizeOf(context).height * .578,
            left: 24,
            right: 24,
            child: Center(child: hint)),
      // 设备操作固定在底部；顶部计时仍取同一 SDK 连接时长。
      Positioned(
          left: 0,
          right: 0,
          bottom: math.max(video ? 32 : 84, padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // 用户确认网络不佳也保留操作区；提示随实际内容高度排在按钮上方，不互相覆盖。
            if (accepted)
              Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Center(child: hint)),
            controls,
          ])),
      Positioned(
          top: padding.top + 16,
          left: 80,
          right: 80,
          child: Center(child: timer)),
    ]);
  }

  /// 无画面背景取对方头像；本端与远端分别检查自己的摄像头，互换后仍遵守该规则。
  Widget _pane(CallSceneUser? info, CallSceneUser? remote,
      {required bool video, required bool main, required bool showAvatar}) {
    return CallParticipantPane(
      userId: info?.id ?? '',
      name: _name(info),
      avatarUrl: info?.avatarUrl ?? '',
      hasVideo: video && info?.cameraOn == true,
      video: video && info != null && info.id.isNotEmpty
          ? videoBuilder(info.id)
          : const SizedBox.shrink(),
      isMainView: main,
      showAvatar: showAvatar,
      backgroundUserId: main ? remote?.id : null,
      backgroundName: main ? _name(remote) : null,
      backgroundAvatarUrl: main ? remote?.avatarUrl : null,
    );
  }

  /// 资料使用消息列表同源头像并独立展示子标题；缺少真实资料时保留布局空间。
  Widget _userInfo(BuildContext context, CallSceneUser? remote) => Positioned(
        top: video
            ? MediaQuery.paddingOf(context).top + 80
            : MediaQuery.sizeOf(context).height * 250 / 844,
        left: 24,
        right: 24,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppUserAvatar(
              userId: remote?.id,
              name: _name(remote),
              url: remote?.avatarUrl,
              size: video ? 72 : 96),
          const SizedBox(height: 20),
          Text(_name(remote),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 20,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: context.appColors.onScrim)),
          // 子标题独立展示；生产资料缺失时留白，不能用姓名或虚构机构补齐。
          if (remote?.subtitle.isNotEmpty == true) ...[
            const SizedBox(height: 16),
            Text(remote!.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16,
                    height: 22 / 16,
                    fontWeight: FontWeight.w500,
                    color: context.appColors.callStatusText)),
          ] else
            const SizedBox(height: 38),
        ]),
      );

  String _name(CallSceneUser? info) => info?.name ?? '';
}

/// 接通后统一处理小画面的拖动和互换，避免手势落到原生视频纹理。
class _CallSmallWindow extends StatefulWidget {
  const _CallSmallWindow({required this.onSwap, required this.child});

  /// 由通话页交换主次参与者，拖动位置留在当前小画面。
  final VoidCallback onSwap;

  /// 当前小画面的头像或视频。
  final Widget child;

  @override
  State<_CallSmallWindow> createState() => _CallSmallWindowState();
}

/// 在安全区内记录小画面的拖动位置。
class _CallSmallWindowState extends State<_CallSmallWindow> {
  /// 记录用户拖动后的左上角坐标，尺寸变化后重新限制在安全区。
  Offset? _position;

  @override
  Widget build(BuildContext context) {
    const width = 98.0;
    const height = 211.0;
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final maxLeft = math.max(0.0, size.width - width);
    final maxTop = math.max(padding.top, size.height - padding.bottom - height);
    final position = _position ?? Offset(maxLeft - 8, padding.top + 62);
    // 拖动和屏幕尺寸变化后都把小画面约束在可点击区域内。
    final left = position.dx.clamp(0.0, maxLeft).toDouble();
    final top = position.dy.clamp(padding.top, maxTop).toDouble();
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Semantics(
        identifier: 'call.swap',
        label: AppLocalization.of(context)
            .resolve('chat.uikit.callSwapViews', '交换主次画面'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSwap,
          onPanUpdate: (details) => setState(() {
            _position = Offset(left, top) + details.delta;
          }),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
