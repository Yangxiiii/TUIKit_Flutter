import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_calls_uikit/src/common/platform/harmony_call_bridge.dart';
import 'package:tencent_calls_uikit/src/tui_call_kit_impl.dart';
import 'package:tencent_calls_uikit/tencent_calls_uikit.dart';
import 'package:tuikit_atomic_x/base_component/utils/tui_event_bus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CallKit 的鸿蒙入口复用聊天登录、群呼结果和真实场次', () async {
    const channel = MethodChannel('harmony_public_callkit_test');
    final events = <String>[];
    final chat = _ChatLoginStore(events);
    final requests = <MethodCall>[];
    var rejectFirstCall = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      requests.add(call);
      events.add(call.method);
      if (call.method == 'harmonyCalls' && rejectFirstCall) {
        rejectFirstCall = false;
        throw PlatformException(code: 'CALL_FAILED', message: '当前正在通话中');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final TUICallKit kit = TUICallKitImpl(
      harmonyBridge: HarmonyCallBridge(
        _TestLogger(),
        guard: ActionGuard(),
        chatLoginStore: chat,
        channel: channel,
      ),
    );
    final starts = <(String, String, CallMediaType, List<String>, String)>[];
    kit.setGroupCallStartedHandler((group, caller, media, ids, id) async {
      starts.add((group, caller, media, ids, id));
    });

    expect((await kit.login(123, 'self', 'sig')).isSuccess, isTrue);
    final params = CallParams(chatGroupId: 'group');
    final failed = await kit.calls(['peer'], CallMediaType.video, params);
    expect(failed.isSuccess, isFalse);
    expect(failed.errorMessage, '当前正在通话中');
    expect(starts, isEmpty);
    expect(
      (await kit.calls(['peer'], CallMediaType.video, params)).isSuccess,
      isTrue,
    );
    final outgoing = requests.last.arguments as Map<Object?, Object?>;
    expect(outgoing['chatGroupId'], 'group');
    expect(outgoing['mediaType'], 'video');
    expect(outgoing['isEphemeralCall'], isFalse);
    final attempt = GroupCallMetadata.attemptId(outgoing['userData'] as String);
    expect(attempt, isNotNull);
    final (group, caller, media, ids, id) = starts.single;
    expect(
      (group, caller, media, id),
      ('group', 'self', CallMediaType.video, attempt),
    );
    expect(ids, ['peer']);
    expect(params.userData, isEmpty);

    await kit.join('room', mediaType: CallMediaType.video);
    expect(requests.last.arguments, {'callId': 'room', 'mediaType': 'video'});
    await kit.join('room');
    expect(requests.last.arguments, {'callId': 'room'});
    await kit.logout();
    expect(events, [
      'chatLogin:self',
      'harmonyLogin',
      'harmonyCalls',
      'harmonyCalls',
      'harmonyJoin',
      'harmonyJoin',
      'harmonyLogout',
      'chatLogout',
    ]);
  });

  test('群加入使用原生场次与媒体，重复合并、失败可重试且登出后不可加入', () async {
    const channel = MethodChannel('harmony_join_test');
    final pending = Completer<void>();
    final requests = <Map<Object?, Object?>>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'harmonyJoin') {
        requests.add(call.arguments as Map<Object?, Object?>);
        if (requests.length == 1) await pending.future;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final bridge = HarmonyCallBridge(
      _TestLogger(),
      guard: ActionGuard(),
      channel: channel,
      chatLoginStore: _ChatLoginStore(),
    );
    await expectLater(
      bridge.join('call', CallMediaType.audio),
      throwsStateError,
    );
    await bridge.login(sdkAppId: 123, userId: 'self', userSig: 'sig');
    await expectLater(
      bridge.join(' ', CallMediaType.audio),
      throwsArgumentError,
    );
    final first = bridge.join('call', CallMediaType.video);
    final repeated = bridge.join('call', CallMediaType.video);
    final failures = [
      expectLater(first, throwsA(isA<PlatformException>())),
      expectLater(repeated, throwsA(isA<PlatformException>())),
    ];
    await Future<void>.delayed(Duration.zero);
    pending.completeError(PlatformException(code: 'JOIN_FAILED'));
    await Future.wait(failures);
    expect(requests, [
      {'callId': 'call', 'mediaType': 'video'},
    ]);
    await bridge.join('call', CallMediaType.video);
    expect(requests, hasLength(2));
    await bridge.logout();
    await expectLater(
      bridge.join('call', CallMediaType.audio),
      throwsStateError,
    );
  });

  test('原生登录失败会回收聊天登录并允许重试', () async {
    const channel = MethodChannel('harmony_login_retry_test');
    final events = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var rejectLogin = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      events.add(call.method);
      if (call.method == 'harmonyLogin' && rejectLogin) {
        throw PlatformException(code: 'LOGIN_FAILED');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final bridge = HarmonyCallBridge(
      _TestLogger(),
      guard: ActionGuard(),
      chatLoginStore: _ChatLoginStore(events),
      channel: channel,
    );
    Future<CompletionHandler> login() =>
        bridge.login(sdkAppId: 123, userId: 'self', userSig: 'sig');
    await expectLater(login(), throwsA(isA<PlatformException>()));
    await expectLater(
      bridge.join('room', CallMediaType.video),
      throwsStateError,
    );
    expect(events, ['chatLogin:self', 'harmonyLogin', 'chatLogout']);
    rejectLogin = false;
    expect((await login()).isSuccess, isTrue);
    await bridge.logout();
    expect(events, [
      'chatLogin:self',
      'harmonyLogin',
      'chatLogout',
      'chatLogin:self',
      'harmonyLogin',
      'harmonyLogout',
      'chatLogout',
    ]);
  });

  test('加入事件转原生，登出清理订阅并拒绝迟到加入成功', () async {
    const channel = MethodChannel('harmony_join_event_test');
    final pending = Completer<void>();
    final methods = <String>[];
    var delayJoin = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'harmonyJoin' && delayJoin) await pending.future;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final bridge = HarmonyCallBridge(
      _TestLogger(),
      guard: ActionGuard(),
      channel: channel,
      chatLoginStore: _ChatLoginStore(),
    );
    await bridge.login(sdkAppId: 123, userId: 'self', userSig: 'sig');
    void publish() => TUIEventBus.shared.publish(
      'call.startJoin',
      null,
      PublishParams(data: {'callId': 'call', 'mediaType': CallMediaType.audio}),
    );
    publish();
    await Future<void>.delayed(Duration.zero);
    expect(methods, ['harmonyLogin', 'harmonyJoin']);
    delayJoin = true;
    final joining = bridge.join('call', CallMediaType.audio);
    final lateFailure = expectLater(joining, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    await bridge.logout();
    publish();
    pending.complete();
    await lateFailure;
    await Future<void>.delayed(Duration.zero);
    expect(methods, [
      'harmonyLogin',
      'harmonyJoin',
      'harmonyJoin',
      'harmonyLogout',
    ]);
  });

  test('登出使等待中的登录失效，原生登出排在登录之后且旧订阅不恢复', () async {
    const channel = MethodChannel('harmony_stale_login_test');
    final pendingLogin = Completer<void>();
    final methods = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'harmonyLogin') await pendingLogin.future;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final bridge = HarmonyCallBridge(
      _TestLogger(),
      guard: ActionGuard(),
      channel: channel,
      chatLoginStore: _ChatLoginStore(),
    );
    final login = bridge.login(sdkAppId: 123, userId: 'old', userSig: 'sig');
    final failedLogin = expectLater(login, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    final logout = bridge.logout();
    await Future<void>.delayed(Duration.zero);
    expect(methods, ['harmonyLogin']);
    pendingLogin.complete();
    await failedLogin;
    await logout;
    await expectLater(
      bridge.calls(['peer'], CallMediaType.audio),
      throwsStateError,
    );
    TUIEventBus.shared.publish(
      'call.startCall',
      null,
      PublishParams(
        data: {
          'participantIds': ['peer'],
          'mediaType': CallMediaType.audio,
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(methods, ['harmonyLogin', 'harmonyLogout']);
  });

  test('后发登录保留自己的账号，旧登录完成不能覆盖新账号的调用边界', () async {
    const channel = MethodChannel('harmony_new_login_test');
    final oldLogin = Completer<void>();
    final logins = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'harmonyLogin') {
        final id =
            (call.arguments as Map<Object?, Object?>)['userId'] as String;
        logins.add(id);
        if (id == 'old') await oldLogin.future;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final bridge = HarmonyCallBridge(
      _TestLogger(),
      guard: ActionGuard(),
      channel: channel,
      chatLoginStore: _ChatLoginStore(),
    );
    final first = bridge.login(sdkAppId: 123, userId: 'old', userSig: 'sig');
    final failedFirst = expectLater(first, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    final latest = bridge.login(sdkAppId: 123, userId: 'new', userSig: 'sig');
    oldLogin.complete();
    await failedFirst;
    await latest;
    expect(logins, ['old', 'new']);
    await expectLater(
      bridge.calls(['new'], CallMediaType.audio),
      throwsArgumentError,
    );
    await bridge.calls(['old'], CallMediaType.audio);
    await bridge.logout();
  });

  test('群呼叫透传群归属，并发合并且平台失败可再次发起', () async {
    const channel = MethodChannel('harmony_group_call_test');
    final result = Completer<void>();
    final requests = <Map<Object?, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'harmonyCalls') {
            requests.add(call.arguments as Map<Object?, Object?>);
            if (requests.length == 1) await result.future;
          }
          return null;
        });
    final bridge = HarmonyCallBridge(
      _TestLogger(),
      guard: ActionGuard(),
      channel: channel,
      chatLoginStore: _ChatLoginStore(),
    );
    await bridge.login(sdkAppId: 123, userId: 'self', userSig: 'sig');
    Future<void> call() => bridge.calls(
      ['a', 'a', 'b'],
      CallMediaType.audio,
      CallParams(chatGroupId: 'group'),
    );
    final first = call();
    final second = call();
    final failures = [
      expectLater(first, throwsA(isA<PlatformException>())),
      expectLater(second, throwsA(isA<PlatformException>())),
    ];
    await Future<void>.delayed(Duration.zero);
    result.completeError(PlatformException(code: 'CALL_FAILED'));
    await Future.wait(failures);
    expect(requests, hasLength(1));
    expect(requests.single, {
      'userIds': ['a', 'b'],
      'mediaType': 'audio',
      'chatGroupId': 'group',
      'timeout': 45,
      'roomId': '',
      'userData': '',
      'isEphemeralCall': false,
      'cloudRecordPolicy': 'followConsoleConfig',
      'offlinePushTitle': '',
      'offlinePushDescription': '',
    });
    await call();
    expect(requests, hasLength(2));
    await bridge.logout();
    await expectLater(call(), throwsStateError);
  });

  test('鸿蒙桥接复用登录凭证并转发聊天群视频呼叫', () async {
    const channel = MethodChannel('harmony_call_bridge_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    final bridge = HarmonyCallBridge(
      _TestLogger(),
      guard: ActionGuard(),
      channel: channel,
      chatLoginStore: _ChatLoginStore(),
    );

    await bridge.login(sdkAppId: 123, userId: 'alice', userSig: 'sig');
    TUIEventBus.shared.publish(
      'call.startCall',
      null,
      PublishParams(
        data: {
          'participantIds': ['bob'],
          'chatGroupId': 'group',
          'mediaType': CallMediaType.video,
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await bridge.logout();

    expect(calls.map((call) => call.method), [
      'harmonyLogin',
      'harmonyCalls',
      'harmonyLogout',
    ]);
    expect(calls[1].arguments, {
      'userIds': ['bob'],
      'mediaType': 'video',
      'chatGroupId': 'group',
      'timeout': 45,
      'roomId': '',
      'userData': '',
      'isEphemeralCall': false,
      'cloudRecordPolicy': 'followConsoleConfig',
      'offlinePushTitle': '',
      'offlinePushDescription': '',
    });
  });
}

/// 记录聊天 Store 生命周期，媒体测试只走模拟的原生通道。
final class _ChatLoginStore extends LoginStore {
  _ChatLoginStore([this.events]);

  final List<String>? events;

  @override
  Future<CompletionHandler> login({
    required int sdkAppID,
    required String userID,
    required String userSig,
  }) async {
    events?.add('chatLogin:$userID');
    return CompletionHandler();
  }

  @override
  Future<CompletionHandler> logout() async {
    events?.add('chatLogout');
    return CompletionHandler();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _TestLogger implements AppLogger {
  @override
  void trace(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void debug(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void info(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void warning(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void fatal(String message, {Object? error, StackTrace? stackTrace}) {}
}
