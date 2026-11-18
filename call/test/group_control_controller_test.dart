import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/control/group_control_media.dart';
import 'package:tencent_calls_uikit/src/control/group_control_message.dart';
import 'package:tencent_calls_uikit/src/control/group_control_transport.dart';
import 'package:tencent_calls_uikit/src/manager/group_control_controller.dart';
import 'package:tencent_calls_uikit/src/state/group_control_state.dart';

void main() {
  late _Network network;
  late Map<String, GroupControlController> controls;
  late Map<String, _Media> media;
  late DateTime clock;
  var serial = 0;
  GroupControlController create(String id,
      {String? trustedHost, int epoch = 0}) {
    final device = _Media();
    media[id] = device;
    final controller = GroupControlController(
        callId: 'call',
        selfId: id,
        inviterId: 'host',
        groupId: 'group',
        video: true,
        transport: network.transport(id),
        media: device,
        guard: ActionGuard(),
        trustedHostId: trustedHost,
        trustedHostEpoch: epoch,
        newId: () => '$id-${++serial}',
        random: Random(1),
        now: () => clock,
        ackTimeout: const Duration(milliseconds: 200));
    controls[id] = controller;
    controller.updateMembers(['host', 'a', 'b']);
    return controller;
  }

  Future<void> flush() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> joinAll() async {
    for (final id in ['host', 'a', 'b']) {
      await create(id).start();
    }
    await flush();
  }

  setUp(() {
    network = _Network();
    controls = {};
    media = {};
    serial = 0;
    clock = DateTime.utc(2026, 11, 17);
  });
  tearDown(() async {
    for (final controller in controls.values) {
      controller.dispose();
    }
    await network.dispose();
  });

  test('真实发送者同步策略，全员静音默认禁止自行开，授权不等于立即开麦', () async {
    await joinAll();
    final host = controls['host']!;
    final member = controls['a']!;
    expect(member.value.policyKnown, isTrue);
    expect(member.value.canManage, isFalse);
    expect((await host.muteAll()).success, isTrue);
    expect(member.value.allowSelfUnmute, isFalse);
    expect(media.values.every((m) => !m.microphoneOn), isTrue);
    final denied =
        await member.setMemberDevice('a', GroupControlDevice.microphone, true);
    expect(denied.success, isFalse);
    expect(
        member.value.resultsByUserId['a']!.status, GroupControlStatus.denied);
    expect((await host.updatePolicy(allowSelfUnmute: true)).success, isTrue);
    expect(media['a']!.microphoneOn, isFalse);
    expect(
        (await member.setMemberDevice('a', GroupControlDevice.microphone, true))
            .success,
        isTrue);
    expect((await host.unmuteAll()).success, isTrue);
    expect(media.values.every((m) => m.microphoneOn), isTrue);
  });

  test('伪造主持、非目标、旧session、乱序和重复命令不能重复执行设备', () async {
    await joinAll();
    final host = controls['host']!;
    await host.muteAll();
    final packet = network.sent
        .lastWhere((entry) =>
            entry.$1 == 'host' &&
            entry.$2.kind == GroupControlMessageKind.command &&
            entry.$2.targetUserId == 'a')
        .$2;
    final before = media['a']!.operations.length;
    network.deliver('b', packet);
    network.deliver('host', packet);
    for (final changes in <Map<String, Object?>>[
      {
        'commandId': 'wrong-session',
        'targetSessionId': 'old-session',
        'enabled': true
      },
      {'commandId': 'wrong-user', 'targetUserId': 'b', 'enabled': true},
      {'commandId': 'old-version', 'version': 0, 'enabled': true},
      {'commandId': 'expired', 'expiresAtMs': 1, 'enabled': true},
    ]) {
      network.deliverTo(
          'a', 'host', jsonEncode({...packet.toJson(), ...changes}));
    }
    await flush();
    expect(media['a']!.operations.length, before);
    expect(media['a']!.microphoneOn, isFalse);
  });

  test('旧session命令不能影响重入，新session按当前策略重置个人静音', () async {
    await joinAll();
    final host = controls['host']!;
    await host.setMemberDevice('a', GroupControlDevice.microphone, false);
    final old = network.sent
        .lastWhere((e) =>
            e.$1 == 'host' &&
            e.$2.kind == GroupControlMessageKind.command &&
            e.$2.targetUserId == 'a')
        .$2;
    controls.remove('a')!.dispose();
    host.updateMembers(['host', 'b']);
    host.updateMembers(['host', 'a', 'b']);
    final rejoined = create('a');
    await rejoined.start();
    await flush();
    expect(rejoined.sessionId, isNot(old.targetSessionId));
    expect(media['a']!.microphoneOn, isTrue);
    network.deliver('host', old);
    await flush();
    expect(media['a']!.microphoneOn, isTrue);
    await host.muteAll();
    controls.remove('a')!.dispose();
    host.updateMembers(['host', 'b']);
    host.updateMembers(['host', 'a', 'b']);
    await create('a').start();
    await flush();
    expect(media['a']!.microphoneOn, isFalse);
    expect(controls['a']!.value.canOpenMicrophone, isFalse);
  });

  test('主持交接使用可信管理员，原主持重入不能恢复旧权限', () async {
    await joinAll();
    network.admins = {'b'};
    final host = controls['host']!;
    expect((await host.prepareLeave()).success, isTrue);
    expect(controls.values.every((c) => c.value.hostId == 'b'), isTrue);
    expect(controls['b']!.value.canManage, isTrue);
    expect((await host.muteAll()).success, isFalse);
    controls.remove('host')!.dispose();
    for (final controller in controls.values) {
      controller.updateMembers(['a', 'b']);
    }
    for (final controller in controls.values) {
      controller.updateMembers(['a', 'b', 'host']);
    }
    final rejoined = create('host', trustedHost: 'b', epoch: 1);
    await rejoined.start();
    await flush();
    expect(rejoined.value.policyKnown, isTrue);
    expect(rejoined.value.canManage, isFalse);
    expect(rejoined.value.hostId, 'b');
  });

  test('首次主持固定截止，晚加入和交接继承同一一小时窗口', () async {
    final host = create('host');
    await host.start();
    final connectedAt = host.value.connectedAtMs!;
    final deadline = host.value.deadlineMs!;
    expect(deadline - connectedAt, 3600000);
    clock = clock.add(const Duration(minutes: 30));
    final late = create('a');
    await late.start();
    await flush();
    expect(late.value.connectedAtMs, connectedAt);
    expect(late.value.deadlineMs, deadline);
    clock = clock.add(const Duration(minutes: 20));
    final successor = create('b');
    await successor.start();
    await flush();
    network.admins = {'b'};
    expect((await host.prepareLeave()).success, isTrue);
    expect(successor.value.hostId, 'b');
    expect(successor.value.connectedAtMs, connectedAt);
    expect(successor.value.deadlineMs, deadline);
    expect(late.value.deadlineMs, deadline);
  });

  test('丢失ACK和系统权限拒绝均不是成功，真实发送成功不提前更新结果', () async {
    await joinAll();
    network.dropAckFrom = 'a';
    final result = await controls['host']!
        .setMemberDevice('a', GroupControlDevice.microphone, false);
    expect(result.outcomes['a']!.status, GroupControlStatus.timeout);
    expect(media['a']!.microphoneOn, isFalse);
    network.dropAckFrom = null;
    media['a']!.denyOpen = true;
    final denied = await controls['host']!
        .setMemberDevice('a', GroupControlDevice.microphone, true);
    expect(denied.outcomes['a']!.status, GroupControlStatus.denied);
    expect(denied.success, isFalse);
  });

  test('未知策略关闭设备，本人等待真实结果时提供统一pending', () async {
    final member = create('a');
    media['a']!.microphone = true;
    await member.start();
    await flush();
    expect(member.value.policyKnown, isFalse);
    expect(member.value.microphoneOn, isFalse);
    expect(
        (await member.setSelfDevice(GroupControlDevice.microphone, true))
            .success,
        isFalse);
    final pending = Completer<void>();
    media['a']!.delay = pending;
    final close = member.setSelfDevice(GroupControlDevice.camera, false);
    await Future<void>.delayed(Duration.zero);
    expect(member.value.pendingByUserId['a'], GroupControlDevice.camera);
    pending.complete();
    expect((await close).success, isTrue);
    expect(member.value.pendingByUserId, isEmpty);
  });

  test('ACK 版本不符不能完成等待，成功 ACK 设备不一致仍显示未确认', () async {
    await joinAll();
    network.dropAckFrom = 'a';
    final pending = controls['host']!
        .setMemberDevice('a', GroupControlDevice.microphone, false);
    await flush();
    final ack = network.sent.lastWhere((entry) => entry.$1 == 'a').$2;
    network.deliverTo(
        'host', 'a', jsonEncode({...ack.toJson(), 'version': ack.version + 1}));
    await flush();
    expect(controls['host']!.value.pendingByUserId.containsKey('a'), isTrue);
    network.deliverTo(
        'host', 'a', jsonEncode({...ack.toJson(), 'microphoneOn': true}));
    expect(
        (await pending).outcomes['a']!.status, GroupControlStatus.unconfirmed);
  });

  test('重复全员命令合并，完成后允许再次执行', () async {
    await joinAll();
    final blocked = Completer<void>();
    media['a']!.delay = blocked;
    final host = controls['host']!;
    final first = host.muteAll();
    final repeated = host.muteAll();
    await flush();
    expect(
        network.sent
            .where((entry) =>
                entry.$1 == 'host' &&
                entry.$2.kind == GroupControlMessageKind.command &&
                entry.$2.targetUserId == 'a')
            .length,
        1);
    blocked.complete();
    expect((await first).success, isTrue);
    expect(identical(await first, await repeated), isTrue);
    media['a']!.delay = null;
    expect((await host.unmuteAll()).success, isTrue);
    expect((await host.muteAll()).success, isTrue);
  });

  test('协议生成器拒绝未知结构、字段类型和版本，未识别载荷不执行', () {
    expect(GroupControlMessage.decode('{"protocol":"other"}'), isNull);
    final packet = GroupControlMessage(
        kind: GroupControlMessageKind.hello,
        callId: 'call',
        commandId: 'id',
        senderSessionId: 's',
        targetUserId: 'host',
        targetSessionId: '',
        version: 0,
        expiresAtMs: 123);
    expect(GroupControlMessage.decode(jsonEncode(packet.toJson())), isNotNull);
    for (final changes in <Map<String, Object?>>[
      {'version': '1'},
      {'version': 1.5},
      {'schemaVersion': 2},
      {'unknown': true},
      {'callId': ''},
    ]) {
      expect(
          GroupControlMessage.decode(
              jsonEncode({...packet.toJson(), ...changes})),
          isNull);
    }
  });
}

class _Media extends ChangeNotifier implements GroupControlMedia {
  bool microphone = false, camera = false, denyOpen = false;
  Completer<void>? delay;
  final List<(GroupControlDevice, bool)> operations = [];
  @override
  Listenable get changes => this;
  @override
  bool get microphoneOn => microphone;
  @override
  bool get cameraOn => camera;
  @override
  Future<GroupControlOutcome> setDevice(GroupControlDevice device, bool enabled,
      {required bool Function() isCurrent}) async {
    if (delay != null) await delay!.future;
    if (!isCurrent()) {
      return const GroupControlOutcome(GroupControlStatus.expired);
    }
    operations.add((device, enabled));
    if (enabled && denyOpen) {
      return const GroupControlOutcome(GroupControlStatus.denied);
    }
    if (device == GroupControlDevice.microphone) {
      microphone = enabled;
    } else {
      camera = enabled;
    }
    notifyListeners();
    return GroupControlOutcome(GroupControlStatus.success,
        microphoneOn: microphone, cameraOn: camera);
  }
}

class _Network {
  final Map<String, StreamController<GroupControlInbound>> streams = {};
  final List<(String, GroupControlMessage)> sent = [];
  Set<String> admins = {};
  String? dropAckFrom;
  _Transport transport(String id) => _Transport(this, id);
  void deliver(String sender, GroupControlMessage packet) =>
      deliverTo(packet.targetUserId, sender, jsonEncode(packet.toJson()));
  void deliverTo(String target, String sender, String payload) =>
      streams[target]
          ?.add(GroupControlInbound(senderId: sender, payload: payload));
  Future<void> dispose() async {
    for (final stream in streams.values) {
      await stream.close();
    }
  }
}

class _Transport implements GroupControlTransport {
  _Transport(this.network, this.self) {
    network.streams
        .putIfAbsent(self, () => StreamController.broadcast(sync: true));
  }
  final _Network network;
  final String self;
  @override
  Stream<GroupControlInbound> get messages => network.streams[self]!.stream;
  @override
  Future<Set<String>> loadAdministrators(
          String groupId, List<String> memberIds) async =>
      network.admins;
  @override
  Future<void> send(String targetUserId, String payload) async {
    final packet = GroupControlMessage.decode(payload)!;
    network.sent.add((self, packet));
    if (network.dropAckFrom == self &&
        packet.kind == GroupControlMessageKind.ack) {
      return;
    }
    network.deliverTo(targetUserId, self, payload);
  }
}
