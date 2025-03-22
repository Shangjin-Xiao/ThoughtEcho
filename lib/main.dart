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
import 'package:mind_trace/pages/home_page.dart';
import 'package:mind_trace/theme/app_theme.dart';

Future<void> initializeDatabasePlatform() async {
  if (!kIsWeb) {
    // 初始化 SQLite
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    
    // 确保数据库目录存在
    final dbPath = await getDatabasesPath();
    await Directory(dbPath).create(recursive: true);
    
    // 设置数据库路径
    final path = join(dbPath, 'mind_trace.db');
    if (!await Directory(dirname(path)).exists()) {
      await Directory(dirname(path)).create(recursive: true);
    }
  }
}

void main() async {
  try {
    // 确保Flutter绑定初始化
    WidgetsFlutterBinding.ensureInitialized();

    // 初始化数据库平台
    await initializeDatabasePlatform();

    // 初始化服务
    final settingsService = await SettingsService.create();
    final databaseService = DatabaseService();
    
    // 初始化数据库
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

    // 运行应用
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => settingsService),
          ChangeNotifierProvider(create: (_) => databaseService),
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
    
    // 显示错误界面
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '应用启动失败',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '错误信息: ${e.toString()}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      main(); // 重试启动应用
                    },
                    child: const Text('重新启动'),
                  ),
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
    return MaterialApp(
      title: '心迹',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: FutureBuilder(
        // 给予一个短暂的延迟，确保所有服务都已经正确初始化
        future: Future.delayed(const Duration(milliseconds: 100)),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          return const HomePage();
        },
      ),
    );
  }
}
