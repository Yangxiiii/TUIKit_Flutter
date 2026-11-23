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
  GroupControlController({
    required this.callId,
    required this.selfId,
    required String inviterId,
    required this.groupId,
    required this.video,
    required GroupControlTransport transport,
    required GroupControlMedia media,
    required ActionGuard guard,
    Future<bool> Function(GroupControlDevice, Duration)? confirmDeviceOpen,
    DateTime Function()? now,
    String Function()? newId,
    String? trustedHostId,
    int trustedHostEpoch = 0,
    int? connectedAtMs,
    int? deadlineMs,
    Random? random,
    this.ackTimeout = const Duration(seconds: 8),
  })  : _transport = transport,
        _media = media,
        _guard = guard,
        _confirmDeviceOpen = confirmDeviceOpen,
        _now = now ?? DateTime.now,
        _newId = newId ?? _randomId,
        _random = random ?? Random.secure(),
        _hostId = trustedHostId ?? inviterId,
        _hostEpoch = trustedHostEpoch,
        _connectedAtMs = connectedAtMs,
        _deadlineMs = deadlineMs,
        sessionId = (newId ?? _randomId)(),
        super(
          GroupControlState(
            callId: callId,
            sessionId: '',
            selfId: selfId,
            hostId: trustedHostId ?? inviterId,
            policyKnown: false,
            version: 0,
            allowSelfUnmute: true,
            allowVideo: true,
            muteAll: false,
            cameraAllClosed: false,
            microphoneOn: media.microphoneOn,
            cameraOn: media.cameraOn,
          ),
        ) {
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

  /// IM 发送和普通指令的等待上限，开启请求另留本人确认时间。
  final Duration ackTimeout;
  final GroupControlTransport _transport;
  final GroupControlMedia _media;
  final ActionGuard _guard;

  /// 仅通话界面能取得本人的开启同意；没有确认入口时保持设备关闭。
  final Future<bool> Function(GroupControlDevice, Duration)? _confirmDeviceOpen;

  /// 开启请求给本人留出确认时间，其余指令沿用短超时。
  static const _openRequestTimeout = Duration(seconds: 30);

  /// 在线握手可能先于对端的 SDK 入会事件，给主持端留出刷新成员名单的时间。
  static const _syncRetryInterval = Duration(seconds: 1);

  /// 单轮握手包含首发，避免对暂时不可达或未支持会控的客户端持续发包。
  static const _maxSyncAttempts = 5;

  /// 收到可信同步或销毁会话时唤醒等待，IM 发送成功不代表握手完成。
  Completer<void>? _syncResponse;

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

  /// 标记主持策略是否已验证，用于主持操作和远端命令校验。
  bool _known = false;

  /// 权限与入会默认状态分别保存，个人设备命令不改变全员默认策略。
  bool _allowUnmute = true,
      _muteBlocksUnmute = false,
      _allowVideo = true,
      _muteAll = false,
      _cameraAllClosed = false;

  /// 当前主持代次已接收的各设备指令版本，避免另一个设备使本设备的指令失效。
  final Map<GroupControlDevice, int> _deviceVersions = {};

  /// 最近一次可信策略同步的版本；旧授权指令不能覆盖已同步的更新权限。
  int _policyVersion = -1;

  /// 成员收到的逐设备实际权限，优先于同步中的群体默认值。
  final Map<GroupControlDevice, bool> _memberPermissions = {};

  /// 本次入会本人已选择摄像头状态，迟到的允许策略不能替用户重新打开。
  bool _selfCameraSelected = false;

  /// 远端开启同意可能跨多个消息回调，执行中收到同 ID 时等待首个结果。
  final Set<String> _runningCommands = {};

  /// 计算本端实际开麦权限，解除全员静音后仍保留单独配置的限制。
  bool get _canMemberUnmute =>
      _memberPermissions[GroupControlDevice.microphone] ??
      (_allowUnmute && !_muteBlocksUnmute);

  /// 计算本端实际摄像头权限，逐人权限先于全员默认。
  bool get _canMemberOpenCamera =>
      _memberPermissions[GroupControlDevice.camera] ?? _allowVideo;

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

  /// 按成员和设备保留等待所有权，空设备表示策略或交接。
  final Map<(String, GroupControlDevice?), Object> _pendingOwners = {};

  /// 最近一次实际执行/回执结果，绝不由发送成功推导设备成功。
  final Map<String, GroupControlOutcome> _results = {};

  /// 设备提示独立保存，某个设备的失败不覆盖另一个设备。
  final Map<(String, GroupControlDevice), GroupControlOutcome> _deviceResults =
      {};

  /// 可信命令和主持发送分别串行，ACK 接收不排队，避免等待自身回执死锁。
  Future<void> _receiving = Future.value(), _sending = Future.value();

  /// 同一设备按顺序执行，麦克风不必等待摄像头确认。
  final Map<GroupControlDevice, Future<void>> _mediaQueues = {};

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
    // 主持离场后撤销管理权限，保留已收到的设备限制和本机采集状态。
    if (_known && !_members.contains(_hostId)) {
      _known = false;
    }
    _publish();
  }

  /// 接通后按默认权限开麦，成员可手动开摄像头，同时向主持同步策略。
  Future<void> start() async {
    if (_disposed) return;
    if (_hostId == selfId) {
      // 首名被叫接通后初始主持才进入此阶段；SDK 时间缺失才取同一刻本机时间。
      _connectedAtMs ??= _now().millisecondsSinceEpoch;
      _deadlineMs ??= _connectedAtMs! + 3600000;
      _known = true;
      _publish();
    } else {
      unawaited(requestSync());
    }
    await Future.wait([
      // 同步版本变化时仍按实际麦克风策略校验，允许快照不取消本次开麦。
      _executeDevice(
        GroupControlDevice.microphone,
        true,
        isCommandCurrent: () => !_muteAll,
      ),
      _applyJoinCamera(),
    ]);
  }

  /// 入会及重连向可信主持请求同步。合并同会话的请求，只重试握手消息。
  Future<void> requestSync() => _guard.singleFlight(
    ('tim.call.control.sync', callId, sessionId),
    () async {
      final response = Completer<void>();
      _syncResponse = response;
      try {
        for (
          var attempt = 0;
          attempt < _maxSyncAttempts && !response.isCompleted;
          attempt++
        ) {
          if (_disposed || _hostId == selfId || !_members.contains(selfId)) {
            return;
          }
          // 每次使用新的有效期，保持同一个入会标识，避免迟到包绑定到其他设备。
          final hello = _message(
            GroupControlMessageKind.hello,
            _hostId,
            targetSession: '',
            commandId: _newId(),
          );
          final sent = Future<void>.sync(() => _send(hello))
              .timeout(_syncRetryInterval)
              .catchError((Object _) {});
          await Future.wait([
            sent,
            response.future.timeout(_syncRetryInterval, onTimeout: () {}),
          ]);
        }
      } finally {
        _syncResponse = null;
      }
    },
  );

  /// 收到有效策略或离场时唤醒等待，避免后续重发旧入会的握手。
  void _finishSyncRequest() {
    final response = _syncResponse;
    if (response != null && !response.isCompleted) response.complete();
  }

  /// 全员静音只作用于其他成员，允许自行开麦时下发单纯关麦。
  Future<GroupControlResult> muteAll({bool allowSelfUnmute = false}) =>
      _hostAction('muteAll', () async {
        _muteAll = true;
        _muteBlocksUnmute = !allowSelfUnmute;
        final allowed = _allowUnmute && !_muteBlocksUnmute;
        return _broadcastDevices({
          GroupControlDevice.microphone: allowed
              ? (GroupControlAction.close, null)
              : (GroupControlAction.setAllowed, false),
        });
      });

  /// 解除全员静音只恢复相应权限，保留单独限制，成员自行决定是否开麦。
  Future<GroupControlResult> unmuteAll() => _hostAction('unmuteAll', () async {
        _muteAll = false;
        _muteBlocksUnmute = false;
        return _broadcastDevices({
          GroupControlDevice.microphone: (
            GroupControlAction.setAllowed,
            _allowUnmute,
          ),
        });
      });

  /// 控制他人须为主持，开启只向本人发送请求；直接操作自己的设备沿用本地入口。
  Future<GroupControlResult> setMemberDevice(
    String userId,
    GroupControlDevice device,
    bool enabled,
  ) async {
    if (userId == selfId) {
      return GroupControlResult({selfId: await setSelfDevice(device, enabled)});
    }
    return _hostAction(
      'device/$userId/${device.name}/$enabled',
      () => _broadcast(
        GroupControlMessageKind.command,
        targets: [userId],
        device: device,
        action:
            enabled ? GroupControlAction.requestOpen : GroupControlAction.close,
      ),
    );
  }

  /// 发布逐设备权限；恢复时不启动采集，禁止时目标端同步关闭设备。
  Future<GroupControlResult> updatePolicy({
    bool? allowSelfUnmute,
    bool? allowVideo,
  }) =>
      _hostAction('policy', () async {
        _allowUnmute = allowSelfUnmute ?? _allowUnmute;
        _allowVideo = allowVideo ?? _allowVideo;
        if (allowSelfUnmute != null) _muteBlocksUnmute = false;
        return _broadcastDevices({
          if (allowSelfUnmute != null)
            GroupControlDevice.microphone: (
              GroupControlAction.setAllowed,
              _allowUnmute,
            ),
          if (allowVideo != null)
            GroupControlDevice.camera: (
              GroupControlAction.setAllowed,
              _allowVideo
            ),
        });
      });

  /// 全员摄像头动作保持开启权限，开启时逐人请求本人确认。
  Future<GroupControlResult> setAllCameras(bool enabled) =>
      _hostAction('cameras/$enabled', () async {
        _cameraAllClosed = !enabled;
        return _broadcastDevices({
          GroupControlDevice.camera: (
            enabled ? GroupControlAction.requestOpen : GroupControlAction.close,
            null,
          ),
        });
      });

  /// 本人默认可开关设备，收到明确的开启限制后按当前权限执行。
  Future<GroupControlOutcome> setSelfDevice(
    GroupControlDevice device,
    bool enabled,
  ) =>
      _guard.singleFlight(
        ('tim.call.control.self', callId, sessionId, device, enabled),
        () async {
          if (_disposed || (enabled && !_canOpen(device))) {
            const denied = GroupControlOutcome(
              GroupControlStatus.denied,
              error: '当前策略不允许开启设备',
            );
            _results[selfId] = denied;
            _deviceResults[(selfId, device)] = denied;
            _publish();
            return denied;
          }
          final isCamera = device == GroupControlDevice.camera;
          if (isCamera) _selfCameraSelected = true;
          final deviceVersion = _deviceVersions[device];
          final pending = _beginPending(selfId, device);
          try {
            // 同步允许策略不中断手动开关摄像头，新指令或禁止开启仍有效。
            final result = await _executeDevice(
              device,
              enabled,
              isCommandCurrent: isCamera
                  ? () => _deviceVersions[device] == deviceVersion
                  : null,
            );
            _finishPending(pending, result);
            return result;
          } finally {
            _finishPending(pending, null);
          }
        },
      );

  /// 正常离开先按可信管理员名单交接；失败结果交给宿主提示，不阻止资源释放。
  Future<GroupControlResult> prepareLeave() => _hostAction('leave', () async {
        final remaining = _members.where((id) => id != selfId).toList();
        if (remaining.isEmpty) {
          return GroupControlResult({
            selfId: const GroupControlOutcome(GroupControlStatus.success),
          });
        }
        Set<String> admins;
        try {
          admins = await _transport
              .loadAdministrators(groupId, remaining)
              .timeout(ackTimeout);
        } catch (_) {
          return GroupControlResult({
            selfId: const GroupControlOutcome(
              GroupControlStatus.unconfirmed,
              error: '无法确认管理员，主持交接未完成',
            ),
          });
        }
        if (_disposed || !value.canManage) return _denied();
        final stillPresent = remaining.where(_members.contains).toList();
        if (stillPresent.isEmpty) return _denied();
        final candidates = stillPresent.where(admins.contains).toList();
        final successor = candidates.isEmpty
            ? stillPresent.first
            : candidates[_random.nextInt(candidates.length)];
        final result = await _broadcast(
          GroupControlMessageKind.transfer,
          targets: stillPresent,
          nextHost: successor,
        );
        // 本端随可信交接消息一同交出权限；未确认接收的成员不能被标为交接成功。
        _hostId = successor;
        _hostEpoch++;
        _known = result.success;
        _publish();
        return result;
      });

  /// 同类重复操作合并，其他操作串行并复核排队前的主持身份、策略版本。
  Future<GroupControlResult> _hostAction(
    String action,
    Future<GroupControlResult> Function() execute,
  ) {
    // 确认时的权限快照随动作入队，等待其他主持动作后不能悄悄采用另一版策略。
    final expectedVersion = _version;
    final expectedHost = _hostId;
    return _guard.singleFlight(
      ('tim.call.control', callId, sessionId, action),
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
        _sending = result.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        return result;
      },
    );
  }

  GroupControlResult _denied() => GroupControlResult({
        selfId: const GroupControlOutcome(
          GroupControlStatus.denied,
          error: '主持身份或通话策略已变更',
        ),
      });

  /// 每种设备独立等待回执，汇总时为每位成员保留失败，当前策略另行同步。
  Future<GroupControlResult> _broadcastDevices(
    Map<GroupControlDevice, (GroupControlAction, bool?)> devices,
  ) async {
    final targets = _members.where((id) => id != selfId).toList();
    final results = await Future.wait(
      devices.entries.map((entry) {
        final (action, allowed) = entry.value;
        return _broadcast(
          GroupControlMessageKind.command,
          targets: targets,
          device: entry.key,
          action: action,
          allowed: allowed,
        );
      }),
    );
    final outcomes = <String, GroupControlOutcome>{};
    // 一位成员的另一设备成功时，不能覆盖本设备已有的失败。
    for (final result in results) {
      for (final entry in result.outcomes.entries) {
        outcomes.update(
          entry.key,
          (prior) => prior.success ? entry.value : prior,
          ifAbsent: () => entry.value,
        );
      }
    }
    // 成员可能错过逐设备指令；同步当前策略也会在其再次入会或重连时重发。
    if (!_disposed && value.canManage) {
      for (final id in targets.where(_sessions.containsKey)) {
        unawaited(
          _send(
            _message(GroupControlMessageKind.sync, id, commandId: _newId()),
          ).catchError((Object _) {}),
        );
      }
    }
    return GroupControlResult(outcomes);
  }

  /// 每个目标单独关联 session 与命令，缺少会控接入的成员必须返回未确认。
  Future<GroupControlResult> _broadcast(
    GroupControlMessageKind kind, {
    required List<String> targets,
    GroupControlDevice? device,
    GroupControlAction? action,
    bool? allowed,
    String? nextHost,
  }) async {
    final outcomes = <String, GroupControlOutcome>{};
    _publish();
    // 各目标单独发送并等待回执，IM 的发送成功不标记设备成功。
    await Future.wait(
      targets.map((id) async {
        if (!_members.contains(id) || _sessions[id] == null) {
          outcomes[id] = const GroupControlOutcome(
            GroupControlStatus.unavailable,
            error: '成员尚未接入会控',
          );
          return;
        }
        final message = _message(
          kind,
          id,
          commandId: _newId(),
          device: device,
          action: action,
          allowed: allowed,
          nextHost: nextHost,
        );
        final pending = _beginPending(id, device);
        final outcome = await _sendAndWait(message);
        outcomes[id] = outcome;
        _finishPending(pending, outcome);
      }),
    );
    return GroupControlResult(outcomes);
  }

  /// 先登记等待项再发送，避免同进程或极速 IM 回执早于登记；超时不补写成功。
  Future<GroupControlOutcome> _sendAndWait(GroupControlMessage message) async {
    final pending = _PendingControl(message);
    _pending[message.commandId] = pending;
    try {
      await _send(message).timeout(ackTimeout);
      return await pending.result.future.timeout(
        _remaining(message),
        onTimeout: () => const GroupControlOutcome(
          GroupControlStatus.timeout,
          error: '未收到设备确认',
        ),
      );
    } catch (_) {
      return const GroupControlOutcome(
        GroupControlStatus.failed,
        error: '控制消息发送失败',
      );
    } finally {
      _pending.remove(message.commandId);
    }
  }

  /// 回执直接完成等待，其余消息按接收顺序验证可信主持和入会身份。
  void _received(GroupControlInbound inbound) {
    if (_disposed) return;
    final message = GroupControlMessage.decode(inbound.payload);
    if (message == null ||
        message.callId != callId ||
        message.groupId != groupId ||
        message.targetUserId != selfId ||
        !_members.contains(inbound.senderId)) {
      return;
    }
    if (message.kind == GroupControlMessageKind.ack ||
        message.kind == GroupControlMessageKind.transferAck) {
      _receiveAck(inbound.senderId, message);
      return;
    }
    _receiving = _receiving
        .then((_) => _receive(inbound.senderId, message))
        .catchError((Object _, StackTrace _) {});
  }

  /// 只以已登记的对端会话、主持代次和实际设备状态完成等待。
  void _receiveAck(String sender, GroupControlMessage ack) {
    final pending = _pending[ack.commandId];
    if (pending == null ||
        pending.userId != sender ||
        pending.sessionId != ack.senderSessionId ||
        ack.targetSessionId != sessionId ||
        ack.hostEpoch != pending.message.hostEpoch ||
        ack.version != pending.message.version ||
        ack.device != pending.message.device ||
        _remaining(pending.message) == Duration.zero ||
        pending.result.isCompleted) {
      return;
    }
    // 线上的 applied 还需要对应动作的 SDK 状态佐证，恢复授权允许设备继续关闭。
    final status = switch (ack.status!) {
      GroupControlAckStatus.applied => _ackMatchesTarget(pending.message, ack)
          ? GroupControlStatus.success
          : GroupControlStatus.unconfirmed,
      GroupControlAckStatus.rejected => GroupControlStatus.denied,
      GroupControlAckStatus.failed => GroupControlStatus.failed,
      GroupControlAckStatus.expired => GroupControlStatus.expired,
    };
    final enabled = switch (ack.deviceState) {
      GroupControlDeviceState.on => true,
      GroupControlDeviceState.off => false,
      _ => null,
    };
    pending.result.complete(
      GroupControlOutcome(
        status,
        microphoneOn:
            ack.device == GroupControlDevice.microphone ? enabled : null,
        cameraOn: ack.device == GroupControlDevice.camera ? enabled : null,
      ),
    );
  }

  /// 成功回执按原指令检查设备；交接和恢复权限没有必须开启的设备。
  bool _ackMatchesTarget(
    GroupControlMessage command,
    GroupControlMessage ack,
  ) =>
      switch (command.action) {
        GroupControlAction.close =>
          ack.deviceState == GroupControlDeviceState.off,
        GroupControlAction.requestOpen =>
          ack.deviceState == GroupControlDeviceState.on,
        GroupControlAction.setAllowed =>
          command.allowed! || ack.deviceState == GroupControlDeviceState.off,
        null => command.kind == GroupControlMessageKind.transfer,
      };

  /// hello 从 SDK 在场成员登记会话，命令和同步必须来自当前可信主持。
  Future<void> _receive(String sender, GroupControlMessage message) async {
    if (_disposed || !_members.contains(sender)) return;
    final expired = _remaining(message) == Duration.zero;
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
        _message(GroupControlMessageKind.sync, sender, commandId: _newId()),
      );
      return;
    }
    if (sender != _hostId ||
        message.targetSessionId != sessionId ||
        _retiredSessions.contains('$sender/${message.senderSessionId}')) {
      return;
    }
    final knownHostSession = _sessions[sender];
    if (knownHostSession != null && knownHostSession != message.senderSessionId) {
      return;
    }
    if (message.kind == GroupControlMessageKind.command) {
      // 设备指令不能建立主持会话，须先完成可信策略同步。
      if (_known &&
          knownHostSession == message.senderSessionId &&
          message.hostEpoch == _hostEpoch) {
        _receiveCommand(sender, message);
      }
      return;
    }
    // 同步和交接延续原通话锚点，较旧同步不能覆盖较新的可信策略。
    final transfer = message.kind == GroupControlMessageKind.transfer;
    if (expired ||
        (transfer
            ? message.hostEpoch != _hostEpoch + 1 ||
                !_members.contains(message.hostId) ||
                message.version <= _version
            : message.hostEpoch != _hostEpoch ||
                message.hostId != _hostId ||
                message.version < _policyVersion) ||
        (_connectedAtMs != null &&
            (_connectedAtMs != message.connectedAtMs ||
                _deadlineMs != message.deadlineMs))) {
      return;
    }
    final wasKnown = _known;
    _sessions[sender] = message.senderSessionId;
    if (message.version > _version) _version = message.version;
    _policyVersion = message.version;
    _connectedAtMs = message.connectedAtMs;
    _deadlineMs = message.deadlineMs;
    _allowUnmute = message.allowSelfUnmute!;
    _muteBlocksUnmute = message.muteBlocksUnmute!;
    _allowVideo = message.allowVideo!;
    _muteAll = message.muteAll!;
    _cameraAllClosed = message.cameraAllClosed!;
    _known = true;
    _finishSyncRequest();
    if (transfer) {
      _hostId = message.hostId!;
      _hostEpoch = message.hostEpoch;
      _deviceVersions.clear();
      _memberPermissions.clear();
      _sessions.addAll(
        Map.fromEntries(
          message.sessions!.entries.where(
            (e) =>
                _members.contains(e.key) &&
                e.value.isNotEmpty &&
                !_retiredSessions.contains('${e.key}/${e.value}'),
          ),
        ),
      );
      _publish();
      await _send(
        _replyMessage(sender, message, _actual(GroupControlStatus.success)),
      );
    } else {
      // 同步只替代不晚于该快照的逐设备权限，不能撤销已经收到的后续操作。
      _memberPermissions.removeWhere(
        (device, _) => (_deviceVersions[device] ?? -1) <= message.version,
      );
      _publish();
      if (wasKnown) {
        await _applyRestrictions();
      } else {
        // 首次同步执行明确关停；允许策略保留本人已选的设备状态。
        await Future.wait([
          if (_muteAll || !_canOpen(GroupControlDevice.microphone))
            _executeDevice(GroupControlDevice.microphone, false),
          if (!_selfCameraSelected || _cameraAllClosed || !value.canOpenCamera)
            _applyJoinCamera(),
        ]);
      }
    }
  }

  /// 等待本人确认前登记版本，后续关停或禁止无需等待弹窗结束。
  void _receiveCommand(String sender, GroupControlMessage message) {
    final key = '$sender/${message.senderSessionId}/${message.commandId}';
    final cached = _ackCache[key];
    if (cached != null) {
      unawaited(_send(cached).catchError((Object _) {}));
      return;
    }
    if (_runningCommands.contains(key)) return;
    if (_remaining(message) == Duration.zero) {
      // 过期指令只回执，不占用当前设备的版本或处理中状态。
      unawaited(
        _cacheAndSendAck(
          sender,
          message,
          key,
          _actual(GroupControlStatus.expired),
        ).catchError((Object _) {}),
      );
      return;
    }
    final device = message.device!;
    if (message.version <= (_deviceVersions[device] ?? -1) ||
        (message.action == GroupControlAction.setAllowed &&
            message.version < _policyVersion)) {
      return;
    }
    _deviceVersions[device] = message.version;
    if (message.version > _version) _version = message.version;
    _runningCommands.add(key);
    final pending = _beginPending(selfId, device);
    unawaited(
      _completeCommand(
        sender,
        message,
        key,
        pending,
      ).catchError((Object _, StackTrace _) {}),
    );
  }

  /// 完成设备动作后记下回执，同一指令重传只返回该执行结果。
  Future<void> _completeCommand(
    String sender,
    GroupControlMessage message,
    String key,
    ((String, GroupControlDevice?), Object) pending,
  ) async {
    GroupControlOutcome outcome;
    try {
      outcome = await _apply(message);
    } catch (_) {
      outcome = _actual(GroupControlStatus.failed, '设备执行失败');
    } finally {
      _runningCommands.remove(key);
    }
    if (_disposed) return;
    _finishPending(pending, outcome);
    await _cacheAndSendAck(sender, message, key, outcome);
  }

  /// 先缓存再发送，IM 发送失败也能在指令重发时返回同一执行结果。
  Future<void> _cacheAndSendAck(
    String sender,
    GroupControlMessage message,
    String key,
    GroupControlOutcome outcome,
  ) async {
    final ack = _replyMessage(sender, message, outcome);
    if (_ackCache.length >= 256) _ackCache.remove(_ackCache.keys.first);
    _ackCache[key] = ack;
    await _send(ack);
  }

  /// 远端开启需要本次指令的本人许可，授权恢复本身不启动采集。
  Future<GroupControlOutcome> _apply(GroupControlMessage message) async {
    final device = message.device!;
    bool current() =>
        !_disposed &&
        _known &&
        _hostEpoch == message.hostEpoch &&
        _sessions[_hostId] == message.senderSessionId &&
        _deviceVersions[device] == message.version &&
        _remaining(message) != Duration.zero;
    if (!current()) return _actual(GroupControlStatus.expired);
    // 更新授权后立即生效，即使本机暂时未确认停止采集也禁止用户重新开启。
    if (message.action == GroupControlAction.setAllowed) {
      _memberPermissions[device] = message.allowed!;
      _publish();
      if (message.allowed!) return _actual(GroupControlStatus.success);
    }
    final opening = message.action == GroupControlAction.requestOpen;
    if (opening) {
      if (!_canOpen(device)) return _actual(GroupControlStatus.denied);
      final remaining = _remaining(message);
      final confirmed = await _confirmDeviceOpen
          ?.call(device, remaining)
          .timeout(remaining, onTimeout: () => false);
      // 弹窗返回时旧主持或旧指令可能已失效，系统授权完成后还会再校验。
      if (!current()) return _actual(GroupControlStatus.expired);
      if (confirmed != true || !_canOpen(device)) {
        return _actual(GroupControlStatus.denied);
      }
    }
    return _executeDevice(device, opening, isCommandCurrent: current);
  }

  /// 禁止策略关闭相关设备；允许策略保留成员自己的当前设备选择。
  Future<void> _applyRestrictions() async {
    // 同步可能同时限制两种设备，一种设备失败仍须关闭另一种设备。
    await Future.wait([
      for (final device in GroupControlDevice.values)
        if (!_canOpen(device) &&
            (_deviceOn(device) || _pendingOwners.containsKey((selfId, device))))
          _executeDevice(
            device,
            false,
            isCommandCurrent: () => !_canOpen(device),
          ),
    ]);
  }

  /// 只在已知策略下按视频入会默认值自动开摄像头；手动开启单独按设备权限判断。
  Future<GroupControlOutcome> _applyJoinCamera() => _executeDevice(
        GroupControlDevice.camera,
        video && _known && !_cameraAllClosed && value.canOpenCamera,
      );

  /// 默认准备、本人操作和远端命令按设备串行，旧版本不能覆盖后发策略。
  Future<GroupControlOutcome> _executeDevice(
    GroupControlDevice device,
    bool enabled, {
    bool Function()? isCommandCurrent,
  }) {
    final expected = _version;
    final result = (_mediaQueues[device] ?? Future<void>.value())
        .then<GroupControlOutcome>((_) async {
      bool current() =>
          !_disposed &&
          (isCommandCurrent?.call() ?? (expected == _version)) &&
          (!enabled ||
              (_canOpen(device) &&
                  (_deadlineMs == null ||
                      _now().millisecondsSinceEpoch < _deadlineMs!)));
      if (!current()) return _actual(GroupControlStatus.expired);
      try {
        return await _media.setDevice(device, enabled, isCurrent: current);
      } catch (_) {
        return _actual(GroupControlStatus.failed, '设备执行失败');
      }
    });
    _mediaQueues[device] = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  GroupControlOutcome _actual(GroupControlStatus status, [String? error]) =>
      GroupControlOutcome(
        status,
        error: error,
        microphoneOn: _media.microphoneOn,
        cameraOn: _media.cameraOn,
      );

  /// 本人和远端开启共用当前策略，关闭操作始终可执行。
  bool _canOpen(GroupControlDevice device) =>
      device == GroupControlDevice.microphone
          ? value.canOpenMicrophone
          : value.canOpenCamera;

  /// 依据 SDK 状态判断有无采集，避免策略同步重复关闭已停止的设备。
  bool _deviceOn(GroupControlDevice device) =>
      device == GroupControlDevice.microphone
          ? _media.microphoneOn
          : _media.cameraOn;

  /// 发送和确认都使用指令的剩余时间，超时不会延长有效期。
  Duration _remaining(GroupControlMessage message) => Duration(
        milliseconds:
            max(0, message.expiresAtMs! - _now().millisecondsSinceEpoch),
      );

  /// 每条定向消息固定当前入会，策略快照只附在同步及交接消息上。
  GroupControlMessage _message(
    GroupControlMessageKind kind,
    String target, {
    required String commandId,
    String? targetSession,
    GroupControlDevice? device,
    GroupControlAction? action,
    bool? allowed,
    String? nextHost,
  }) {
    final carriesPolicy = kind == GroupControlMessageKind.sync ||
        kind == GroupControlMessageKind.transfer;
    final ttl = action == GroupControlAction.requestOpen
        ? _openRequestTimeout
        : ackTimeout;
    return GroupControlMessage(
      kind: kind,
      callId: callId,
      groupId: groupId,
      commandId: commandId,
      senderSessionId: sessionId,
      targetUserId: target,
      targetSessionId: targetSession ?? _sessions[target] ?? '',
      version: _version,
      expiresAtMs: _now().add(ttl).millisecondsSinceEpoch,
      hostId: carriesPolicy ? nextHost ?? _hostId : null,
      hostEpoch: _hostEpoch + (nextHost == null ? 0 : 1),
      allowSelfUnmute: carriesPolicy ? _allowUnmute : null,
      muteBlocksUnmute: carriesPolicy ? _muteBlocksUnmute : null,
      allowVideo: carriesPolicy ? _allowVideo : null,
      muteAll: carriesPolicy ? _muteAll : null,
      cameraAllClosed: carriesPolicy ? _cameraAllClosed : null,
      connectedAtMs: carriesPolicy ? _connectedAtMs : null,
      deadlineMs: carriesPolicy ? _deadlineMs : null,
      sessions: nextHost != null ? Map.unmodifiable(_sessions) : null,
      device: device,
      action: action,
      allowed: allowed,
    );
  }

  /// 回执调换收发入会标识，仅报告原指令对应设备的 SDK 状态。
  GroupControlMessage _replyMessage(
    String sender,
    GroupControlMessage original,
    GroupControlOutcome result,
  ) {
    final device = original.device;
    // 每次只回报原指令所控设备，系统执行结果映射到线上状态枚举。
    final enabled = switch (device) {
      GroupControlDevice.microphone => result.microphoneOn,
      GroupControlDevice.camera => result.cameraOn,
      null => null,
    };
    return GroupControlMessage(
      kind: device == null
          ? GroupControlMessageKind.transferAck
          : GroupControlMessageKind.ack,
      callId: callId,
      groupId: groupId,
      commandId: original.commandId,
      senderSessionId: sessionId,
      targetUserId: sender,
      targetSessionId: original.senderSessionId,
      version: original.version,
      hostEpoch: original.hostEpoch,
      device: device,
      status: switch (result.status) {
        GroupControlStatus.success => GroupControlAckStatus.applied,
        GroupControlStatus.denied => GroupControlAckStatus.rejected,
        GroupControlStatus.expired => GroupControlAckStatus.expired,
        _ => GroupControlAckStatus.failed,
      },
      deviceState: device == null
          ? null
          : switch (enabled) {
              true => GroupControlDeviceState.on,
              false => GroupControlDeviceState.off,
              null => result.status == GroupControlStatus.unavailable
                  ? GroupControlDeviceState.unavailable
                  : GroupControlDeviceState.unknown,
            },
    );
  }

  /// 序列化后直接走本场在线 C2C 通道。
  Future<void> _send(GroupControlMessage message) =>
      _transport.send(message.targetUserId, jsonEncode(message.toJson()));

  /// 自行操作和远端控制共用等待出口，操作身份用于拒绝迟到结果覆盖后续操作。
  ((String, GroupControlDevice?), Object) _beginPending(
    String id,
    GroupControlDevice? device,
  ) {
    final key = (id, device);
    final owner = Object();
    _pendingOwners[key] = owner;
    if (device != null) _deviceResults.remove((id, device));
    _publish();
    return (key, owner);
  }

  /// 旧操作完成只返回给原调用者，不清除或覆盖同一设备的新操作。
  void _finishPending(
    ((String, GroupControlDevice?), Object) pending,
    GroupControlOutcome? outcome,
  ) {
    final (key, owner) = pending;
    if (!identical(_pendingOwners[key], owner)) return;
    _pendingOwners.remove(key);
    if (outcome != null) {
      final (id, device) = key;
      _results[id] = outcome;
      if (device != null) _deviceResults[(id, device)] = outcome;
    }
    _publish();
  }

  /// 只读状态复制集合，UI 无法修改控制器正在等待或已经验证的结果。
  void _publish() {
    if (_disposed) return;
    final pendingByUserId = <String, Set<GroupControlDevice?>>{};
    for (final (id, device) in _pendingOwners.keys) {
      pendingByUserId.putIfAbsent(id, () => {}).add(device);
    }
    value = GroupControlState(
      callId: callId,
      sessionId: sessionId,
      selfId: selfId,
      hostId: _hostId,
      policyKnown: _known,
      version: _version,
      allowSelfUnmute: _canMemberUnmute,
      allowVideo: _canMemberOpenCamera,
      muteAll: _muteAll,
      cameraAllClosed: _cameraAllClosed,
      microphoneOn: _media.microphoneOn,
      cameraOn: _media.cameraOn,
      connectedAtMs: _connectedAtMs,
      deadlineMs: _deadlineMs,
      pendingByUserId: pendingByUserId,
      resultsByUserId: _results,
      resultsByDevice: _deviceResults,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _finishSyncRequest();
    _subscription.cancel();
    _media.changes.removeListener(_publish);
    for (final pending in _pending.values) {
      if (!pending.result.isCompleted) {
        pending.result.complete(
          const GroupControlOutcome(GroupControlStatus.expired),
        );
      }
    }
    _pending.clear();
    _pendingOwners.clear();
    _sessions.clear();
    _ackCache.clear();
    _runningCommands.clear();
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
