import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'services/database_service.dart';
import 'services/settings_service.dart';
import 'services/ai_service.dart';
import 'services/location_service.dart';
import 'services/weather_service.dart';
import 'services/mmkv_service.dart';
import 'services/clipboard_service.dart';
import 'services/log_service.dart';
import 'theme/app_theme.dart';
import 'app_providers.dart'; // 将创建
import 'app_widget.dart';   // 将创建

// 全局导航key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 日志写入递归保护
bool _isLogging = false;

// 全局紧急模式标志
bool _isEmergencyMode = false;

// 缓存早期捕获的错误
final List<Map<String, dynamic>> _deferredErrors = [];

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
      debugPrint('创建数据库目录失败: $e');
      // 在紧急模式下，可能需要更健壮的处理，但目前仅记录
      _isEmergencyMode = true; // 标记为紧急模式
      // rethrow; // 暂时不重新抛出，允许应用尝试以紧急模式启动
    }
  } else {
    debugPrint('Web平台：使用内存数据库');
    // Web平台无需特殊初始化
  }
}

void _logPlatformError(Object error, StackTrace stack) {
  debugPrint('捕获到平台分发器错误: $error');
  debugPrint('堆栈: $stack');
  _deferredErrors.add({
    'message': '平台分发器错误',
    'error': error,
    'stackTrace': stack,
    'source': 'PlatformDispatcher',
  });
}

void _logFlutterError(FlutterErrorDetails details) {
  FlutterError.dumpErrorToConsole(details);
  final context = navigatorKey.currentContext;
  try {
    if (context != null) {
      final logService = Provider.of<LogService>(context, listen: false);
      logService.error(
        'Flutter异常: ${details.exceptionAsString()}',
        error: details.exception,
        stackTrace: details.stack,
        source: 'FlutterError',
      );
    } else {
      _deferredErrors.add({
        'message': 'Flutter异常: ${details.exceptionAsString()}',
        'error': details.exception,
        'stackTrace': details.stack,
        'source': 'FlutterError',
      });
    }
  } catch (e) {
    debugPrint('记录Flutter异常时出错: $e');
  }
}

void _setupErrorHandling() {
  PlatformDispatcher.instance.onError = (error, stack) {
    _logPlatformError(error, stack);
    return true; // 表示错误已处理
  };

  FlutterError.onError = _logFlutterError;

  // 保存原始 print 函数
  const originalPrint = print;

  // 重新定义 debugPrint 以集成日志
  debugPrint = (String? message, {int? wrapWidth}) {
    if (_isLogging) {
      originalPrint(message);
      return;
    }
    _isLogging = true;
    try {
      originalPrint(message); // 总是输出到控制台

      // 尝试记录到 LogService
      final context = navigatorKey.currentContext;
      if (message != null && message.isNotEmpty && context != null) {
        try {
          // 使用 read 防止不必要的监听
          final logService = Provider.of<LogService>(context, listen: false);
          logService.info(message, source: 'debugPrint');
        } catch (_) {
          // 忽略 Provider 查找错误，可能服务尚未完全初始化
        }
      }
    } finally {
      _isLogging = false;
    }
  };
}

Future<void> _initializeCoreServices(SettingsService settingsService, MMKVService mmkvService) async {
  // 初始化轻量级且必须的服务
  await mmkvService.init();
  // SettingsService 创建时已初始化部分数据
}

Future<void> _initializeUIServices(AppTheme appTheme) async {
  // 初始化主题
  await appTheme.initialize();
}

void _initializeBackgroundServices(
  BuildContext context,
  ValueNotifier<bool> servicesInitialized,
) {
  // 使用 microtask 确保在首帧绘制后执行
  Future.microtask(() async {
    try {
      debugPrint('UI已显示，正在后台初始化服务...');
      final clipboardService = context.read<ClipboardService>();
      final logService = context.read<LogService>();
      final databaseService = context.read<DatabaseService>();
      final locationService = context.read<LocationService>();

      // 初始化 ClipboardService
      await clipboardService.init().timeout(
        const Duration(seconds: 3),
        onTimeout: () => debugPrint('剪贴板服务初始化超时'),
      );

      // 初始化 DatabaseService (可能耗时)
      // 注意：需要处理初始化失败的情况
      try {
        await databaseService.init();
      } catch (e, s) {
         debugPrint('数据库初始化失败: $e');
         _isEmergencyMode = true; // 进入紧急模式
         _deferredErrors.add({
            'message': '数据库初始化失败',
            'error': e,
            'stackTrace': s,
            'source': 'DatabaseServiceInit',
         });
         // 可以考虑通知用户或进行其他恢复操作
      }


      // 初始化 LocationService
      await locationService.init();

      // 所有后台服务初始化完成后，处理之前缓存的错误
      if (_deferredErrors.isNotEmpty) {
        debugPrint('处理启动期间缓存的 ${_deferredErrors.length} 个错误...');
        for (var errorInfo in _deferredErrors) {
          logService.error(
            errorInfo['message'],
            error: errorInfo['error'],
            stackTrace: errorInfo['stackTrace'],
            source: errorInfo['source'],
          );
        }
        _deferredErrors.clear();
      }

      // 更新服务初始化状态
      servicesInitialized.value = true;
      debugPrint('后台服务初始化完成。');

    } catch (e, s) {
      debugPrint('后台服务初始化过程中发生未捕获错误: $e\n$s');
       _deferredErrors.add({
            'message': '后台服务初始化未捕获错误',
            'error': e,
            'stackTrace': s,
            'source': 'BackgroundInit',
         });
       // 尝试记录
       final logService = context.read<LogService>();
       logService.error('后台服务初始化未捕获错误', error: e, stackTrace: s, source: 'BackgroundInit');
    }
  });
}

Future<void> bootstrapApp() async {
  // 使用 runZonedGuarded 捕获顶层异步错误
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 设置全局错误处理
    _setupErrorHandling();

    try {
      // 1. 初始化平台数据库设置
      await initializeDatabasePlatform();

      // 2. 创建核心服务实例 (不在此处 await 重量级初始化)
      final mmkvService = MMKVService();
      final settingsService = await SettingsService.create(); // Settings 需要先加载
      final databaseService = DatabaseService();
      final locationService = LocationService();
      final weatherService = WeatherService();
      final clipboardService = ClipboardService();
      final logService = LogService(); // LogService 会自行加载配置
      final appTheme = AppTheme();
      final servicesInitialized = ValueNotifier<bool>(false);

      // 3. 初始化核心服务 (MMKV, Settings)
      await _initializeCoreServices(settingsService, mmkvService);

      // 4. 初始化 UI 相关服务 (Theme)
      await _initializeUIServices(appTheme);

      // 5. 检查版本和引导状态
      final packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;
      final String? lastVersion = settingsService.getAppVersion();
      final bool hasCompletedOnboarding = settingsService.hasCompletedOnboarding();

      bool showFullOnboarding = !hasCompletedOnboarding;
      bool showUpdateReady = hasCompletedOnboarding && (lastVersion != currentVersion);

      if (showUpdateReady) {
        // 标记为升级，但不在此处处理数据迁移，应由专门逻辑处理
        debugPrint('检测到应用升级: $lastVersion -> $currentVersion');
        // await settingsService.setAppVersion(currentVersion); // 不应在这里自动更新版本号，应在升级流程完成后更新
      }

      // 6. 构建 Provider 列表
      final providers = createAppProviders(
        settingsService: settingsService,
        databaseService: databaseService,
        locationService: locationService,
        weatherService: weatherService,
        clipboardService: clipboardService,
        logService: logService,
        appTheme: appTheme,
        mmkvService: mmkvService,
        servicesInitialized: servicesInitialized,
      );

      // 7. 启动 App UI
      runApp(
        MultiProvider(
          providers: providers,
          // 使用 Builder 获取正确的 BuildContext 传递给后台初始化
          child: Builder(
            builder: (context) {
              // 8. 启动后台服务初始化
              _initializeBackgroundServices(context, servicesInitialized);

              // 返回根 Widget
              return AppWidget( // 使用新的根 Widget
                navigatorKey: navigatorKey,
                isEmergencyMode: _isEmergencyMode,
                showUpdateReady: showUpdateReady,
                showFullOnboarding: showFullOnboarding,
                currentVersion: currentVersion, // 传递当前版本号
              );
            }
          ),
        ),
      );

    } catch (error, stack) {
      // 捕获启动过程中的同步错误
      _logPlatformError('应用启动时发生严重错误: $error', stack);
      // 可以考虑显示一个紧急错误页面
      runApp(ErrorMaterialApp(error: error, stack: stack));
    }

  }, (error, stack) {
    // runZonedGuarded 的 onError 回调
    _logPlatformError('runZonedGuarded 捕获到未处理错误: $error', stack);
    // 理论上 PlatformDispatcher.instance.onError 应该已经捕获了
  });
}

// 启动失败时显示的简单错误页面
class ErrorMaterialApp extends StatelessWidget {
  final Object error;
  final StackTrace stack;

  const ErrorMaterialApp({super.key, required this.error, required this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '应用启动失败，请联系开发者。\n\n错误: $error\n\n堆栈: $stack',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      ),
    );
  }
} 