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
import 'services/clipboard_service.dart'; 
import 'services/log_service.dart';
import 'pages/home_page.dart';
import 'pages/backup_restore_page.dart'; // 导入备份恢复页面
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

// 添加一个全局标志，表示是否处于紧急模式（数据库损坏等情况）
bool _isEmergencyMode = false;

// 缓存早期捕获但无法立即记录的错误
final List<Map<String, dynamic>> _deferredErrors = [];

void main() async {
  // 确保Flutter绑定已初始化，这样我们可以使用平台通道和插件
  WidgetsFlutterBinding.ensureInitialized();
  
  // 全局记录未捕获的异步错误
  PlatformDispatcher.instance.onError = (error, stack) {
    // 使用原始 print 而不是通过日志系统重定向
    print('捕获到平台分发器错误: $error');
    print('堆栈: $stack');
    
    // 捕获到错误后再记录到日志系统
    _deferredErrors.add({
      'message': '平台分发器错误',
      'error': error,
      'stackTrace': stack,
      'source': 'PlatformDispatcher',
    });
    
    return true; // 返回true表示错误已处理
  };
  
  // 保存原始 print 函数
  final originalPrint = print;
  
  // 重新定义 debugPrint，创建一个安全版本避免递归
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (_isLogging) {
      // 防止递归 - 如果已经在日志过程中，直接使用原始 print
      originalPrint(message);
      return;
    }
    
    _isLogging = true;
    try {
      // 直接使用原始 print 输出，不触发递归
      originalPrint(message);
      
      // 只有当 LogService 实例可用时才记录日志
      if (message != null && message.isNotEmpty) {
        // 尝试获取上下文
        final context = navigatorKey.currentContext;
        if (context != null) {
          try {
            final logService = Provider.of<LogService>(context, listen: false);
            if (logService != null) {
              logService.info(message, source: 'debugPrint');
            }
          } catch (_) {
            // 忽略 Provider 错误
          }
        }
      }
    } finally {
      _isLogging = false;
    }
  };

  // 捕获Flutter框架异常并写入日志服务
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    
    // 尝试获取LogService实例
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
        // 无法通过context获取LogService时，先保存到全局缓存
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
  };

  // 在区域内捕获所有未处理的异常和错误
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
      
      try {
        // 对所有平台统一初始化数据库
        await databaseService.init().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('数据库初始化超时');
          },
        );
        // 初始化默认一言分类
        await databaseService.initDefaultHitokotoCategories();
      } catch (e, stackTrace) {
        // 数据库初始化失败，进入紧急模式
        debugPrint('数据库初始化失败，将启动紧急模式: $e');
        _isEmergencyMode = true;
        
        // 记录错误，但不重新抛出，让应用在紧急模式下继续
        logService.error(
          '数据库初始化失败，进入紧急模式',
          error: e,
          stackTrace: stackTrace,
          source: 'main',
        );
      }
      
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
          child: MyApp(
            navigatorKey: navigatorKey,
            isEmergencyMode: _isEmergencyMode,
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('应用初始化失败: \\$e');
      debugPrint('堆栈跟踪: \\$stackTrace');
      
      // 如果初始化失败，直接运行一个简单的错误应用
      _isEmergencyMode = true;
      runApp(EmergencyApp(error: e.toString(), stackTrace: stackTrace.toString()));
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
  final bool isEmergencyMode;
  
  const MyApp({
    super.key, 
    required this.navigatorKey, 
    this.isEmergencyMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final appTheme = context.watch<AppTheme>();
    
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '心迹',
      theme: appTheme.createLightThemeData(),
      darkTheme: appTheme.createDarkThemeData(),
      themeMode: appTheme.themeMode,
      home: isEmergencyMode 
        ? const EmergencyRecoveryPage() 
        : const HomePage(),
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
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.warning_amber_rounded, 
                size: 64, 
                color: Colors.red
              ),
              const SizedBox(height: 24),
              const Text(
                '数据库初始化失败',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
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
                onPressed: () {
                  Navigator.push(
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
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HomePage(),
                    ),
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
    required this.stackTrace
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '心迹 - 紧急恢复',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.light,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('紧急恢复模式'),
          backgroundColor: Colors.red,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.error_outline, 
                  size: 64, 
                  color: Colors.red
                ),
                const SizedBox(height: 16),
                const Text(
                  '应用启动失败',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
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
      ),
    );
  }

  void restartApp() {
    // 重新启动应用的逻辑
    // 在Flutter中不能真正地重启应用，所以这里只是重新运行main函数
    main();
  }
}

/// 全局方法，让LogService能够获取并处理缓存的早期错误
List<Map<String, dynamic>> getAndClearDeferredErrors() {
  final errors = List<Map<String, dynamic>>.from(_deferredErrors);
  _deferredErrors.clear();
  return errors;
}
