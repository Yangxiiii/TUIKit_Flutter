import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'audio_recorder.dart';

class AudioRecordResult {
  final AudioRecordResultCode resultCode;
  final String? filePath;
  final int durationMs;

  AudioRecordResult({
    required this.resultCode,
    this.filePath,
    required this.durationMs,
  });

  bool get isSuccess =>
      resultCode == AudioRecordResultCode.success ||
      resultCode == AudioRecordResultCode.successExceedMaxDuration;

  @override
  String toString() {
    return 'AudioRecordResult(resultCode: ${resultCode.name}, filePath: $filePath, durationMs: $durationMs)';
  }
}

class AudioRecorderConfig {
  final String? filepath;
  final bool enableAIDeNoise;
  final int minDurationMs;
  final int maxDurationMs;

  const AudioRecorderConfig({
    this.filepath,
    this.enableAIDeNoise = false,
    this.minDurationMs = 1000,
    this.maxDurationMs = 60000,
  });
}

/// 桥接录音与音轨合并；合并输出必须是新文件，不能覆盖正在预览的原音。
class AudioRecorderPlatform {
  static const MethodChannel _methodChannel =
      MethodChannel('tencent_chat_uikit/audio_recorder');
  static const EventChannel _eventChannel =
      EventChannel('tencent_chat_uikit/audio_recorder_events');

  /// HarmonyOS detection. `Platform.isOhos` only exists in the Flutter-OH SDK,
  /// so we compare the OS string to stay compilable under standard Flutter.
  ///
  /// HarmonyOS 检测。`Platform.isOhos` 仅在 Flutter-OH SDK 中存在，因此我们通过比较操作系统字符串来保持在标准 Flutter 下可编译。
  static bool get _isOhos => Platform.operatingSystem == 'ohos';

  static StreamSubscription? _eventSubscription;
  static Function(int timeMs)? _onRecordTime;
  static Function(int powerLevel)? _onPowerLevel;

  /// 合并压缩音轨并校验返回边界，失败交给草稿保留原有效音频。
  static Future<RecordInfo> mergeRecordings(
      List<String> paths, String destination) async {
    final result = await _methodChannel.invokeMethod<Object?>(
      'mergeRecordings',
      {'paths': paths, 'destination': destination},
    );
    if (result is! Map ||
        result['filePath'] != destination ||
        result['durationMs'] is! int) {
      throw PlatformException(code: 'INVALID_MERGED_AUDIO');
    }
    final durationMs = result['durationMs'] as int;
    if (durationMs < 1000 || durationMs > 60000) {
      throw PlatformException(code: 'INVALID_MERGED_DURATION');
    }
    return RecordInfo(
      path: destination,
      duration: (durationMs + 999) ~/ 1000,
      durationMs: durationMs,
    );
  }

  /// Start recording with native implementation
  ///
  /// 使用本地实现开始录音
  static Future<AudioRecordResult> startRecordNative({
    required AudioRecorderConfig config,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS && !_isOhos) {
      throw UnsupportedError(
          'Native AudioRecorder is only supported on Android, iOS and HarmonyOS');
    }

    try {
      // Setup event channel for progress updates
      //
      // 设置事件通道以获取进度更新
      await _eventSubscription?.cancel();

      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is Map) {
            final eventType = event['type'] as String?;

            if (eventType == 'recordTime') {
              final timeMs = event['timeMs'] as int;
              _onRecordTime?.call(timeMs);
            } else if (eventType == 'powerLevel') {
              final powerLevel = event['powerLevel'] as int;
              _onPowerLevel?.call(powerLevel);
            }
          }
        },
        onError: (error) {
          debugPrint('AudioRecorderPlatform EventChannel error: $error');
        },
      );

      // Call native method to start recording
      //
      // 调用本地方法开始录音
      final result = await _methodChannel.invokeMethod(
        'startRecord',
        {
          'filepath': config.filepath,
          'enableAIDeNoise': config.enableAIDeNoise,
          'minDurationMs': config.minDurationMs,
          'maxDurationMs': config.maxDurationMs,
        },
      );

      if (result == null) {
        throw Exception('AudioRecorder returned null result');
      }

      final resultMap = result as Map;
      final resultCode = AudioRecordResultCode.fromCode(
        resultMap['resultCode'] as int? ?? -5,
      );

      return AudioRecordResult(
        resultCode: resultCode,
        filePath: resultMap['filePath'] as String?,
        durationMs: resultMap['durationMs'] as int? ?? 0,
      );
    } catch (e) {
      debugPrint('AudioRecorderPlatform.startRecordNative error: $e');
      rethrow;
    } finally {
      await dispose();
    }
  }

  /// Stop recording
  ///
  /// 停止录音
  static Future<AudioRecordResult?> stopRecordNative() async {
    try {
      await _methodChannel.invokeMethod('stopRecord');
      return null;
    } catch (e) {
      debugPrint('AudioRecorderPlatform.stopRecordNative error: $e');
      return null;
    }
  }

  /// Cancel recording
  ///
  /// 取消录音
  static Future<void> cancelRecordNative() async {
    try {
      await _methodChannel.invokeMethod('cancelRecord');
    } catch (e) {
      debugPrint('AudioRecorderPlatform.cancelRecordNative error: $e');
    }
  }

  /// Set callback for recording time updates
  ///
  /// 设置录音时间更新的回调
  static void setOnRecordTime(Function(int timeMs)? callback) {
    _onRecordTime = callback;
  }

  /// Set callback for power level updates
  ///
  /// 设置电量更新的回调
  static void setOnPowerLevel(Function(int powerLevel)? callback) {
    _onPowerLevel = callback;
  }

  /// Dispose resources
  ///
  /// 释放资源
  static Future<void> dispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _onRecordTime = null;
    _onPowerLevel = null;
  }
}
