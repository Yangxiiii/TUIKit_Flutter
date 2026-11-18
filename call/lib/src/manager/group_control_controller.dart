import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';
import '../control/group_control_media.dart';
import '../control/group_control_message.dart';
import '../control/group_control_transport.dart';
import '../state/group_control_state.dart';

/// 每次真实入会创建一个控制器；鉴权、设备执行与 ACK 都绑定此入会生命周期。
class GroupControlController extends ValueNotifier<GroupControlState> {
  GroupControlController(
      {required this.callId,
      required this.selfId,
      required String inviterId,
      required this.groupId,
      required this.video,
      required GroupControlTransport transport,
      required GroupControlMedia media,
      required ActionGuard guard,
      DateTime Function()? now,
      String Function()? newId,
      String? trustedHostId,
      int trustedHostEpoch = 0,
      int? connectedAtMs,
      int? deadlineMs,
      Random? random,
      this.ackTimeout = const Duration(seconds: 8)})
      : _transport = transport,
        _media = media,
        _guard = guard,
        _now = now ?? DateTime.now,
        _newId = newId ?? _randomId,
        _random = random ?? Random.secure(),
        _hostId = trustedHostId ?? inviterId,
        _hostEpoch = trustedHostEpoch,
        _connectedAtMs = connectedAtMs,
        _deadlineMs = deadlineMs,
        sessionId = (newId ?? _randomId)(),
        super(GroupControlState(
            callId: callId,
            sessionId: '',
            selfId: selfId,
            hostId: trustedHostId ?? inviterId,
            policyKnown: false,
            version: 0,
            allowSelfUnmute: false,
            allowVideo: false,
            muteAll: false,
            cameraAllClosed: false,
            microphoneOn: media.microphoneOn,
            cameraOn: media.cameraOn)) {
    _sessions[selfId] = sessionId;
    _subscription = _transport.messages.listen(_received);
    _media.changes.addListener(_publish);
    _publish();
  }

  /// 腾讯真实场次及本端真实登录账号，不能由消息正文改写。
  final String callId, selfId;

  /// SDK 群来源；临时多人为空，不构造虚假群 ID。
  final String groupId;

  /// 本场真实媒体类型，语音场次不默认开启摄像头。
  final bool video;

  /// 本次入会唯一标识，重入创建新控制器，绝不重用旧命令或个人静音。
  final String sessionId;

  /// IM 发送及 ACK 的最大等待，超时始终作为非成功结果。
  final Duration ackTimeout;
  final GroupControlTransport _transport;
  final GroupControlMedia _media;
  final ActionGuard _guard;

  /// 注入时间与随机源只用于可重复验证；生产有效期以本机墙钟判断。
  final DateTime Function() _now;
  final String Function() _newId;
  final Random _random;
  late final StreamSubscription<GroupControlInbound> _subscription;

  /// 初始主持来自 SDK inviter，后续只接收当前主持的真实 IM 交接。
  String _hostId;

  /// 每次可信交接递增，旧主持代次不得继续发布设备命令。
  int _hostEpoch;

  /// 本端已验证的主持交接代次，仅供同账号重入保留可信主持来源。
  int get hostEpoch => _hostEpoch;

  /// 本场递增策略/命令序号，交接沿用已有版本，拒绝乱序设备指令。
  int _version = 0;

  /// 同一场次的可信时间锚点；仅初始主持首次接通创建，后续只接受完全相同的值。
  int? _connectedAtMs, _deadlineMs;

  /// 未获可信同步前禁止自行开启设备。
  bool _known = false;

  /// 权限与入会默认状态分别保存，个人设备命令不改变全员默认策略。
  bool _allowUnmute = true,
      _allowVideo = true,
      _muteAll = false,
      _cameraAllClosed = false;

  /// SDK 确认的在场成员，调用方优先按真实加入事件排序，缺少事件不伪造序号。
  List<String> _members = [];

  /// 仅当前入会的 session 注册表，旧 session 在离开后进入拒绝集合。
  final Map<String, String> _sessions = {};

  /// 已离场的入会标识不能通过迟到 hello 重新注册。
  final Set<String> _retiredSessions = {};

  /// 按原命令缓存 ACK，重传只回原结果，禁止再次打开设备。
  final Map<String, GroupControlMessage> _ackCache = {};

  /// 主持端等待的真实回执，以 commandId 唯一关联。
  final Map<String, _PendingControl> _pending = {};

  /// 发送和本人执行共享的 UI 进度，空设备表示策略或交接。
  final Map<String, GroupControlDevice?> _pendingUsers = {};

  /// 同一成员的操作可能交错完成，只有最新操作能撤销自己的等待态。
  final Map<String, Object> _pendingOwners = {};

  /// 最近一次实际执行/回执结果，绝不由发送成功推导设备成功。
  final Map<String, GroupControlOutcome> _results = {};

  /// 设备执行和主持发送分别串行，ACK 接收不排队，避免等待自身回执死锁。
  Future<void> _receiving = Future.value(),
      _sending = Future.value(),
      _mediaQueue = Future.value();

  /// 结束/注销后使所有待返回设备、发送及 ACK 结果失效。
  bool _disposed = false;

  /// 入会和命令使用独立的 128 位随机标识，不能沿用用户 ID 或上次场次计数。
  static String _randomId() {
    final random = Random.secure();
    return List.generate(
            16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// 成员名单必须来自 SDK 已加入事实；离开立即撤销 session 和等待中的回执。
  void updateMembers(List<String> members) {
    if (_disposed) return;
    final next = members.where((id) => id.isNotEmpty).toSet().toList();
    for (final id in _members.where((id) => !next.contains(id))) {
      final session = _sessions.remove(id);
      if (session != null) _retiredSessions.add('$id/$session');
      for (final pending in _pending.values.where((p) => p.userId == id)) {
        if (!pending.result.isCompleted) {
          pending.result.complete(const GroupControlOutcome(
              GroupControlStatus.unavailable,
              error: '成员已离开'));
        }
      }
    }
    _members = next;
    // 未收到可信交接而主持离场时失去策略权威，不能自行选举或相信任意成员自报。
    if (_known && !_members.contains(_hostId)) {
      _known = false;
      unawaited(_suspend());
    }
    _publish();
  }

  /// 入会先关闭设备再同步当前策略，新 session 不继承上一次个人静音意图。
  Future<void> start() async {
    await _suspend();
    if (_disposed) return;
    if (_hostId == selfId) {
      // 首名被叫接通后初始主持才进入此阶段；SDK 时间缺失才取同一刻本机时间。
      _connectedAtMs ??= _now().millisecondsSinceEpoch;
      _deadlineMs ??= _connectedAtMs! + 3600000;
      _known = true;
      _publish();
      await _applyJoinDefaults();
    } else {
      await requestSync();
    }
  }

  /// 重连重新向已验证主持请求当前策略，不重放旧设备命令。
  Future<void> requestSync() async {
    if (_disposed || _hostId == selfId || !_members.contains(selfId)) return;
    try {
      await _send(_message(GroupControlMessageKind.hello, _hostId,
          targetSession: '', commandId: _newId()));
    } catch (_) {
      // 在线消息不能恢复离线历史；同步失败保持未知或现有已验证策略。
    }
  }

  /// 全员静音默认禁止成员自行开麦，勾选允许时只改变该独立权限。
  Future<GroupControlResult> muteAll({bool allowSelfUnmute = false}) =>
      _hostAction('muteAll', () async {
        _muteAll = true;
        _allowUnmute = allowSelfUnmute;
        return _broadcast(GroupControlMessageKind.command,
            device: GroupControlDevice.microphone, enabled: false);
      });

  /// 恢复开麦同时恢复自行开麦权限，逐目标等待真实设备 ACK。
  Future<GroupControlResult> unmuteAll() => _hostAction('unmuteAll', () async {
        _muteAll = false;
        _allowUnmute = true;
        return _broadcast(GroupControlMessageKind.command,
            device: GroupControlDevice.microphone, enabled: true);
      });

  /// 控制他人须为主持；本人按当前授权操作。单成员命令不改变全员入会默认策略。
  Future<GroupControlResult> setMemberDevice(
      String userId, GroupControlDevice device, bool enabled) async {
    if (userId == selfId) {
      return GroupControlResult({selfId: await setSelfDevice(device, enabled)});
    }
    return _hostAction(
        'device/$userId/${device.name}/$enabled',
        () => _broadcast(GroupControlMessageKind.command,
            targets: [userId], device: device, enabled: enabled));
  }

  /// 修改自行开启权限，允许不等于立即开启；禁止时同步关闭对应设备。
  Future<GroupControlResult> updatePolicy(
          {bool? allowSelfUnmute, bool? allowVideo}) =>
      _hostAction('policy', () async {
        if (allowSelfUnmute != null) _allowUnmute = allowSelfUnmute;
        if (allowVideo != null) _allowVideo = allowVideo;
        return _broadcast(GroupControlMessageKind.policy);
      });

  /// 全员摄像头恢复同时授权，关闭与是否允许自行重新开启分别表示。
  Future<GroupControlResult> setAllCameras(bool enabled) =>
      _hostAction('cameras/$enabled', () async {
        _cameraAllClosed = !enabled;
        if (enabled) _allowVideo = true;
        return _broadcast(GroupControlMessageKind.command,
            device: GroupControlDevice.camera, enabled: enabled);
      });

  /// 本人设备入口同样执行策略；关闭始终允许，未知或被禁止时不能自行打开。
  Future<GroupControlOutcome> setSelfDevice(
          GroupControlDevice device, bool enabled) =>
      _guard.singleFlight(
          ('tim.call.control.self', callId, sessionId, device, enabled),
          () async {
        if (_disposed ||
            (enabled &&
                !(device == GroupControlDevice.microphone
                    ? value.canOpenMicrophone
                    : value.canOpenCamera))) {
          const denied = GroupControlOutcome(GroupControlStatus.denied,
              error: '当前策略不允许开启设备');
          _results[selfId] = denied;
          _publish();
          return denied;
        }
        final pending = _beginPending(selfId, device);
        try {
          final result = await _executeDevice(device, enabled);
          _finishPending(selfId, pending, result);
          return result;
        } finally {
          _finishPending(selfId, pending, null);
        }
      });

  /// 正常离开先按可信管理员名单交接；失败结果交给宿主提示，不阻止资源释放。
  Future<GroupControlResult> prepareLeave() => _hostAction('leave', () async {
        final remaining = _members.where((id) => id != selfId).toList();
        if (remaining.isEmpty) {
          return GroupControlResult(
              {selfId: const GroupControlOutcome(GroupControlStatus.success)});
        }
        Set<String> admins;
        try {
          admins = await _transport
              .loadAdministrators(groupId, remaining)
              .timeout(ackTimeout);
        } catch (_) {
          return GroupControlResult({
            selfId: const GroupControlOutcome(GroupControlStatus.unconfirmed,
                error: '无法确认管理员，主持交接未完成')
          });
        }
        if (_disposed || !value.canManage) return _denied();
        final stillPresent = remaining.where(_members.contains).toList();
        if (stillPresent.isEmpty) return _denied();
        final candidates = stillPresent.where(admins.contains).toList();
        final successor = candidates.isEmpty
            ? stillPresent.first
            : candidates[_random.nextInt(candidates.length)];
        final result = await _broadcast(GroupControlMessageKind.transfer,
            targets: stillPresent, nextHost: successor);
        // 本端随可信交接消息一同交出权限；未确认接收的成员不能被标为交接成功。
        _hostId = successor;
        _hostEpoch++;
        _known = result.success;
        _publish();
        return result;
      });

  /// 同类重复操作合并，其他操作串行并复核排队前的主持身份、策略版本。
  Future<GroupControlResult> _hostAction(
      String action, Future<GroupControlResult> Function() execute) {
    // 确认时的权限快照随动作入队，等待其他主持动作后不能悄悄采用另一版策略。
    final expectedVersion = _version;
    final expectedHost = _hostId;
    return _guard.singleFlight(('tim.call.control', callId, sessionId, action),
        () {
      final result = _sending.then((_) async {
        if (_disposed ||
            !value.canManage ||
            expectedHost != _hostId ||
            expectedVersion != _version) {
          return _denied();
        }
        // 同一主持操作只占一个版本，所有目标都接收同一策略快照。
        _version++;
        _results.clear();
        _publish();
        return execute();
      });
      _sending =
          result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
      return result;
    });
  }

  GroupControlResult _denied() => GroupControlResult({
        selfId: const GroupControlOutcome(GroupControlStatus.denied,
            error: '主持身份或通话策略已变更')
      });

  /// 每个目标单独关联 session 与命令，缺少会控接入的成员必须返回未确认。
  Future<GroupControlResult> _broadcast(GroupControlMessageKind kind,
      {List<String>? targets,
      GroupControlDevice? device,
      bool? enabled,
      String? nextHost}) async {
    final recipients = targets ?? List<String>.from(_members);
    final outcomes = <String, GroupControlOutcome>{};
    _publish();
    // 定向逐人发送避免把不存在会控接入的成员算成功；不同目标的 ACK 可并行等待。
    await Future.wait(recipients.map((id) async {
      if (!_members.contains(id) || _sessions[id] == null) {
        outcomes[id] = const GroupControlOutcome(GroupControlStatus.unavailable,
            error: '成员尚未接入会控');
        return;
      }
      final message = _message(kind, id,
          commandId: _newId(),
          device: device,
          enabled: enabled,
          nextHost: nextHost);
      final pending = _beginPending(id, device);
      GroupControlOutcome outcome;
      if (id == selfId) {
        outcome = await _apply(message);
      } else {
        outcome = await _sendAndWait(message);
      }
      outcomes[id] = outcome;
      _finishPending(id, pending, outcome);
    }));
    return GroupControlResult(outcomes);
  }

  /// 先登记等待项再发送，避免同进程或极速 IM 回执早于登记；超时不补写成功。
  Future<GroupControlOutcome> _sendAndWait(GroupControlMessage message) async {
    final pending = _PendingControl(message);
    _pending[message.commandId] = pending;
    try {
      await _send(message).timeout(ackTimeout);
      return await pending.result.future.timeout(ackTimeout,
          onTimeout: () => const GroupControlOutcome(GroupControlStatus.timeout,
              error: '未收到设备确认'));
    } catch (_) {
      return const GroupControlOutcome(GroupControlStatus.failed,
          error: '控制消息发送失败');
    } finally {
      _pending.remove(message.commandId);
    }
  }

  /// 先从 IM 实际发送者和目标会话过滤，ACK 快速完成等待，设备指令串行执行。
  void _received(GroupControlInbound inbound) {
    if (_disposed) return;
    final message = GroupControlMessage.decode(inbound.payload);
    if (message == null ||
        message.callId != callId ||
        message.targetUserId != selfId ||
        !_members.contains(inbound.senderId)) {
      return;
    }
    if (message.kind == GroupControlMessageKind.ack) {
      final pending = _pending[message.commandId];
      if (pending == null ||
          pending.userId != inbound.senderId ||
          pending.sessionId != message.senderSessionId ||
          message.targetSessionId != sessionId ||
          message.version != pending.message.version ||
          message.expiresAtMs < _now().millisecondsSinceEpoch ||
          pending.result.isCompleted) {
        return;
      }
      final status = GroupControlStatus.values
          .where((v) => v.name == message.status)
          .firstOrNull;
      if (status == null) return;
      // ACK 的成功状态必须与原指令目标一致，缺失或矛盾的实际设备字段只算未确认。
      final consistent = status != GroupControlStatus.success ||
          _ackMatchesTarget(pending.message, message);
      pending.result.complete(GroupControlOutcome(
          consistent ? status : GroupControlStatus.unconfirmed,
          error: consistent ? message.error : '回执设备状态与指令不一致',
          microphoneOn: message.microphoneOn,
          cameraOn: message.cameraOn));
      return;
    }
    _receiving = _receiving
        .then((_) => _receive(inbound.senderId, message))
        .catchError((Object _, StackTrace __) {});
  }

  /// 成功 ACK 除身份和版本外，还必须报告所控设备；授权本身不要求设备已开启。
  bool _ackMatchesTarget(GroupControlMessage command, GroupControlMessage ack) {
    if (command.kind == GroupControlMessageKind.command) {
      return switch (command.device) {
        'microphone' => ack.microphoneOn == command.enabled,
        'camera' => ack.cameraOn == command.enabled,
        _ => false,
      };
    }
    if (command.kind == GroupControlMessageKind.policy) {
      return (command.allowSelfUnmute || ack.microphoneOn == false) &&
          (command.allowVideo || ack.cameraOn == false);
    }
    return command.kind == GroupControlMessageKind.transfer;
  }

  /// hello 仅注册 SDK 已在场成员；其他消息必须来自当前可信主持并命中本次入会。
  Future<void> _receive(String sender, GroupControlMessage message) async {
    if (_disposed || !_members.contains(sender)) return;
    final expired = message.expiresAtMs < _now().millisecondsSinceEpoch;
    if (message.kind == GroupControlMessageKind.hello) {
      if (!value.canManage ||
          expired ||
          _retiredSessions.contains('$sender/${message.senderSessionId}')) {
        return;
      }
      final registered = _sessions[sender];
      if (registered != null && registered != message.senderSessionId) return;
      _sessions[sender] = message.senderSessionId;
      await _send(
          _message(GroupControlMessageKind.sync, sender, commandId: _newId()));
      return;
    }
    if (sender != _hostId ||
        message.targetSessionId != sessionId ||
        _retiredSessions.contains('$sender/${message.senderSessionId}')) {
      return;
    }
    final knownHostSession = _sessions[sender];
    if (knownHostSession != null &&
        knownHostSession != message.senderSessionId) {
      return;
    }
    if (message.kind == GroupControlMessageKind.transfer) {
      if (message.hostEpoch != _hostEpoch + 1 ||
          !_members.contains(message.hostId)) {
        return;
      }
    } else if (message.hostEpoch != _hostEpoch || message.hostId != _hostId) {
      return;
    }
    // 时间锚点属于可信策略，消息不能为晚加入或新主持重新开始一小时。
    if (message.connectedAtMs == null ||
        message.deadlineMs == null ||
        (_connectedAtMs != null &&
            (_connectedAtMs != message.connectedAtMs ||
                _deadlineMs != message.deadlineMs))) {
      return;
    }
    final cacheKey = '$sender/${message.senderSessionId}/${message.commandId}';
    // 同一命令重传直接复用旧回执，不能因用户当前设备状态不同而再次执行。
    final cached = _ackCache[cacheKey];
    if (cached != null) {
      await _send(cached);
      return;
    }
    if (expired) {
      await _reply(sender, message,
          const GroupControlOutcome(GroupControlStatus.expired));
      return;
    }
    if (message.version < _version ||
        (message.version == _version &&
            message.kind != GroupControlMessageKind.sync)) {
      return;
    }
    // 可信消息先提交权限版本，再串行执行设备；本人同时操作也必须复核此版本。
    final wasKnown = _known;
    _sessions[sender] = message.senderSessionId;
    _version = message.version;
    _connectedAtMs = message.connectedAtMs;
    _deadlineMs = message.deadlineMs;
    _allowUnmute = message.allowSelfUnmute;
    _allowVideo = message.allowVideo;
    _muteAll = message.muteAll;
    _cameraAllClosed = message.cameraAllClosed;
    _known = true;
    _publish();
    final pending = _beginPending(
        selfId,
        GroupControlDevice.values
            .where((device) => device.name == message.device)
            .firstOrNull);
    GroupControlOutcome outcome;
    if (message.kind == GroupControlMessageKind.transfer) {
      _hostId = message.hostId;
      _hostEpoch = message.hostEpoch;
      _sessions.addAll(Map.fromEntries(message.sessions.entries.where((e) =>
          _members.contains(e.key) &&
          e.value.isNotEmpty &&
          !_retiredSessions.contains('${e.key}/${e.value}'))));
      outcome = _actual(GroupControlStatus.success);
    } else if (message.kind == GroupControlMessageKind.sync) {
      outcome =
          wasKnown ? await _applyRestrictions() : await _applyJoinDefaults();
    } else {
      outcome = await _apply(message);
    }
    if (_disposed) return;
    // 只有执行完成才回执，UI 同步展示本端被控操作的真实结果。
    _finishPending(selfId, pending, outcome);
    final ack = _replyMessage(sender, message, outcome);
    if (_ackCache.length >= 256) _ackCache.remove(_ackCache.keys.first);
    _ackCache[cacheKey] = ack;
    _publish();
    await _send(ack);
  }

  /// 授权与设备分开处理；策略不允许时关闭，允许策略本身不主动打开现有成员设备。
  Future<GroupControlOutcome> _apply(GroupControlMessage message) async {
    if (_disposed) return _actual(GroupControlStatus.expired);
    if (message.kind == GroupControlMessageKind.policy) {
      return _applyRestrictions();
    }
    final device = GroupControlDevice.values
        .where((v) => v.name == message.device)
        .firstOrNull;
    if (device == null || message.enabled == null) {
      return _actual(GroupControlStatus.failed, '设备指令无效');
    }
    return _executeDevice(device, message.enabled!);
  }

  /// 禁止策略关闭相关设备；允许策略保留成员自己的当前设备选择。
  Future<GroupControlOutcome> _applyRestrictions() async {
    if (!_allowUnmute) {
      final result = await _executeDevice(GroupControlDevice.microphone, false);
      if (!result.success) return result;
    }
    if (!_allowVideo) return _executeDevice(GroupControlDevice.camera, false);
    return _actual(GroupControlStatus.success);
  }

  /// 仅全新入会采用全局默认；重连同步不会覆盖此前的个人设备选择。
  Future<GroupControlOutcome> _applyJoinDefaults() async {
    final microphone = await _executeDevice(
        GroupControlDevice.microphone, !_muteAll && _allowUnmute);
    if (_disposed) return _actual(GroupControlStatus.expired);
    final camera = await _executeDevice(
        GroupControlDevice.camera, video && !_cameraAllClosed && _allowVideo);
    return !microphone.success ? microphone : camera;
  }

  /// 同步前以及主持失联时先停止本端采集，未知策略不能自动打开设备。
  Future<void> _suspend() async {
    await _executeDevice(GroupControlDevice.microphone, false);
    await _executeDevice(GroupControlDevice.camera, false);
  }

  /// 默认准备、本人操作和远端命令共用设备队列，旧版本不能覆盖后发策略。
  Future<GroupControlOutcome> _executeDevice(
      GroupControlDevice device, bool enabled) {
    final expected = _version;
    final result = _mediaQueue.then<GroupControlOutcome>((_) async {
      bool current() =>
          !_disposed &&
          expected == _version &&
          (!enabled ||
              (_known &&
                  (_deadlineMs == null ||
                      _now().millisecondsSinceEpoch < _deadlineMs!)));
      if (!current()) return _actual(GroupControlStatus.expired);
      try {
        return await _media.setDevice(device, enabled, isCurrent: current);
      } catch (_) {
        return _actual(GroupControlStatus.failed, '设备执行失败');
      }
    });
    _mediaQueue =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  GroupControlOutcome _actual(GroupControlStatus status, [String? error]) =>
      GroupControlOutcome(status,
          error: error,
          microphoneOn: _media.microphoneOn,
          cameraOn: _media.cameraOn);

  /// 每条定向消息固定当前入会与策略快照，不在传输期间补写新场次字段。
  GroupControlMessage _message(GroupControlMessageKind kind, String target,
          {required String commandId,
          String? targetSession,
          GroupControlDevice? device,
          bool? enabled,
          String? nextHost}) =>
      GroupControlMessage(
          kind: kind,
          callId: callId,
          commandId: commandId,
          senderSessionId: sessionId,
          targetUserId: target,
          targetSessionId: targetSession ?? _sessions[target] ?? '',
          version: _version,
          expiresAtMs: _now().add(ackTimeout * 2).millisecondsSinceEpoch,
          hostId: nextHost ?? _hostId,
          hostEpoch: _hostEpoch + (nextHost == null ? 0 : 1),
          allowSelfUnmute: _allowUnmute,
          allowVideo: _allowVideo,
          muteAll: _muteAll,
          cameraAllClosed: _cameraAllClosed,
          connectedAtMs: _connectedAtMs,
          deadlineMs: _deadlineMs,
          sessions: Map.unmodifiable(_sessions),
          device: device?.name,
          enabled: enabled);

  /// ACK 绑定原始 commandId 和版本，发送时携带执行结束后的真实设备状态。
  GroupControlMessage _replyMessage(String sender, GroupControlMessage original,
          GroupControlOutcome result) =>
      GroupControlMessage(
          kind: GroupControlMessageKind.ack,
          callId: callId,
          commandId: original.commandId,
          senderSessionId: sessionId,
          targetUserId: sender,
          targetSessionId: original.senderSessionId,
          version: original.version,
          expiresAtMs: _now().add(ackTimeout).millisecondsSinceEpoch,
          hostId: _hostId,
          hostEpoch: _hostEpoch,
          status: result.status.name,
          microphoneOn: result.microphoneOn,
          cameraOn: result.cameraOn,
          error: result.error);

  Future<void> _reply(String sender, GroupControlMessage original,
          GroupControlOutcome result) =>
      _send(_replyMessage(sender, original, result));
  Future<void> _send(GroupControlMessage message) =>
      _transport.send(message.targetUserId, jsonEncode(message.toJson()));

  /// 自行操作和远端控制共用等待出口，操作身份用于拒绝迟到结果覆盖后续操作。
  Object _beginPending(String id, GroupControlDevice? device) {
    final owner = Object();
    _pendingOwners[id] = owner;
    _pendingUsers[id] = device;
    _publish();
    return owner;
  }

  /// 旧操作完成只返回给原调用者，不清除或覆盖新操作正在展示的状态。
  void _finishPending(String id, Object owner, GroupControlOutcome? outcome) {
    if (!identical(_pendingOwners[id], owner)) return;
    _pendingOwners.remove(id);
    _pendingUsers.remove(id);
    if (outcome != null) _results[id] = outcome;
    _publish();
  }

  /// 只读状态复制集合，UI 无法修改控制器正在等待或已经验证的结果。
  void _publish() {
    if (_disposed) return;
    value = GroupControlState(
        callId: callId,
        sessionId: sessionId,
        selfId: selfId,
        hostId: _hostId,
        policyKnown: _known,
        version: _version,
        allowSelfUnmute: _known && _allowUnmute,
        allowVideo: _known && _allowVideo,
        muteAll: _muteAll,
        cameraAllClosed: _cameraAllClosed,
        microphoneOn: _media.microphoneOn,
        cameraOn: _media.cameraOn,
        connectedAtMs: _connectedAtMs,
        deadlineMs: _deadlineMs,
        pendingByUserId: _pendingUsers,
        resultsByUserId: _results);
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    _media.changes.removeListener(_publish);
    for (final pending in _pending.values) {
      if (!pending.result.isCompleted) {
        pending.result
            .complete(const GroupControlOutcome(GroupControlStatus.expired));
      }
    }
    _pending.clear();
    _pendingOwners.clear();
    _sessions.clear();
    _ackCache.clear();
    super.dispose();
  }
}

/// 等待项绑定目标真实入会标识，旧账号或旧 session 的回执不能完成新请求。
class _PendingControl {
  _PendingControl(this.message);

  /// 原始指令用来复核 ACK 版本、目标 session 与实际设备状态。
  final GroupControlMessage message;
  String get userId => message.targetUserId;
  String get sessionId => message.targetSessionId;

  /// 仅真实匹配回执、成员离开、超时或控制器销毁能够完成。
  final Completer<GroupControlOutcome> result = Completer();
}
