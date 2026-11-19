import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/control/group_control_media.dart';
import 'package:tencent_calls_uikit/src/control/group_control_message.dart';
import 'package:tencent_calls_uikit/src/control/group_control_transport.dart';
import 'package:tencent_calls_uikit/src/control/harmony_group_control_media.dart';
import 'package:tencent_calls_uikit/src/manager/group_control_controller.dart';
import 'package:tencent_calls_uikit/src/manager/group_control_lifecycle.dart';
import 'package:tencent_calls_uikit/src/state/group_control_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Network network;
  late Map<String, GroupControlController> controls;
  late Map<String, _Media> media;
  late DateTime clock;
  late Map<String, Future<bool> Function(GroupControlDevice)> confirmations;
  var serial = 0;
  GroupControlController create(
    String id, {
    String? trustedHost,
    int epoch = 0,
    bool video = true,
  }) {
    final device = _Media();
    media[id] = device;
    final controller = GroupControlController(
      callId: 'call',
      selfId: id,
      inviterId: 'host',
      groupId: 'group',
      video: video,
      transport: network.transport(id),
      media: device,
      guard: ActionGuard(),
      confirmDeviceOpen: (device, _) async =>
          await confirmations[id]?.call(device) ?? true,
      trustedHostId: trustedHost,
      trustedHostEpoch: epoch,
      newId: () => '$id-${++serial}',
      random: Random(1),
      now: () => clock,
      ackTimeout: const Duration(milliseconds: 200),
    );
    controls[id] = controller;
    controller.updateMembers(['host', 'a', 'b']);
    return controller;
  }

  /// 修改线上载荷部分字段，保留 OA v1 外层供边界测试使用。
  String withPayload(GroupControlMessage packet, Map<String, Object?> changes) {
    final envelope = packet.toJson();
    return jsonEncode({
      ...envelope,
      'payload': {...envelope['payload'] as Map<String, dynamic>, ...changes},
    });
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
    confirmations = {};
    serial = 0;
    clock = DateTime.utc(2026, 11, 17);
  });
  tearDown(() async {
    for (final controller in controls.values) {
      controller.dispose();
    }
    await network.dispose();
  });

  for (final video in [true, false]) {
    test('主叫入会时${video ? '视频默认开' : '语音默认关'}相机，不等待麦克风', () async {
      final host = create('host', video: video);
      final device = media['host']!;
      device.delay = Completer<void>();
      device.cameraDelay = Completer<void>()..complete();
      final joined = host.start();
      try {
        await flush();
        expect(host.value.microphoneOn, isFalse);
        expect(host.value.cameraOn, video);
        expect(device.operations, [(GroupControlDevice.camera, video)]);
      } finally {
        device.delay!.complete();
        await joined;
      }
    });
  }

  test('被叫首次同步允许视频后默认开摄像头，禁止视频时保持关闭', () async {
    final host = create('host');
    await host.start();
    final first = create('a');
    await first.start();
    await flush();
    expect(first.value.cameraOn, isTrue);

    await host.updatePolicy(allowVideo: false);
    final lateMember = create('b');
    await lateMember.start();
    await flush();
    expect(lateMember.value.policyKnown, isTrue);
    expect(lateMember.value.cameraOn, isFalse);
  });

  test('首个握手早于主持端成员事件时重试，随后可控制两个设备', () async {
    final host = create('host')..updateMembers(['host']);
    await host.start();
    final member = create('a');
    await member.start();
    await flush();
    expect(member.value.policyKnown, isFalse);
    expect(member.value.canOpenMicrophone, isTrue);
    expect(member.value.microphoneOn, isTrue);
    expect(
      (await member.setSelfDevice(
        GroupControlDevice.microphone,
        false,
      )).success,
      isTrue,
    );

    final synced = Completer<void>();
    void onPolicy() {
      if (member.value.policyKnown && !synced.isCompleted) synced.complete();
    }

    member.addListener(onPolicy);
    try {
      host.updateMembers(['host', 'a']);
      await synced.future.timeout(const Duration(seconds: 3));
    } finally {
      member.removeListener(onPolicy);
    }
    await flush();
    expect(media['a']!.microphoneOn, isFalse);
    expect(media['a']!.cameraOn, isTrue);
    expect(
      (await member.setSelfDevice(GroupControlDevice.microphone, true)).success,
      isTrue,
    );
    for (final device in GroupControlDevice.values) {
      final result = await host.setMemberDevice('a', device, false);
      expect(result.success, isTrue, reason: device.name);
    }
    expect(media['a']!.microphoneOn, isFalse);
    expect(media['a']!.cameraOn, isFalse);
  });

  test('真实发送者同步策略，全员静音默认禁止自行开，授权不等于立即开麦', () async {
    await joinAll();
    final host = controls['host']!;
    final member = controls['a']!;
    expect(member.value.policyKnown, isTrue);
    expect(member.value.canManage, isFalse);
    expect((await host.muteAll()).success, isTrue);
    expect(member.value.allowSelfUnmute, isFalse);
    expect(media['host']!.microphoneOn, isTrue);
    expect(media['a']!.microphoneOn, isFalse);
    expect(media['b']!.microphoneOn, isFalse);
    final denied = await member.setMemberDevice(
      'a',
      GroupControlDevice.microphone,
      true,
    );
    expect(denied.success, isFalse);
    expect(
      member.value.resultsByUserId['a']!.status,
      GroupControlStatus.denied,
    );
    expect((await host.updatePolicy(allowSelfUnmute: true)).success, isTrue);
    expect(media['a']!.microphoneOn, isFalse);
    expect(
      (await member.setMemberDevice(
        'a',
        GroupControlDevice.microphone,
        true,
      )).success,
      isTrue,
    );
    expect((await host.unmuteAll()).success, isTrue);
    expect(media['a']!.microphoneOn, isTrue);
    expect(media['b']!.microphoneOn, isFalse);
  });

  test('伪造主持、非目标、旧session、乱序和重复命令不能重复执行设备', () async {
    await joinAll();
    final host = controls['host']!;
    await host.muteAll();
    final packet = network.sent
        .lastWhere(
          (entry) =>
              entry.$1 == 'host' &&
              entry.$2.kind == GroupControlMessageKind.command &&
              entry.$2.targetUserId == 'a',
        )
        .$2;
    final before = media['a']!.operations.length;
    network.deliver('b', packet);
    network.deliver('host', packet);
    for (final changes in <Map<String, Object?>>[
      {
        'commandId': 'wrong-session',
        'targetSessionId': 'old-session',
        'revision': 2,
      },
      {'commandId': 'wrong-user', 'targetUserId': 'b', 'revision': 2},
      {'commandId': 'wrong-group', 'groupId': 'other-group', 'revision': 2},
      {'commandId': 'old-version', 'revision': 0},
      {'commandId': 'expired', 'expiresAtMs': 1, 'revision': 2},
    ]) {
      network.deliverTo('a', 'host', withPayload(packet, changes));
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
        .lastWhere(
          (e) =>
              e.$1 == 'host' &&
              e.$2.kind == GroupControlMessageKind.command &&
              e.$2.targetUserId == 'a',
        )
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
    final mutedMember = create('a');
    await mutedMember.start();
    await flush();
    expect(media['a']!.microphoneOn, isFalse);
    expect(mutedMember.value.canOpenMicrophone, isFalse);
    mutedMember.updateMembers(['a', 'b']);
    expect(mutedMember.value.policyKnown, isFalse);
    expect(mutedMember.value.canOpenMicrophone, isFalse);
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
    final result = await controls['host']!.setMemberDevice(
      'a',
      GroupControlDevice.microphone,
      false,
    );
    expect(result.outcomes['a']!.status, GroupControlStatus.timeout);
    expect(media['a']!.microphoneOn, isFalse);
    network.dropAckFrom = null;
    media['a']!.denyOpen = true;
    final denied = await controls['host']!.setMemberDevice(
      'a',
      GroupControlDevice.microphone,
      true,
    );
    expect(denied.outcomes['a']!.status, GroupControlStatus.failed);
    expect(denied.success, isFalse);
  });

  test('未同步时默认开麦且能自行开关，摄像头仍须等授权', () async {
    final member = create('a');
    await member.start();
    await flush();
    expect(member.value.policyKnown, isFalse);
    expect(member.value.microphoneOn, isTrue);
    expect(member.value.canManage, isFalse);
    expect(member.value.canOpenCamera, isFalse);
    expect(member.value.cameraOn, isFalse);
    expect(
      (await member.setSelfDevice(
        GroupControlDevice.microphone,
        false,
      )).success,
      isTrue,
    );
    final pending = Completer<void>();
    media['a']!.delay = pending;
    final open = member.setSelfDevice(GroupControlDevice.microphone, true);
    await Future<void>.delayed(Duration.zero);
    expect(member.value.pendingByUserId['a'], {GroupControlDevice.microphone});
    pending.complete();
    expect((await open).success, isTrue);
    expect(member.value.microphoneOn, isTrue);
    expect(member.value.pendingByUserId, isEmpty);
  });

  test('摄像头等待期间可独立控制麦克风，短操作完成不清除另一设备进度', () async {
    await joinAll();
    final host = controls['host']!;
    final cameraGate = Completer<void>();
    media['host']!.cameraDelay = cameraGate;
    final camera = host.setSelfDevice(GroupControlDevice.camera, true);
    await flush();
    expect(
      host.value.isDevicePending('host', GroupControlDevice.camera),
      isTrue,
    );
    expect(
      host.value.isDevicePending('host', GroupControlDevice.microphone),
      isFalse,
    );
    final microphone = await host.setSelfDevice(
      GroupControlDevice.microphone,
      false,
    );
    expect(microphone.success, isTrue);
    expect(
      host.value.isDevicePending('host', GroupControlDevice.camera),
      isTrue,
    );
    expect(
      host
          .value
          .resultsByDevice[('host', GroupControlDevice.microphone)]
          ?.success,
      isTrue,
    );
    cameraGate.complete();
    expect((await camera).success, isTrue);
    expect(host.value.pendingByUserId, isEmpty);
  });

  test('ACK 版本不符不能完成等待，成功 ACK 设备不一致仍显示未确认', () async {
    await joinAll();
    network.dropAckFrom = 'a';
    final pending = controls['host']!.setMemberDevice(
      'a',
      GroupControlDevice.microphone,
      false,
    );
    await flush();
    final ack = network.sent.lastWhere((entry) => entry.$1 == 'a').$2;
    network.deliverTo(
      'host',
      'a',
      withPayload(ack, {'revision': ack.version + 1}),
    );
    await flush();
    expect(controls['host']!.value.pendingByUserId.containsKey('a'), isTrue);
    network.deliverTo('host', 'a', withPayload(ack, {'deviceState': 'on'}));
    expect(
      (await pending).outcomes['a']!.status,
      GroupControlStatus.unconfirmed,
    );
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
          .where(
            (entry) =>
                entry.$1 == 'host' &&
                entry.$2.kind == GroupControlMessageKind.command &&
                entry.$2.targetUserId == 'a',
          )
          .length,
      1,
    );
    blocked.complete();
    expect((await first).success, isTrue);
    expect(identical(await first, await repeated), isTrue);
    media['a']!.delay = null;
    expect((await host.unmuteAll()).success, isTrue);
    expect((await host.muteAll()).success, isTrue);
  });

  test('开启须本人确认，拒绝、等待和确认分别反映真实执行结果', () async {
    await joinAll();
    final host = controls['host']!;
    final member = media['a']!;
    await host.setMemberDevice('a', GroupControlDevice.camera, false);
    final decision = Completer<bool>();
    confirmations['a'] = (_) => decision.future;
    final open = host.setMemberDevice('a', GroupControlDevice.camera, true);
    await flush();
    expect(member.cameraOn, isFalse);
    expect(host.value.isDevicePending('a', GroupControlDevice.camera), isTrue);
    decision.complete(false);
    expect((await open).outcomes['a']!.status, GroupControlStatus.denied);
    expect(member.cameraOn, isFalse);

    confirmations['a'] = (_) async => true;
    expect(
      (await host.setMemberDevice(
        'a',
        GroupControlDevice.camera,
        true,
      )).success,
      isTrue,
    );
    expect(member.cameraOn, isTrue);
  });

  test('释放全员静音保留原有开麦限制，恢复权限仍保持关麦', () async {
    await joinAll();
    final host = controls['host']!;
    final member = controls['a']!;
    expect((await host.updatePolicy(allowSelfUnmute: false)).success, isTrue);
    expect((await host.muteAll()).success, isTrue);
    expect((await host.unmuteAll()).success, isTrue);
    expect(member.value.allowSelfUnmute, isFalse);
    expect((await host.updatePolicy(allowSelfUnmute: true)).success, isTrue);
    expect(member.value.allowSelfUnmute, isTrue);
    expect(media['a']!.microphoneOn, isFalse);
  });

  test('收到更高版本的同设备禁止后，迟到的本人确认不能开启', () async {
    await joinAll();
    final host = controls['host']!;
    final target = media['a']!;
    await host.setMemberDevice('a', GroupControlDevice.camera, false);
    final confirmation = Completer<bool>();
    confirmations['a'] = (_) => confirmation.future;
    final requesting = host.setMemberDevice(
      'a',
      GroupControlDevice.camera,
      true,
    );
    await flush();
    final packet = network.sent
        .lastWhere(
          (entry) =>
              entry.$1 == 'host' &&
              entry.$2.kind == GroupControlMessageKind.command,
        )
        .$2;
    network.deliverTo(
      'a',
      'host',
      withPayload(packet, {
        'commandId': 'deny-during-confirmation',
        'revision': packet.version + 1,
        'action': 'setAllowed',
        'allowed': false,
      }),
    );
    await flush();
    confirmation.complete(true);
    expect(
      (await requesting).outcomes['a']!.status,
      GroupControlStatus.expired,
    );
    expect(target.cameraOn, isFalse);
  });

  test('摄像头收到较新指令后，未处理的麦克风指令仍可执行', () async {
    await joinAll();
    final host = controls['host']!;
    await host.setMemberDevice('a', GroupControlDevice.camera, false);
    final packet = network.sent
        .lastWhere(
          (entry) =>
              entry.$1 == 'host' &&
              entry.$2.kind == GroupControlMessageKind.command,
        )
        .$2;
    network.deliverTo(
      'a',
      'host',
      withPayload(packet, {
        'commandId': 'camera-newer',
        'revision': packet.version + 2,
      }),
    );
    network.deliverTo(
      'a',
      'host',
      withPayload(packet, {
        'commandId': 'microphone-earlier',
        'device': 'microphone',
        'revision': packet.version + 1,
      }),
    );
    await flush();
    expect(media['a']!.cameraOn, isFalse);
    expect(media['a']!.microphoneOn, isFalse);
  });

  test('鸿蒙接收共用主持策略，设备快照确认后才回执', () async {
    const channel = MethodChannel('test/harmony_group_control');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final native = HarmonyGroupControlMedia(
      presentationId: 'native-view',
      callId: 'call',
      channel: channel,
    );
    final lifecycle = GroupControlLifecycle.harmony(ActionGuard());
    addTearDown(() {
      lifecycle.clear(clearAuthority: true);
      native.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    });

    clock = DateTime.now();
    final host = create('host');
    await host.start();
    final permissions = <GroupControlDevice>[];
    final requests = <GroupControlDevice>[];
    final actions = <(GroupControlDevice, bool)>[];
    var holdCameraClose = false;
    var consent = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'harmonyPresentationGroupDevice');
      final args = call.arguments as Map;
      expect(args['id'], 'native-view');
      expect(args['callId'], 'call');
      final device = GroupControlDevice.values.byName(args['device'] as String);
      final enabled = args['enabled'] as bool?;
      if (enabled == null) {
        permissions.add(device);
      } else {
        actions.add((device, enabled));
        if (!holdCameraClose ||
            device != GroupControlDevice.camera ||
            enabled) {
          native.update(
            microphone: device == GroupControlDevice.microphone
                ? enabled
                : native.microphoneOn,
            camera: device == GroupControlDevice.camera
                ? enabled
                : native.cameraOn,
          );
        }
      }
      return true;
    });

    lifecycle.setTransport(network.transport('a'));
    lifecycle.updateHarmony(
      callId: 'call',
      selfId: 'a',
      inviterId: 'host',
      groupId: 'group',
      video: true,
      connectedAtMs: 0,
      joinedIds: ['host', 'a'],
      media: native,
      confirm: (device, _) async {
        requests.add(device);
        return consent;
      },
    );
    expect(lifecycle.controller!.value.canOpenMicrophone, isTrue);
    await flush();
    expect(lifecycle.controller!.value.policyKnown, isTrue);
    expect(native.microphoneOn, isTrue);
    expect(native.cameraOn, isTrue);

    holdCameraClose = true;
    final closeCamera = host.setMemberDevice(
      'a',
      GroupControlDevice.camera,
      false,
    );
    await flush();
    expect(actions.last, (GroupControlDevice.camera, false));
    expect(native.cameraOn, isTrue);
    expect(
      network.sent.where(
        (entry) =>
            entry.$1 == 'a' && entry.$2.kind == GroupControlMessageKind.ack,
      ),
      isEmpty,
    );
    native.update(microphone: true, camera: false);
    expect((await closeCamera).outcomes['a']?.success, isTrue);

    consent = false;
    permissions.clear();
    final denied = await host.setMemberDevice(
      'a',
      GroupControlDevice.camera,
      true,
    );
    expect(denied.outcomes['a']?.status, GroupControlStatus.denied);
    expect(native.cameraOn, isFalse);
    expect(permissions, isEmpty);

    final closeMic = await host.setMemberDevice(
      'a',
      GroupControlDevice.microphone,
      false,
    );
    expect(closeMic.outcomes['a']?.success, isTrue);
    consent = true;
    final openMic = await host.setMemberDevice(
      'a',
      GroupControlDevice.microphone,
      true,
    );
    expect(openMic.outcomes['a']?.success, isTrue);
    final openCamera = await host.setMemberDevice(
      'a',
      GroupControlDevice.camera,
      true,
    );
    expect(openCamera.outcomes['a']?.success, isTrue);
    expect(requests, [
      GroupControlDevice.camera,
      GroupControlDevice.microphone,
      GroupControlDevice.camera,
    ]);
    expect(native.microphoneOn && native.cameraOn, isTrue);
  });

  test('协议生成器只接受 OA v1 外层和各消息类型的严格字段', () {
    expect(
      GroupControlMessage.decode('{"protocol":"zd.group-call.control.v1"}'),
      isNull,
    );
    const packet = GroupControlMessage(
      kind: GroupControlMessageKind.command,
      callId: 'call',
      groupId: 'group',
      commandId: 'id',
      senderSessionId: 's',
      targetUserId: 'member',
      targetSessionId: 'member-session',
      version: 0,
      hostEpoch: 0,
      expiresAtMs: 123,
      device: GroupControlDevice.microphone,
      action: GroupControlAction.close,
    );
    final wire = packet.toJson();
    expect(wire.keys, unorderedEquals(['businessID', 'version', 'payload']));
    expect(wire['businessID'], 'oa_group_call_control');
    expect(wire['payload']['revision'], 0);
    expect(
      GroupControlMessage.decode(jsonEncode(wire))?.action,
      GroupControlAction.close,
    );
    expect(
      GroupControlMessage.decode(jsonEncode({...wire, 'version': 2})),
      isNull,
    );
    for (final changes in <Map<String, Object?>>[
      {'revision': '1'},
      {'revision': 1.5},
      {'revision': 9007199254740992},
      {'unknown': true},
      {'callId': ''},
      {'device': null},
      {'allowed': true},
      {'action': 'setAllowed'},
    ]) {
      expect(GroupControlMessage.decode(withPayload(packet, changes)), isNull);
    }
  });
}

class _Media extends ChangeNotifier implements GroupControlMedia {
  bool microphone = false, camera = false, denyOpen = false;
  Completer<void>? delay, cameraDelay;
  final List<(GroupControlDevice, bool)> operations = [];
  @override
  Listenable get changes => this;
  @override
  bool get microphoneOn => microphone;
  @override
  bool get cameraOn => camera;
  @override
  Future<GroupControlOutcome> setDevice(
    GroupControlDevice device,
    bool enabled, {
    required bool Function() isCurrent,
  }) async {
    final blocked = device == GroupControlDevice.camera
        ? cameraDelay ?? delay
        : delay;
    if (blocked != null) await blocked.future;
    if (!isCurrent()) {
      return const GroupControlOutcome(GroupControlStatus.expired);
    }
    operations.add((device, enabled));
    if (enabled && denyOpen) {
      return const GroupControlOutcome(GroupControlStatus.failed);
    }
    if (device == GroupControlDevice.microphone) {
      microphone = enabled;
    } else {
      camera = enabled;
    }
    notifyListeners();
    return GroupControlOutcome(
      GroupControlStatus.success,
      microphoneOn: microphone,
      cameraOn: camera,
    );
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
      streams[target]?.add(
        GroupControlInbound(senderId: sender, payload: payload),
      );
  Future<void> dispose() async {
    for (final stream in streams.values) {
      await stream.close();
    }
  }
}

class _Transport implements GroupControlTransport {
  _Transport(this.network, this.self) {
    network.streams.putIfAbsent(
      self,
      () => StreamController.broadcast(sync: true),
    );
  }
  final _Network network;
  final String self;
  @override
  Stream<GroupControlInbound> get messages => network.streams[self]!.stream;
  @override
  Future<Set<String>> loadAdministrators(
    String groupId,
    List<String> memberIds,
  ) async => network.admins;
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
