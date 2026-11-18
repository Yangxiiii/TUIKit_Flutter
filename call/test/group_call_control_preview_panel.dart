import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:tencent_calls_uikit/src/state/group_control_state.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_control_feedback.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_member.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_members_sheet.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_call_more_sheet.dart';
import 'package:tencent_calls_uikit/src/view/callview/public/multi/group_mute_all_dialog.dart';

import 'group_call_control_preview_session.dart';

/// 仅为离线预览创建会控会话，生产成员表及更多管理的布局完全复用。
Future<void> showGroupControlPreview(
        BuildContext context, List<GroupCallMember> members) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        backgroundColor: context.appColors.surface,
        builder: (_) => FractionallySizedBox(
            heightFactor: 1, child: _ControlPreviewPanel(members: members)));

/// 控制器只在管理预览打开期间存续，关闭后释放所有替身传输与计时器。
class _ControlPreviewPanel extends StatefulWidget {
  const _ControlPreviewPanel({required this.members});

  /// 仅姓名、机构和邀请状态是固定样例，已加入成员的设备来自替身端。
  final List<GroupCallMember> members;
  @override
  State<_ControlPreviewPanel> createState() => _ControlPreviewPanelState();
}

/// 预览使用实际控制器的状态通知，不通过本地bool伪造成功或等待回执。
class _ControlPreviewPanelState extends State<_ControlPreviewPanel> {
  /// 本面板唯一的离线控制会话，销毁时统一取消回执等待并释放端点。
  late final GroupControlPreviewSession _session;
  @override
  void initState() {
    super.initState();
    _session = GroupControlPreviewSession(widget.members);
    unawaited(_session.start());
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _session,
      builder: (_, __) => GroupCallMembersSheet(
          members: _session.members,
          selfId: 'self',
          ended: false,
          controlState: _session.host.value,
          onMicrophone: () => _device('self', GroupControlDevice.microphone,
              !_session.host.value.microphoneOn),
          onCamera: () => _device(
              'self', GroupControlDevice.camera, !_session.host.value.cameraOn),
          onMemberDevice: _device,
          onRetry: (_) => _notice('离线预览不发送通话邀请'),
          onMuteAll: _muteAll,
          onUnmuteAll: () => _session.execute(
              'unmute', _session.host.value, _session.host.unmuteAll),
          onMore: _more));

  Future<void> _device(
      String id, GroupControlDevice device, bool enabled) async {
    await _session.execute('device/$id', _session.host.value,
        () => _session.host.setMemberDevice(id, device, enabled));
  }

  /// 默认不勾选的确认内容与生产一致，确认期间策略改变会被同一边界拒绝。
  Future<void> _muteAll() =>
      _session.guard.singleFlight<void>('offline.muteDialog', () async {
        final state = _session.host.value;
        final allow = await showGroupMuteAllConfirmation(context);
        if (!mounted || allow == null) return;
        await _session.execute(
            'mute', state, () => _session.host.muteAll(allowSelfUnmute: allow));
      });

  /// 两类设备动作与权限草稿分别提交给正式控制器，通过替身端点收到其生成的ACK。
  Future<void> _more() =>
      _session.guard.singleFlight<void>('offline.more', () async {
        await showModalBottomSheet<void>(
            context: context,
            backgroundColor: context.appColors.groupedPageBackground,
            barrierColor: context.appColors.scrim,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            builder: (_) => AnimatedBuilder(
                animation: _session,
                builder: (_, __) {
                  final state = _session.host.value;
                  return GroupCallMoreSheet(
                      allowSelfUnmute:
                          state.policyKnown ? state.allowSelfUnmute : null,
                      allowVideo: state.policyKnown ? state.allowVideo : null,
                      policyVersion: state.version,
                      canManage: state.canManage,
                      pending: state.pendingByUserId.isNotEmpty,
                      status: groupControlStatusText(state, _session.members),
                      onConfirm: (unmute, video) => _session.execute(
                          'policy',
                          state,
                          () => _session.host.updatePolicy(
                              allowSelfUnmute: unmute, allowVideo: video)),
                      onAllCameras: (enabled) => _session.execute('cameras',
                          state, () => _session.host.setAllCameras(enabled)));
                }));
      });

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
