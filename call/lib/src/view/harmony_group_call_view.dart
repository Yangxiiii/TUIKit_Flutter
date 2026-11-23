import 'package:app_ui/app_ui.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../state/group_control_state.dart';
import 'callview/public/hint/timer_widget.dart';
import 'callview/public/multi/group_call_control_feedback.dart';
import 'callview/public/multi/group_call_controls.dart';
import 'callview/public/multi/group_call_member.dart';
import 'callview/public/multi/group_call_scene.dart';
import 'callview/public/multi/group_camera_capability.dart';

/// 原生 SDK 当前成员的只读快照，保留值相等性以免轮询重建宫格。
typedef HarmonyGroupMember = ({
  String id,
  String name,
  String avatarUrl,
  bool joined,
  bool microphone,
  bool camera,
  int volume,
});

/// 当前场次的多人展示数据。群来源只用于界面文案。
typedef HarmonyGroupCall = ({
  bool chatGroup,
  String inviterId,
  List<HarmonyGroupMember> members,
});

/// 将鸿蒙通道的多人数据转换为展示值，复用未变化的成员列表。
HarmonyGroupCall? decodeHarmonyGroup(
  Map<String, Object?> snapshot,
  HarmonyGroupCall? previous,
) {
  final raw = snapshot['members'];
  if (raw is! List) return null;
  final members = <HarmonyGroupMember>[
    for (final row in raw)
      if (row is Map)
        if (row['id'] case final String id when id.isNotEmpty)
          (
            id: id,
            name: row['name'] as String? ?? id,
            avatarUrl: row['avatar'] as String? ?? '',
            joined: row['joined'] == true,
            microphone: row['microphone'] == true,
            camera: row['camera'] == true,
            volume: (row['volume'] as num?)?.clamp(0, 100).toInt() ?? 0,
          ),
  ];
  final before = previous?.members;
  return (
    chatGroup: snapshot['chatGroup'] == true,
    inviterId: snapshot['inviterId'] as String? ?? '',
    members: before != null && listEquals(before, members)
        ? before
        : List.unmodifiable(members),
  );
}

/// 复用其他 Flutter 端的多人宫格和控制区，视频和操作均由鸿蒙通话层提供。
class HarmonyGroupCallView extends StatefulWidget {
  const HarmonyGroupCallView({
    super.key,
    required this.group,
    this.groupId,
    required this.selfId,
    required this.duration,
    required this.incoming,
    required this.accepted,
    required this.video,
    required this.microphone,
    required this.speaker,
    required this.camera,
    required this.videoBuilder,
    required this.onAction,
    this.control,
  });

  /// 鸿蒙原生 SDK 提供的群来源和成员状态。
  final HarmonyGroupCall group;

  /// 原生场次的来源群 ID，临时多人通话为空。
  final String? groupId;

  /// 只用于区分本端与远端，不能作为主持身份。
  final String selfId;

  /// SDK 已接通的通话时长，单位为秒。
  final int duration;

  /// 接听状态和媒体类型来自当前有效场次。
  final bool incoming, accepted, video;

  /// 实际设备状态，不随按钮点击提前翻转。
  final bool microphone, speaker, camera;

  /// 同一个成员在布局切换时复用同一路纹理。
  final Widget Function(String) videoBuilder;

  /// 当前会控控制器提供的策略及命令结果，成员在收到明确限制前可自行开启设备。
  final GroupControlState? control;

  /// 由浮层统一校验场次并将操作交还 SDK。
  final ValueChanged<String> onAction;

  @override
  State<HarmonyGroupCallView> createState() => _HarmonyGroupCallViewState();
}

/// 只管理本机摄像头能力查询，其余状态来自实时通话快照。
class _HarmonyGroupCallViewState extends State<HarmonyGroupCallView> {
  /// 摄像头方向未知时先隐藏翻转入口。
  bool _canFlip = false;

  @override
  void initState() {
    super.initState();
    _loadCameraCapability();
  }

  /// 摄像头数量回包可能晚于退出通话，先确认视图仍在。
  Future<void> _loadCameraCapability() async {
    final count = await readGroupCameraCount();
    if (mounted && (count ?? 0) > 1) setState(() => _canFlip = true);
  }

  @override
  Widget build(BuildContext context) {
    final members = [
      for (final member in widget.group.members)
        GroupCallMember(
          id: member.id,
          name: AppUserAvatarScope.personName(
            context,
            member.id,
            groupId: widget.groupId,
            fallback: member.name,
          ),
          avatarUrl: member.avatarUrl,
          status: member.joined
              ? GroupCallMemberStatus.joined
              : GroupCallMemberStatus.waiting,
          microphoneOn: member.microphone,
          cameraOn: member.camera,
          volume: member.volume,
        ),
    ];
    // 视频布局和设备按钮沿用共享组件，鸿蒙动作走原生场次通道。
    return GroupCallScene(
      title: widget.group.chatGroup ? '群通话' : '多人通话',
      status: Text(
        widget.accepted
            ? const TimerWidget().formatDuration(widget.duration)
            : '正在呼叫…',
        style: TextStyle(
          fontSize: 12,
          color: context.appColors.onScrimSecondary,
        ),
      ),
      members: members,
      inviterId: widget.group.inviterId,
      selfId: widget.selfId,
      incoming: widget.incoming,
      video: widget.video,
      videoBuilder: (id) =>
          widget.video &&
              members.any((member) => member.id == id && member.joined)
          ? widget.videoBuilder(id)
          : const SizedBox.shrink(),
      controls: GroupCallControls(
        incoming: widget.incoming,
        connected: widget.accepted,
        ended: false,
        retryable: false,
        showRecording: false,
        microphoneOn: widget.microphone,
        canOpenMicrophone: widget.control?.canOpenMicrophone ?? true,
        canOpenCamera: widget.control?.canOpenCamera ?? false,
        microphonePending:
            widget.control?.isDevicePending(
              widget.selfId,
              GroupControlDevice.microphone,
            ) ==
            true,
        cameraPending:
            widget.control?.isDevicePending(
              widget.selfId,
              GroupControlDevice.camera,
            ) ==
            true,
        microphoneHint: widget.control == null
            ? null
            : groupDeviceHint(
                widget.control,
                widget.selfId,
                GroupControlDevice.microphone,
              ),
        cameraHint: groupDeviceHint(
          widget.control,
          widget.selfId,
          GroupControlDevice.camera,
        ),
        speakerOn: widget.speaker,
        cameraOn: widget.camera,
        canFlip: widget.video && _canFlip,
        onEnd: () => widget.onAction('end'),
        onAccept: () => widget.onAction('accept'),
        onMicrophone: () => widget.onAction('microphone'),
        onSpeaker: () => widget.onAction('speaker'),
        onCamera: () => widget.onAction('camera'),
        onFlip: () => widget.onAction('flip'),
      ),
    );
  }
}
