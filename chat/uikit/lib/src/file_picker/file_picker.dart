import 'package:app_ui/app_ui.dart';
import 'dart:io';

import 'package:tencent_chat_uikit/tencent_chat_uikit.dart' hide AlertDialog;
import 'package:flutter/material.dart';

import 'file_open_cache.dart';
import 'file_picker_platform.dart';

class PickerResult {
  final String filePath;
  final String fileName;
  final int fileSize;
  final String extension;

  const PickerResult({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.extension,
  });

  @override
  String toString() {
    return 'PickerResult(filePath: $filePath, fileName: $fileName, fileSize: $fileSize, extension: $extension)';
  }
}

/// 为不同业务入口指定原生文件多选上限，不在平台侧截断结果。
class FilePickerConfig {
  /// 为空时沿用SDK默认九项，独立文件发送由宿主显式指定十项。
  final int? maxCount;

  FilePickerConfig({
    this.maxCount,
  });
}

/// 通过系统文档选择器获取文件授权，并使用平台能力打开本地文件。
class FilePicker {
  static const int maxFileCount = 9;

  static final FilePicker instance = FilePicker._internal();

  FilePicker._internal();

  /// HarmonyOS detection. `Platform.isOhos` only exists in the Flutter-OH SDK,
  /// so we compare the OS string to stay compilable under standard Flutter.
  ///
  /// HarmonyOS 检测。`Platform.isOhos` 仅存在于 Flutter-OH SDK 中，所以我们比较操作系统字符串，以保证在标准 Flutter 下可编译
  static bool get _isOhos => Platform.operatingSystem == 'ohos';

  /// 返回系统选择的全部文件；超量整体拒绝，取消则不改变业务选择。
  static Future<List<PickerResult>> pickFiles({
    required BuildContext context,
    FilePickerConfig? config,
  }) async {
    try {
      // 系统文档选择器按所选资源授予访问权，不能用照片权限阻挡普通文件选择。
      if (Platform.isAndroid || Platform.isIOS || _isOhos) {
        int maxCount = config?.maxCount ?? maxFileCount;

        final List<PickerResult> results = await FilePickerPlatform.pickFiles(
          maxCount: maxCount,
          allowedMimeTypes: [],
        );

        if (results.isEmpty) {
          return [];
        }

        if (results.length > maxCount) {
          if (context.mounted) {
            AppLocalizedText atomicLocal = AppLocalization.of(context);
            _showErrorDialog(context, atomicLocal.maxCountFile(maxCount));
          }
          return [];
        }

        return results;
      } else {
        throw UnsupportedError(
            'FilePicker only supports Android, iOS and HarmonyOS');
      }
    } catch (e) {
      debugPrint('FilePicker.pickFiles error: $e');
      return [];
    }
  }

  /// 用平台文档预览或外部应用打开文件；传入 [fileName] 时使用消息里的文件名。
  /// 文件准备结束后由 [canOpen] 复核页面和消息是否仍允许拉起系统应用。
  static Future<bool> openFile(
    String filePath, {
    String? fileName,
    bool Function()? canOpen,
  }) async {
    try {
      if (!Platform.isAndroid && !Platform.isIOS && !_isOhos) {
        throw UnsupportedError(
            'File opening only supports Android, iOS and HarmonyOS');
      }

      // 鸿蒙文档选择器可能返回系统 URI，交给原生层处理。Android 和 iOS 使用本地路径。
      if (!_isOhos) {
        final file = File(filePath);
        if (!file.existsSync()) {
          debugPrint('FilePicker.openFile: File does not exist: $filePath');
          return false;
        }
      }

      // 原生侧从文件路径提取文件名和类型，先为 UUID 或摘要缓存准备可读路径。
      final openPath = await prepareFileForOpen(filePath, fileName);
      if (canOpen?.call() == false) return false;
      return await FilePickerPlatform.openFile(openPath);
    } catch (e) {
      debugPrint('FilePicker.openFile error: $e');
      return false;
    }
  }

  static void _showErrorDialog(BuildContext context, String message) {
    AppLocalizedText atomicLocal = AppLocalization.of(context);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(atomicLocal.error),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(atomicLocal.confirm),
            ),
          ],
        );
      },
    );
  }
}
