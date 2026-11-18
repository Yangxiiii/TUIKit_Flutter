import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:tencent_calls_uikit/src/state/group_control_state.dart';

import 'group_call_member.dart';
import 'group_call_control_feedback.dart';

/// 管理列表的单个成员，设备图标来自实际状态，操作遵循本场主持权限与策略。
class GroupCallMemberRow extends StatelessWidget {
  const GroupCallMemberRow(
      {super.key,
      required this.member,
      required this.selfId,
      required this.ended,
      required this.onMicrophone,
      required this.onCamera,
      required this.onRetry,
      this.controlState,
      this.onMemberDevice});

  /// 当前场次投影，保留姓名、机构资料、邀请结果和实时设备状态。
  final GroupCallMember member;

  /// 判断本人设备的唯一身份，不将邀请人身份推断为管理权限。
  final String selfId;

  /// 结束后的展示结果不允许继续操作设备或邀请。
  final bool ended;

  /// 宿主提供的本人设备操作，复用既有权限及错误处理。
  final VoidCallback onMicrophone, onCamera;

  /// 仅仍有效场次中可重试的邀请终态提供此动作。
  final ValueChanged<String> onRetry;

  /// 主持身份、策略和等待结果来自同一场次控制器，不由邀请人字段在此推断。
  final GroupControlState? controlState;

  /// 指定成员的设备目标由编排层校验当前场次并等待真实 ACK。
  final void Function(String userId, GroupControlDevice device, bool enabled)?
      onMemberDevice;

  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(
            height: 63.5,
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  AppUserAvatar(
                      userId: member.id,
                      name: member.name,
                      url: member.avatarUrl,
                      size: 40),
                  const SizedBox(width: 12),
                  // 姓名资料吸收剩余宽度；尾部设备或重呼按钮保持各自固定尺寸。
                  Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        _memberName(context, member),
                        if (member.subtitle.isNotEmpty)
                          Text(member.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  height: 18 / 12,
                                  letterSpacing: 0,
                                  color: context.appColors.textSecondary)),
                      ])),
                  if (member.joined) ...[
                    _device(context, member, microphone: true),
                    _device(context, member, microphone: false)
                  ] else if (member.canRetry)
                    _retry(context, member),
                ]))),
        Padding(
            padding: const EdgeInsets.only(left: 68, right: 16),
            child: Divider(
                height: .5, thickness: .5, color: context.appColors.outline)),
      ]);

  /// 邀请结果在姓名同行使用独立状态标记，不占据机构资料的第三行。
  Widget _memberName(BuildContext context, GroupCallMember member) =>
      Row(children: [
        Flexible(
            child: Text(member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, height: 20 / 14, letterSpacing: 0))),
        if (!member.joined) ...[
          const SizedBox(width: 8),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                  border:
                      Border.all(color: context.appColors.outline, width: .5),
                  borderRadius: BorderRadius.circular(3)),
              child: Text(member.statusLabel,
                  style: TextStyle(
                      fontSize: 10,
                      height: 14 / 10,
                      letterSpacing: 0,
                      color: context.appColors.textSecondary))),
        ],
      ]);

  /// 小按钮独占语义节点，同时提供名称和点击动作，避免标识被整行吸收。
  Widget _retry(BuildContext context, GroupCallMember member) => Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Semantics(
          identifier: 'call.group.members.retry.${member.id}',
          container: true,
          button: true,
          label: '重新呼叫${member.name}',
          enabled: !ended,
          onTap: ended ? null : () => onRetry(member.id),
          excludeSemantics: true,
          child: SizedBox(
              width: 56,
              height: 28,
              child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      side:
                          BorderSide(color: context.appColors.primaryContainer),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                  onPressed: ended ? null : () => onRetry(member.id),
                  child: const Text('重新呼叫',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0))))));

  /// 本人可关闭设备；开启受当前策略限制，远端操作只开放给可信主持人。
  Widget _device(BuildContext context, GroupCallMember member,
      {required bool microphone}) {
    final on = microphone ? member.microphoneOn : member.cameraOn;
    final label = microphone ? '麦克风' : '摄像头';
    final device =
        microphone ? GroupControlDevice.microphone : GroupControlDevice.camera;
    final state = controlState;
    final pending = state?.pendingByUserId.containsKey(member.id) == true;
    final canOpen = microphone
        ? state?.canOpenMicrophone == true
        : state?.canOpenCamera == true;
    final permitted =
        member.id == selfId ? on || canOpen : state?.canManage == true;
    final enabled = !ended &&
        !pending &&
        permitted &&
        (member.id == selfId || onMemberDevice != null);
    final result = state?.resultsByUserId[member.id];
    final reason = pending
        ? '正在等待设备确认'
        : result != null && !result.success
            ? groupControlOutcomeText(result)
            : !permitted
                ? '当前策略或主持权限不允许此操作'
                : '$label${on ? '已开' : '已关'}';
    return Semantics(
        identifier:
            'call.group.members.${microphone ? 'microphone' : 'camera'}.${member.id}',
        enabled: enabled,
        label: '$label${on ? '已开' : '已关'}，$reason',
        child: SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: reason,
                onPressed: !enabled
                    ? null
                    : () {
                        if (onMemberDevice != null) {
                          onMemberDevice!(member.id, device, !on);
                        } else {
                          (microphone ? onMicrophone : onCamera)();
                        }
                      },
                icon: pending
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.appColors.textSecondary))
                    : Icon(
                        microphone
                            ? (on ? AppIcons.mic : AppIcons.micOff)
                            : (on ? AppIcons.cameraOn : AppIcons.videoOff),
                        size: 20,
                        color: on
                            ? context.appColors.groupCallMemberDeviceOn
                            : context.appColors.danger))));
  }
}
