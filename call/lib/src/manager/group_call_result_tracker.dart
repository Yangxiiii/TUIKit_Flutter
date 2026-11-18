import 'package:atomic_x_core/atomicxcore.dart';

import '../state/group_call_snapshot.dart';

/// 本人通话终态报告；不把本端无法确认的远端参与时长写成事实。
class GroupCallResultReport {
  GroupCallResultReport({
    required this.callId,
    required this.groupId,
    required this.callerId,
    this.callerName = '',
    this.callerAvatarURL = '',
    required this.reporterId,
    required List<String> participantIds,
    required Map<String, GroupCallMemberStatus> invitationResults,
    Set<String> joinedUserIds = const {},
    required this.mediaType,
    required this.outcome,
    required this.durationSeconds,
    required this.endedAtMs,
    required this.revision,
    this.attemptId,
  })  : participantIds = List.unmodifiable(participantIds),
        invitationResults = Map.unmodifiable(invitationResults),
        joinedUserIds = Set.unmodifiable(joinedUserIds);

  /// SDK真实场次，同场重入的报告沿用此标识。
  final String callId;

  /// 群来源；临时多人为空，不创建群聊。
  final String groupId;

  /// 真实发起人，主持权交接不改变单聊结果的收件人关系。
  final String callerId;

  /// SDK发起人资料，只影响记录头像和名称，不影响主持权限。
  final String callerName, callerAvatarURL;

  /// 当前登录的本人；宿主发送前必须再次核对账号。
  final String reporterId;

  /// 已知受邀成员的去重集合，包含本人及发起人。
  final List<String> participantIds;

  /// SDK已确认的各目标邀请结果，主叫用于生成分别面向被叫的结果。
  final Map<String, GroupCallMemberStatus> invitationResults;

  /// SDK曾确认加入的成员；仅有left状态不足以证明曾参与媒体。
  final Set<String> joinedUserIds;

  /// 本场真实媒体类型，不读取本地相机开关推断。
  final CallMediaType mediaType;

  /// 本人对应的终态，不由页面关闭或本地振铃倒计时伪造。
  final GroupCallResultOutcome outcome;

  /// 本人所有已加入区间累计秒数；主叫从首位被叫接通时开始。
  final int durationSeconds;

  /// 结果生成时的UTC毫秒时间戳。
  final int endedAtMs;

  /// 同场同报告者重入后的递增版本。
  final int revision;

  /// 初始呼叫的气泡关联标识，未收到 SDK 透传时为空。
  final String? attemptId;
}

/// 与SDK结束事件对应的结果值；业务序列化在宿主边界处理。
enum GroupCallResultOutcome {
  cancelled,
  unanswered,
  rejected,
  busy,
  completed,
  interrupted,

  /// 同账号其他设备接听，本机不生成时长。
  otherDeviceAccepted,
}

/// 宿主按真实报告发布个人记录；失败须传播，不把发送失败当作已保存。
typedef GroupCallResultHandler = Future<void> Function(GroupCallResultReport);

/// 跟踪本人实际参与区间，结束时发布一次；同callId重入累加而非房间时长。
class GroupCallResultTracker {
  GroupCallResultTracker({
    required GroupCallSession session,
    required String Function() accountId,
    DateTime Function()? now,
  })  : _session = session,
        _accountId = accountId,
        _now = now ?? DateTime.now {
    _session.addListener(_refresh);
  }

  final GroupCallSession _session;
  final String Function() _accountId;
  final DateTime Function() _now;

  /// 仅保留当前账号最近一小时内可重入的场次，不跨账号携带个人资料。
  final Map<String, _Participation> _calls = {};

  /// 累计区间所属账号；切号立即丢弃，不能跨账号复用。
  String _account = '';

  /// 账号只在新场次代次绑定；切号后同一旧快照不能重新绑定给另一用户。
  int _observedGeneration = -1;

  /// 同一SDK展示代次允许报告的唯一账号，失效后须等待新代次。
  String _generationAccount = '';

  /// 当前实际参与区间，切换场次或SDK清空时关闭计时。
  _Participation? _active;

  /// 同一展示代次的重复SDK结束回调只产生一份报告。
  int _lastEndedGeneration = -1;

  /// 当前宿主的真实消息发布器，替换时不补发历史结果。
  GroupCallResultHandler? _handler;

  /// 宿主替换发布器不补发旧账号的结果。
  void setHandler(GroupCallResultHandler? handler) => _handler = handler;

  /// 同一场重新加入时复用已校验的标识，新场次或账号不复用。
  String? attemptForCall(String callId) =>
      _account == _accountId() ? _calls[callId]?.attemptId : null;

  /// 每次SDK快照变化只维护计时，不在资料变化或重建时写聊天消息。
  void _refresh() {
    final account = _accountId();
    if (_observedGeneration != _session.generation) {
      if (account != _account) _clearParticipation();
      _observedGeneration = _session.generation;
      _generationAccount = account;
      _account = account;
    } else if (account != _generationAccount) {
      // 注销、切号或切回都不能消费上个账号尚未清理的SDK结束事件。
      _clearParticipation();
      _generationAccount = '';
      _account = '';
      return;
    }
    final now = _now();
    final snapshot = _session.value;
    if (snapshot == null ||
        snapshot.callId.isEmpty ||
        account.isEmpty ||
        !snapshot.members.any((member) => member.id == account)) {
      _active?.leave(now);
      _active = null;
      return;
    }
    // 只缓存可存续的一小时场次；历史聊天由IM存储承担，不让内存表无限增长。
    _calls.removeWhere((_, value) =>
        value != _active && now.difference(value.touchedAt).inHours >= 1);
    final entry =
        _calls.putIfAbsent(snapshot.callId, () => _Participation(now));
    if (_active != entry) _active?.leave(now);
    _active = entry;
    entry.touchedAt = now;
    entry.attemptId ??= _session.attemptId;
    final self = snapshot.members.where((m) => m.id == account).firstOrNull;
    // 主叫自身waiting不表示接通；必须有SDK确认的首次通话建立。
    final joined = !snapshot.ended &&
        snapshot.hasConnected &&
        (self?.status == GroupCallMemberStatus.joined ||
            (self?.status == GroupCallMemberStatus.waiting &&
                snapshot.inviterId == account &&
                snapshot.members.any((m) =>
                    m.id != account &&
                    m.status == GroupCallMemberStatus.joined)));
    if (joined) {
      entry.join(now);
    } else {
      entry.leave(now);
    }
  }

  /// 在session.end之后调用；使用真实SDK原因，不以UI挂断点击作为成功终态。
  Future<void> onEnded(String callId, CallEndReason reason) async {
    _refresh();
    final snapshot = _session.value;
    final entry = _calls[callId];
    if (snapshot == null ||
        !snapshot.ended ||
        snapshot.callId != callId ||
        entry == null ||
        _account.isEmpty ||
        _lastEndedGeneration == _session.generation) {
      return;
    }
    _lastEndedGeneration = _session.generation;
    final now = _now();
    entry.leave(now);
    final ids = snapshot.members.map((m) => m.id).toSet()
      ..add(_account)
      ..add(snapshot.inviterId)
      ..remove('');
    if (ids.length < 2) return;
    final outcome = entry.joinedOnce
        ? (reason == CallEndReason.hangup
            ? GroupCallResultOutcome.completed
            : GroupCallResultOutcome.interrupted)
        : switch (reason) {
            CallEndReason.reject ||
            CallEndReason.otherDeviceReject =>
              GroupCallResultOutcome.rejected,
            CallEndReason.otherDeviceAccepted =>
              GroupCallResultOutcome.otherDeviceAccepted,
            CallEndReason.noResponse ||
            CallEndReason.offline =>
              GroupCallResultOutcome.unanswered,
            CallEndReason.lineBusy => GroupCallResultOutcome.busy,
            CallEndReason.canceled => GroupCallResultOutcome.cancelled,
            _ => GroupCallResultOutcome.interrupted,
          };
    // 每个端只报告自己的时长，宿主按主叫与各被叫关系发布，不产生被叫两两会话。
    final caller =
        snapshot.members.where((m) => m.id == snapshot.inviterId).firstOrNull;
    final report = GroupCallResultReport(
      callId: callId,
      groupId: snapshot.groupId,
      callerId: snapshot.inviterId,
      callerName: caller?.name ?? '',
      callerAvatarURL: caller?.avatarURL ?? '',
      reporterId: _account,
      participantIds: ids.toList(),
      invitationResults: {for (final m in snapshot.members) m.id: m.status},
      joinedUserIds: {
        for (final m in snapshot.members)
          if (m.joinOrder > 0 || m.status == GroupCallMemberStatus.joined) m.id
      },
      mediaType: snapshot.mediaType,
      outcome: outcome,
      durationSeconds: entry.elapsed.inSeconds,
      endedAtMs: now.millisecondsSinceEpoch,
      revision: ++entry.revision,
      attemptId: entry.attemptId,
    );
    await _handler?.call(report);
  }

  /// 注销时清空个人区间及代次；不会替其他账号发布旧通话记录。
  void clear() {
    _clearParticipation();
    _observedGeneration = _session.generation;
    _generationAccount = '';
    _account = '';
  }

  void _clearParticipation() {
    _calls.clear();
    _active = null;
    _lastEndedGeneration = -1;
  }

  /// 取消监听并丢弃所有本端计时资源。
  void dispose() {
    _session.removeListener(_refresh);
    clear();
  }
}

/// 单个场次内本人的累计区间，离开后保留供同callId重入。
class _Participation {
  _Participation(this.touchedAt);

  /// 同一 SDK 场次内保留，重新加入可继续更新原气泡。
  String? attemptId;

  /// 最近SDK快照时间，用于一小时缓存淘汰。
  DateTime touchedAt;

  /// 当前实际加入的起点；null表示此刻没有参与媒体。
  DateTime? enteredAt;

  /// 已关闭区间的累计值，SDK重复通知不重复累计。
  Duration elapsed = Duration.zero;

  /// 曾接通过即保留，零秒短通话也不能归为未接听。
  bool joinedOnce = false;

  /// 同场本人已发布结果的次数，重入后的报告递增。
  int revision = 0;

  void join(DateTime now) {
    enteredAt ??= now;
    joinedOnce = true;
  }

  void leave(DateTime now) {
    final start = enteredAt;
    if (start != null && !now.isBefore(start)) elapsed += now.difference(start);
    enteredAt = null;
  }
}
