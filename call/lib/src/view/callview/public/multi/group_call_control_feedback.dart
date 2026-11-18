import 'package:tencent_calls_uikit/src/state/group_control_state.dart';

import 'group_call_member.dart';

/// 将真实执行结果转换为界面说明，不把消息发送成功当成设备成功。
String groupControlOutcomeText(GroupControlOutcome outcome) =>
    switch (outcome.status) {
      GroupControlStatus.success => '设备状态已确认',
      GroupControlStatus.timeout => '等待设备确认超时',
      GroupControlStatus.expired => '操作已过期',
      GroupControlStatus.unconfirmed => '设备状态尚未确认',
      GroupControlStatus.denied => outcome.error ?? '设备权限未允许',
      GroupControlStatus.unavailable => outcome.error ?? '设备暂不可用',
      GroupControlStatus.failed => outcome.error ?? '设备执行失败',
    };

/// 汇总当前操作进度与失败目标，空值表示没有需要额外提示的控制状态。
String? groupControlStatusText(
    GroupControlState? state, List<GroupCallMember> members) {
  if (state == null || !state.policyKnown) return '会控权限尚未同步，暂不可开启设备';
  if (state.pendingByUserId.isNotEmpty) {
    return '正在等待${state.pendingByUserId.length}位成员确认';
  }
  final failure = state.resultsByUserId.entries
      .where((entry) => !entry.value.success)
      .firstOrNull;
  if (failure != null) {
    final name =
        members.where((member) => member.id == failure.key).firstOrNull?.name ??
            failure.key;
    return '$name：${groupControlOutcomeText(failure.value)}';
  }
  return state.canManage ? null : '仅主持人可以管理其他成员';
}
