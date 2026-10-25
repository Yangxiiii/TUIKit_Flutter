import 'package:app_ui/app_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// iOS-only font-size scale factor.
///
/// SF Pro + PingFang on iOS render visually smaller than Roboto + Noto
/// Sans CJK on Android at the same logical pixel size, which made the
/// whole product feel "one size too small" on iPhones. We bump every
/// fontSize in the design system by this factor on iOS only — other
/// platforms keep the original size.
///
/// Hardcoded `fontSize: xx` literals scattered around the codebase are
/// NOT affected by this scale. Those should be migrated to FontScheme
/// over time; until then they will still look slightly small on iOS.
const double _kIosFontScale = 1.07;

double _scaled(double base) {
  return defaultTargetPlatform == TargetPlatform.iOS
      ? base * _kIosFontScale
      : base;
}

final SemanticFontScheme FontScheme = SemanticFontScheme(
  title1Bold: _Fonts.bold40,
  title2Bold: _Fonts.bold36,
  title3Bold: _Fonts.bold34,
  title4Bold: _Fonts.bold32,
  body1Bold: _Fonts.bold28,
  body2Bold: _Fonts.bold24,
  body3Bold: _Fonts.bold20,
  body4Bold: _Fonts.bold18,
  caption1Bold: _Fonts.bold16,
  caption2Bold: _Fonts.bold14,
  caption3Bold: _Fonts.bold12,
  caption4Bold: _Fonts.bold10,
  title1Medium: _Fonts.medium40,
  title2Medium: _Fonts.medium36,
  title3Medium: _Fonts.medium34,
  title4Medium: _Fonts.medium32,
  body1Medium: _Fonts.medium28,
  body2Medium: _Fonts.medium24,
  body3Medium: _Fonts.medium20,
  body4Medium: _Fonts.medium18,
  caption1Medium: _Fonts.medium16,
  caption2Medium: _Fonts.medium14,
  caption3Medium: _Fonts.medium12,
  caption4Medium: _Fonts.medium10,
  title1Regular: _Fonts.regular40,
  title2Regular: _Fonts.regular36,
  title3Regular: _Fonts.regular34,
  title4Regular: _Fonts.regular32,
  body1Regular: _Fonts.regular28,
  body2Regular: _Fonts.regular24,
  body3Regular: _Fonts.regular20,
  body4Regular: _Fonts.regular18,
  caption1Regular: _Fonts.regular16,
  caption2Regular: _Fonts.regular14,
  caption3Regular: _Fonts.regular12,
  caption4Regular: _Fonts.regular10,
);

class SemanticFontScheme {
  final TextStyle title1Bold;
  final TextStyle title2Bold;
  final TextStyle title3Bold;
  final TextStyle title4Bold;
  final TextStyle body1Bold;
  final TextStyle body2Bold;
  final TextStyle body3Bold;
  final TextStyle body4Bold;
  final TextStyle caption1Bold;
  final TextStyle caption2Bold;
  final TextStyle caption3Bold;
  final TextStyle caption4Bold;

  final TextStyle title1Medium;
  final TextStyle title2Medium;
  final TextStyle title3Medium;
  final TextStyle title4Medium;
  final TextStyle body1Medium;
  final TextStyle body2Medium;
  final TextStyle body3Medium;
  final TextStyle body4Medium;
  final TextStyle caption1Medium;
  final TextStyle caption2Medium;
  final TextStyle caption3Medium;
  final TextStyle caption4Medium;

  final TextStyle title1Regular;
  final TextStyle title2Regular;
  final TextStyle title3Regular;
  final TextStyle title4Regular;
  final TextStyle body1Regular;
  final TextStyle body2Regular;
  final TextStyle body3Regular;
  final TextStyle body4Regular;
  final TextStyle caption1Regular;
  final TextStyle caption2Regular;
  final TextStyle caption3Regular;
  final TextStyle caption4Regular;

  const SemanticFontScheme({
    required this.title1Bold,
    required this.title2Bold,
    required this.title3Bold,
    required this.title4Bold,
    required this.body1Bold,
    required this.body2Bold,
    required this.body3Bold,
    required this.body4Bold,
    required this.caption1Bold,
    required this.caption2Bold,
    required this.caption3Bold,
    required this.caption4Bold,
    required this.title1Medium,
    required this.title2Medium,
    required this.title3Medium,
    required this.title4Medium,
    required this.body1Medium,
    required this.body2Medium,
    required this.body3Medium,
    required this.body4Medium,
    required this.caption1Medium,
    required this.caption2Medium,
    required this.caption3Medium,
    required this.caption4Medium,
    required this.title1Regular,
    required this.title2Regular,
    required this.title3Regular,
    required this.title4Regular,
    required this.body1Regular,
    required this.body2Regular,
    required this.body3Regular,
    required this.body4Regular,
    required this.caption1Regular,
    required this.caption2Regular,
    required this.caption3Regular,
    required this.caption4Regular,
  });
}

/// 为SDK文字保留原有字号与字重，并统一使用宿主打包字体。
class _Fonts {
  static TextStyle _style(double size, FontWeight weight) => TextStyle(
        fontSize: _scaled(size),
        fontWeight: weight,
        fontFamily: AppThemeFactory.fontFamily,
      );
  // All font sizes below pass through [_scaled] so iOS gets the
  // _kIosFontScale bump while other platforms keep the design value.
  // Because [_scaled] reads `defaultTargetPlatform` at call time these
  // can't be `const`; `static final` is the right shape — initialised
  // once per process when the class is first touched.
  static final TextStyle bold40 = _style(40, FontWeight.bold);
  static final TextStyle bold36 = _style(36, FontWeight.bold);
  static final TextStyle bold34 = _style(34, FontWeight.bold);
  static final TextStyle bold32 = _style(32, FontWeight.bold);
  static final TextStyle bold28 = _style(28, FontWeight.bold);
  static final TextStyle bold24 = _style(24, FontWeight.bold);
  static final TextStyle bold20 = _style(20, FontWeight.bold);
  static final TextStyle bold18 = _style(18, FontWeight.bold);
  static final TextStyle bold16 = _style(16, FontWeight.bold);
  static final TextStyle bold14 = _style(14, FontWeight.bold);
  static final TextStyle bold12 = _style(12, FontWeight.bold);
  static final TextStyle bold10 = _style(10, FontWeight.bold);

  static final TextStyle medium40 = _style(40, FontWeight.w500);
  static final TextStyle medium36 = _style(36, FontWeight.w500);
  static final TextStyle medium34 = _style(34, FontWeight.w500);
  static final TextStyle medium32 = _style(32, FontWeight.w500);
  static final TextStyle medium28 = _style(28, FontWeight.w500);
  static final TextStyle medium24 = _style(24, FontWeight.w500);
  static final TextStyle medium20 = _style(20, FontWeight.w500);
  static final TextStyle medium18 = _style(18, FontWeight.w500);
  static final TextStyle medium16 = _style(16, FontWeight.w500);
  static final TextStyle medium14 = _style(14, FontWeight.w500);
  static final TextStyle medium12 = _style(12, FontWeight.w500);
  static final TextStyle medium10 = _style(10, FontWeight.w500);

  static final TextStyle regular40 = _style(40, FontWeight.normal);
  static final TextStyle regular36 = _style(36, FontWeight.normal);
  static final TextStyle regular34 = _style(34, FontWeight.normal);
  static final TextStyle regular32 = _style(32, FontWeight.normal);
  static final TextStyle regular28 = _style(28, FontWeight.normal);
  static final TextStyle regular24 = _style(24, FontWeight.normal);
  static final TextStyle regular20 = _style(20, FontWeight.normal);
  static final TextStyle regular18 = _style(18, FontWeight.normal);
  static final TextStyle regular16 = _style(16, FontWeight.normal);
  static final TextStyle regular14 = _style(14, FontWeight.normal);
  static final TextStyle regular12 = _style(12, FontWeight.normal);
  static final TextStyle regular10 = _style(10, FontWeight.normal);
}
