import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'services/database_service.dart';
import 'services/settings_service.dart';
import 'services/ai_service.dart';
import 'services/location_service.dart';
import 'services/weather_service.dart';
import 'services/mmkv_service.dart';
import 'services/clipboard_service.dart'; // 导入剪贴板服务
import 'services/log_service.dart'; // 导入日志服务
import 'pages/home_page.dart';
import 'theme/app_theme.dart';

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

      final path = join(dbPath, 'mind_trace.db');
      if (!await Directory(dirname(path)).exists()) {
        await Directory(dirname(path)).create(recursive: true);
      }

      await databaseFactory.setDatabasesPath(dbPath);
    } catch (e) {
      debugPrint('创建数据库目录失败: $e');
      rethrow;
    }
  } else {
    debugPrint('Web平台：使用内存数据库');
    // Web平台无需特殊初始化，SQLite会自动使用内存数据库
  }
}

// 全局导航key，用于日志服务在无context时获取context
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 日志写入递归保护
bool _isLogging = false;

// main函数开始
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 重定向debugPrint到日志服务，增加递归保护
  debugPrint = (String? message, {int? wrapWidth}) {
    if (_isLogging) {
      // 防止递归
      return;
    }
    _isLogging = true;
    try {
      debugPrintSynchronously(message);
      final context = navigatorKey.currentContext;
      if (context != null && message != null && message.isNotEmpty) {
        try {
          Provider.of<LogService>(context, listen: false).info(
            message,
            source: 'debugPrint',
          );
        } catch (_) {}
      }
    } finally {
      _isLogging = false;
    }
  };

  // 捕获Flutter框架异常并写入日志服务
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    final context = navigatorKey.currentContext;
    if (context != null) {
      try {
        Provider.of<LogService>(context, listen: false).error(
          'Flutter异常: \\${details.exceptionAsString()}',
          error: details.exception,
          stackTrace: details.stack,
          source: 'FlutterError',
        );
      } catch (_) {}
    }
  };

  await runZonedGuarded<Future<void>>(() async {
    try {
      // 初始化平台特定的数据库配置
      await initializeDatabasePlatform();

      // 初始化MMKV
      final mmkvService = MMKVService();
      await mmkvService.init();

      // 初始化设置服务（传入MMKV服务实例）
      final settingsService = await SettingsService.create();
      final databaseService = DatabaseService();
      final locationService = LocationService();
      final weatherService = WeatherService();
      final clipboardService = ClipboardService();
      final logService = LogService();
      // 初始化剪贴板服务
      await clipboardService.init();
      // 对所有平台统一初始化数据库
      await databaseService.init().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('数据库初始化超时');
        },
      );
      // 初始化默认一言分类
      await databaseService.initDefaultHitokotoCategories();
      // 初始化主题服务
      final appTheme = AppTheme();
      await appTheme.initialize();
      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => settingsService),
            ChangeNotifierProvider(create: (_) => databaseService),
            ChangeNotifierProvider(create: (_) => locationService),
            ChangeNotifierProvider(create: (_) => weatherService),
            ChangeNotifierProvider(create: (_) => clipboardService),
            ChangeNotifierProvider(create: (_) => logService),
            ChangeNotifierProvider(create: (_) => appTheme),
            ChangeNotifierProxyProvider<SettingsService, AIService>(
              create:
                  (context) => AIService(
                    settingsService: context.read<SettingsService>(),
                    locationService: context.read<LocationService>(),
                    weatherService: context.read<WeatherService>(),
                  ),
              update:
                  (context, settings, previous) =>
                      previous ??
                      AIService(
                        settingsService: settings,
                        locationService: context.read<LocationService>(),
                        weatherService: context.read<WeatherService>(),
                      ),
            ),
          ],
          child: MyApp(navigatorKey: navigatorKey),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('应用初始化失败: \\$e');
      debugPrint('堆栈跟踪: \\$stackTrace');
      final context = navigatorKey.currentContext;
      if (context != null) {
        try {
          Provider.of<LogService>(context, listen: false).error(
            '应用初始化失败: \\$e',
            error: e,
            stackTrace: stackTrace,
            source: 'main',
          );
        } catch (_) {}
      }
      rethrow;
    }
  }, (error, stackTrace) {
    debugPrint('未捕获的异常: \\$error');
    debugPrint('堆栈跟踪: \\$stackTrace');
    final context = navigatorKey.currentContext;
    if (context != null) {
      try {
        Provider.of<LogService>(context, listen: false).error(
          '未捕获异常: \\$error',
          error: error,
          stackTrace: stackTrace,
          source: 'runZonedGuarded',
        );
      } catch (_) {}
    }
  });
}

class MyApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  const MyApp({required this.navigatorKey, super.key});

  @override
  Widget build(BuildContext context) {
    final appTheme = Provider.of<AppTheme>(context);

    return MaterialApp(
      title: '心迹',
      theme: ThemeData.from(colorScheme: appTheme.lightColorScheme),
      darkTheme: ThemeData.from(colorScheme: appTheme.darkColorScheme),
      themeMode: appTheme.themeMode,
      navigatorKey: navigatorKey,
      home: const HomePage(),
    );
  }
}
