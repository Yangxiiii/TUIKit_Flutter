import 'dart:async';

import 'package:flutter/material.dart';

import 'audio_recorder_platform.dart';

enum AudioRecordResultCode {
  successExceedMaxDuration(1),
  success(0),
  errorCancel(-1),
  errorRecording(-2),
  errorStorageUnavailable(-3),
  errorLessThanMinDuration(-4),
  errorRecordInnerFail(-5),
  errorRecordPermissionDenied(-6);

  final int code;
  const AudioRecordResultCode(this.code);

  static AudioRecordResultCode fromCode(int code) {
    return AudioRecordResultCode.values.firstWhere(
      (e) => e.code == code,
      orElse: () => AudioRecordResultCode.errorRecordInnerFail,
    );
  }
}

/// 录音完成或合并后的文件信息，同时保留SDK秒数和续录累计所需的毫秒数。
class RecordInfo {
  /// 原生录音结果；只有成功结果可以进入草稿或发送。
  AudioRecordResultCode errorCode = AudioRecordResultCode.success;

  /// 当前设备上的完整音频文件路径。
  String path;

  /// SDK 发送使用的整秒时长；精确累计使用 durationMs。
  final int duration;

  /// 实际有效音频毫秒数，续录时不把每段舍入误差累加。
  final int durationMs;

  RecordInfo({
    required this.duration,
    required this.path,
    int? durationMs,
  }) : durationMs = durationMs ?? duration * 1000;

  @override
  String toString() {
    return 'RecordInfo(errorCode: ${errorCode.name}, path: $path, duration: $duration)';
  }
}

typedef RecordingProgressCallback = void Function(
    int duration, double progress);

typedef RecordingStateCallback = void Function(bool isRecording);

typedef RecordingPowerLevelCallback = void Function(int powerLevel);

typedef AudioRecordCompleteCallback = void Function(RecordInfo? recordInfo);

/// 调用现有原生录音器，统一返回精确时长并管理录音回调生命周期。
class AudioRecorder {
  /// 标记采音会话，原生终态回调清理后才允许下一次录音。
  bool _isRecording = false;

  /// 一条语音的录制上限，单位为毫秒；续录调用传入剩余额度。
  final int maxDuration = 60000;

  /// 单次有效片段的最短时长，单位为毫秒。
  final int minDuration = 1000;

  /// 原生进度回调，时长单位为毫秒，进度范围为0至1。
  RecordingProgressCallback? onProgressUpdate;

  /// 采音开始和清理时通知输入栏更新录音状态。
  RecordingStateCallback? onStateChanged;

  /// 原生提供的dBFS音量，0为满幅，负值越小越安静；供录音波形展示使用。
  RecordingPowerLevelCallback? onPowerLevel;

  /// 是否仍在等待当前原生录音会话结束。
  bool get isRecording => _isRecording;

  /// 当前片段的原生录音进度，单位为毫秒，结束时清零。
  int _recordingDuration = 0;

  /// 当前片段时长，单位为毫秒，不含预览期间的停顿。
  int get recordingDuration => _recordingDuration;

  /// 当前片段相对单条上限的进度，续录的累计进度由草稿维护。
  double get recordingProgress => _recordingDuration / maxDuration;

  /// 注册当前输入栏的录音观察回调，销毁时一并释放。
  void initialize({
    RecordingProgressCallback? onProgressUpdate,
    RecordingStateCallback? onStateChanged,
    RecordingPowerLevelCallback? onPowerLevel,
  }) {
    this.onProgressUpdate = onProgressUpdate;
    this.onStateChanged = onStateChanged;
    this.onPowerLevel = onPowerLevel;
  }

  /// 启动原生采音；完成回调在停止、取消、超时或失败后触发。
  Future<bool> startRecord({
    required String filePath,
    required AudioRecordCompleteCallback onComplete,
    int? maxDurationMs,
  }) async {
    if (_isRecording) {
      debugPrint('Already recording');
      return false;
    }

    try {
      _recordingDuration = 0;
      _isRecording = true;

      onStateChanged?.call(_isRecording);

      // 先注册进度监听，再启动原生会话，避免丢失开始阶段的回调。
      AudioRecorderPlatform.setOnRecordTime((timeMs) {
        _recordingDuration = timeMs;
        onProgressUpdate?.call(_recordingDuration, recordingProgress);
      });

      AudioRecorderPlatform.setOnPowerLevel((powerLevel) {
        onPowerLevel?.call(powerLevel);
      });

      // 原生启动调用一直挂起到录音终态；启动成功不代表已经生成音频文件。
      _startNativeRecording(
        filePath: filePath,
        onComplete: onComplete,
        maxDurationMs: maxDurationMs ?? maxDuration,
      );

      return true;
    } catch (e) {
      debugPrint('Start record failed: $e');
      _cleanup();
      return false;
    }
  }

  /// 等待原生终态并统一时长单位，清理状态后再向调用方交付结果。
  Future<void> _startNativeRecording({
    required String filePath,
    required AudioRecordCompleteCallback onComplete,
    int? maxDurationMs,
  }) async {
    try {
      final result = await AudioRecorderPlatform.startRecordNative(
        config: AudioRecorderConfig(
          filepath: filePath,
          enableAIDeNoise: false,
          minDurationMs: minDuration,
          maxDurationMs: maxDurationMs ?? maxDuration,
        ),
      );

      // SDK发送保留整秒兼容，草稿始终使用毫秒避免续录累计舍入误差。
      RecordInfo? recordInfo;

      if (result.isSuccess && result.filePath != null) {
        recordInfo = RecordInfo(
          duration: (result.durationMs / 1000).floor(),
          durationMs: result.durationMs,
          path: result.filePath!,
        )..errorCode = result.resultCode;
      } else if (result.resultCode ==
          AudioRecordResultCode.errorLessThanMinDuration) {
        recordInfo = RecordInfo(
          duration: result.durationMs ~/ 1000,
          durationMs: result.durationMs,
          path: '',
        )..errorCode = result.resultCode;
      } else {
        recordInfo = RecordInfo(
          duration: result.durationMs ~/ 1000,
          durationMs: result.durationMs,
          path: result.filePath ?? '',
        )..errorCode = result.resultCode;
      }

      _cleanup();
      onComplete(recordInfo);
    } catch (e) {
      debugPrint('Native recording error: $e');
      _cleanup();
      onComplete(null);
    }
  }

  /// 请求停止采音，文件结果仍通过启动时的完成回调交付。
  void stopRecord() {
    if (!_isRecording) {
      return;
    }

    try {
      AudioRecorderPlatform.stopRecordNative();
    } catch (e) {
      debugPrint('Stop record failed: $e');
    }
  }

  /// 取消当前采音并释放本地状态，取消结果不可进入发送链路。
  Future<void> cancelRecord() async {
    if (!_isRecording) {
      return;
    }

    try {
      await AudioRecorderPlatform.cancelRecordNative();
      _cleanup();
    } catch (e) {
      debugPrint('Cancel record failed: $e');
      _cleanup();
    }
  }

  /// 终态先清理标记和计时，再通知界面，避免旧状态污染下次录音。
  void _cleanup() {
    final wasRecording = _isRecording;
    _isRecording = false;
    _recordingDuration = 0;

    if (wasRecording) {
      onStateChanged?.call(_isRecording);
      onProgressUpdate?.call(_recordingDuration, recordingProgress);
    }
  }

  /// 释放当前输入栏的录音状态和平台进度监听。
  void dispose() {
    _cleanup();
    AudioRecorderPlatform.dispose();
  }
}
