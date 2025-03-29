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
import 'package:mind_trace/pages/home_page.dart';
import 'package:mind_trace/utils/color_utils.dart'; // 引入 color_utils.dart

Future<void> initializeDatabasePlatform() async {
  if (!kIsWeb) {
    // 非 Web 平台
    if (Platform.isWindows) {
      // 初始化 SQLite FFI（仅 Windows 平台需要）
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    // Android 平台使用默认的 sqflite 实现，无需特殊处理

    try {
      // 获取应用的可写目录
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = join(appDir.path, 'databases');

      // 确保数据库目录存在
      await Directory(dbPath).create(recursive: true);

      // 设置数据库路径
      final path = join(dbPath, 'mind_trace.db');
      if (!await Directory(dirname(path)).exists()) {
        await Directory(dirname(path)).create(recursive: true);
      }

      // 设置 sqflite 的数据库目录（仅在非 Web 平台下设置）
      if (!kIsWeb) { // 仅在非 Web 平台下设置数据库路径
        await databaseFactory.setDatabasesPath(dbPath);
      }
    } catch (e) {
      debugPrint('创建数据库目录失败: $e');
      rethrow;
    }
  } else {
    // Web 平台：无需初始化特定平台数据库
    debugPrint('Web平台：跳过平台特定数据库初始化');
  }
}

void main() async {
  try {
    // 确保 Flutter 绑定初始化
    WidgetsFlutterBinding.ensureInitialized();

    // 初始化数据库平台
    await initializeDatabasePlatform();

    // 初始化服务
    final settingsService = await SettingsService.create(); // 提前创建 SettingsService
    final databaseService = DatabaseService();

    // 初始化数据库，设置超时时间为 5 秒（仅在非 Web 平台下初始化）
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
          ChangeNotifierProvider(create: (_) => settingsService), // 使用已创建的 settingsService
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
              // 直接将 ListView 作为 Padding 的 child
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
                  Text(e.toString()), // 显示错误信息
                  const SizedBox(height: 16),
                  Text(
                    '堆栈跟踪:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(stackTrace.toString()), // 显示堆栈跟踪
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

  // 根据平台获取不同的 primarySwatch
  MaterialColor _getPrimarySwatchForPlatform(BuildContext context) {
    try {
      // 所有平台都使用默认蓝色，避免在应用初始化阶段使用Theme.of(context)导致空值异常
      debugPrint('所有平台: 使用默认蓝色');
      return createMaterialColor(Colors.blue);
      // 注释掉原来的平台特定逻辑，因为在应用初始化阶段可能导致问题
      /*
      if (kIsWeb) {
        debugPrint('Web平台: 使用默认蓝色');
        // Web平台直接使用默认蓝色，不尝试获取Theme.of(context)
        return createMaterialColor(Colors.blue);
      } else if (Platform.isAndroid) {
        // 动态获取安卓主题色
        final Color? androidDynamicColor = Theme.of(context).colorScheme.primary;
        debugPrint('Android平台: 动态颜色 - $androidDynamicColor');
        return createMaterialColor(androidDynamicColor ?? Colors.blue);
      } else {
        debugPrint('其他平台: 使用默认蓝色');
        return createMaterialColor(Colors.blue); // 其他平台默认蓝色
      }
      */
    } catch (e, stackTrace) {
      debugPrint('获取平台主题色出错: $e');
      debugPrint('错误堆栈: $stackTrace');
      return createMaterialColor(Colors.blue); // 出错时使用默认蓝色
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = _getPrimarySwatchForPlatform(context);
    // 确保 primaryColor[150] 不为空，特别是在Web平台上
    final Color secondaryColor = kIsWeb 
        ? primaryColor // Web平台直接使用primaryColor作为secondaryColor
        : (primaryColor[150] ?? primaryColor); // 非Web平台尝试使用色阶150
    
    return MaterialApp(
      title: 'Mind Trace',
      themeMode: ThemeMode.system, // 默认使用系统主题
      theme: ThemeData.light().copyWith(
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          secondary: secondaryColor,
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          primary: primaryColor,
          secondary: secondaryColor,
        ),
      ),
      home: const HomePage(),
    );
  }
}
