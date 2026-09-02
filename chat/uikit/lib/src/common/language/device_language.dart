import 'package:flutter/material.dart';

/// Helper for resolving the current device language code for ChatKit.
///
/// 用于解析 ChatKit 当前设备语言代码的辅助方法。
class ChatDeviceLanguage {
  static String getCurrentLanguageCode(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    final scriptCode = Localizations.localeOf(context).scriptCode;
    if (languageCode == 'zh' && scriptCode == 'Hant') {
      return 'zh-Hant';
    }
    if (languageCode == 'zh') {
      return 'zh-Hans';
    }
    return languageCode;
  }

  static bool checkLocale(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return languageCode == 'zh' || languageCode == 'en';
  }
}
