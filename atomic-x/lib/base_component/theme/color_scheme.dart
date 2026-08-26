import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 把 app_ui 语义颜色集中映射为 AtomicX 组件所需的细分状态色。
class SemanticColorScheme {
  // text & icon
  final Color textColorPrimary;
  final Color textColorSecondary;
  final Color textColorTertiary;
  final Color textColorDisable;
  final Color textColorButton;
  final Color textColorButtonDisabled;
  final Color textColorLink;
  final Color textColorLinkHover;
  final Color textColorLinkActive;
  final Color textColorLinkDisabled;
  final Color textColorAntiPrimary;
  final Color textColorAntiSecondary;
  final Color textColorWarning;
  final Color textColorSuccess;
  final Color textColorError;

  // background
  final Color bgColorTopBar;
  final Color bgColorOperate;
  final Color bgColorDialog;
  final Color bgColorDialogModule;
  final Color bgColorEntryCard;
  final Color bgColorFunction;
  final Color bgColorBottomBar;
  final Color bgColorInput;
  final Color bgColorBubbleReciprocal;
  final Color bgColorBubbleOwn;
  final Color bgColorDefault;
  final Color bgColorTagMask;
  final Color bgColorElementMask;
  final Color bgColorMask;
  final Color bgColorMaskDisappeared;
  final Color bgColorMaskBegin;
  final Color bgColorAvatar;

  // border
  final Color strokeColorPrimary;
  final Color strokeColorSecondary;
  final Color strokeColorModule;

  // shadow
  final Color shadowColor;

  // status
  final Color listColorDefault;
  final Color listColorHover;
  final Color listColorFocused;

  // button
  final Color buttonColorPrimaryDefault;
  final Color buttonColorPrimaryHover;
  final Color buttonColorPrimaryActive;
  final Color buttonColorPrimaryDisabled;
  final Color buttonColorSecondaryDefault;
  final Color buttonColorSecondaryHover;
  final Color buttonColorSecondaryActive;
  final Color buttonColorSecondaryDisabled;
  final Color buttonColorAccept;
  final Color buttonColorHangupDefault;
  final Color buttonColorHangupDisabled;
  final Color buttonColorHangupHover;
  final Color buttonColorHangupActive;
  final Color buttonColorOn;
  final Color buttonColorOff;

  // dropdown
  final Color dropdownColorDefault;
  final Color dropdownColorHover;
  final Color dropdownColorActive;

  // scrollbar
  final Color scrollbarColorDefault;
  final Color scrollbarColorHover;

  // floating
  final Color floatingColorDefault;
  final Color floatingColorOperate;

  // checkbox
  final Color checkboxColorSelected;

  // toast
  final Color toastColorWarning;
  final Color toastColorSuccess;
  final Color toastColorError;
  final Color toastColorDefault;

  // tag
  final Color tagColorLevel1;
  final Color tagColorLevel2;
  final Color tagColorLevel3;
  final Color tagColorLevel4;

  // switch
  final Color switchColorOff;
  final Color switchColorOn;
  final Color switchColorButton;

  // slider
  final Color sliderColorFilled;
  final Color sliderColorEmpty;
  final Color sliderColorButton;

  // tab
  final Color tabColorSelected;
  final Color tabColorUnselected;
  final Color tabColorOption;

  // clear
  final Color clearColor;

  const SemanticColorScheme._({
    required this.textColorPrimary,
    required this.textColorSecondary,
    required this.textColorTertiary,
    required this.textColorDisable,
    required this.textColorButton,
    required this.textColorButtonDisabled,
    required this.textColorLink,
    required this.textColorLinkHover,
    required this.textColorLinkActive,
    required this.textColorLinkDisabled,
    required this.textColorAntiPrimary,
    required this.textColorAntiSecondary,
    required this.textColorWarning,
    required this.textColorSuccess,
    required this.textColorError,
    required this.bgColorTopBar,
    required this.bgColorOperate,
    required this.bgColorDialog,
    required this.bgColorDialogModule,
    required this.bgColorEntryCard,
    required this.bgColorFunction,
    required this.bgColorBottomBar,
    required this.bgColorInput,
    required this.bgColorBubbleReciprocal,
    required this.bgColorBubbleOwn,
    required this.bgColorDefault,
    required this.bgColorTagMask,
    required this.bgColorElementMask,
    required this.bgColorMask,
    required this.bgColorMaskDisappeared,
    required this.bgColorMaskBegin,
    required this.bgColorAvatar,
    required this.strokeColorPrimary,
    required this.strokeColorSecondary,
    required this.strokeColorModule,
    required this.shadowColor,
    required this.listColorDefault,
    required this.listColorHover,
    required this.listColorFocused,
    required this.buttonColorPrimaryDefault,
    required this.buttonColorPrimaryHover,
    required this.buttonColorPrimaryActive,
    required this.buttonColorPrimaryDisabled,
    required this.buttonColorSecondaryDefault,
    required this.buttonColorSecondaryHover,
    required this.buttonColorSecondaryActive,
    required this.buttonColorSecondaryDisabled,
    required this.buttonColorAccept,
    required this.buttonColorHangupDefault,
    required this.buttonColorHangupDisabled,
    required this.buttonColorHangupHover,
    required this.buttonColorHangupActive,
    required this.buttonColorOn,
    required this.buttonColorOff,
    required this.dropdownColorDefault,
    required this.dropdownColorHover,
    required this.dropdownColorActive,
    required this.scrollbarColorDefault,
    required this.scrollbarColorHover,
    required this.floatingColorDefault,
    required this.floatingColorOperate,
    required this.checkboxColorSelected,
    required this.toastColorWarning,
    required this.toastColorSuccess,
    required this.toastColorError,
    required this.toastColorDefault,
    required this.tagColorLevel1,
    required this.tagColorLevel2,
    required this.tagColorLevel3,
    required this.tagColorLevel4,
    required this.switchColorOff,
    required this.switchColorOn,
    required this.switchColorButton,
    required this.sliderColorFilled,
    required this.sliderColorEmpty,
    required this.sliderColorButton,
    required this.tabColorSelected,
    required this.tabColorUnselected,
    required this.tabColorOption,
    required this.clearColor,
  });

  /// 从当前 app_ui 主题即时生成组件颜色，不持有或持久化第二套主题状态。
  factory SemanticColorScheme.of(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final appColors = context.appColors;
    final surface = colors.surface;
    final container = colors.surfaceContainer;
    final containerHigh = colors.surfaceContainerHigh;
    final disabled = colors.onSurface.withValues(alpha: 0.38);

    return SemanticColorScheme._(
      textColorPrimary: appColors.textPrimary,
      textColorSecondary: appColors.textSecondary,
      textColorTertiary: appColors.textTertiary,
      textColorDisable: disabled,
      textColorButton: appColors.onPrimary,
      textColorButtonDisabled: colors.onSurface.withValues(alpha: 0.38),
      textColorLink: colors.primary,
      textColorLinkHover: colors.primary.withValues(alpha: 0.86),
      textColorLinkActive: colors.primary.withValues(alpha: 0.72),
      textColorLinkDisabled: colors.primary.withValues(alpha: 0.38),
      textColorAntiPrimary: colors.onPrimaryContainer,
      textColorAntiSecondary: colors.onPrimaryContainer.withValues(alpha: 0.72),
      textColorWarning: appColors.warning,
      textColorSuccess: appColors.success,
      textColorError: appColors.danger,
      bgColorTopBar: surface,
      bgColorOperate: surface,
      bgColorDialog: containerHigh,
      bgColorDialogModule: container,
      bgColorEntryCard: container,
      bgColorFunction: container,
      bgColorBottomBar: surface,
      bgColorInput: appColors.chatInputBackground,
      bgColorBubbleReciprocal: appColors.chatIncomingBubble,
      bgColorBubbleOwn: appColors.chatOutgoingBubble,
      bgColorDefault: theme.scaffoldBackgroundColor,
      bgColorTagMask: colors.surface.withValues(alpha: 0.72),
      bgColorElementMask: colors.scrim.withValues(alpha: 0.38),
      bgColorMask: colors.scrim.withValues(alpha: 0.54),
      bgColorMaskDisappeared: colors.scrim.withValues(alpha: 0.12),
      bgColorMaskBegin: colors.scrim.withValues(alpha: 0.02),
      bgColorAvatar: colors.primaryContainer,
      strokeColorPrimary: appColors.outline,
      strokeColorSecondary: appColors.outline.withValues(alpha: 0.72),
      strokeColorModule: appColors.outline,
      shadowColor: colors.shadow.withValues(alpha: 0.24),
      listColorDefault: surface,
      listColorHover: container,
      listColorFocused: appColors.chatConversationPinned,
      buttonColorPrimaryDefault: appColors.primary,
      buttonColorPrimaryHover: appColors.primary.withValues(alpha: 0.86),
      buttonColorPrimaryActive: appColors.primary.withValues(alpha: 0.72),
      buttonColorPrimaryDisabled: appColors.primary.withValues(alpha: 0.38),
      buttonColorSecondaryDefault: container,
      buttonColorSecondaryHover: containerHigh,
      buttonColorSecondaryActive: colors.surfaceContainerHighest,
      buttonColorSecondaryDisabled: container.withValues(alpha: 0.38),
      buttonColorAccept: appColors.success,
      buttonColorHangupDefault: appColors.danger,
      buttonColorHangupDisabled: appColors.danger.withValues(alpha: 0.38),
      buttonColorHangupHover: appColors.danger.withValues(alpha: 0.86),
      buttonColorHangupActive: appColors.danger.withValues(alpha: 0.72),
      buttonColorOn: appColors.onPrimary,
      buttonColorOff: disabled,
      dropdownColorDefault: surface,
      dropdownColorHover: container,
      dropdownColorActive: colors.primaryContainer,
      scrollbarColorDefault: colors.outlineVariant,
      scrollbarColorHover: colors.outline,
      floatingColorDefault: surface,
      floatingColorOperate: container,
      checkboxColorSelected: appColors.primary,
      toastColorWarning: appColors.warningContainer,
      toastColorSuccess: colors.primaryContainer,
      toastColorError: colors.errorContainer,
      toastColorDefault: colors.secondaryContainer,
      tagColorLevel1: colors.tertiaryContainer,
      tagColorLevel2: colors.primary,
      tagColorLevel3: colors.secondaryContainer,
      tagColorLevel4: colors.errorContainer,
      switchColorOff: colors.outlineVariant,
      switchColorOn: appColors.primary,
      switchColorButton: colors.surface,
      sliderColorFilled: appColors.primary,
      sliderColorEmpty: colors.outlineVariant,
      sliderColorButton: colors.surface,
      tabColorSelected: colors.primaryContainer,
      tabColorUnselected: container,
      tabColorOption: colors.outlineVariant,
      clearColor: Colors.transparent,
    );
  }
}
