import 'package:app_ui/app_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:tencent_calls_uikit/tencent_calls_uikit.dart';
import 'package:tencent_live_uikit/tencent_live_uikit.dart';
import 'package:tencent_conference_uikit/tencent_conference_uikit.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
// import 'package:te_beauty_kit/te_beauty_kit.dart';

import 'src/login/index.dart';
import 'src/utils/index.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  runApp(
    EasyLocalization(
      supportedLocales: AppLocalization.supportedLocales,
      fallbackLocale: AppLocalization.fallbackLocale,
      path: AppLocalization.assetPath,
      saveLocale: true,
      child: const ProviderScope(child: MyApp()),
    ),
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await AppBuilder.init(path: 'assets/appConfig.json');
  }

  @override
  Widget build(BuildContext context) {
    final localization = EasyLocalization.of(context);
    final themeMode = ref.watch(appThemeModeProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorObservers: [
        AppNavigatorObserver.instance,
        TUILiveKitNavigatorObserver.instance,
        RoomNavigatorObserver.instance,
        TUICallKit.navigatorObserver,
      ],
      localizationsDelegates: [
        ...?localization?.delegates,
        ...AppLocalizations.localizationsDelegates,
        ...LiveKitLocalizations.localizationsDelegates,
        ...BarrageLocalizations.localizationsDelegates,
        ...GiftLocalizations.localizationsDelegates,
        ...RoomLocalizations.localizationsDelegates,
        // ...TEBeautyKitLocalizations.localizationsDelegates,
      ],
      supportedLocales: AppLocalization.supportedLocales,
      locale: localization?.locale,
      theme: AppThemeFactory.create(
        const AppNormalColorScheme(),
        Brightness.light,
      ),
      darkTheme: AppThemeFactory.create(
        const AppDarkColorScheme(),
        Brightness.dark,
      ),
      themeMode: switch (themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      builder: (context, child) => Scaffold(
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          onTap: () {
            hideKeyboard(context);
          },
          child: child,
        ),
      ),
      home: const LoginWidget(),
    );
  }

  void hideKeyboard(BuildContext context) {
    FocusScopeNode currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }
}
