import 'dart:async';
import 'package:thoughtecho/utils/platform_io_stub.dart'
    if (dart.library.io) 'dart:io';

// Flutter核心库
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// 国际化
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

// 第三方包
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:logging/logging.dart' as logging;

// 项目内部
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/note_sync_service.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/services/backup_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/network_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/services/clipboard_service.dart';
import 'package:thoughtecho/services/media_cleanup_service.dart';
import 'package:thoughtecho/services/apk_download_service.dart';
import 'package:thoughtecho/services/version_check_service.dart';
import 'package:thoughtecho/services/insight_history_service.dart';
import 'package:thoughtecho/services/connectivity_service.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/services/data_directory_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';
import 'package:thoughtecho/utils/update_dialog_helper.dart';
import 'package:thoughtecho/services/smart_push_service.dart';
import 'package:thoughtecho/services/background_push_handler.dart';
import 'package:workmanager/workmanager.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'controllers/search_controller.dart';
import 'utils/app_logger.dart';
import 'utils/global_exception_handler.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/backup_restore_page.dart';
import 'widgets/quote_content_widget.dart';

part 'app/app_initialization.dart';
part 'app/app_emergency_pages.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

bool _isEmergencyMode = false;

final List<Map<String, dynamic>> _deferredErrors = [];
const int _maxDeferredErrors = 100;

void _addDeferredError(Map<String, dynamic> error) {
  if (_deferredErrors.length >= _maxDeferredErrors) {
    _deferredErrors.removeAt(0);
  }
  _deferredErrors.add(error);
}

Future<void> main() async {
  logging.hierarchicalLoggingEnabled = true;
  logging.Logger.root.level = logging.Level.INFO;

  BindingBase.debugZoneErrorsAreFatal =
      (!kIsWeb && Platform.isWindows) ? false : true;

  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      if (kIsWeb) {
        throw UnsupportedError(
            'ThoughtEcho does not support the Web platform.');
      }

      if (!kIsWeb) {
        try {
          if (Platform.isAndroid) {
            await AndroidAlarmManager.initialize();
          }
          await Workmanager().initialize(callbackDispatcher);
          logInfo('后台任务组件初始化成功', source: 'Main');
        } catch (e) {
          logError('后台任务组件初始化失败: $e', source: 'Main');
        }
      }

      AppLogger.initialize();

      GlobalExceptionHandler.initialize();

      PlatformDispatcher.instance.onError = (error, stack) {
        if (!kIsWeb && Platform.isWindows) {
          logError(
            '捕获到平台分发器错误: $error',
            error: error,
            source: 'PlatformDispatcher',
          );
        } else {
          logError(
            '捕获到平台分发器错误: $error',
            error: error,
            stackTrace: stack,
            source: 'PlatformDispatcher',
          );
          logError('堆栈: $stack', source: 'PlatformDispatcher');
        }
        _addDeferredError({
          'message': '平台分发器错误',
          'error': error,
          'stackTrace':
              (!kIsWeb && Platform.isWindows) ? null : stack,
          'source': 'PlatformDispatcher',
        });

        return true;
      };
      FlutterError.onError = (FlutterErrorDetails details) {
        if (kDebugMode) {
          FlutterError.dumpErrorToConsole(details);
        }

        if (!kIsWeb && Platform.isWindows) {
          logError(
            'Flutter异常: ${details.exceptionAsString()}',
            error: details.exception,
            source: 'FlutterError',
          );
          return;
        }

        final context = navigatorKey.currentContext;
        try {
          if (context != null) {
            final logService = Provider.of<UnifiedLogService>(
              context,
              listen: false,
            );
            logService.error(
              'Flutter异常: ${details.exceptionAsString()}',
              error: details.exception,
              stackTrace: details.stack,
              source: 'FlutterError',
            );
          } else {
            _addDeferredError({
              'message': 'Flutter异常: ${details.exceptionAsString()}',
              'error': details.exception,
              'stackTrace': details.stack,
              'source': 'FlutterError',
            });
          }
        } catch (e) {
          logError('记录Flutter异常时出错: $e', error: e, source: 'FlutterError');
        }
      };
      try {
        final mmkvService = MMKVService();
        late final SettingsService settingsService;
        late final PackageInfo packageInfo;
        await Future.wait([
          initializeDatabasePlatform(),
          mmkvService.init(),
          NetworkService.instance.init(),
          SettingsService.create().then((s) => settingsService = s),
          PackageInfo.fromPlatform().then((p) => packageInfo = p),
        ]);
        final String currentVersion = packageInfo.version;
        final String? lastVersion = settingsService.getAppVersion();
        final bool hasCompletedOnboarding =
            settingsService.hasCompletedOnboarding();

        bool showFullOnboarding = !hasCompletedOnboarding;
        bool showUpdateReady =
            hasCompletedOnboarding && (lastVersion != currentVersion);
        if (showUpdateReady) {
          await settingsService.setAppVersion(currentVersion);
        }
        if (showFullOnboarding) {
          // 由 OnboardingPage 负责设置 hasCompletedOnboarding 和 lastVersion
        }

        final databaseService = DatabaseService();
        final locationService = LocationService();
        final weatherService = WeatherService();
        final clipboardService = ClipboardService();
        final unifiedLogService = UnifiedLogService.instance;

        unifiedLogService
            .setPersistenceEnabled(settingsService.appSettings.developerMode);

        final aiAnalysisDbService = AIAnalysisDatabaseService();
        final connectivityService = ConnectivityService();
        final featureGuideService = FeatureGuideService(SafeMMKV());

        final smartPushService = SmartPushService(
          databaseService: databaseService,
          locationService: locationService,
          mmkvService: mmkvService,
        );

        final appTheme = AppTheme();

        await appTheme.initialize();

        final servicesInitialized = ValueNotifier<bool>(false);

        runApp(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => settingsService),
              ChangeNotifierProvider(create: (_) => databaseService),
              ChangeNotifierProvider(create: (_) => locationService),
              ChangeNotifierProvider(create: (_) => weatherService),
              ChangeNotifierProvider(create: (_) => clipboardService),
              ChangeNotifierProvider(create: (_) => unifiedLogService),
              ChangeNotifierProvider(create: (_) => appTheme),
              ChangeNotifierProvider(create: (_) => aiAnalysisDbService),
              ChangeNotifierProvider(create: (_) => connectivityService),
              ChangeNotifierProvider(create: (_) => featureGuideService),
              ChangeNotifierProvider(create: (_) => smartPushService),
              ChangeNotifierProvider(create: (_) => NoteSearchController()),
              ChangeNotifierProxyProvider<SettingsService,
                  InsightHistoryService>(
                create: (context) => InsightHistoryService(
                  settingsService: context.read<SettingsService>(),
                ),
                update: (context, settingsService, insightHistoryService) =>
                    insightHistoryService ??
                    InsightHistoryService(settingsService: settingsService),
              ),
              Provider.value(
                value: mmkvService,
              ),
              Provider<ValueNotifier<bool>>.value(
                value: servicesInitialized,
              ),
              ValueListenableProvider<bool>.value(value: servicesInitialized),
              ChangeNotifierProxyProvider<SettingsService, AIService>(
                create: (context) =>
                    AIService(settingsService: context.read<SettingsService>()),
                update: (context, settings, previous) =>
                    previous ?? AIService(settingsService: settings),
              ),
              ProxyProvider3<DatabaseService, SettingsService,
                  AIAnalysisDatabaseService, BackupService>(
                update: (
                  context,
                  dbService,
                  settingsService,
                  aiService,
                  previous,
                ) =>
                    BackupService(
                  databaseService: dbService,
                  settingsService: settingsService,
                  aiAnalysisDbService: aiService,
                ),
              ),
              ChangeNotifierProxyProvider4<BackupService, DatabaseService,
                  SettingsService, AIAnalysisDatabaseService, NoteSyncService>(
                create: (context) => NoteSyncService(
                  backupService: context.read<BackupService>(),
                  databaseService: context.read<DatabaseService>(),
                  settingsService: context.read<SettingsService>(),
                  aiAnalysisDbService:
                      context.read<AIAnalysisDatabaseService>(),
                ),
                update: (
                  context,
                  backupService,
                  databaseService,
                  settingsService,
                  aiAnalysisDbService,
                  previous,
                ) =>
                    previous ??
                    NoteSyncService(
                      backupService: backupService,
                      databaseService: databaseService,
                      settingsService: settingsService,
                      aiAnalysisDbService: aiAnalysisDbService,
                    ),
              ),
            ],
            child: Builder(
              builder: (context) {
                return MyApp(
                  navigatorKey: navigatorKey,
                  isEmergencyMode: _isEmergencyMode,
                  showUpdateReady: showUpdateReady,
                  showFullOnboarding: showFullOnboarding,
                );
              },
            ),
          ),
        );

        Future.microtask(() async {
          try {
            if (!kIsWeb && Platform.isAndroid) {
              logDebug('启动清理旧安装包逻辑...');
              await ApkDownloadService.cleanupApkFiles();
            }

            logDebug('开始预初始化位置服务...');
            locationService.currentLocaleCode = settingsService.localeCode;
            await locationService.init();
            logDebug('位置服务预初始化完成');

            logDebug('开始初始化智能推送服务...');
            await smartPushService.initialize();
            logDebug('智能推送服务初始化完成');

            try {
              await smartPushService.analytics.recordAppOpen();
              logDebug('SOTA: 已记录 App 打开时间');
            } catch (e) {
              logDebug('SOTA: 记录 App 打开时间失败: $e');
            }
          } catch (e) {
            logDebug('预初始化服务失败: $e');
          }
        });
        final initDelay = (!kIsWeb && Platform.isWindows)
            ? const Duration(milliseconds: 100)
            : TimeoutConstants.uiInitDelayDefault;
        Future.delayed(initDelay, () async {
          try {
            logInfo('UI已显示，正在后台初始化服务...', source: 'BackgroundInit');

            try {
              await connectivityService.init();
              logInfo('连接服务初始化完成', source: 'BackgroundInit');
            } catch (e) {
              logWarning('连接服务初始化失败: $e', source: 'BackgroundInit');
            }

            final timeoutDuration = (!kIsWeb && Platform.isWindows)
                ? TimeoutConstants.clipboardInitTimeoutWindows
                : TimeoutConstants.clipboardInitTimeoutDefault;

            if (!kIsWeb && Platform.isWindows) {
              Future.microtask(() async {
                try {
                  await clipboardService.init().timeout(
                        timeoutDuration,
                        onTimeout: () =>
                            logWarning('剪贴板服务初始化超时', source: 'BackgroundInit'),
                      );
                } catch (e) {
                  logWarning('剪贴板服务初始化失败: $e', source: 'BackgroundInit');
                }
              });
            } else {
              try {
                await clipboardService.init().timeout(
                      timeoutDuration,
                      onTimeout: () => logWarning(
                        '剪贴板服务初始化超时，将继续后续初始化',
                        source: 'BackgroundInit',
                      ),
                    );
              } catch (e) {
                logWarning('剪贴板服务初始化失败: $e', source: 'BackgroundInit');
              }
            }

            final hasMigrated = settingsService.isDatabaseMigrationComplete();
            final hasCompletedOnboarding =
                settingsService.hasCompletedOnboarding();
            logInfo(
              '数据库迁移状态: ${hasMigrated ? "已完成" : "未完成"}',
              source: 'BackgroundInit',
            );
            logInfo(
              '引导流程状态: ${hasCompletedOnboarding ? "已完成" : "未完成"}',
              source: 'BackgroundInit',
            );

            if (hasCompletedOnboarding && !hasMigrated) {
              logInfo('引导已完成但数据库迁移未完成，开始后台数据库迁移...', source: 'BackgroundInit');
              try {
                final dbTimeoutDuration = Platform.isWindows
                    ? TimeoutConstants.databaseInitTimeoutWindows
                    : TimeoutConstants.databaseInitTimeoutDefault;

                await databaseService.init().timeout(
                  dbTimeoutDuration,
                  onTimeout: () {
                    throw TimeoutException('数据库初始化超时');
                  },
                );
                try {
                  await aiAnalysisDbService.init();
                  logInfo('AI分析数据库初始化完成', source: 'BackgroundInit');
                } catch (aiDbError) {
                  logError(
                    'AI分析数据库初始化失败: $aiDbError',
                    error: aiDbError,
                    source: 'BackgroundInit',
                  );
                }

                await settingsService.setDatabaseMigrationComplete(true);

                logInfo('后台数据库迁移完成', source: 'BackgroundInit');
              } catch (e, stackTrace) {
                logError(
                  '后台数据库迁移失败: $e',
                  error: e,
                  stackTrace: stackTrace,
                  source: 'BackgroundInit',
                );

                try {
                  await databaseService.initializeNewDatabase();

                  try {
                    await aiAnalysisDbService.init();
                    logInfo('紧急恢复：AI分析数据库初始化完成', source: 'BackgroundInit');
                  } catch (aiDbError) {
                    logError(
                      '紧急恢复：AI分析数据库初始化失败: $aiDbError',
                      error: aiDbError,
                      source: 'BackgroundInit',
                    );
                  }

                  await settingsService.setDatabaseMigrationComplete(true);
                  logInfo('后台初始化新数据库成功', source: 'BackgroundInit');
                } catch (newDbError) {
                  logError(
                    '后台初始化新数据库也失败: $newDbError',
                    error: newDbError,
                    source: 'BackgroundInit',
                  );
                  _isEmergencyMode = true;
                }
                logError(
                  '后台数据库迁移失败',
                  error: e,
                  stackTrace: stackTrace,
                  source: 'background_init',
                );
              }
            } else if (!hasCompletedOnboarding) {
              logInfo('等待引导流程中的数据库迁移...', source: 'BackgroundInit');
            } else {
              logInfo('数据库已迁移，执行常规初始化', source: 'BackgroundInit');

              try {
                await aiAnalysisDbService.init();
                logInfo('AI分析数据库初始化完成', source: 'BackgroundInit');
              } catch (aiDbError) {
                logError(
                  'AI分析数据库初始化失败: $aiDbError',
                  error: aiDbError,
                  source: 'BackgroundInit',
                );
              }
              try {
                await _initializeDatabaseNormally(
                  databaseService,
                  unifiedLogService,
                );
              } catch (e, stackTrace) {
                logError(
                  '常规数据库初始化失败: $e',
                  error: e,
                  stackTrace: stackTrace,
                  source: 'BackgroundInit',
                );
                _isEmergencyMode = true;
              }
            }

            try {
              await MediaCleanupService.initialize();
              logInfo('媒体清理服务初始化完成', source: 'BackgroundInit');
            } catch (e) {
              logError('媒体清理服务初始化失败: $e', error: e, source: 'BackgroundInit');
            }

            servicesInitialized.value = true;
            logInfo('所有后台服务初始化完成', source: 'BackgroundInit');

            VersionCheckService.backgroundCheckForUpdates(
              onUpdateAvailable: (versionInfo) {
                logInfo(
                  '检测到新版本: ${versionInfo.latestVersion}',
                  source: 'VersionCheck',
                );
                Future.delayed(const Duration(seconds: 2), () {
                  try {
                    final context = navigatorKey.currentContext;
                    if (context != null && context.mounted) {
                      UpdateDialogHelper.showUpdateDialog(context, versionInfo);
                    }
                  } catch (e) {
                    logWarning('显示更新对话框失败: $e', source: 'VersionCheck');
                  }
                });
              },
              delay: const Duration(seconds: 5),
            );
          } catch (e, stackTrace) {
            logError(
              '后台服务初始化失败: $e',
              error: e,
              stackTrace: stackTrace,
              source: 'BackgroundInit',
            );

            try {
              _addDeferredError({
                'message': '后台服务初始化失败',
                'error': e,
                'stackTrace': stackTrace,
                'source': 'background_init',
              });
            } catch (e) {
              debugPrint('[main] deferred error recording failed: $e');
            }
          }
        });
      } catch (e, stackTrace) {
        logError(
          '应用初始化失败: $e',
          error: e,
          stackTrace: stackTrace,
          source: 'AppInit',
        );
        logError('堆栈跟踪: $stackTrace', source: 'AppInit');

        _isEmergencyMode = true;

        runApp(
          EmergencyApp(
            error:
                kDebugMode ? e.toString() : 'Application initialization failed',
            stackTrace: kDebugMode ? stackTrace.toString() : '',
          ),
        );
      }
    },
    (error, stackTrace) {
      logError(
        '未捕获的异常: $error',
        error: error,
        stackTrace: stackTrace,
        source: 'runZonedGuarded',
      );
      logError('堆栈跟踪: $stackTrace', source: 'runZonedGuarded');

      try {
        _addDeferredError({
          'message': '未捕获异常: $error',
          'error': error,
          'stackTrace': stackTrace,
          'source': 'runZonedGuarded',
        });
      } catch (e) {
        debugPrint('[main] deferred error recording failed: $e');
      }
    },
  );
}

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
