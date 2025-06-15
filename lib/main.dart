import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:dynamic_color/dynamic_color.dart'; // 添加 dynamic_color 导入
import 'services/database_service.dart';
import 'services/settings_service.dart';
import 'services/ai_service.dart';
import 'services/location_service.dart';
import 'services/weather_service.dart';
import 'services/mmkv_service.dart';
import 'services/clipboard_service.dart';
import 'services/unified_log_service.dart';
import 'services/ai_analysis_database_service.dart';
import 'services/network_service.dart';
import 'utils/app_logger.dart';
import 'pages/home_page.dart';
import 'pages/backup_restore_page.dart'; // 导入备份恢复页面
import 'theme/app_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'pages/onboarding_page.dart'; // 添加引导页面导入
import 'package:flutter_quill/flutter_quill.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> initializeDatabasePlatform() async {
  if (!kIsWeb) {
    if (Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = join(appDir.path, 'databases');

      await Directory(dbPath).create(recursive: true);

      final path = join(dbPath, 'thoughtecho.db');
      if (!await Directory(dirname(path)).exists()) {
        await Directory(dirname(path)).create(recursive: true);
      }

      await databaseFactory.setDatabasesPath(dbPath);
    } catch (e) {
      logError('创建数据库目录失败: $e', error: e, source: 'DatabaseInit');
      rethrow;
    }
  } else {
    logInfo('Web平台：使用内存数据库', source: 'DatabaseInit');
    // Web平台无需特殊初始化，SQLite会自动使用内存数据库
  }
}

// 全局导航key，用于日志服务在无context时获取context
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 添加一个全局标志，表示是否处于紧急模式（数据库损坏等情况）
bool _isEmergencyMode = false;

// 缓存早期捕获但无法立即记录的错误
final List<Map<String, dynamic>> _deferredErrors = [];

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      // 确保Flutter绑定已初始化，这样我们可以使用平台通道和插件
      WidgetsFlutterBinding.ensureInitialized();

      // 初始化日志系统
      AppLogger.initialize();

      // 全局记录未捕获的异步错误
      PlatformDispatcher.instance.onError = (error, stack) {
        // 使用新的日志系统而不是logDebug
        logError(
          '捕获到平台分发器错误: $error',
          error: error,
          stackTrace: stack,
          source: 'PlatformDispatcher',
        );
        logError('堆栈: $stack', source: 'PlatformDispatcher');

        // 捕获到错误后再记录到日志系统
        _deferredErrors.add({
          'message': '平台分发器错误',
          'error': error,
          'stackTrace': stack,
          'source': 'PlatformDispatcher',
        });

        return true; // 返回true表示错误已处理
      };

      // 初始化日志系统
      AppLogger.initialize();

      // 捕获Flutter框架异常并写入日志服务
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.dumpErrorToConsole(details);

        // 尝试获取LogService实例
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
            // 无法通过context获取LogService时，先保存到全局缓存
            _deferredErrors.add({
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
        // 先初始化必要的平台特定的数据库配置
        await initializeDatabasePlatform();

        // 初始化轻量级且必须的服务
        final mmkvService = MMKVService();
        await mmkvService.init();

        // 初始化网络服务
        await NetworkService.instance.init();

        // 初始化设置服务
        final settingsService = await SettingsService.create();
        // 自动获取应用版本号
        final packageInfo = await PackageInfo.fromPlatform();
        final String currentVersion = packageInfo.version;
        final String? lastVersion = settingsService.getAppVersion();
        final bool hasCompletedOnboarding =
            settingsService.hasCompletedOnboarding();

        // 判断是否需要完整引导或升级引导
        bool showFullOnboarding = !hasCompletedOnboarding;
        bool showUpdateReady =
            hasCompletedOnboarding && (lastVersion != currentVersion);
        if (showUpdateReady) {
          // 只显示引导最后一页，自动迁移数据，升级完成后写入 lastVersion
          await settingsService.setAppVersion(currentVersion);
        }
        if (showFullOnboarding) {
          // 完整引导完成后写入 lastVersion
          // 由 OnboardingPage 负责设置 hasCompletedOnboarding 和 lastVersion
        }

        // 创建服务实例但暂不初始化重量级服务
        final databaseService = DatabaseService();
        final locationService = LocationService();
        final weatherService = WeatherService();
        final clipboardService = ClipboardService(); // 创建统一日志服务
        final unifiedLogService = UnifiedLogService.instance;
        // 不再这里强制设置级别，让UnifiedLogService从用户配置中加载

        final appTheme = AppTheme();

        // 初始化主题 - 这是UI显示必须的
        await appTheme.initialize();

        // 使用ValueNotifier跟踪服务初始化状态
        final servicesInitialized = ValueNotifier<bool>(false);

        // 启动应用UI
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
              ChangeNotifierProvider(
                create: (_) => AIAnalysisDatabaseService(),
              ),
              Provider.value(
                value: mmkvService,
              ), // 使用 Provider.value 提供 MMKVService
              // 提供初始化状态
              ValueListenableProvider<bool>.value(value: servicesInitialized),
              ChangeNotifierProxyProvider<SettingsService, AIService>(
                create:
                    (context) => AIService(
                      settingsService: context.read<SettingsService>(),
                    ),
                update:
                    (context, settings, previous) =>
                        previous ?? AIService(settingsService: settings),
              ),
            ],
            child: MyApp(
              navigatorKey: navigatorKey,
              isEmergencyMode: _isEmergencyMode,
              showUpdateReady: showUpdateReady,
              showFullOnboarding: showFullOnboarding,
            ),
          ),
        );

        // 首屏UI显示后，异步初始化其他服务
        // 使用microtask确保在UI渲染后执行
        Future.microtask(() async {
          try {
            logInfo('UI已显示，正在后台初始化服务...', source: 'BackgroundInit');

            // 初始化clipboardService
            await clipboardService.init().timeout(
              const Duration(seconds: 3),
              onTimeout:
                  () => logWarning(
                    '剪贴板服务初始化超时，将继续后续初始化',
                    source: 'BackgroundInit',
                  ),
            );

            // 检查设置服务中的数据库迁移状态
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

            // 如果已经完成了引导流程，但数据库迁移未完成，则直接在后台初始化数据库
            if (hasCompletedOnboarding && !hasMigrated) {
              logInfo('引导已完成但数据库迁移未完成，开始后台数据库迁移...', source: 'BackgroundInit');
              try {
                // 初始化数据库，这通常是最耗时的操作
                await databaseService.init().timeout(
                  const Duration(seconds: 10),
                  onTimeout: () {
                    throw TimeoutException('数据库初始化超时');
                  },
                );

                // 初始化默认一言分类
                await databaseService.initDefaultHitokotoCategories();

                // 标记数据库迁移已完成
                await settingsService.setDatabaseMigrationComplete(true);

                logInfo('后台数据库迁移完成', source: 'BackgroundInit');
              } catch (e, stackTrace) {
                logError(
                  '后台数据库迁移失败: $e',
                  error: e,
                  stackTrace: stackTrace,
                  source: 'BackgroundInit',
                );

                // 在紧急情况下尝试初始化新数据库
                try {
                  await databaseService.initializeNewDatabase();
                  await settingsService.setDatabaseMigrationComplete(true);
                  logInfo('后台初始化新数据库成功', source: 'BackgroundInit');
                } catch (newDbError) {
                  logError(
                    '后台初始化新数据库也失败: $newDbError',
                    error: newDbError,
                    source: 'BackgroundInit',
                  );
                  _isEmergencyMode = true;
                } // 记录错误但继续执行
                logError(
                  '后台数据库迁移失败',
                  error: e,
                  stackTrace: stackTrace,
                  source: 'background_init',
                );
              }
            } else if (!hasCompletedOnboarding) {
              // 如果尚未完成引导流程，数据库迁移将在引导流程中处理
              logInfo('等待引导流程中的数据库迁移...', source: 'BackgroundInit');
            } else {
              // 引导已完成且数据库已迁移，正常初始化
              logInfo('数据库已迁移，执行常规初始化', source: 'BackgroundInit');
              await _initializeDatabaseNormally(
                databaseService,
                unifiedLogService,
              );
            }

            // 初始化完成，更新状态
            servicesInitialized.value = true;
            logInfo('所有后台服务初始化完成', source: 'BackgroundInit');
          } catch (e, stackTrace) {
            logError(
              '后台服务初始化失败: $e',
              error: e,
              stackTrace: stackTrace,
              source: 'BackgroundInit',
            );

            // 记录错误，不使用 BuildContext
            try {
              // 将错误信息添加到延迟处理队列
              _deferredErrors.add({
                'message': '后台服务初始化失败',
                'error': e,
                'stackTrace': stackTrace,
                'source': 'background_init',
              });
            } catch (_) {}
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

        // 如果初始化失败，直接运行一个简单的错误应用
        _isEmergencyMode = true;
        runApp(
          EmergencyApp(error: e.toString(), stackTrace: stackTrace.toString()),
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

      // 使用非 context 相关访问方式记录错误，避免 use_build_context_synchronously 警告
      try {
        // 将错误信息添加到延迟处理队列
        _deferredErrors.add({
          'message': '未捕获异常: $error',
          'error': error,
          'stackTrace': stackTrace,
          'source': 'runZonedGuarded',
        });
      } catch (_) {}
    },
  );
}

class MyApp extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // 获取设置服务实例
    final settingsService = Provider.of<SettingsService>(context);
    final appTheme = Provider.of<AppTheme>(context);
    // 检查是否需要显示引导页面
    final bool hasCompletedOnboarding =
        settingsService.hasCompletedOnboarding();

    // 使用 DynamicColorBuilder 以支持动态取色功能
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // 更新主题中的动态颜色方案
        // 直接更新主题中的动态颜色方案，确保MaterialApp构建时能获取到
        appTheme.updateDynamicColorScheme(lightDynamic, darkDynamic);

        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'ThoughtEcho',
          theme: appTheme.createLightThemeData(),
          darkTheme: appTheme.createDarkThemeData(),
          themeMode: appTheme.themeMode,
          debugShowCheckedModeBanner: false,
          home:
              showUpdateReady
                  ? const OnboardingPage(showUpdateReady: true)
                  : !hasCompletedOnboarding
                  ? const OnboardingPage() // 如果未完成引导，显示引导页面
                  : isEmergencyMode
                  ? const EmergencyRecoveryPage()
                  : HomePage(
                    initialPage: settingsService.appSettings.defaultStartPage,
                  ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        );
      },
    );
  }
}

/// 紧急恢复页面，在数据库初始化失败时显示
class EmergencyRecoveryPage extends StatelessWidget {
  const EmergencyRecoveryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('心迹 - 数据恢复'),
        backgroundColor: Colors.red,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          // 添加SingleChildScrollView使内容可滚动
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min, // 设置为min以适应内容
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 24),
                const Text(
                  '数据库初始化失败',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  '应用无法正常启动。可能是数据库损坏或无法访问。\n\n'
                  '您可以尝试备份现有数据以防数据丢失，或尝试重新启动应用。',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () async {
                    // 标记为 async
                    // 导航前检查 mounted 状态
                    if (!context.mounted) return;
                    await Navigator.push(
                      // 使用 await
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BackupRestorePage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.backup),
                  label: const Text('备份和恢复数据'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    // 标记为 async
                    // 导航前检查 mounted 状态
                    if (!context.mounted) return;
                    await Navigator.pushReplacement(
                      // 使用 await
                      context,
                      MaterialPageRoute(builder: (context) => const HomePage()),
                    );
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('尝试重新启动应用'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  '提示: 如果问题持续存在，可能需要重新安装应用。请确保在此之前备份您的数据。',
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 极端情况下的应急应用，当初始化完全失败时启动
class EmergencyApp extends StatelessWidget {
  final String error;
  final String stackTrace;

  const EmergencyApp({
    super.key,
    required this.error,
    required this.stackTrace,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '心迹 - 紧急恢复',
      navigatorKey: navigatorKey, // 使用全局导航键
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.light,
        ),
      ),
      home: EmergencyHomePage(error: error, stackTrace: stackTrace),
      routes: {'/backup_restore': (context) => const BackupRestorePage()},
    );
  }
}

/// 紧急模式下的主页面
class EmergencyHomePage extends StatelessWidget {
  final String error;
  final String stackTrace;

  const EmergencyHomePage({
    super.key,
    required this.error,
    required this.stackTrace,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('紧急恢复模式'), backgroundColor: Colors.red),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                '应用启动失败',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                '心迹应用启动过程中发生严重错误。这可能是由于数据损坏或者存储权限问题导致。',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '错误信息:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(error),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                title: const Text('技术详情'),
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.grey.shade100,
                      child: SelectableText(
                        stackTrace,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EmergencyBackupPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.backup),
                label: const Text('备份和恢复数据'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  // 尝试重新启动应用
                  restartApp();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('尝试重新启动应用'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  // 退出应用
                  exit(0);
                },
                icon: const Icon(Icons.exit_to_app),
                label: const Text('退出应用'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  foregroundColor: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '如果问题持续存在，请尝试重新安装应用，或联系开发者获取支持。',
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void restartApp() {
    // 重新启动应用的逻辑
    // 在Flutter中不能真正地重启应用，所以这里只是重新运行main函数
    main();
  }
}

/// 极端情况下的备份恢复页面，即使在数据库完全损坏的情况下也能工作
class EmergencyBackupPage extends StatefulWidget {
  const EmergencyBackupPage({super.key});

  @override
  State<EmergencyBackupPage> createState() => _EmergencyBackupPageState();
}

class _EmergencyBackupPageState extends State<EmergencyBackupPage> {
  bool _isLoading = false;
  String? _statusMessage;
  bool _hasError = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('紧急数据恢复'),
        backgroundColor: Colors.orange,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.data_saver_on, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                '数据紧急恢复工具',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                '由于应用发生了严重错误，您可以尝试：\n\n'
                '1. 导出数据库文件 - 导出原始数据库文件供专业人员恢复\n'
                '2. 尝试查看备份恢复页 - 注意：由于数据库可能损坏，此功能可能无法正常工作',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 32),
              if (_isLoading)
                Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('正在处理...${_statusMessage ?? ""}'),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: _exportDatabaseFile,
                      icon: const Icon(Icons.folder),
                      label: const Text('导出数据库文件'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        try {
                          Navigator.of(context).pushNamed('/backup_restore');
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('无法打开备份还原页面：$e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.backup),
                      label: const Text('尝试打开标准备份还原页面'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ),
              if (_statusMessage != null && !_isLoading)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        _hasError ? Colors.red.shade100 : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      color:
                          _hasError
                              ? Colors.red.shade900
                              : Colors.green.shade900,
                    ),
                  ),
                ),
              const Spacer(),
              const Text(
                '提示: 导出的数据库文件可以发送给开发人员进行专业恢复。',
                style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportDatabaseFile() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '正在定位数据库文件...';
      _hasError = false;
    });

    try {
      // 获取数据库文件路径
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = join(appDir.path, 'databases');
      final dbFile = File(join(dbPath, 'thoughtecho.db'));
      final oldDbFile = File(join(dbPath, 'mind_trace.db'));

      // 确认文件存在
      if (!dbFile.existsSync() && !oldDbFile.existsSync()) {
        setState(() {
          _isLoading = false;
          _statusMessage = '未找到数据库文件';
          _hasError = true;
        });
        return;
      }

      // 使用存在的文件
      final sourceFile = dbFile.existsSync() ? dbFile : oldDbFile;

      setState(() {
        _statusMessage = '正在准备导出...';
      });

      // 创建一个导出目录
      final downloadsDir = Directory(join(appDir.path, 'Downloads'));
      if (!downloadsDir.existsSync()) {
        await downloadsDir.create(recursive: true);
      }

      // 创建导出文件名
      final now = DateTime.now();
      final timestamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final exportFileName = 'thoughtecho_emergency_$timestamp.db';
      final exportFile = File(join(downloadsDir.path, exportFileName));

      // 复制文件
      setState(() {
        _statusMessage = '正在复制文件...';
      });

      await sourceFile.copy(exportFile.path);

      setState(() {
        _isLoading = false;
        _statusMessage = '数据库文件已导出到: ${exportFile.path}';
        _hasError = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '导出失败: $e';
        _hasError = true;
      });
    }
  }
}

/// 全局方法，让LogService能够获取并处理缓存的早期错误
List<Map<String, dynamic>> getAndClearDeferredErrors() {
  final errors = List<Map<String, dynamic>>.from(_deferredErrors);
  _deferredErrors.clear();
  return errors;
}

// 提取常规数据库初始化为独立函数
Future<void> _initializeDatabaseNormally(
  DatabaseService databaseService,
  UnifiedLogService logService,
) async {
  try {
    await databaseService.init().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        throw TimeoutException('数据库初始化超时');
      },
    );

    // 确保初始化默认一言分类，即使数据库已初始化
    await databaseService.initDefaultHitokotoCategories();
    logDebug('数据库服务及默认标签初始化完成');
  } catch (e, stackTrace) {
    logDebug('数据库初始化失败: $e');

    // 尝试恢复：即使数据库初始化失败，也尝试创建默认标签
    try {
      await databaseService.initDefaultHitokotoCategories();
      logDebug('尝试恢复：虽然数据库初始化可能有问题，但已尝试创建默认标签');
    } catch (tagError) {
      logDebug('创建默认标签也失败: $tagError');
      _isEmergencyMode = true;
    }

    // 如果还是失败，进入紧急模式
    if (!databaseService.isInitialized) {
      _isEmergencyMode = true;
    }

    // 记录错误但继续执行其他服务初始化
    logService.error(
      '数据库初始化失败，但应用将尝试继续运行',
      error: e,
      stackTrace: stackTrace,
      source: 'background_init',
    );
  }
}
