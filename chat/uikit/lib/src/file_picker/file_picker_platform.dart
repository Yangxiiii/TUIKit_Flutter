import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'file_picker.dart' show PickerResult;

class FilePickerPlatform {
  static const MethodChannel _methodChannel =
      MethodChannel('tencent_chat_uikit/file_picker');

  /// HarmonyOS detection. `Platform.isOhos` only exists in the Flutter-OH SDK,
  /// so we compare the OS string to stay compilable under standard Flutter.
  ///
  /// HarmonyOS 检测。`Platform.isOhos` 只存在于 Flutter-OH SDK 中，所以我们通过比较 OS 字符串来保持在标准 Flutter 下可编译。
  static bool get _isOhos => Platform.operatingSystem == 'ohos';

  /// Pick files using native implementation
  ///
  /// 使用原生实现选择文件
  static Future<List<PickerResult>> pickFiles({
    int maxCount = 1,
    List<String> allowedMimeTypes = const [],
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS && !_isOhos) {
      throw UnsupportedError(
          'Native FilePicker is only supported on Android, iOS and HarmonyOS');
    }

    try {
      final result = await _methodChannel.invokeMethod('pickFiles', {
        'maxCount': maxCount,
        'allowedMimeTypes': allowedMimeTypes,
      });

      if (result == null || result is! List) {
        return [];
      }

      final List<PickerResult> pickerResults = [];
      for (final item in result) {
        if (item is Map) {
          pickerResults.add(PickerResult(
            filePath: item['filePath'] as String? ?? '',
            fileName: item['fileName'] as String? ?? '',
            fileSize: (item['fileSize'] as num?)?.toInt() ?? 0,
            extension: item['extension'] as String? ?? '',
          ));
        }
      }

      return pickerResults;
    } catch (e) {
      print('FilePickerPlatform.pickFiles error: $e');
      rethrow;
    }
  }

  /// Open file with system default application
  ///
  /// 使用系统默认应用打开文件
  static Future<bool> openFile(String filePath) async {
    if (!Platform.isAndroid && !Platform.isIOS && !_isOhos) {
      throw UnsupportedError(
          'Native file opening is only supported on Android, iOS and HarmonyOS');
    }

    try {
      final result = await _methodChannel.invokeMethod<bool>('openFile', {
        'filePath': filePath,
      });
      return result ?? false;
    } catch (e) {
      print('FilePickerPlatform.openFile error: $e');
      return false;
    }
  }
}
