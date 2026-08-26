import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart' hide AlertDialog;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import 'package:provider/provider.dart';
import 'package:uikit_next/login_page.dart';

import 'profile_page.dart';
import 'voice_message_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late LoginStore _loginStore;
  late SemanticColorScheme colorsTheme;
  StreamSubscription<LoginEvent>? _loginEventSubscription;

  // Translate language options (same as Android SettingsViewModel)
  static const List<Map<String, String>> _translateLanguageOptions = [
    {"code": "zh", "name": "简体中文"},
    {"code": "zh-TW", "name": "繁體中文"},
    {"code": "en", "name": "English"},
    {"code": "ja", "name": "日本語"},
    {"code": "ko", "name": "한국어"},
    {"code": "fr", "name": "Français"},
    {"code": "es", "name": "Español"},
    {"code": "it", "name": "Italiano"},
    {"code": "de", "name": "Deutsch"},
    {"code": "tr", "name": "Türkçe"},
    {"code": "ru", "name": "Русский"},
    {"code": "pt", "name": "Português"},
    {"code": "vi", "name": "Tiếng Việt"},
    {"code": "id", "name": "Bahasa Indonesia"},
    {"code": "th", "name": "ภาษาไทย"},
    {"code": "ms", "name": "Bahasa Melayu"},
    {"code": "hi", "name": "हिन्दी"},
  ];

  @override
  void initState() {
    super.initState();
    _loginStore = LoginStore.shared;
    _loginEventSubscription = _loginStore.loginEventStream.listen(
      _onLoginEvent,
    );
  }

  @override
  void dispose() {
    _loginEventSubscription?.cancel();
    super.dispose();
  }

  void _onLoginEvent(LoginEvent event) {
    if (!mounted) return;
    switch (event) {
      case LoginEvent.kickedOffline:
        Toast.warning(
          context,
          'Your account has been logged in on another device.',
        );
        break;
      case LoginEvent.loginExpired:
        Toast.warning(context, 'Login expired. Please log in again.');
        break;
    }
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    colorsTheme = SemanticColorScheme.of(context);
  }

  void showThemeSelector(
    BuildContext context,
    AppThemeController controller,
    AppThemeMode currentTheme,
  ) {
    final atomicLocale = AppLocalization.of(context);

    final List<Map<String, dynamic>> themes = [
      {"label": atomicLocale.themeLight, "value": AppThemeMode.light},
      {"label": atomicLocale.themeDark, "value": AppThemeMode.dark},
      {"label": atomicLocale.followSystem, "value": AppThemeMode.system},
    ];

    ActionSheet.show(
      context,
      actions: themes
          .map(
            (theme) => ActionSheetItem(
              title: theme["label"],
              isDestructive: currentTheme == theme["value"],
              onTap: () => controller.setMode(theme["value"]),
            ),
          )
          .toList(),
    );
  }

  void showFriendRequestSelector(
    BuildContext context,
    AppLocalizedText atomicLocale,
    AllowType? currentAllowType,
  ) {
    final List<Map<String, dynamic>> options = [
      {"label": atomicLocale.allowAny, "value": AllowType.allowAny},
      {"label": atomicLocale.needConfirm, "value": AllowType.needConfirm},
      {"label": atomicLocale.denyAny, "value": AllowType.denyAny},
    ];

    ActionSheet.show(
      context,
      actions: options
          .map(
            (option) => ActionSheetItem(
              title: option["label"],
              isDestructive: currentAllowType == option["value"],
              onTap: () => _updateFriendRequestSetting(option["value"]),
            ),
          )
          .toList(),
    );
  }

  Future<void> _updateFriendRequestSetting(AllowType allowType) async {
    final currentUser = _loginStore.loginState.loginUserInfo;

    if (currentUser != null) {
      final updatedProfile = UserProfile(
        userID: currentUser.userID,
        allowType: allowType,
      );

      await _loginStore.setSelfInfo(userInfo: updatedProfile);
    }
  }

  String _getTranslateLanguageDisplayName(String code) {
    final option = _translateLanguageOptions.firstWhere(
      (opt) => opt["code"] == code,
      orElse: () => {"code": code, "name": code},
    );
    return option["name"] ?? code;
  }

  void _showTranslateLanguageSelector(BuildContext context) {
    final currentLanguage =
        AppBuilder.getInstance().translateConfig.targetLanguage;

    ActionSheet.show(
      context,
      actions: _translateLanguageOptions
          .map(
            (option) => ActionSheetItem(
              title: option["name"] ?? "English",
              isDestructive: currentLanguage == option["code"],
              onTap: () async {
                await AppBuilder.getInstance().translateConfig
                    .setTargetLanguage(option["code"]!);
                setState(() {});
              },
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _loginStore,
      child: Scaffold(
        backgroundColor: colorsTheme.bgColorOperate,
        appBar: AppBar(
          backgroundColor: colorsTheme.bgColorOperate,
          automaticallyImplyLeading: false,
          title: Text(
            AppLocalization.of(context).settings,
            style: FontScheme.title3Medium.copyWith(
              color: colorsTheme.textColorPrimary,
            ),
          ),
          centerTitle: false,
        ),
        body: Consumer<LoginStore>(
          builder: (context, loginStore, child) {
            return _buildBody(context, loginStore);
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, LoginStore loginStore) {
    AppLocalizedText atomicLocale = AppLocalization.of(context);
    final container = riverpod.ProviderScope.containerOf(context);
    final currentTheme = container.read(appThemeModeProvider);
    final currentLocaleMode = container.read(appLocaleModeProvider);
    final loginInfoState = Provider.of<LoginInfoState>(context);
    final currentLocale = atomicLocale.locale;
    final currentUser = loginStore.loginState.loginUserInfo;

    String getThemeName(AppThemeMode themeType) {
      switch (themeType) {
        case AppThemeMode.light:
          return atomicLocale.themeLight;
        case AppThemeMode.dark:
          return atomicLocale.themeDark;
        case AppThemeMode.system:
          return atomicLocale.followSystem;
      }
    }

    String getLocaleName(Locale? locale) {
      switch (locale?.languageCode) {
        case 'zh':
          if (locale?.scriptCode == 'Hant') return atomicLocale.languageZhHant;
          return atomicLocale.languageZh;
        case 'en':
          return atomicLocale.languageEn;
        case 'ja':
          return atomicLocale.languageJa;
        case 'ko':
          return atomicLocale.languageKo;
        case 'ar':
          return atomicLocale.languageAr;
        default:
          return atomicLocale.followSystem;
      }
    }

    void showLanguageSelector() {
      final atomicLocale = AppLocalization.of(context);

      final List<Map<String, dynamic>> languages = [
        {"label": atomicLocale.followSystem, "value": AppLocaleMode.system},
        {"label": atomicLocale.languageZh, "value": AppLocaleMode.zhCn},
        {"label": atomicLocale.languageEn, "value": AppLocaleMode.en},
      ];

      ActionSheet.show(
        context,
        actions: languages
            .map(
              (lang) => ActionSheetItem(
                title: lang["label"],
                isDestructive: currentLocaleMode == lang["value"],
                onTap: () => container
                    .read(appLocaleModeProvider.notifier)
                    .setMode(context, lang["value"]),
              ),
            )
            .toList(),
      );
    }

    String getFriendRequestName(
      AppLocalizedText atomicLocale,
      AllowType? allowType,
    ) {
      switch (allowType) {
        case AllowType.allowAny:
          return atomicLocale.allowAny;
        case AllowType.needConfirm:
          return atomicLocale.needConfirm;
        case AllowType.denyAny:
          return atomicLocale.denyAny;
        default:
          return atomicLocale.needConfirm;
      }
    }

    return Column(
      children: [
        Container(
          color: colorsTheme.bgColorOperate,
          padding: const EdgeInsets.all(16),
          child: InkWell(
            splashColor: colorsTheme.clearColor,
            highlightColor: colorsTheme.clearColor,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfilePage()),
              );
            },
            child: Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundImage:
                      currentUser?.avatarURL != null &&
                          currentUser!.avatarURL!.isNotEmpty
                      ? NetworkImage(currentUser.avatarURL!)
                      : null,
                  child:
                      currentUser?.avatarURL == null ||
                          currentUser!.avatarURL!.isEmpty
                      ? const Icon(Icons.person, size: 36)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (currentUser?.nickname?.isEmpty ?? true)
                            ? currentUser?.userID ?? ''
                            : currentUser?.nickname ?? '',
                        style: FontScheme.body3Bold.copyWith(
                          color: colorsTheme.textColorPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "ID: ${currentUser?.userID ?? ''}",
                        style: FontScheme.caption1Regular.copyWith(
                          color: colorsTheme.textColorSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentUser?.selfSignature?.isEmpty ?? true
                            ? atomicLocale.noSignature
                            : currentUser!.selfSignature!,
                        style: FontScheme.caption1Regular.copyWith(
                          color: colorsTheme.textColorSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 24),
                SettingWidgets.buildSettingGroup(
                  context: context,
                  children: [
                    SettingWidgets.buildNavigationRow(
                      context: context,
                      title: atomicLocale.addRule,
                      value: getFriendRequestName(
                        atomicLocale,
                        currentUser?.allowType,
                      ),
                      onTap: () {
                        showFriendRequestSelector(
                          context,
                          atomicLocale,
                          currentUser?.allowType,
                        );
                      },
                    ),
                    SettingWidgets.buildDivider(context),
                    SettingWidgets.buildNavigationRow(
                      context: context,
                      title: atomicLocale.theme,
                      value: getThemeName(currentTheme),
                      onTap: () {
                        showThemeSelector(
                          context,
                          container.read(appThemeModeProvider.notifier),
                          currentTheme,
                        );
                      },
                    ),
                    SettingWidgets.buildDivider(context),
                    SettingWidgets.buildNavigationRow(
                      context: context,
                      title: atomicLocale.language,
                      value: getLocaleName(currentLocale),
                      onTap: showLanguageSelector,
                    ),
                    SettingWidgets.buildDivider(context),
                    SettingWidgets.buildSettingRow(
                      context: context,
                      title: atomicLocale.messageReadReceipt,
                      value: AppBuilder.getInstance()
                          .messageListConfig
                          .enableReadReceipt,
                      onChanged: (value) async {
                        await AppBuilder.getInstance().messageListConfig
                            .setEnableReadReceipt(value);
                        setState(() {});
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        AppBuilder.getInstance()
                                .messageListConfig
                                .enableReadReceipt
                            ? atomicLocale.messageReadReceiptEnabledDesc
                            : atomicLocale.messageReadReceiptDisabledDesc,
                        style: FontScheme.caption2Regular.copyWith(
                          color: colorsTheme.textColorSecondary,
                        ),
                      ),
                    ),
                    SettingWidgets.buildDivider(context),
                    SettingWidgets.buildNavigationRow(
                      context: context,
                      title: atomicLocale.translateTargetLanguage,
                      value: _getTranslateLanguageDisplayName(
                        AppBuilder.getInstance().translateConfig.targetLanguage,
                      ),
                      onTap: () => _showTranslateLanguageSelector(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SettingWidgets.buildSettingGroup(
                  context: context,
                  children: [
                    SettingWidgets.buildNavigationRow(
                      context: context,
                      title: AppLocalization.of(context).voiceMessageSettings,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const VoiceMessageSettingsPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () async {
                final result = await loginInfoState.logout();
                if (result && context.mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colorsTheme.bgColorTopBar,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                atomicLocale.logout,
                style: FontScheme.caption1Medium.copyWith(
                  color: colorsTheme.textColorError,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
