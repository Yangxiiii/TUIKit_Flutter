import 'dart:async';
import 'package:app_core/app_core.dart';
import 'package:app_service/app_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/manager/call_manager.dart';
import 'package:tencent_calls_uikit/src/manager/group_control_controller.dart';
import 'package:tencent_calls_uikit/src/state/global_state.dart';
import 'package:tencent_calls_uikit/src/state/group_call_metadata.dart';
import 'package:tencent_calls_uikit/src/state/group_control_state.dart';
import 'package:tuikit_atomic_x/atomicx.dart';
import 'support/call_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeCallStore store;
  late CallManager manager;
  late String account;
  Future<PermissionType?> Function(CallMediaType)? permission;
  Future<String?> Function(String)? groupTitle;
  setUp(() async {
    await AppServiceLocator.registerOrReplace(ActionGuard());
    GlobalState.instance.clearGroupCall();
    store = FakeCallStore();
    account = 'self';
    permission = null;
    groupTitle = null;
    manager = CallManager.testing(
        store: store,
        accountId: () => account,
        requestPermission: (type) =>
            permission?.call(type) ?? Future.value(null),
        queryGroupTitle: (id) => groupTitle?.call(id) ?? Future.value(null));
  });
  tearDown(() {
    GlobalState.instance.clearGroupCall();
    GlobalState.instance.groupControlController = null;
  });

  test('关闭媒体等待期间场次失效或关闭失败均不能继续 SDK join', () async {
    final suspended = Completer<void>();
    manager = CallManager.testing(
        store: store,
        accountId: () => account,
        requestPermission: (_) async => null,
        suspendGroupDevices: () => suspended.future);
    final joining = manager.join('room');
    await Future<void>.delayed(Duration.zero);
    manager.invalidateDevicePreparation();
    suspended.complete();
    expect((await joining).errorCode, isNot(0));
    expect(store.joins, isEmpty);
    manager = CallManager.testing(
        store: store,
        accountId: () => account,
        requestPermission: (_) async => null,
        suspendGroupDevices: () async => throw StateError('close failed'));
    expect((await manager.join('room')).errorCode, -3301);
    expect(store.joins, isEmpty);
  });

  test('等待主持交接期间进入新场次，旧挂断不能结束新通话', () async {
    final transfer = Completer<GroupControlResult>();
    GlobalState.instance.groupControlController =
        _LeaveControl(transfer.future);
    store.state.activeCall.value = FakeCallInfo(callId: 'old');
    final leaving = manager.hangup();
    store.state.activeCall.value = FakeCallInfo(callId: 'new');
    manager.invalidateDevicePreparation();
    transfer.complete(GroupControlResult(
        {'other': const GroupControlOutcome(GroupControlStatus.success)}));
    expect(await leaving, isFalse);
    expect(store.hangups, 0);
    GlobalState.instance.groupControlController = null;
    expect(await manager.hangup(), isTrue);
    expect(store.hangups, 1);
  });

  test('到期结束不等待正在进行的主持交接，SDK结束使旧交接失效', () async {
    final transfer = Completer<GroupControlResult>();
    GlobalState.instance.groupControlController =
        _LeaveControl(transfer.future);
    store.state.activeCall.value = FakeCallInfo(callId: 'old');
    final manual = manager.hangup();
    store.operation = () async {
      manager.invalidateDevicePreparation();
      return CompletionHandler();
    };
    expect(await manager.hangup(transferHost: false), isTrue);
    expect(store.hangups, 1);
    transfer.complete(GroupControlResult(
        {'other': const GroupControlOutcome(GroupControlStatus.timeout)}));
    expect(await manual, isFalse);
    expect(store.hangups, 1);
  });

  test('空名单、空白 ID、本人及超过九人不会请求 SDK，重复 ID 只占一个名额', () async {
    for (final ids in <List<String>>[
      [],
      [''],
      [' a'],
      ['self'],
      List.generate(9, (i) => '$i')
    ]) {
      expect(
          (await manager.calls(ids, CallMediaType.audio)).errorCode, isNot(0));
    }
    expect(store.starts, isEmpty);
    final params = CallParams(
        timeout: 12,
        chatGroupId: 'g',
        isEphemeralCall: true,
        cloudRecordPolicy: CloudRecordPolicy.enable,
        offlinePushTitle: '来电');
    expect(
        (await manager.calls(['a', 'a', ...List.generate(7, (i) => '$i')],
                CallMediaType.video, params))
            .errorCode,
        0);
    expect(store.starts.single.length, 8);
    expect(store.lastParams!.timeout, 45);
    expect(params.timeout, 12);
    expect(store.lastParams!.cloudRecordPolicy, CloudRecordPolicy.enable);
    expect(store.lastParams!.offlinePushTitle, '来电');
  });

  test('临时多人只选一人仍保留多人场景，无标识的两人通话继续单聊', () async {
    await manager.calls(['a'], CallMediaType.audio,
        CallParams(userData: GroupCallMetadata.temporaryMultiUserData));
    expect(
        GlobalState.instance.groupCall.value!.members
            .map((member) => member.id),
        ['self', 'a']);
    expect(GlobalState.instance.groupCall.value!.groupId, isEmpty);
    expect(
        store.lastParams!.userData, GroupCallMetadata.temporaryMultiUserData);
    await manager.calls(['a'], CallMediaType.audio);
    expect(GlobalState.instance.groupCall.value, isNull);
    expect(
        GroupCallMetadata.isTemporaryMulti(
            '{"zdoaCallScene":"multi","version":2}'),
        isFalse);
    expect(GroupCallMetadata.isTemporaryMulti('invalid'), isFalse);
  });

  test('权限等待期间换账号、收到新来电或代次失效均不发起旧请求', () async {
    for (final mutate in <void Function()>[
      () => account = 'other',
      () => store.state.activeCall.value =
          FakeCallInfo(callId: 'incoming', mediaType: CallMediaType.audio),
      manager.invalidateDevicePreparation,
    ]) {
      account = 'self';
      store.state.activeCall.value = FakeCallInfo();
      final pending = Completer<PermissionType?>();
      permission = (_) => pending.future;
      final result = manager.calls(['a', 'b'], CallMediaType.audio);
      mutate();
      pending.complete(null);
      expect((await result).errorCode, isNot(0));
    }
    expect(store.starts, isEmpty);
  });

  test('发起和加入共享准入守卫，未登录、忙线及拒绝权限不会加入', () async {
    account = '';
    expect((await manager.join('call')).errorCode, -1201);
    account = 'self';
    store.state.activeCall.value =
        FakeCallInfo(callId: 'active', mediaType: CallMediaType.audio);
    expect((await manager.join('call')).errorCode, -1203);
    store.state.activeCall.value = FakeCallInfo();
    permission = (_) async => PermissionType.microphone;
    expect((await manager.join('call')).errorCode, -1101);
    final pending = Completer<PermissionType?>();
    permission = (_) => pending.future;
    final starting = manager.calls(['a', 'b'], CallMediaType.audio);
    final joining = manager.join('different-call');
    pending.complete(null);
    expect((await joining).errorCode, -1203);
    expect((await starting).errorCode, 0);
    expect(store.starts.length, 1);
    expect(store.joins, isEmpty);
  });

  test('SDK 抛错返回失败并清除重呼参数，重复点击合并一次 SDK 操作', () async {
    store.operation = () async => throw StateError('native failure');
    expect((await manager.calls(['a', 'b'], CallMediaType.audio)).errorCode,
        -3301);
    expect(GlobalState.instance.groupCall.value, isNull);
    final pending = Completer<CompletionHandler>();
    store.operation = () => pending.future;
    final first = manager.calls(['a', 'b'], CallMediaType.audio);
    final repeated = manager.calls(['a', 'b'], CallMediaType.audio);
    await Future<void>.delayed(Duration.zero);
    expect(store.starts.length, 2);
    pending.complete(CompletionHandler());
    await Future.wait([first, repeated]);
  });

  test('追加邀请重新核对场次、去重排除已占成员，并把等待成员计入九人容量', () async {
    store.state.activeCall.value =
        FakeCallInfo(callId: 'active', mediaType: CallMediaType.audio);
    store.state.selfInfo.value =
        FakeParticipant('self', status: CallParticipantStatus.accept);
    store.state.allParticipants.value = [
      FakeParticipant('self', status: CallParticipantStatus.accept),
      ...List.generate(7, (i) => FakeParticipant('$i'))
    ];
    expect((await manager.invite(['a'], expectedCallId: 'old')).errorCode,
        isNot(0));
    expect(
        (await manager.invite(['a', 'b'], expectedCallId: 'active')).errorCode,
        101010);
    expect(
        (await manager
                .invite(['self', '0', 'a', 'a'], expectedCallId: 'active'))
            .errorCode,
        0);
    expect(store.invitations.single, ['a']);
  });

  test('追加邀请等待 SDK 返回时切换场次，旧结果不能报告成功', () async {
    store.state.activeCall.value =
        FakeCallInfo(callId: 'active', mediaType: CallMediaType.audio);
    store.state.selfInfo.value =
        FakeParticipant('self', status: CallParticipantStatus.accept);
    final pending = Completer<CompletionHandler>();
    store.operation = () => pending.future;
    final result = manager.invite(['a'], expectedCallId: 'active');
    manager.invalidateDevicePreparation();
    pending.complete(CompletionHandler());
    expect((await result).errorCode, -1203);
  });

  test('群名仅在原账号和场次补齐，迟到查询结果不污染新通话', () async {
    store.state.activeCall.value = FakeCallInfo(
        callId: 'active', chatGroupId: 'g', mediaType: CallMediaType.audio);
    GlobalState.instance.groupCallSession.begin(
        callId: 'active',
        groupId: 'g',
        groupName: '',
        inviterId: 'other',
        mediaType: CallMediaType.audio,
        memberIds: ['self', 'other']);
    groupTitle = (_) async => '真实群名';
    await manager.refreshGroupCallTitle();
    expect(GlobalState.instance.groupCall.value!.groupName, '真实群名');
    GlobalState.instance.clearGroupCall();
    final pending = Completer<String?>();
    groupTitle = (_) => pending.future;
    final loading = manager.refreshGroupCallTitle();
    store.state.activeCall.value = FakeCallInfo(
        callId: 'next', chatGroupId: 'g', mediaType: CallMediaType.audio);
    pending.complete('旧资料');
    await loading;
    expect(GlobalState.instance.groupCallTitle('g'), isEmpty);
  });

  test('重呼 SDK 失败保留已结束的展示结果，后续可以再次重新发起', () async {
    await manager.calls(['a', 'b'], CallMediaType.audio);
    GlobalState.instance.groupCallSession
        .end('ended', CallEndReason.noResponse, isCaller: true);
    final ended = GlobalState.instance.groupCall.value;
    store.operation = () async => throw StateError('network failure');
    expect((await manager.retryGroupCall()).errorCode, -3301);
    expect(GlobalState.instance.groupCall.value, same(ended));
    expect(GlobalState.instance.groupCall.value!.canRetry, isTrue);
    store.operation = null;
    expect((await manager.retryGroupCall()).errorCode, 0);
    expect(GlobalState.instance.groupCall.value!.ended, isFalse);
  });

  test('全员未接重呼创建新请求，既不沿用 roomId 也不邀请已结束场次', () async {
    await manager.calls(['a', 'b'], CallMediaType.video,
        CallParams(chatGroupId: 'g', roomId: 'old-room'));
    GlobalState.instance.groupCallSession
        .end('ended-call', CallEndReason.noResponse, isCaller: true);
    expect((await manager.retryGroupCall()).errorCode, 0);
    expect(store.starts.length, 2);
    expect(store.lastParams!.roomId, isEmpty);
    expect(store.lastParams!.chatGroupId, 'g');
    expect(store.invitations, isEmpty);
    manager.clearGroupRequest();
    expect((await manager.retryGroupCall()).errorCode, isNot(0));
  });
}

/// 延迟主持交接的替身，只用于验证挂断等待之后仍会核对当前场次。
class _LeaveControl extends Fake implements GroupControlController {
  _LeaveControl(this.transfer);
  final Future<GroupControlResult> transfer;
  @override
  GroupControlState get value => GroupControlState(
      callId: 'old',
      sessionId: 'session',
      selfId: 'self',
      hostId: 'self',
      policyKnown: true,
      version: 0,
      allowSelfUnmute: true,
      allowVideo: true,
      muteAll: false,
      cameraAllClosed: false,
      microphoneOn: false,
      cameraOn: false);
  @override
  Future<GroupControlResult> prepareLeave() => transfer;
}
