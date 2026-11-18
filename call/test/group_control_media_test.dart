import 'dart:async';
import 'package:flutter/foundation.dart';
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
  var isFrontCamera = true;
  int? viewId;
  Future<bool> Function(GroupControlDevice)? permission;

  setUp(() {
    store = FakeCallStore();
    store.state.selfInfo.value = FakeParticipant('self');
    engine = _Engine();
    permission = null;
    current = true;
    isFrontCamera = true;
    viewId = null;
    media = SdkGroupControlMedia(
        store: store,
        engine: engine,
        requestPermission: (device) =>
            permission?.call(device) ?? Future.value(true),
        isFrontCamera: () => isFrontCamera,
        readLocalVideoView: () => viewId,
        confirmationTimeout: const Duration(milliseconds: 15));
  });

  tearDown(() => media.dispose());

  test('视频页传递有效预览句柄，原生成功不再等待可能缺失的本端状态事件', () async {
    viewId = 1234;
    isFrontCamera = false;
    final opened = await media.setDevice(GroupControlDevice.camera, true,
        isCurrent: () => current);
    expect(engine.cameraRequest, (TUICamera.back, 1234));
    expect(opened.success, isTrue);
    expect(opened.cameraOn, isTrue);
    expect(opened.microphoneOn, isFalse);
    expect(store.state.selfInfo.value.isCameraOpened, isFalse);

    // 旧 CallStore 状态和远端视频流均不参与本机摄像头确认。
    expect(engine.observer!.onUserVideoAvailable, isNull);
    store.state.selfInfo.value = FakeParticipant('self', isCameraOpened: true);
    expect(media.cameraOn, isTrue);
    final closed = await media.setDevice(GroupControlDevice.camera, false,
        isCurrent: () => current);
    expect(closed.success, isTrue);
    expect(closed.cameraOn, isFalse);
    expect(media.cameraOn, isFalse);
    expect(store.state.selfInfo.value.isCameraOpened, isTrue);
  });

  test('关闭清除原生绑定后，重新开启先恢复仍存活的本端预览', () async {
    viewId = 1234;
    int? boundView;
    engine.cameraCommand = (command) async {
      expect(command['api'], 'setLocalView');
      boundView = (command['params'] as Map)['videoView'] as int;
    };
    engine.openVideo = (view) async {
      expect(boundView, view);
      return TUIActionCallback(code: TUIError.success, message: null);
    };
    engine.close = () async {
      boundView = null;
    };

    for (final enabled in [true, false, true]) {
      final result = await media.setDevice(GroupControlDevice.camera, enabled,
          isCurrent: () => current);
      expect(result.success, isTrue);
      expect(result.cameraOn, enabled);
      expect(result.microphoneOn, isFalse);
    }
    expect(boundView, 1234);
  });

  test('视频默认开启早于预览挂载时，拿到本端句柄后再调用开相机', () async {
    final preview = ValueNotifier<int?>(null);
    final joiningMedia = SdkGroupControlMedia(
      store: store,
      engine: engine,
      requestPermission: (_) async => true,
      isFrontCamera: () => true,
      readLocalVideoView: () => preview.value,
      localVideoViewChanges: preview,
    );
    addTearDown(() {
      joiningMedia.dispose();
      preview.dispose();
    });
    final opening = joiningMedia.setDevice(GroupControlDevice.camera, true,
        isCurrent: () => current);
    await Future<void>.delayed(Duration.zero);
    expect(engine.cameraRequest, isNull);
    preview.value = 1234;
    expect((await opening).success, isTrue);
    expect(engine.cameraRequest, (TUICamera.front, 1234));
  });

  test('开启摄像头回包失败时保留关闭状态和 SDK 错误码', () async {
    viewId = 1234;
    engine.openVideo = (_) async => TUIActionCallback(
        code: TUIError.fromRawValue(-1202), message: 'invalid parameter');
    final commands = <Object?>[];
    engine.cameraCommand = (command) async => commands.add(command['api']);
    final result = await media.setDevice(GroupControlDevice.camera, true,
        isCurrent: () => current);
    expect(commands, ['setLocalView']);
    expect(media.cameraOn, isFalse);
    expect(result.status, GroupControlStatus.failed);
    expect(result.error, contains('-1202'));
  });

  test('没有预览视图时传空句柄，只有本机开启成功回包才更新状态', () async {
    isFrontCamera = false;
    final dispatched = Completer<void>();
    final callback = Completer<TUIActionCallback>();
    engine.openVideo = (_) {
      dispatched.complete();
      return callback.future;
    };
    final opening = media.setDevice(GroupControlDevice.camera, true,
        isCurrent: () => current);
    await dispatched.future.timeout(const Duration(seconds: 1));
    expect(engine.cameraRequest, (TUICamera.back, null));

    store.state.selfInfo.value = FakeParticipant(
      'self',
      isMicrophoneOpened: false,
      isCameraOpened: true,
    );
    expect(media.cameraOn, isFalse);
    callback.complete(TUIActionCallback(code: TUIError.success, message: null));
    final outcome = await opening;
    expect(outcome.status, GroupControlStatus.success);
    expect(outcome.cameraOn, isTrue);
  });

  test('麦克风开启使用原生回包，关闭仍等待麦克风事件', () async {
    final opened = await media.setDevice(GroupControlDevice.microphone, true,
        isCurrent: () => current);
    expect(opened.status, GroupControlStatus.success);
    expect(opened.microphoneOn, isTrue);
    final closed = await media.setDevice(GroupControlDevice.microphone, false,
        isCurrent: () => current);
    expect(closed.status, GroupControlStatus.unconfirmed);
    expect(closed.microphoneOn, isTrue);
    expect(media.cameraOn, isFalse);
  });

  test('原生错误、系统权限拒绝和关闭异常不能返回成功', () async {
    engine.open = () async =>
        TUIActionCallback(code: TUIError.errFailed, message: 'native failed');
    expect(
        (await media.setDevice(GroupControlDevice.microphone, true,
                isCurrent: () => current))
            .status,
        GroupControlStatus.failed);
    engine.openVideo = (_) async => throw StateError('native open failed');
    expect(
        (await media.setDevice(GroupControlDevice.camera, true,
                isCurrent: () => current))
            .status,
        GroupControlStatus.failed);
    permission = (_) async => false;
    expect(
        (await media.setDevice(GroupControlDevice.camera, true,
                isCurrent: () => current))
            .status,
        GroupControlStatus.failed);
    expect(engine.openCalls, 1);
    engine.close = () async => throw StateError('native close failed');
    for (final device in GroupControlDevice.values) {
      expect(
          (await media.setDevice(device, false, isCurrent: () => current)).status,
          GroupControlStatus.failed);
    }
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

/// 模拟 TUICallEngine 请求和返回，不注册原生监听、不访问真实媒体设备。
class _Engine extends Fake implements TUICallEngine {
  int openCalls = 0;
  (TUICamera, int?)? cameraRequest;
  TUICallObserver? observer;

  @override
  Future<void> addObserver(TUICallObserver value) async {
    observer = value;
  }

  @override
  Future<void> removeObserver(TUICallObserver value) async {
    if (identical(observer, value)) observer = null;
  }

  @override
  Future<TUIActionCallback> openCamera(TUICamera camera, int? viewId) async {
    cameraRequest = (camera, viewId);
    return await openVideo?.call(viewId) ??
        TUIActionCallback(code: TUIError.success, message: null);
  }

  /// 可模拟需要现有预览绑定或拒绝预览参数的原生开启回包。
  Future<TUIActionCallback> Function(int?)? openVideo;

  Future<TUIActionCallback> Function()? open;
  Future<void> Function(Map<String, dynamic>)? cameraCommand;
  Future<void> Function()? close;
  @override
  Future<TUIActionCallback> openMicrophone() {
    openCalls++;
    return open?.call() ??
        Future.value(TUIActionCallback(code: TUIError.success, message: null));
  }

  @override
  Future<void> callExperimentalAPI(Map<String, dynamic> jsonMap) async {
    await cameraCommand?.call(jsonMap);
  }

  @override
  Future<void> closeMicrophone() => close?.call() ?? Future.value();

  @override
  Future<void> closeCamera() => closeMicrophone();
}
