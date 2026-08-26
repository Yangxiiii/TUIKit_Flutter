import 'dart:io' show Platform;

import 'package:app_ui/app_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:tencent_chat_uikit/tencent_chat_uikit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_calls_uikit/tencent_calls_uikit.dart';
import 'package:tencent_cloud_chat_push/tencent_cloud_chat_push.dart';

import 'login_page.dart';
import 'splash_page.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

// HarmonyOS(纯血鸿蒙)判断。CallKit 主干未支持鸿蒙,所有 TUICallKit / CallStore
// 调用都要在此 guard 下跳过,否则会因为 native 端 method channel 不存在而挂起。
// Android/iOS 完全走原流程,不受影响。
bool get _isOhos => Platform.operatingSystem == 'ohos';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  TencentCloudChatPush().registerOnAppWakeUpEvent(
    onAppWakeUpEvent: () async {
      debugPrint('onAppWakeUpEvent onAppWakeUpEvent');
      await _setTestEnvironment();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final userID = prefs.getString(LoginScreen.DEV_LOGIN_USER_ID);
      final userSig = prefs.getString(LoginScreen.DEV_LOGIN_USER_SIG);
      if (!_isOhos) {
        TUICallKit.instance.login(SDKAPPID, userID ?? "", userSig ?? "");
      }
    },
  );

  runApp(
    EasyLocalization(
      supportedLocales: AppLocalization.supportedLocales,
      fallbackLocale: AppLocalization.fallbackLocale,
      path: AppLocalization.assetPath,
      saveLocale: true,
      child: const ProviderScope(child: MyApp()),
    ),
  );
}

Future<void> _setTestEnvironment() async {
  final prefs = await SharedPreferences.getInstance();
  final isTest = prefs.getBool("testEnvironment") ?? false;
  if (!isTest) return;
  try {
    Map<String, dynamic> param = {"request_set_env_param": true};
    await TencentImSDKPlugin.v2TIMManager.callExperimentalAPI(
      api: "internal_operation_set_env",
      param: param,
    );
    debugPrint("测试环境已启用");
  } catch (e) {
    debugPrint("设置测试环境失败: $e");
  }
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await AppBuilder.init(path: 'assets/appConfig.json');

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorObservers: _isOhos ? const [] : [TUICallKit.navigatorObserver],
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final localization = EasyLocalization.of(context);
    final themeMode = ref.watch(appThemeModeProvider);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => LoginInfoState()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'TUIKit Next Demo',
        navigatorObservers: _isOhos ? const [] : [TUICallKit.navigatorObserver],
        localizationsDelegates: [...?localization?.delegates],
        supportedLocales:
            localization?.supportedLocales ?? AppLocalization.supportedLocales,
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
        home: const SplashPage(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/splash': (context) => const SplashPage(),
        },
      ),
    );
  }
}
