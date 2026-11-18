import 'dart:io';

import 'package:flutter/services.dart';

/// 工作区根包无 Flutter 资源清单，测试读取已核实的 SDK 资源而不伪造图片。
class RepositoryAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    const prefix = 'packages/tuikit_atomic_x/';
    if (key.startsWith(prefix)) {
      final bytes = await File(
              'third_party/tencent_tuikit_flutter/atomic-x/${key.substring(prefix.length)}')
          .readAsBytes();
      return ByteData.sublistView(bytes);
    }
    return rootBundle.load(key);
  }
}
