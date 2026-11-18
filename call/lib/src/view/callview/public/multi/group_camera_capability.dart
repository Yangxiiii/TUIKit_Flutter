import 'package:flutter/services.dart';

/// 查询原生可切换摄像头数量；未知能力不推测为双摄像头。
Future<int?> readGroupCameraCount() async {
  try {
    final count = await const MethodChannel('tencent_calls_uikit')
        .invokeMethod<int>('getCameraCount');
    return count != null && count >= 0 ? count : null;
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
