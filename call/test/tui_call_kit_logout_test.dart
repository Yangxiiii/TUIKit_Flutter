import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';
import 'package:tencent_calls_uikit/src/tui_call_kit_impl.dart';
import 'package:tencent_cloud_chat_sdk/manager/v2_tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

final class _FailedLogoutManager extends V2TIMManager {
  @override
  Future<V2TimCallback> logout() async =>
      V2TimCallback(code: 1001, desc: 'SDK logout failed');
}
