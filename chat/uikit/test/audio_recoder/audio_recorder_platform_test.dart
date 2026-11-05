import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/audio_recoder/audio_recorder_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tencent_chat_uikit/audio_recorder');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('按顺序桥接输入路径，保留毫秒并将SDK秒数向上取整', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'mergeRecordings');
      expect(call.arguments, {
        'paths': ['A.m4a', 'B.m4a'],
        'destination': 'AB.m4a',
      });
      return {'filePath': 'AB.m4a', 'durationMs': 2750};
    });
    final result = await AudioRecorderPlatform.mergeRecordings(
        ['A.m4a', 'B.m4a'], 'AB.m4a');
    expect(result.path, 'AB.m4a');
    expect(result.durationMs, 2750);
    expect(result.duration, 3);
  });

  test('拒绝路径替换、错误类型和超出时长范围的原生结果', () async {
    for (final response in <Object?>[
      null,
      {'filePath': 'A.m4a', 'durationMs': 2000},
      {'filePath': 'AB.m4a', 'durationMs': '2000'},
      {'filePath': 'AB.m4a', 'durationMs': 999},
      {'filePath': 'AB.m4a', 'durationMs': 60001},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      await expectLater(
        AudioRecorderPlatform.mergeRecordings(['A.m4a', 'B.m4a'], 'AB.m4a'),
        throwsA(isA<PlatformException>()),
      );
    }
  });

  test('原生合并失败保留异常供草稿恢复旧录音', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'MERGE_ERROR');
    });
    await expectLater(
      AudioRecorderPlatform.mergeRecordings(['A.m4a', 'B.m4a'], 'AB.m4a'),
      throwsA(isA<PlatformException>()
          .having((e) => e.code, 'code', 'MERGE_ERROR')),
    );
  });
}
