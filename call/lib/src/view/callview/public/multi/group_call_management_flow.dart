import 'package:app_core/app_core.dart';
import 'package:app_service/app_service.dart';
import 'package:app_ui/app_ui.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_calls_uikit/src/manager/call_manager.dart';
import 'package:tencent_calls_uikit/src/state/global_state.dart'
    hide GroupCallMember, GroupCallMemberStatus;
import 'package:tencent_calls_uikit/src/state/group_control_state.dart';

import 'group_call_control_feedback.dart';
import 'group_call_member.dart';
import 'group_call_members_sheet.dart';
import 'group_call_more_sheet.dart';
import 'group_call_presentation.dart';
import 'group_mute_all_dialog.dart';

/// 群管理的导航与交互编排；所有策略、主持权和设备结果仍由会控控制器持有。
class GroupCallManagementFlow {
  GroupCallManagementFlow(
      {required this.context,
      required this.updates,
      required this.readMembers,
      required this.onRetry,
      required this.isCurrentPresentation})
      : _epoch = CallManager.instance.sessionEpoch,
        _callId = CallStore.shared.state.activeCall.value.callId,
        _selfId = CallStore.shared.state.selfInfo.value.id;

  /// 只用于导航与错误说明，任何异步返回后先检查页面存续。
  final BuildContext context;

  /// 同场 SDK 成员、真实媒体和会控进度的通知源。
  final Listenable updates;

  /// 每次刷新按事实重新投影，不缓存另一份可变成员状态。
  final List<GroupCallMember> Function() readMembers;

  /// 已有邀请入口仍负责腾讯 SDK 的容量与场次复核。
  final Future<void> Function(String id) onRetry;

  /// 原浮层是否存续，保护 SDK 尚未分配 ID 的等待阶段。
  final bool Function()? isCurrentPresentation;

  /// 本次交互绑定的场次代次、已分配 ID 和登录身份。
  final int _epoch;
  final String _callId, _selfId;

  ActionGuard get _guard => AppServiceLocator.get<ActionGuard>();

  /// 只读取当前腾讯场次的策略，路由切换期间不能短暂沿用旧场次会控。
  GroupControlState? get _state {
    final state = GlobalState.instance.groupControl.value;
    return state?.callId == CallStore.shared.state.activeCall.value.callId
        ? state
        : null;
  }

  bool get _current =>
      context.mounted &&
      GlobalState.instance.groupCall.value?.ended != true &&
      _selfId == CallStore.shared.state.selfInfo.value.id &&
      isCurrentGroupCallPresentation(
          capturedEpoch: _epoch,
          currentEpoch: CallManager.instance.sessionEpoch,
          capturedCallId: _callId,
          currentCallId: CallStore.shared.state.activeCall.value.callId,
          presentationIsCurrent: isCurrentPresentation?.call() ?? false);

  /// 打开的成员表只属于原场次，旧表不显示新来电成员也不能下发设备命令。
  Future<void> open() =>
      _guard.singleFlight<void>(('call.group.members', _epoch, _callId),
          () async {
        final initialMembers = readMembers();
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: context.appColors.surface,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          clipBehavior: Clip.antiAlias,
          builder: (_) => FractionallySizedBox(
              heightFactor: 1,
              child: ListenableBuilder(
                  listenable: updates,
                  builder: (_, __) => GroupCallMembersSheet(
                      members: _current ? readMembers() : initialMembers,
                      selfId: _selfId,
                      ended: !_current,
                      controlState: _current ? _state : null,
                      onMicrophone: () =>
                          _toggleSelf(GroupControlDevice.microphone),
                      onCamera: () => _toggleSelf(GroupControlDevice.camera),
                      onMemberDevice: setDevice,
                      onRetry: _retry,
                      onMuteAll: muteAll,
                      onUnmuteAll: unmuteAll,
                      onMore: _showMore))),
        );
      });

  /// 本人设备入口按真实状态确定目标，禁止用 DeviceStore 的乐观字段反转。
  void _toggleSelf(GroupControlDevice device) {
    final self = CallStore.shared.state.selfInfo.value;
    final on = device == GroupControlDevice.microphone
        ? _state?.microphoneOn ?? self.isMicrophoneOpened
        : _state?.cameraOn ?? self.isCameraOpened;
    setDevice(_selfId, device, !on);
  }

  /// 本人按当前设备权限操作，开麦默认允许；远端操作仍需主持权限和真实回执。
  Future<void> setDevice(
          String userId, GroupControlDevice device, bool enabled) =>
      _guard.singleFlight<void>(('call.group.device', _epoch, userId, device),
          () async {
        if (!_current) return;
        final state = _state;
        final controller = CallManager.instance.groupControl;
        if (userId == _selfId &&
            !enabled &&
            (state == null || controller == null)) {
          try {
            if (device == GroupControlDevice.microphone) {
              await CallManager.instance.closeLocalMicrophone();
            } else {
              await CallManager.instance.closeLocalCamera();
            }
          } catch (_) {
            if (_current) AppToast.show('关闭设备失败，请重试');
          }
          return;
        }
        if (state == null || controller == null) return;
        final permitted = userId == _selfId
            ? !enabled ||
                (device == GroupControlDevice.microphone
                    ? state.canOpenMicrophone
                    : state.canOpenCamera)
            : state.canManage;
        if (!permitted ||
            !readMembers()
                .any((member) => member.id == userId && member.joined)) {
          return;
        }
        await _execute(
            state, () => controller.setMemberDevice(userId, device, enabled));
      });

  /// 全员静音确认默认禁止自行开麦，确认后重新验证主持人和策略版本。
  Future<void> muteAll() =>
      _guard.singleFlight<void>(('call.group.muteAll', _epoch), () async {
        final state = _state;
        if (!_current || state?.canManage != true || state!.muteAll) return;
        final allow = await showGroupMuteAllConfirmation(context);
        if (allow == null) return;
        final controller = CallManager.instance.groupControl;
        if (controller != null) {
          await _execute(
              state, () => controller.muteAll(allowSelfUnmute: allow));
        }
      });

  /// 解除全员静音由控制器恢复策略，成员自行决定何时开麦。
  Future<void> unmuteAll() =>
      _guard.singleFlight<void>(('call.group.unmuteAll', _epoch), () async {
        final state = _state;
        final controller = CallManager.instance.groupControl;
        if (state == null ||
            !state.canManage ||
            !state.muteAll ||
            controller == null) {
          return;
        }
        await _execute(state, controller.unmuteAll);
      });

  /// 更多管理持续读取当前权限，版本变更后旧草稿不能覆盖新的主持策略。
  Future<void> _showMore() =>
      _guard.singleFlight<void>(('call.group.more', _epoch), () async {
        await showModalBottomSheet<void>(
            context: context,
            backgroundColor: context.appColors.groupedPageBackground,
            barrierColor: context.appColors.scrim,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            builder: (_) => ListenableBuilder(
                listenable: updates,
                builder: (_, __) {
                  final state = _state;
                  final known = _current && state?.policyKnown == true;
                  return GroupCallMoreSheet(
                      key: ValueKey((state?.sessionId, state?.hostId)),
                      allowSelfUnmute: known ? state!.allowSelfUnmute : null,
                      allowVideo: known ? state!.allowVideo : null,
                      policyVersion: state?.version ?? 0,
                      canManage: known && state!.canManage,
                      pending: state?.pendingByUserId.isNotEmpty == true,
                      status: _current
                          ? groupControlStatusText(state, readMembers())
                          : '当前通话已结束',
                      onAllCameras: (enabled) => _guard.singleFlight<bool>(
                              ('call.group.allCameras', _epoch), () async {
                            final controller =
                                CallManager.instance.groupControl;
                            if (state == null ||
                                !state.canManage ||
                                controller == null) {
                              return false;
                            }
                            return _execute(
                                state, () => controller.setAllCameras(enabled));
                          }),
                      onConfirm: (unmute, video) => _guard.singleFlight<bool>(
                              ('call.group.policy', _epoch), () async {
                            final controller =
                                CallManager.instance.groupControl;
                            if (state == null ||
                                !state.canManage ||
                                controller == null) {
                              return false;
                            }
                            return _execute(
                                state,
                                () => controller.updatePolicy(
                                    allowSelfUnmute: unmute,
                                    allowVideo: video));
                          }));
                }));
      });

  /// 异步确认只使用原主持人与版本；执行后不显示发送成功提示，仅暴露真实失败。
  Future<bool> _execute(GroupControlState expected,
      Future<GroupControlResult> Function() command) async {
    final state = _state;
    if (!isCurrentGroupControlOperation(
        expected: expected, current: state, presentationIsCurrent: _current)) {
      if (context.mounted) AppToast.show('会控状态已变化，请重新操作');
      return false;
    }
    try {
      final result = await command();
      if (!_current ||
          _state?.sessionId != expected.sessionId ||
          _state?.hostId != expected.hostId) {
        return false;
      }
      if (!result.success) {
        final failure = result.outcomes.values
            .where((outcome) => !outcome.success)
            .firstOrNull;
        AppToast.show(
            failure == null ? '操作尚未确认，请重试' : groupControlOutcomeText(failure));
      }
      return result.success;
    } catch (_) {
      if (_current) AppToast.show('会控操作失败，请重试');
      return false;
    }
  }

  /// 管理表中的重呼只作用于原场次，重复点击共享已有异步动作。
  Future<void> _retry(String userId) =>
      _guard.singleFlight<void>(('call.group.retryMember', _epoch, userId),
          () async {
        if (_current) await onRetry(userId);
      });
}
