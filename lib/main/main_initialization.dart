part of '../main.dart';

// 超时时间常量 (Timeout constants)
class TimeoutConstants {
  // 剪贴板服务初始化超时时间
  static const Duration clipboardInitTimeoutWindows = Duration(seconds: 2);
  static const Duration clipboardInitTimeoutDefault = Duration(seconds: 3);

  // 数据库初始化超时时间
  static const Duration databaseInitTimeoutWindows = Duration(seconds: 5);
  static const Duration databaseInitTimeoutDefault = Duration(seconds: 10);

  // UI初始化延迟时间
  static const Duration uiInitDelayWindows = Duration(milliseconds: 1000);
  static const Duration uiInitDelayDefault = Duration(milliseconds: 0);
}

// 全局标志,确保FFI只初始化一次
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
        // 检查并执行旧版数据迁移(从 Documents 根目录迁移到 Documents/ThoughtEcho)
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
    logInfo('Web平台:使用内存数据库', source: 'DatabaseInit');
    // Web平台无需特殊初始化,SQLite会自动使用内存数据库
  }
}

// 全局导航key,用于日志服务在无context时获取context
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 添加一个全局标志,表示是否处于紧急模式(数据库损坏等情况)
bool _isEmergencyMode = false;

// 缓存早期捕获但无法立即记录的错误
final List<Map<String, dynamic>> _deferredErrors = [];
const int _maxDeferredErrors = 100; // 修复:设置最大容量防止无限增长

/// 安全添加延迟错误(带容量限制)
void _addDeferredError(Map<String, dynamic> error) {
  if (_deferredErrors.length >= _maxDeferredErrors) {
    _deferredErrors.removeAt(0);
  }
  _deferredErrors.add(error);
}

/// 全局方法,让LogService能够获取并处理缓存的早期错误
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

    // 修复:数据库初始化已包含默认分类初始化
    logDebug('数据库服务初始化完成');
  } catch (e, stackTrace) {
    logDebug('数据库初始化失败: $e');

    // 尝试恢复:即使数据库初始化失败,也尝试创建默认标签
    try {
      await databaseService.initDefaultHitokotoCategories();
      logDebug('尝试恢复:虽然数据库初始化可能有问题,但已尝试创建默认标签');
    } catch (tagError) {
      logDebug('创建默认标签也失败: $tagError');
      _isEmergencyMode = true;
    }

    // 如果还是失败,进入紧急模式
    if (!databaseService.isInitialized) {
      _isEmergencyMode = true;
    }

    // 记录错误但继续执行其他服务初始化
    logService.error(
      '数据库初始化失败,但应用将尝试继续运行',
      error: e,
      stackTrace: stackTrace,
      source: 'background_init',
    );
  }
}
