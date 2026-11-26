import 'package:app_core/app_core.dart';
import 'package:app_service/app_service.dart';
import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_calls_uikit/src/manager/call_manager.dart';
import 'package:tencent_calls_uikit/src/state/global_state.dart'
    hide GroupCallMember, GroupCallMemberStatus;

import '../hint/timer_widget.dart';
import '../participant/call_video_view.dart';
import 'group_camera_capability.dart';
import 'group_call_controls.dart';
import 'group_call_scene.dart';
import 'group_call_member.dart';
import 'group_call_management_flow.dart';
import 'group_call_control_feedback.dart';
import 'package:tencent_calls_uikit/src/state/group_control_state.dart';
import 'group_call_projection.dart';

/// 群和临时多人通话的 SDK 适配页，媒体状态与邀请结果都来自当前场次。
class CallGridWidget extends StatefulWidget {
  const CallGridWidget({
    super.key,
    required this.controller,
    this.enableAITranscriber = false,
    this.isCurrentPresentation,
  });

  /// 上层统一持有 SDK 控制器，群画面使用独立成员视频视图。
  final CallCoreController controller;

  /// 保留公共配置兼容，当前群通话设计未展示转写入口。
  final bool enableAITranscriber;

  /// 原路由浮层的身份检查，SDK 尚未分配通话 ID 时仍能隔离旧页面。
  final bool Function()? isCurrentPresentation;

  @override
  State<CallGridWidget> createState() => _CallGridWidgetState();
}

/// 页面仅保存视图纹理、设备能力和弹层忙碌态，不推导远端主持权限。
class _CallGridWidgetState extends State<CallGridWidget> {
  /// 同一成员只绑定一个视频纹理，切换大画面时移动原节点。
  final Map<String, GlobalKey> _videoKeys = {};

  /// 真实原生能力未返回前隐藏翻转入口，不把移动设备默认为双摄像头。
  int? _cameraCount;

  /// 防止重复确认框及重复邀请；实际调用仍由 manager 做场次复核。
  bool _ending = false;

  /// 同一成员的一次邀请完成前不重复点击；场次校验仍由 manager 执行。
  final Set<String> _inviting = {};

  Listenable get _updates => Listenable.merge([
    CallStore.shared.state.activeCall,
    CallStore.shared.state.selfInfo,
    CallStore.shared.state.allParticipants,
    CallStore.shared.state.speakerVolumes,
    DeviceStore.shared.state.microphoneStatus,
    DeviceStore.shared.state.cameraStatus,
    DeviceStore.shared.state.currentAudioRoute,
    GlobalState.instance.groupCall,
    GlobalState.instance.groupControl,
    GlobalState.instance.groupCallRecording,
  ]);

  @override
  void initState() {
    super.initState();
    _loadCameraCapability();
  }

  /// 异步读取真实摄像头方向数量，页面销毁后不再更新入口可见性。
  Future<void> _loadCameraCapability() async {
    final count = await readGroupCameraCount();
    if (mounted) setState(() => _cameraCount = count);
  }

  /// 会控通知与 SDK 换场通知可能分帧到达，只消费当前场次的真实设备和权限。
  GroupControlState? get _control {
    final state = GlobalState.instance.groupControl.value;
    return state?.callId == CallStore.shared.state.activeCall.value.callId
        ? state
        : null;
  }

  /// 为本场成员按来源群解析姓名；临时多人通话只使用个人资料。
  List<GroupCallMember> _members(BuildContext context) =>
      projectGroupCallMembers(
        snapshot: GlobalState.instance.groupCall.value,
        call: CallStore.shared.state.activeCall.value,
        self: CallStore.shared.state.selfInfo.value,
        participants: CallStore.shared.state.allParticipants.value,
        microphoneOn:
            _control?.microphoneOn ??
            CallStore.shared.state.selfInfo.value.isMicrophoneOpened,
        cameraOn:
            _control?.cameraOn ??
            CallStore.shared.state.selfInfo.value.isCameraOpened,
        volumes: CallStore.shared.state.speakerVolumes.value,
        resolveName: (id, nickname, fallback) => AppUserAvatarScope.personName(
          context,
          id,
          nickname: nickname,
          fallback: fallback,
          groupId: CallStore.shared.state.activeCall.value.chatGroupId,
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _updates,
    builder: (context, _) {
      final self = CallStore.shared.state.selfInfo.value;
      final call = CallStore.shared.state.activeCall.value;
      final snapshot = GlobalState.instance.groupCall.value;
      final control = _control;
      final microphoneOn = control?.microphoneOn ?? self.isMicrophoneOpened;
      final cameraOn = control?.cameraOn ?? self.isCameraOpened;
      final ended = snapshot?.ended ?? false;
      final connected = !ended && self.status == CallParticipantStatus.accept;
      // 被叫本地 SDK 时钟可能从重入重新开始，录像偏移必须使用整场通话的起点。
      final recording = GlobalState.instance.groupCallRecording;
      final recordingStart = control?.connectedAtMs;
      final isRecording = recording.isRecording(call.callId);
      final canRecord =
          recording.available &&
          call.callId.isNotEmpty &&
          (isRecording || recordingStart != null);
      final incoming =
          !ended &&
          call.inviterId != self.id &&
          self.status == CallParticipantStatus.waiting;
      final inviterId = snapshot?.inviterId ?? call.inviterId;
      final members = _members(context);
      final title = snapshot?.groupName.isNotEmpty == true
          ? snapshot!.groupName
          : snapshot?.groupId.isNotEmpty == true
          ? '群通话'
          : '多人通话';
      return GroupCallScene(
        key: ValueKey(snapshot?.callId ?? call.callId),
        title: title,
        status: connected
            ? const TimerWidget(fontSize: 12)
            : Text(
                ended
                    ? snapshot?.canRetry == true
                          ? '呼叫超时，无人接听'
                          : '通话已结束'
                    : incoming
                    ? '等待接听'
                    : '正在呼叫…',
                style: TextStyle(
                  fontSize: 12,
                  color: context.appColors.onScrimSecondary,
                ),
              ),
        members: members,
        inviterId: inviterId,
        selfId: self.id,
        incoming: incoming,
        showMemberOrganizations:
            !ended &&
            inviterId == self.id &&
            self.status == CallParticipantStatus.waiting,
        video: call.mediaType == CallMediaType.video,
        onManage: () => _management().open(),
        videoBuilder: (id) =>
            !ended &&
                self.id.isNotEmpty &&
                members.any((member) => member.id == id && member.joined)
            ? CallVideoView(
                key: _videoKeys.putIfAbsent(id, GlobalKey.new),
                userId: id,
                local: id == self.id,
                groupCallId: id == self.id ? call.callId : null,
              )
            : const SizedBox.shrink(),
        onRetry: !ended && call.callId.isNotEmpty ? _invite : null,
        controls: GroupCallControls(
          incoming: incoming,
          connected: connected,
          ended: ended,
          retryable: snapshot?.canRetry ?? false,
          microphoneOn: !ended && microphoneOn,
          cameraOn: !ended && cameraOn,
          speakerOn:
              DeviceStore.shared.state.currentAudioRoute.value ==
              AudioRoute.speakerphone,
          canOpenMicrophone: control?.canOpenMicrophone == true,
          canOpenCamera: control?.canOpenCamera == true,
          microphonePending:
              control?.isDevicePending(
                self.id,
                GroupControlDevice.microphone,
              ) ==
              true,
          cameraPending:
              control?.isDevicePending(self.id, GroupControlDevice.camera) ==
              true,
          microphoneHint: groupDeviceHint(
            control,
            self.id,
            GroupControlDevice.microphone,
          ),
          cameraHint: groupDeviceHint(
            control,
            self.id,
            GroupControlDevice.camera,
          ),
          recording: isRecording,
          recordingPending: recording.isPending(call.callId),
          onRecord: canRecord
              ? () => _toggleRecording(call.callId, recordingStart)
              : null,
          canFlip: connected && cameraOn && (_cameraCount ?? 0) > 1,
          onEnd: () => _end(incoming: incoming, connected: connected),
          onAccept: CallManager.instance.accept,
          onMicrophone: () => _management().setDevice(
            self.id,
            GroupControlDevice.microphone,
            !microphoneOn,
          ),
          onCamera: () => _management().setDevice(
            self.id,
            GroupControlDevice.camera,
            !cameraOn,
          ),
          onSpeaker: CallManager.instance.toggleSpeaker,
          onFlip: CallManager.instance.flipCamera,
          onRetry: _retry,
        ),
      );
    },
  );

  /// 保存云端录制片段，换场或旧页面离开时不再显示关联提示。
  Future<void> _toggleRecording(String callId, int? connectedAtMs) {
    final epoch = CallManager.instance.sessionEpoch;
    bool isCurrent() =>
        mounted &&
        epoch == CallManager.instance.sessionEpoch &&
        (widget.isCurrentPresentation?.call() ?? true) &&
        GlobalState.instance.groupCall.value?.ended != true &&
        CallStore.shared.state.activeCall.value.callId == callId &&
        CallStore.shared.state.selfInfo.value.status ==
            CallParticipantStatus.accept;
    return AppServiceLocator.get<ActionGuard>().singleFlight(
      ('tim.call.recording', epoch, callId),
      () async {
        // 请求和结果提示共用守卫，快速重复点击也只产生一次提示。
        if (!isCurrent()) return;
        final recording = GlobalState.instance.groupCallRecording;
        final stopping = recording.isRecording(callId);
        try {
          final finished = await recording.toggle(
            callId: callId,
            connectedAtMs: connectedAtMs,
          );
          if (finished && isCurrent()) AppToast.show('录制完成');
        } catch (error, stack) {
          appLogger.error('保存云端录制片段失败', error: error, stackTrace: stack);
          if (isCurrent()) {
            AppToast.show(stopping ? '结束录制失败，请重试' : '开始录制失败，请重试');
          }
        }
      },
    );
  }

  /// 导航和会控交互统一绑定当前浮层，确认返回后仍由编排层复核代次与策略。
  GroupCallManagementFlow _management() => GroupCallManagementFlow(
    context: context,
    updates: _updates,
    readMembers: () => _members(context),
    onRetry: _invite,
    isCurrentPresentation: widget.isCurrentPresentation,
  );

  /// 弹框之后复核场次，不能把旧页面的结束动作应用到新来电。
  Future<void> _end({required bool incoming, required bool connected}) async {
    if (_ending) return;
    if (GlobalState.instance.groupCall.value?.ended == true) {
      CallManager.instance.dismissGroupCallResult();
      return;
    }
    _ending = true;
    final callId = CallStore.shared.state.activeCall.value.callId;
    try {
      if (connected) {
        final confirmed = await AppDialog.showAlert(
          title: '是否挂断当前通话？',
          content: '挂断后，仍在进行中的通话可以重新加入；已结束的通话需重新发起。',
          confirmText: '挂断',
          cancelText: '取消',
          semanticsIdentifier: 'call.group.hangupConfirm',
          theme: Theme.of(context),
        );
        if (confirmed != true) return;
      }
      if (!mounted ||
          CallStore.shared.state.activeCall.value.callId != callId) {
        return;
      }
      if (incoming) {
        await CallManager.instance.reject();
      } else {
        await CallManager.instance.hangup();
      }
    } finally {
      _ending = false;
    }
  }

  /// 当前场次重新邀请只调用公开 invite，失败保留原邀请状态。
  Future<void> _invite(String id) async {
    if (!_inviting.add(id)) return;
    final callId = CallStore.shared.state.activeCall.value.callId;
    try {
      final result = await CallManager.instance.invite([
        id,
      ], expectedCallId: callId);
      if (mounted && result.errorCode != 0) {
        AppToast.show('重新呼叫失败（${result.errorCode}），请重试');
      }
    } finally {
      _inviting.remove(id);
    }
  }

  /// 按已保存的发起参数创建新场次，失败留在结果页而不恢复旧 callId。
  Future<void> _retry() async {
    final result = await CallManager.instance.retryGroupCall();
    if (mounted && result.errorCode != 0) {
      AppToast.show('发起通话失败（${result.errorCode}），请重试');
    }
  }
}
