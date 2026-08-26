import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum StickerDeviceScreenType { desktop, mobile }

class EmojiPickerUtils {
  static StickerDeviceScreenType getDeviceType(BuildContext context) {
    if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final win = WidgetsBinding.instance.platformDispatcher.views.first;
      final size = win.physicalSize;
      final screenWidth = size.width / win.devicePixelRatio;
      final screenHeight = size.height / win.devicePixelRatio;

      final diagonalInInches =
          sqrt(pow(screenWidth, 2) + pow(screenHeight, 2)) / 96.0;

      return diagonalInInches < 10
          ? StickerDeviceScreenType.mobile
          : StickerDeviceScreenType.desktop;
    } else {
      double deviceWidth = MediaQuery.of(context).size.width;
      double deviceHeight = MediaQuery.of(context).size.height;

      if (deviceWidth > 900 || deviceWidth > deviceHeight * 1.1) {
        return StickerDeviceScreenType.desktop;
      } else if (deviceWidth > 300) {
        return StickerDeviceScreenType.mobile;
      }
      return StickerDeviceScreenType.mobile;
    }
  }
}
