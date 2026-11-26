import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';
import 'package:tencent_calls_uikit/src/tui_call_kit_impl.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('通话登录成功后开启多端接听，能力不可用时仍完成登录', () async {
    final engine = _MultiDeviceCallEngine();
    TUICallEngine.instance = engine;
    final kit = TUICallKitImpl();
    engine.operations.clear();

    // 初始化未完成时不能启用多端能力，监听必须先于 SDK 开关就绪。
    final login = kit.loginCallOnly(1, 'fixture-user', 'fixture-signature');
    expect(engine.operations, ['init']);
    engine.initialization.complete(
      TUIActionCallback(code: TUIError.success, message: null),
    );
    expect((await login).errorCode, TUIError.success.rawValue);
    expect(engine.operations, [
      'init',
      'removeObserver',
      'addObserver',
      'enable',
    ]);
    await kit.logoutCallOnly();
  });

  testWidgets('通话引擎未回调时仍能完成退出', (tester) async {
    final engine = _EngineWithoutShutdownCallback();
    TUICallEngine.instance = engine;
    final kit = TUICallKitImpl();
    var completed = false;
    unawaited(kit.logoutCallOnly().then((_) => completed = true));

    await tester.pump();
    expect(engine.shutdownRequested, isTrue);
    expect(completed, isTrue);
  });

  test('登出失败会传递给调用方', () async {
    final previousManager = TencentImSDKPlugin.v2TIMManager;
    TencentImSDKPlugin.v2TIMManager = _FailedLogoutManager();
    addTearDown(() => TencentImSDKPlugin.v2TIMManager = previousManager);

    await expectLater(
      TUICallKitImpl.logoutIm(),
      throwsA(isA<StateError>().having((error) => error.message, 'message',
          contains('1001 SDK logout failed'))),
    );
  });
}

final class _EngineWithoutShutdownCallback extends Fake
    implements TUICallEngine {
  bool shutdownRequested = false;

  @override
  Future<void> addObserver(TUICallObserver observer) async {}

  @override
  Future<void> removeObserver(TUICallObserver observer) async {}

  @override
  Future<TUIActionCallback> unInit() {
    shutdownRequested = true;
    return Completer<TUIActionCallback>().future;
  }
}

/// 用可控的初始化回调验证多端开关顺序，并模拟套餐拒绝该能力。
final class _MultiDeviceCallEngine extends Fake implements TUICallEngine {
  final initialization = Completer<TUIActionCallback>();
  final operations = <String>[];

  @override
  Future<TUIActionCallback> init(int sdkAppID, String userId, String userSig) {
    operations.add('init');
    return initialization.future;
  }

  @override
  Future<void> addObserver(TUICallObserver observer) async {
    operations.add('addObserver');
  }

  @override
  Future<void> removeObserver(TUICallObserver observer) async {
    operations.add('removeObserver');
  }

  @override
  Future<TUIActionCallback> enableMultiDeviceAbility(bool enable) async {
    expect(enable, isTrue);
    operations.add('enable');
    return TUIActionCallback(code: TUIError.errRequirePayment, message: null);
  }

  @override
  Future<TUIActionCallback> unInit() async =>
      TUIActionCallback(code: TUIError.success, message: null);
}

final class _FailedLogoutManager extends V2TIMManager {
  @override
  Future<V2TimCallback> logout() async =>
      V2TimCallback(code: 1001, desc: 'SDK logout failed');
}
