import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../utils/app_logger.dart';
import 'data_directory_service.dart';

/// 数据库平台引导：FFI 初始化与数据库目录设置。
///
/// 独立成文件供 main.dart 与后台推送 isolate 共用，
/// 避免 services 层为调用它而反向 import main.dart。

// 全局标志，确保FFI只初始化一次
bool _ffiInitialized = false;

Future<void> initializeDatabasePlatform() async {
  if (!kIsWeb) {
    if (Platform.isWindows && !_ffiInitialized) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiInitialized = true;
      logInfo('Windows FFI数据库工厂已初始化', source: 'DatabaseInit');
    }

    try {
      // Windows 平台使用 Documents/ThoughtEcho 作为默认数据目录
      // 其他平台继续使用 Documents 根目录
      String basePath;
      if (Platform.isWindows) {
        // 检查并执行旧版数据迁移（从 Documents 根目录迁移到 Documents/ThoughtEcho）
        await DataDirectoryService.checkAndMigrateLegacyData();
        basePath = await DataDirectoryService.getCurrentDataDirectory();
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        basePath = appDir.path;
      }

      final dbPath = join(basePath, 'databases');

      await Directory(dbPath).create(recursive: true);

      final path = join(dbPath, 'thoughtecho.db');
      if (!await Directory(dirname(path)).exists()) {
        await Directory(dirname(path)).create(recursive: true);
      }

      await databaseFactory.setDatabasesPath(dbPath);
      logInfo('数据库路径设置为: $dbPath', source: 'DatabaseInit');
    } catch (e) {
      logError('创建数据库目录失败: $e', error: e, source: 'DatabaseInit');
      rethrow;
    }
  } else {
    logInfo('Web平台：使用内存数据库', source: 'DatabaseInit');
    // Web平台无需特殊初始化，SQLite会自动使用内存数据库
  }
}
