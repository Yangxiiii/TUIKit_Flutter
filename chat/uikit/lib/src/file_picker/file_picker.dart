import 'package:app_ui/app_ui.dart';
import 'dart:io';

import 'package:tencent_chat_uikit/tencent_chat_uikit.dart' hide AlertDialog;
import 'package:tuikit_atomic_x/device_info/device.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

class FilePickerConfig {
  final int? maxCount;

  FilePickerConfig({
    this.maxCount,
  });
}

class FilePicker {
  static const int maxFileCount = 9;

  static final FilePicker instance = FilePicker._internal();

  FilePicker._internal();

  /// HarmonyOS detection. `Platform.isOhos` only exists in the Flutter-OH SDK,
  /// so we compare the OS string to stay compilable under standard Flutter.
  ///
  /// HarmonyOS 检测。`Platform.isOhos` 仅存在于 Flutter-OH SDK 中，所以我们比较操作系统字符串，以保证在标准 Flutter 下可编译
  static bool get _isOhos => Platform.operatingSystem == 'ohos';

  static Future<List<PickerResult>> pickFiles({
    required BuildContext context,
    FilePickerConfig? config,
  }) async {
    try {
      // FilePicker uses SAF (Storage Access Framework) which doesn't require permissions
      // The system handles permission through the document picker UI
      //
      // FilePicker 使用 SAF（存储访问框架），不需要权限，系统通过文档选择器 UI 处理权限
      if (!await _checkAndRequestPermission(context)) {
        return [];
      }

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
          return results.take(maxCount).toList();
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

  static Future<bool> _checkAndRequestPermission(BuildContext context) async {
    if (kIsWeb) {
      return true;
    }

    PermissionType permissionType;
    if (Platform.isAndroid) {
      final sdkInt = await Device.sdkInt;
      if (sdkInt! >= 33) {
        permissionType = PermissionType.photos;
      } else {
        permissionType = PermissionType.storage;
      }
    } else if (Platform.isIOS) {
      permissionType = PermissionType.photos;
    } else {
      return true;
    }

    return Permission.checkAndRequest(context, [permissionType]);
  }

  /// Open file with system default application
  ///
  /// Returns true if the file was successfully opened, false otherwise.
  /// On Android, uses Intent.ACTION_VIEW to open the file.
  /// On iOS, uses UIDocumentInteractionController to open the file.
  /// On HarmonyOS, uses startAbility with implicit want (viewData).
  ///
  /// 用系统默认应用打开文件
  ///
  /// 如果文件成功打开返回 true，否则返回 false。在 Android 上，使用 Intent.ACTION_VIEW 打开文件。在 iOS 上，使用
  /// UIDocumentInteractionController 打开文件。在 HarmonyOS 上，使用带有隐式 want（viewData）的 startAbility。
  static Future<bool> openFile(String filePath) async {
    try {
      if (!Platform.isAndroid && !Platform.isIOS && !_isOhos) {
        throw UnsupportedError(
            'File opening only supports Android, iOS and HarmonyOS');
      }

      // On Android/iOS `filePath` is an absolute sandbox path, so dart:io File
      // can pre-validate existence cheaply. On HarmonyOS `filePath` is typically
      // a `file://docs/...` URI returned by DocumentViewPicker — dart:io File
      // cannot resolve such URIs, so we skip the check and let the native layer
      // decide.
      //
      // 在 Android/iOS 上，`filePath` 是绝对沙箱路径，所以 dart:io File 可以廉价地预验证文件是否存在。在 HarmonyOS 上，`filePath` 通常是由
      // DocumentViewPicker 返回的 `file://docs/...` URI — dart:io File 无法解析这样的 URI，因此我们跳过检查，让原生层处理。
      if (!_isOhos) {
        final file = File(filePath);
        if (!file.existsSync()) {
          debugPrint('FilePicker.openFile: File does not exist: $filePath');
          return false;
        }
      }

      return await FilePickerPlatform.openFile(filePath);
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
