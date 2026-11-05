import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_chat_uikit/src/audio_recoder/audio_recorder.dart';
import 'package:tencent_chat_uikit/src/audio_recoder/audio_recording_draft.dart';

void main() {
  late Directory directory;
  late ActionGuard guard;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chat_voice_test_');
    guard = ActionGuard();
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<RecordInfo> segment(String name, int milliseconds) async {
    final file = await File('${directory.path}/$name.m4a').writeAsString(name);
    return RecordInfo(
      path: file.path,
      duration: (milliseconds + 999) ~/ 1000,
      durationMs: milliseconds,
    );
  }

  test('连续追加按A+B+C顺序提交，累计时长不重置', () async {
    final inputs = <List<String>>[];
    final draft = AudioRecordingDraft(
      guard: guard,
      join: (paths, destination) async {
        inputs.add(paths);
        final text =
            [for (final path in paths) await File(path).readAsString()].join();
        await File(destination).writeAsString(text);
        return RecordInfo(
          path: destination,
          duration: text.length * 10,
          durationMs: text.length * 10000,
        );
      },
    );
    await draft.append(await segment('A', 10000));
    await draft.append(await segment('B', 10000));
    final merged = await draft.append(await segment('C', 10000));
    expect(await File(merged.path).readAsString(), 'ABC');
    expect(inputs.length, 2);
    expect(merged.durationMs, 30000);
    expect(draft.remainingDurationMs, 30000);
    await draft.dispose();
    expect(await File(merged.path).exists(), isFalse);
  });

  test('合并失败保留原音，失败后能再次追加', () async {
    var fail = true;
    final draft = AudioRecordingDraft(
      guard: guard,
      join: (paths, destination) async {
        if (fail) throw const FileSystemException('merge failed');
        await File(destination).writeAsString('AB');
        return RecordInfo(path: destination, duration: 2);
      },
    );
    final first = await segment('A', 1000);
    await draft.append(first);
    final second = await segment('B', 1000);
    await expectLater(
        draft.append(second), throwsA(isA<FileSystemException>()));
    expect(draft.current, same(first));
    expect(await File(first.path).readAsString(), 'A');
    fail = false;
    expect((await draft.append(second)).durationMs, 2000);
    await draft.dispose();
  });

  test('超过整条60秒时拒绝追加且原音不变', () async {
    final draft = AudioRecordingDraft(guard: guard);
    final first = await segment('A', 59000);
    await draft.append(first);
    await expectLater(
      draft.append(await segment('B', 1001)),
      throwsArgumentError,
    );
    expect(draft.current, same(first));
    expect(draft.remainingDurationMs, 1000);
    await draft.dispose();
  });

  test('最短1秒和整条60秒均允许，999毫秒不能成为有效草稿', () async {
    final draft = AudioRecordingDraft(
      guard: guard,
      join: (paths, destination) async {
        await File(destination).writeAsString('AB');
        return RecordInfo(path: destination, duration: 60);
      },
    );
    await expectLater(
        draft.append(await segment('short', 999)), throwsArgumentError);
    expect(draft.current, isNull);
    await draft.append(await segment('A', 59000));
    final full = await draft.append(await segment('B', 1000));
    expect(full.durationMs, 60000);
    expect(draft.remainingDurationMs, 0);
    await expectLater(
        draft.append(await segment('C', 1000)), throwsArgumentError);
    expect(draft.current, same(full));
    await draft.dispose();
  });

  test('无效合并结果清理半成品，同一片段可重试且保留旧草稿', () async {
    var invalid = true;
    final draft = AudioRecordingDraft(
      guard: guard,
      join: (paths, destination) async {
        expect(await File(destination).exists(), isFalse);
        await File(destination).writeAsString('AB');
        return RecordInfo(path: destination, duration: invalid ? 1 : 2);
      },
    );
    final first = await segment('A', 1000);
    final second = await segment('B', 1000);
    await draft.append(first);
    await expectLater(draft.append(second), throwsStateError);
    expect(draft.current, same(first));
    expect(await File('${second.path}.joined.m4a').exists(), isFalse);
    invalid = false;
    expect((await draft.append(second)).durationMs, 2000);
    await draft.dispose();
  });

  test('合并中重复提交只调用一次，发送文件转移后不被清理', () async {
    final complete = Completer<RecordInfo>();
    final started = Completer<void>();
    var calls = 0;
    late String destination;
    final draft = AudioRecordingDraft(
      guard: guard,
      join: (paths, output) {
        calls++;
        destination = output;
        started.complete();
        return complete.future;
      },
    );
    await draft.append(await segment('A', 1000));
    final next = await segment('B', 1000);
    final first = draft.append(next);
    final repeated = draft.append(next);
    await started.future;
    await File(destination).writeAsString('AB');
    complete.complete(RecordInfo(path: destination, duration: 2));
    await Future.wait([first, repeated]);
    expect(calls, 1);
    draft.retainSentAudio();
    await draft.dispose();
    expect(await File(destination).exists(), isTrue);
  });

  test('草稿销毁后忽略并清理迟到的合并结果', () async {
    final complete = Completer<RecordInfo>();
    final started = Completer<void>();
    late String destination;
    final draft = AudioRecordingDraft(
      guard: guard,
      join: (paths, output) {
        destination = output;
        started.complete();
        return complete.future;
      },
    );
    await draft.append(await segment('A', 1000));
    final pending = draft.append(await segment('B', 1000));
    final assertion = expectLater(pending, throwsStateError);
    await started.future;
    await draft.dispose();
    await File(destination).writeAsString('AB');
    complete.complete(RecordInfo(path: destination, duration: 2));
    await assertion;
    expect(await File(destination).exists(), isFalse);
  });
}
