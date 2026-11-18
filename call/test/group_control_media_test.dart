import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtc_room_engine/rtc_room_engine.dart';
import 'package:tencent_calls_uikit/src/control/group_control_media.dart';
import 'package:tencent_calls_uikit/src/state/group_control_state.dart';
import 'support/call_fakes.dart';

void main() {
  late FakeCallStore store;
  late _Engine engine;
  late SdkGroupControlMedia media;
  var current = true;
  Future<bool> Function(GroupControlDevice)? permission;

  setUp(() {
    store = FakeCallStore();
    engine = _Engine();
    permission = null;
    current = true;
    media = SdkGroupControlMedia(
        store: store,
        engine: engine,
        requestPermission: (device) =>
            permission?.call(device) ?? Future.value(true),
        isFrontCamera: () => true,
        confirmationTimeout: const Duration(milliseconds: 15));
  });

  test('原生完成且 SDK available 一致才确认成功，SDK 成功无事件只算未确认', () async {
    engine.open = () async {
      store.state.selfInfo.value = FakeParticipant('self',
          isMicrophoneOpened: true, isCameraOpened: false);
      return TUIActionCallback(code: TUIError.success, message: null);
    };
    final opened = await media.setDevice(GroupControlDevice.microphone, true,
        isCurrent: () => current);
    expect(opened.status, GroupControlStatus.success);
    expect(opened.microphoneOn, isTrue);
    final camera = await media.setDevice(GroupControlDevice.camera, true,
        isCurrent: () => current);
    expect(camera.status, GroupControlStatus.unconfirmed);
    expect(camera.cameraOn, isFalse);
  });

  test('原生错误、系统权限拒绝和关闭异常不能返回成功', () async {
    engine.open = () async =>
        TUIActionCallback(code: TUIError.errFailed, message: 'native failed');
    expect(
        (await media.setDevice(GroupControlDevice.camera, true,
                isCurrent: () => current))
            .status,
        GroupControlStatus.failed);
    permission = (_) async => false;
    expect(
        (await media.setDevice(GroupControlDevice.microphone, true,
                isCurrent: () => current))
            .status,
        GroupControlStatus.denied);
    expect(engine.openCalls, 1);
    engine.close = () async => throw StateError('native close failed');
    expect(
        (await media.setDevice(GroupControlDevice.microphone, false,
                isCurrent: () => current))
            .status,
        GroupControlStatus.failed);
  });

  test('等待系统权限期间入会失效不会调用原生开设备', () async {
    final granted = Completer<bool>();
    permission = (_) => granted.future;
    final result = media.setDevice(GroupControlDevice.microphone, true,
        isCurrent: () => current);
    current = false;
    granted.complete(true);
    expect((await result).status, GroupControlStatus.expired);
    expect(engine.openCalls, 0);
  });
}

/// 只模拟公开 TUICallEngine Future，不注册原生监听、不访问真实媒体设备。
class _Engine extends Fake implements TUICallEngine {
  int openCalls = 0;
  Future<TUIActionCallback> Function()? open;
  Future<void> Function()? close;
  @override
  Future<TUIActionCallback> openMicrophone() {
    openCalls++;
    return open?.call() ??
        Future.value(TUIActionCallback(code: TUIError.success, message: null));
  }

  @override
  Future<TUIActionCallback> openCamera(TUICamera camera, int? viewId) =>
      openMicrophone();

  @override
  Future<void> closeMicrophone() => close?.call() ?? Future.value();

  @override
  Future<void> closeCamera() => closeMicrophone();
}
