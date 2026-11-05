import 'dart:io';

import 'package:app_core/app_core.dart';

import 'audio_recorder.dart';
import 'audio_recorder_platform.dart';

/// 供原生桥接或测试替身按顺序合并音轨，输出路径必须与输入不同。
typedef AudioClipJoiner = Future<RecordInfo> Function(
    List<String> paths, String destination);

/// 管理单条语音草稿的累计时长与临时文件，合并失败不破坏旧录音。
final class AudioRecordingDraft {
  AudioRecordingDraft({
    required ActionGuard guard,
    AudioClipJoiner? join,
  })  : _guard = guard,
        _join = join ?? AudioRecorderPlatform.mergeRecordings;

  final ActionGuard _guard;
  final AudioClipJoiner _join;

  /// 草稿结束时统一清理，避免迟到的识别还在读取旧片段时提前删文件。
  final Set<String> _files = {};

  /// 仅在有效片段或合并结果通过文件校验后更新，失败时仍指向旧音频。
  RecordInfo? _current;

  /// 结束后的异步合并结果不能再接管草稿。
  bool _disposed = false;

  /// 当前已验证的完整音频，包含所有已成功追加的片段。
  RecordInfo? get current => _current;

  /// 整条语音最多60秒，暂停预览的等待时间不占额度。
  int get remainingDurationMs =>
      (60000 - (_current?.durationMs ?? 0)).clamp(0, 60000);

  /// 只在新文件验证后替换当前录音；同一草稿合并中的重复调用复用首次结果。
  Future<RecordInfo> append(RecordInfo segment) =>
      _guard.singleFlight<RecordInfo>(('chat.voice.draft.append', this),
          () async {
        if (_disposed) throw StateError('Recording draft is disposed');
        if (segment.errorCode != AudioRecordResultCode.success &&
            segment.errorCode !=
                AudioRecordResultCode.successExceedMaxDuration) {
          throw ArgumentError('Unsuccessful recording');
        }
        if (segment.path.isEmpty) throw ArgumentError('Empty recording path');
        _files.add(segment.path);
        if (segment.durationMs < 1000 ||
            segment.durationMs > remainingDurationMs ||
            !await File(segment.path).exists() ||
            await File(segment.path).length() == 0) {
          throw ArgumentError('Invalid recording segment');
        }
        if (_disposed) throw StateError('Recording draft is disposed');
        final previous = _current;
        if (previous == null) {
          _current = segment;
          return segment;
        }

        // 输出使用新片段独有的派生路径，原草稿在合并和验证期间始终保留。
        final destination = '${segment.path}.joined.m4a';
        _files.add(destination);
        try {
          final merged = await _join(
            [previous.path, segment.path],
            destination,
          );
          if (_disposed) {
            await _delete(destination);
            throw StateError('Recording draft is disposed');
          }
          if (merged.path != destination ||
              merged.durationMs <= previous.durationMs ||
              merged.durationMs > 60000 ||
              !await File(destination).exists() ||
              await File(destination).length() == 0) {
            throw StateError('Invalid merged audio');
          }
          // 文件校验也会异步让出执行，提交草稿前必须再次复核生命周期。
          if (_disposed) {
            await _delete(destination);
            throw StateError('Recording draft is disposed');
          }
          _current = merged;
          return merged;
        } catch (_) {
          // 原生失败或结果校验失败都清理半成品，保证同一片段仍可重试。
          await _delete(destination);
          rethrow;
        }
      });

  /// 音频已交给发送链路时转移文件所有权，清理草稿不能删除待上传文件。
  void retainSentAudio() {
    final current = _current;
    if (current != null) _files.remove(current.path);
  }

  /// 标记终止后再清理，迟到的合并结果由 append 自行删除。
  Future<void> dispose() async {
    _disposed = true;
    for (final path in _files.toList()) {
      await _delete(path);
    }
    _files.clear();
  }

  /// 临时文件可能已被原生取消流程清理，重复清理保持幂等。
  Future<void> _delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 清理失败不覆盖录音或发送的原始结果，文件仍归应用缓存管理。
    }
  }
}
