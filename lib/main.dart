import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:mind_trace/services/database_service.dart';
import 'package:mind_trace/services/settings_service.dart';
import 'package:mind_trace/services/ai_service.dart';
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

      if (!kIsWeb) {
        await databaseFactory.setDatabasesPath(dbPath);
      }
    } catch (e) {
      debugPrint('创建数据库目录失败: $e');
      rethrow;
    }
  } else {
    debugPrint('Web平台：跳过平台特定数据库初始化');
  }
}

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    
    await initializeDatabasePlatform();

    final settingsService = await SettingsService.create();
    final databaseService = DatabaseService();
    final appTheme = AppTheme();
    await appTheme.initialize();

    if (!kIsWeb) {
      await databaseService.init().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('数据库初始化超时');
        },
      );
    } else {
      await databaseService.init();
    }

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => settingsService),
          ChangeNotifierProvider(create: (_) => databaseService),
          ChangeNotifierProvider(create: (_) => appTheme),
          ChangeNotifierProxyProvider<SettingsService, AIService>(
            create: (context) => AIService(
              settingsService: context.read<SettingsService>(),
            ),
            update: (context, settings, previous) =>
                previous ?? AIService(settingsService: settings),
          ),
        ],
        child: const MyApp(),
      ),
    );
  } catch (e, stackTrace) {
    debugPrint('应用启动错误: $e');
    debugPrint('错误堆栈: $stackTrace');

    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '应用启动失败',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '错误信息:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(e.toString()),
                  const SizedBox(height: 16),
                  Text(
                    '堆栈跟踪:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(stackTrace.toString()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appTheme = context.watch<AppTheme>();
    
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // 更新动态颜色方案
        appTheme.updateDynamicColorScheme(lightDynamic);
        
        return MaterialApp(
          title: 'Mind Trace',
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark().copyWith(
            colorScheme: darkDynamic ?? ColorScheme.dark(
              primary: Colors.blue,
              secondary: Colors.blueAccent,
            ),
          ),
          themeMode: ThemeMode.system,
          home: const HomePage(),
        );
      },
    );
  }
}
