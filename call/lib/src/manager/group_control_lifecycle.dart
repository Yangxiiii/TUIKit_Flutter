import 'dart:async';
import 'package:app_core/app_core.dart';
import 'package:app_service/app_service.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:tuikit_atomic_x/atomicx.dart';
import '../control/group_control_media.dart';
import '../control/group_control_transport.dart';
import '../state/global_state.dart';
import '../state/group_control_state.dart';
import 'call_manager.dart';
import 'group_control_controller.dart';

/// 将 SDK 已接通/离开事实映射为会控入会生命周期，重入必定创建新 session。
class GroupControlLifecycle {
  GroupControlLifecycle({required this.confirmDeviceOpen}) : _guard = null {
    CallStore.shared.state.activeCall.addListener(_refresh);
    CallStore.shared.state.selfInfo.addListener(_refresh);
    CallStore.shared.state.allParticipants.addListener(_refresh);
    GlobalState.instance.groupCall.addListener(_refresh);
  }

  /// 鸿蒙用自身 SDK 快照驱动入会，通过同一控制器校验主持消息和回执。
  GroupControlLifecycle.harmony([ActionGuard? guard])
    : confirmDeviceOpen = null,
      _guard = guard;

  /// 安卓和 iOS 通过通话导航询问本人，鸿蒙由当前展示会话提供确认入口。
  final Future<bool> Function(GroupControlDevice, Duration)? confirmDeviceOpen;

  /// 测试可提供独立的动作防重实例，生产复用应用注册实例。
  final ActionGuard? _guard;

  /// 上次 SDK 确认的在场顺序；高频媒体快照不触发重复会控同步。
  List<String> _joinedIds = const [];

  /// 宿主已登录 IM 在线通道；替换或注销后旧控制器立即失效。
  GroupControlTransport? _transport;

  /// 仅本端真实接通场次拥有控制器，等待邀请不获得主持或设备权限。
  GroupControlController? _controller;

  /// 本次接通负责原生设备观察，离场先解绑控制器再释放监听。
  SdkGroupControlMedia? _media;

  /// 同账号同场保留已验证主持链和到期锚点，过期后重入也不能恢复旧主持或新计一小时。
  final Map<
    String,
    ({
      String account,
      String host,
      int epoch,
      int? connectedAtMs,
      int? deadlineMs,
    })
  >
  _authority = {};

  /// 即使 SDK 未回报结束也限制缓存规模，避免长登录期间无限积累历史场次。
  static const _maxAuthorityEntries = 64;

  /// 当前已接通控制器，邀请等待和 SDK 已结束时为空。
  GroupControlController? get controller => _controller;

  /// 绑定宿主通道，不创建或重复登录任何 IM 实例。
  void setTransport(GroupControlTransport? transport) {
    if (identical(_transport, transport)) return;
    clear();
    _transport = transport;
    if (confirmDeviceOpen != null) _refresh();
  }

  /// 真实成员变化只更新已加入列表；旧场次和未接通状态立即撤销会控权限。
  void _refresh() {
    final call = CallStore.shared.state.activeCall.value;
    final self = CallStore.shared.state.selfInfo.value;
    final group = GlobalState.instance.groupCall.value;
    final account = LoginStore.shared.loginState.loginUserInfo?.userID;
    if (_transport == null ||
        group == null ||
        group.ended ||
        call.callId.isEmpty ||
        self.id.isEmpty ||
        account != self.id ||
        self.status != CallParticipantStatus.accept) {
      clear();
      return;
    }
    // SDK 成员资料可能延迟或缺失，真实加入事件已足以确认在席。
    final joinedIds = <String>{
      self.id,
      ...GlobalState.instance.groupCallSession.joinedIdsFromSdkEvents(
        call.callId,
      ),
      ...CallStore.shared.state.allParticipants.value
          .where((p) => p.status == CallParticipantStatus.accept)
          .map((p) => p.id),
    }.toList();
    final joinOrder = {
      for (final member in group.members) member.id: member.joinOrder,
    };
    // 主持无剩余管理员时优先选择最早收到真实加入事件的成员；未见事件不伪造序号。
    joinedIds.sort((a, b) {
      final first = joinOrder[a] ?? 0;
      final second = joinOrder[b] ?? 0;
      if (first == 0 || second == 0) {
        return first == second
            ? 0
            : first == 0
            ? 1
            : -1;
      }
      return first.compareTo(second);
    });
    final localVideoView = GlobalState.instance.groupLocalVideoView;
    _update(
      callId: call.callId,
      selfId: self.id,
      inviterId: call.inviterId,
      groupId: call.chatGroupId,
      video: call.mediaType == CallMediaType.video,
      connectedAtMs: call.startTime,
      joinedIds: joinedIds,
      confirm: confirmDeviceOpen,
      media: () => _media = SdkGroupControlMedia(
        isFrontCamera: () => CallManager.instance.isFrontCamera,
        localVideoViewChanges: call.mediaType == CallMediaType.video
            ? localVideoView
            : null,
        readLocalVideoView: () {
          final view = localVideoView.value;
          return view?.callId == call.callId && view?.userId == self.id
              ? view?.viewId
              : null;
        },
      ),
      retrySync: true,
    );
  }

  /// 仅有效账号实际接通后使用鸿蒙媒体；换场和未接听均撤销旧会控。
  void updateHarmony({
    required String callId,
    required String selfId,
    required String inviterId,
    required String groupId,
    required bool video,
    required int connectedAtMs,
    required List<String> joinedIds,
    required GroupControlMedia media,
    required Future<bool> Function(GroupControlDevice, Duration) confirm,
  }) {
    if (_transport == null ||
        callId.isEmpty ||
        selfId.isEmpty ||
        inviterId.isEmpty) {
      if (_controller != null) clear();
      return;
    }
    _update(
      callId: callId,
      selfId: selfId,
      inviterId: inviterId,
      groupId: groupId,
      video: video,
      connectedAtMs: connectedAtMs,
      joinedIds: joinedIds,
      media: () => media,
      confirm: confirm,
    );
  }

  /// 共享入会、可信主持缓存和重入逻辑；每次真实接通分配新的协议 session。
  void _update({
    required String callId,
    required String selfId,
    required String inviterId,
    required String groupId,
    required bool video,
    required int connectedAtMs,
    required List<String> joinedIds,
    required GroupControlMedia Function() media,
    required Future<bool> Function(GroupControlDevice, Duration)? confirm,
    bool retrySync = false,
  }) {
    final created =
        _controller?.callId != callId || _controller?.selfId != selfId;
    if (created) {
      clear();
      _authority.removeWhere((_, entry) => entry.account != selfId);
      final known = _authority[callId];
      _controller = GroupControlController(
        callId: callId,
        selfId: selfId,
        inviterId: inviterId,
        groupId: groupId,
        video: video,
        transport: _transport!,
        media: media(),
        confirmDeviceOpen: confirm,
        trustedHostId: known?.host,
        trustedHostEpoch: known?.epoch ?? 0,
        // 晚加入成员沿用可信主持同步时间，只有初始主持能使用本端接通时间。
        connectedAtMs:
            known?.connectedAtMs ??
            (inviterId == selfId && connectedAtMs > 0 ? connectedAtMs : null),
        deadlineMs: known?.deadlineMs,
        guard: _guard ?? AppServiceLocator.get<ActionGuard>(),
      );
      GlobalState.instance.groupControlController = _controller;
      _controller!.addListener(_publish);
    }
    final controller = _controller!;
    if (created || !listEquals(_joinedIds, joinedIds)) {
      _joinedIds = joinedIds;
      controller.updateMembers(joinedIds);
    }
    if (created) {
      unawaited(controller.start());
    } else if (retrySync && !controller.value.policyKnown) {
      unawaited(controller.requestSync());
    }
  }

  /// 保存本端亲自验证的主持链，之后重入不能重新把 SDK 初始主叫当现任主持。
  void _publish() {
    final current = _controller;
    if (current != null) {
      if (!_authority.containsKey(current.callId) &&
          _authority.length >= _maxAuthorityEntries) {
        _authority.remove(_authority.keys.first);
      }
      _authority[current.callId] = (
        account: current.selfId,
        host: current.value.hostId,
        epoch: current.hostEpoch,
        connectedAtMs: current.value.connectedAtMs,
        deadlineMs: current.value.deadlineMs,
      );
    }
    GlobalState.instance.setGroupControlState(current?.value);
  }

  /// 连接恢复由宿主主动触发，仍只向已验证主持请求当前在线策略。
  void syncPolicy() {
    final controller = _controller;
    if (controller != null) unawaited(controller.requestSync());
  }

  /// SDK 结束、账号退出或通道注销时取消旧 session，媒体释放仍由 SDK 负责。
  void clear({bool clearAuthority = false}) {
    _controller?.removeListener(_publish);
    _controller?.dispose();
    _controller = null;
    _joinedIds = const [];
    _media?.dispose();
    _media = null;
    GlobalState.instance.groupControlController = null;
    GlobalState.instance.setGroupControlState(null);
    if (clearAuthority) _authority.clear();
  }
}
