import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:mind_trace/services/database_service.dart';
import 'package:mind_trace/services/settings_service.dart';
import 'package:mind_trace/services/ai_service.dart';
import 'package:mind_trace/services/location_service.dart';
import 'package:mind_trace/services/weather_service.dart';
import 'package:mind_trace/services/mmkv_service.dart';
import 'package:mind_trace/services/clipboard_service.dart'; // 导入剪贴板服务
import 'package:mind_trace/services/log_service.dart'; // 导入日志服务
import 'package:mind_trace/pages/home_page.dart';
import 'package:mind_trace/theme/app_theme.dart';

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

// 添加错误处理函数，用于报告启动过程中的异常
void _reportStartupError(FlutterErrorDetails details) {
  FlutterError.dumpErrorToConsole(details);
  // 可在此处添加崩溃报告逻辑
}

// main函数开始
void main() async {
  // 包装主应用入口点，捕获初始化过程中的错误
  runZonedGuarded<Future<void>>(() async {
    FlutterError.onError = _reportStartupError;

    try {
      // 确保Flutter绑定初始化
      WidgetsFlutterBinding.ensureInitialized();
      
      // 初始化平台特定的数据库配置
      await initializeDatabasePlatform();

      // 初始化MMKV
      final mmkvService = MMKVService();
      await mmkvService.init(); // 使用正确的init()方法而不是initialize()

      // 初始化设置服务（传入MMKV服务实例）
      final settingsService = await SettingsService.create(); // 使用工厂方法创建SettingsService
      
      final databaseService = DatabaseService();
      final locationService = LocationService();
      final weatherService = WeatherService();
      final clipboardService = ClipboardService(); // 创建剪贴板服务实例
      final logService = LogService(); // 创建日志服务实例
      
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
            ChangeNotifierProvider(create: (_) => clipboardService), // 添加剪贴板服务Provider
            ChangeNotifierProvider(create: (_) => logService), // 添加日志服务Provider
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
          child: const MyApp(),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('应用初始化失败: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      // 可以在这里显示错误启动画面或重试逻辑
      rethrow;
    }
  }, (error, stackTrace) {
    debugPrint('未捕获的异常: $error');
    debugPrint('堆栈跟踪: $stackTrace');
    // 可在此添加崩溃报告逻辑
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appTheme = Provider.of<AppTheme>(context);

    return MaterialApp(
      title: '心迹',
      theme: ThemeData.from(colorScheme: appTheme.lightColorScheme),
      darkTheme: ThemeData.from(colorScheme: appTheme.darkColorScheme),
      themeMode: appTheme.themeMode,
      home: const HomePage(),
    );
  }
}
