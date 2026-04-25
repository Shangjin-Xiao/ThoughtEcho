part of '../main.dart';

class MyApp extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final bool isEmergencyMode;
  final bool showUpdateReady;
  final bool showFullOnboarding;

  const MyApp({
    super.key,
    required this.navigatorKey,
    this.isEmergencyMode = false,
    this.showUpdateReady = false,
    this.showFullOnboarding = false,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      logDebug('应用进入后台，清理富文本缓存', source: 'AppLifecycle');
      Future.microtask(() {
        try {
          QuoteContent.resetCaches();
          logDebug('富文本缓存已清理', source: 'AppLifecycle');
        } catch (e) {
          logError('清理缓存失败: $e', error: e, source: 'AppLifecycle');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsService = Provider.of<SettingsService>(context);
    final appTheme = Provider.of<AppTheme>(context);
    final bool hasCompletedOnboarding =
        settingsService.hasCompletedOnboarding();

    final localeCode = settingsService.localeCode;
    final Locale? locale = localeCode != null ? Locale(localeCode) : null;

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        appTheme.updateDynamicColorScheme(lightDynamic, darkDynamic);

        return MaterialApp(
          navigatorKey: widget.navigatorKey,
          title: '心迹',
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(boldText: false),
              child: child ?? const SizedBox.shrink(),
            );
          },
          theme: appTheme.createLightThemeData(),
          darkTheme: appTheme.createDarkThemeData(),
          themeMode: appTheme.themeMode,
          debugShowCheckedModeBanner: false,
          locale: locale,
          home: widget.showUpdateReady
              ? const OnboardingPage(showUpdateReady: true)
              : !hasCompletedOnboarding
                  ? const OnboardingPage()
                  : widget.isEmergencyMode
                      ? const EmergencyRecoveryPage()
                      : HomePage(
                          initialPage:
                              settingsService.appSettings.defaultStartPage,
                        ),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        );
      },
    );
  }
}
