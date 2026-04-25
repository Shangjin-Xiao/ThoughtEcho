part of '../main.dart';

class TimeoutConstants {
  static const Duration clipboardInitTimeoutWindows = Duration(seconds: 2);
  static const Duration clipboardInitTimeoutDefault = Duration(seconds: 3);

  static const Duration databaseInitTimeoutWindows = Duration(seconds: 5);
  static const Duration databaseInitTimeoutDefault = Duration(seconds: 10);

  static const Duration uiInitDelayWindows = Duration(milliseconds: 1000);
  static const Duration uiInitDelayDefault = Duration(milliseconds: 0);
}

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
      String basePath;
      if (Platform.isWindows) {
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
  }
}

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

    logDebug('数据库服务初始化完成');
  } catch (e, stackTrace) {
    logDebug('数据库初始化失败: $e');

    try {
      await databaseService.initDefaultHitokotoCategories();
      logDebug('尝试恢复：虽然数据库初始化可能有问题，但已尝试创建默认标签');
    } catch (tagError) {
      logDebug('创建默认标签也失败: $tagError');
      _isEmergencyMode = true;
    }

    if (!databaseService.isInitialized) {
      _isEmergencyMode = true;
    }

    logService.error(
      '数据库初始化失败，但应用将尝试继续运行',
      error: e,
      stackTrace: stackTrace,
      source: 'background_init',
    );
  }
}

List<Map<String, dynamic>> getAndClearDeferredErrors() {
  final errors = List<Map<String, dynamic>>.from(_deferredErrors);
  _deferredErrors.clear();
  return errors;
}
