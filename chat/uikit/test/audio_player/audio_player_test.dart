import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/audio_player/audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('tencent_chat_uikit/audio_player');
  const events = MethodChannel('tencent_chat_uikit/audio_player_events');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var position = 0;
  var failPause = false;

  Future<void> emit(String type) async {
    final sent = Completer<void>();
    messenger.handlePlatformMessage(events.name,
        codec.encodeSuccessEnvelope({'type': type}), (_) => sent.complete());
    await sent.future;
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    position = 0;
    failPause = false;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'play':
          position = (call.arguments as Map)['startPositionMs'] as int;
          await emit('onPlay');
        case 'pause':
          if (failPause) throw PlatformException(code: 'PAUSE_FAILED');
          await emit('onPause');
        case 'resume':
          await emit('onResume');
        case 'getCurrentPosition':
          return position;
      }
      return null;
    });
  });
  tearDown(() async {
    await AudioPlayer.stopAll();
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('同一消息暂停恢复，切换A到B后再回A保留各自毫秒位置', () async {
    final a = AudioPlayer.createInstance();
    final b = AudioPlayer.createInstance();
    await a.play('A.m4a');
    expect(a.isPlaying, isTrue);
    position = 1234;
    await a.play('A.m4a');
    expect(a.isPaused, isTrue);
    await a.resume();
    expect(a.isPlaying, isTrue);
    await b.play('B.m4a');
    expect(a.isPaused, isTrue);
    expect(b.isPlaying, isTrue);
    position = 2345;
    await a.resume();
    final playCalls = calls.where((call) => call.method == 'play').toList();
    expect(playCalls.map((call) => call.arguments), [
      {'filePath': 'A.m4a', 'startPositionMs': 0},
      {'filePath': 'B.m4a', 'startPositionMs': 0},
      {'filePath': 'A.m4a', 'startPositionMs': 1234},
    ]);
    expect(b.getCurrentPosition(), 2345);
    final stops = calls.where((call) => call.method == 'stop').length;
    await b.dispose();
    expect(calls.where((call) => call.method == 'stop').length, stops);
    expect(a.isPlaying, isTrue);
    await a.dispose();
  });

  test('重复播放合并，原生暂停失败不会伪报暂停且后续队列可恢复', () async {
    final a = AudioPlayer.createInstance();
    await Future.wait([a.play('A.m4a'), a.play('A.m4a')]);
    expect(calls.where((call) => call.method == 'play'), hasLength(1));
    failPause = true;
    await expectLater(a.pause(), throwsA(isA<PlatformException>()));
    expect(a.isPlaying, isTrue);
    failPause = false;
    await a.pause();
    expect(a.isPaused, isTrue);
    await a.dispose();
  });
}
