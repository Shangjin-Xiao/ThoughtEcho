// ignore_for_file: unused_element, unused_field
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
// 仅在 Windows 平台下使用 sqflite_common_ffi，其它平台直接使用 sqflite 默认实现
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/note_category.dart';
import '../models/quote_model.dart';
import 'package:uuid/uuid.dart';
import '../utils/app_logger.dart';
import '../utils/database_platform_init.dart';
import 'large_file_manager.dart';
import 'media_reference_service.dart';
import '../models/merge_report.dart';
import '../widgets/quote_content_widget.dart'; // 用于缓存清理
import 'database_schema_manager.dart';
import 'database_backup_service.dart';
import 'database_health_service.dart';

part 'database/database_cache.dart';
part 'database/database_pagination.dart';
part 'database/database_quote_crud.dart';
part 'database/database_quote_favorites.dart';
part 'database/database_category.dart';
part 'database/database_category_defaults.dart';
part 'database/database_hidden_tag.dart';
part 'database/database_query.dart';
part 'database/database_query_filters.dart';
part 'database/database_import_export.dart';
part 'database/database_lifecycle.dart';
part 'database/database_maintenance.dart';

class DatabaseService extends ChangeNotifier {
  // 单例模式 - 确保所有代码共享同一实例，避免竞态条件
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  /// 用于单元/Widget 测试的可构造实例（绕过单例工厂）。
  ///
  /// 注意：仅测试使用；生产代码应通过 `DatabaseService()` 获取单例。
  @visibleForTesting
  DatabaseService.forTesting();

  final DatabaseSchemaManager _schemaManager = DatabaseSchemaManager();
  final DatabaseBackupService _backupService = DatabaseBackupService();
  final DatabaseHealthService _healthService = DatabaseHealthService();

  static Database? _database;
  StreamController<List<NoteCategory>> _categoriesController =
      StreamController<List<NoteCategory>>.broadcast();
  final _uuid = const Uuid();
  // 内存存储，用于 Web 平台或调试存储，与原有业务流程保持一致
  final List<Quote> _memoryStore = [];
  // 内存存储分类数据
  final List<NoteCategory> _categoryStore = [];

  // 标记是否已经dispose，避免重复操作
  bool _isDisposed = false;

  // 提供访问_watchHasMore状态的getter
  bool get hasMoreQuotes => _watchHasMore;

  // 定义默认一言分类的固定 ID
  static const String defaultCategoryIdHitokoto = 'default_hitokoto';
  static const String defaultCategoryIdAnime = 'default_anime';
  static const String defaultCategoryIdComic = 'default_comic';
  static const String defaultCategoryIdGame = 'default_game';
  static const String defaultCategoryIdNovel = 'default_novel';
  static const String defaultCategoryIdOriginal = 'default_original';
  static const String defaultCategoryIdInternet = 'default_internet';
  static const String defaultCategoryIdOther = 'default_other';
  static const String defaultCategoryIdMovie = 'default_movie';
  static const String defaultCategoryIdPoem = 'default_poem';
  static const String defaultCategoryIdMusic = 'default_music';
  static const String defaultCategoryIdPhilosophy = 'default_philosophy';
  static const String defaultCategoryIdJoke = 'default_joke';

  // 隐藏笔记特殊标签 ID
  static const String hiddenTagId = 'system_hidden_tag';
  // 隐藏标签图标：使用 emoji 小锁
  static const String hiddenTagIconName = '🔒';

  // 新增：流式分页加载笔记
  StreamController<List<Quote>>? _quotesController;
  List<Quote> _quotesCache = [];
  List<String>? _watchTagIds;
  String? _watchCategoryId;
  String _watchOrderBy = 'date DESC';
  int _watchLimit = 20;
  int _watchOffset = 0;
  bool _watchHasMore = true;
  String? _watchSearchQuery;

  // 添加存储天气筛选条件的变量
  List<String>? _watchSelectedWeathers;

  // 添加存储时间段筛选条件的变量
  List<String>? _watchSelectedDayPeriods;

  // 添加初始化状态标志
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // 添加并发访问控制
  Completer<void>? _initCompleter;
  bool _isInitializing = false;
  final _databaseLock = <String, Completer<void>>{};

  // TODO(low): 以下 5 个 Map 手动实现 LRU + 过期缓存，可提取为通用 LRU 缓存类简化维护。
  /// 修复：优化查询缓存，实现更好的LRU机制
  final Map<String, List<Quote>> _filterCache = {};
  final Map<String, DateTime> _cacheTimestamps = {}; // 缓存时间戳
  final Map<String, DateTime> _cacheAccessTimes = {}; // 缓存访问时间，用于LRU
  final int _maxCacheEntries = 30; // 增加缓存容量
  final Duration _cacheExpiration = const Duration(minutes: 5); // 调整缓存过期时间

  // 优化：查询结果缓存
  final Map<String, int> _countCache = {}; // 计数查询缓存
  final Map<String, DateTime> _countCacheTimestamps = {};

  /// 修复：添加查询性能统计

  // 优化：缓存清理定时器，避免每次查询都清理
  Timer? _cacheCleanupTimer;
  DateTime _lastCacheCleanup = DateTime.now();

  // 添加存储加载状态的变量
  bool _isLoading = false;

  // 添加存储当前加载的笔记列表的变量
  List<Quote> _currentQuotes = [];

  // 性能优化：增量维护的 ID Set，避免每次去重时遍历
  final Set<String> _currentQuoteIds = {};

  Database get database {
    if (_database == null || !_database!.isOpen) {
      throw Exception('数据库未初始化或已关闭');
    }
    return _database!;
  }

  /// 修复：安全的数据库访问方法，增加并发控制
  Future<Database> get safeDatabase async {
    // 修复：检查服务是否已销毁
    if (_isDisposed) {
      throw StateError('DatabaseService 已被销毁，无法访问数据库');
    }

    // Web平台使用内存存储，不需要数据库对象
    if (kIsWeb) {
      // 确保已初始化
      if (!_isInitialized) {
        await init();
      }
      // Web平台没有真实数据库，抛出一个标记异常或返回mock
      throw UnsupportedError('Web平台使用内存存储，不支持数据库访问');
    }

    // 修复：如果数据库已经打开，直接返回，避免在 init() 内部调用时死锁
    // 这允许 init() 内部的方法（如 _updateCategoriesStream）正常工作
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    // 如果正在初始化，等待初始化完成
    // 注意：只有在数据库尚未打开时才等待，避免死锁
    if (_isInitializing && _initCompleter != null) {
      await _initCompleter!.future;
    }

    // 再次检查数据库状态（可能在等待期间已初始化完成）
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    // 如果数据库未初始化或已关闭，重新初始化
    logDebug('数据库需要重新初始化');
    await init();

    if (_database == null || !_database!.isOpen) {
      throw Exception('数据库初始化失败');
    }

    return _database!;
  }

  /// 带锁和超时的数据库操作执行器，防止死锁
  Future<T> _executeWithLock<T>(
    String operationId,
    Future<T> Function() action,
  ) async {
    // 等待已有锁释放，使用循环处理多个等待者竞争的情况
    for (;;) {
      final existing = _databaseLock[operationId];
      if (existing == null) break;
      try {
        await existing.future;
      } catch (_) {
        // 前一个操作的失败不影响当前操作获取锁
      }
      // 重新检查：其他等待者可能已抢先获取锁
    }

    // Safe: break→assign is synchronous (no await), so Dart's event loop
    // cannot interleave another coroutine between the check and the set.
    final completer = Completer<void>();
    _databaseLock[operationId] = completer;

    try {
      final result = await action().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException(
            '数据库操作超时: $operationId',
            const Duration(seconds: 30),
          );
        },
      );
      return result;
    } catch (e) {
      logError('数据库操作失败: $operationId', error: e);
      rethrow;
    } finally {
      completer.complete();
      _databaseLock.remove(operationId);
    }
  }

  /// Test method to set a test database instance
  static void setTestDatabase(Database testDb) {
    _database = testDb;
  }

  /// Test method to clear the test database instance
  @visibleForTesting
  static void clearTestDatabase() {
    _database = null;
  }

  void refreshAllData() {
    _clearAllCache();
    notifyListeners();
    _refreshQuotesStream();
  }
}
