import 'dart:async';
import 'package:app_core/app_core.dart';
import 'package:app_service/app_service.dart';
import 'package:tuikit_atomic_x/atomicx.dart';
import '../control/group_control_media.dart';
import '../control/group_control_transport.dart';
import '../state/global_state.dart';
import 'group_control_controller.dart';

/// 将 SDK 已接通/离开事实映射为会控入会生命周期，重入必定创建新 session。
class GroupControlLifecycle {
  GroupControlLifecycle() {
    CallStore.shared.state.activeCall.addListener(_refresh);
    CallStore.shared.state.selfInfo.addListener(_refresh);
    CallStore.shared.state.allParticipants.addListener(_refresh);
    GlobalState.instance.groupCall.addListener(_refresh);
  }

  /// 宿主已登录 IM 在线通道；替换或注销后旧控制器立即失效。
  GroupControlTransport? _transport;

  /// 仅本端真实接通场次拥有控制器，等待邀请不获得主持或设备权限。
  GroupControlController? _controller;

  /// 同账号同场保留已验证主持链和到期锚点，过期后重入也不能恢复旧主持或新计一小时。
  final Map<
      String,
      ({
        String account,
        String host,
        int epoch,
        int? connectedAtMs,
        int? deadlineMs
      })> _authority = {};

  /// 即使 SDK 未回报结束也限制缓存规模，避免长登录期间无限积累历史场次。
  static const _maxAuthorityEntries = 64;

  /// 当前已接通控制器，邀请等待和 SDK 已结束时为空。
  GroupControlController? get controller => _controller;

  /// 绑定宿主通道，不创建或重复登录任何 IM 实例。
  void setTransport(GroupControlTransport? transport) {
    if (identical(_transport, transport)) return;
    clear();
    _transport = transport;
    _refresh();
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
    var created = false;
    if (_controller?.callId != call.callId || _controller?.selfId != self.id) {
      clear();
      _authority.removeWhere((_, entry) => entry.account != self.id);
      final known = _authority[call.callId];
      _controller = GroupControlController(
          callId: call.callId,
          selfId: self.id,
          inviterId: call.inviterId,
          groupId: call.chatGroupId,
          video: call.mediaType == CallMediaType.video,
          transport: _transport!,
          media: SdkGroupControlMedia(),
          trustedHostId: known?.account == self.id ? known?.host : null,
          trustedHostEpoch: known?.account == self.id ? known!.epoch : 0,
          // CallStore.startTime 是本端 onCallBegin 时间，只有初始主持可以它建立锚点。
          // 晚加入成员及继任主持必须继承可信同步时间，不能改用自己的接通时刻。
          connectedAtMs: known?.account == self.id
              ? known?.connectedAtMs
              : call.inviterId == self.id && call.startTime > 0
                  ? call.startTime
                  : null,
          deadlineMs: known?.account == self.id ? known?.deadlineMs : null,
          guard: AppServiceLocator.get<ActionGuard>());
      GlobalState.instance.groupControlController = _controller;
      _controller!.addListener(_publish);
      created = true;
    }
    final joinedIds = <String>{
      self.id,
      ...CallStore.shared.state.allParticipants.value
          .where((p) => p.status == CallParticipantStatus.accept)
          .map((p) => p.id),
    }.toList();
    final joinOrder = {
      for (final member in group.members) member.id: member.joinOrder
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
    _controller!.updateMembers(joinedIds);
    _publish();
    if (created) {
      unawaited(_controller!.start());
    } else if (!_controller!.value.policyKnown) {
      unawaited(_controller!.requestSync());
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
    GlobalState.instance.groupControlController = null;
    GlobalState.instance.setGroupControlState(null);
    if (clearAuthority) _authority.clear();
  }
}
