// ignore_for_file: unused_element, unused_field
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
// 仅在 Windows 平台下使用 sqflite_common_ffi，其它平台直接使用 sqflite 默认实现
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/note_category.dart';
import '../models/quote_model.dart';
import '../models/app_settings.dart';
import 'package:uuid/uuid.dart';
import '../utils/app_logger.dart';
import '../utils/database_platform_init.dart';
import 'large_file_manager.dart';
import 'media_reference_service.dart';
import 'mmkv_service.dart';
import 'unified_log_service.dart';
import '../models/merge_report.dart';
import '../widgets/quote_content_widget.dart'; // 用于缓存清理
import 'database_schema_manager.dart';
import 'database_backup_service.dart';
import 'database_health_service.dart';

part 'database/database_cache_mixin.dart';
part 'database/database_query_mixin.dart';
part 'database/database_query_helpers_mixin.dart';
part 'database/database_quote_crud_mixin.dart';
part 'database/database_favorite_mixin.dart';
part 'database/database_category_mixin.dart';
part 'database/database_category_init_mixin.dart';
part 'database/database_hidden_tag_mixin.dart';
part 'database/database_trash_mixin.dart';
part 'database/database_pagination_mixin.dart';
part 'database/database_import_export_mixin.dart';
part 'database/database_migration_mixin.dart';

enum QuoteUpdateResult { updated, skippedDeleted, notFound }

abstract class _DatabaseServiceBase extends ChangeNotifier {
  _DatabaseServiceBase._internal();

  @visibleForTesting
  _DatabaseServiceBase.forTesting();

  final DatabaseSchemaManager _schemaManager = DatabaseSchemaManager();
  final DatabaseBackupService _backupService = DatabaseBackupService();
  final DatabaseHealthService _healthService = DatabaseHealthService();
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
  static const String hiddenTagId = 'system_hidden_tag';
  static const String hiddenTagIconName = '🔒';

  Future<void> addQuote(Quote quote);
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false});
  Future<List<Quote>> getAllQuotes({
    bool excludeHiddenNotes = true,
    bool includeDeleted = false,
  });
  Future<void> deleteQuote(String id);
  Future<List<Quote>> searchQuotesByContent(
    String query, {
    bool includeDeleted = false,
  });
  Future<QuoteUpdateResult> updateQuote(Quote quote);

  Future<List<Quote>> getUserQuotes({
    List<String>? tagIds,
    String? categoryId,
    int offset = 0,
    int limit = 20,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool excludeHiddenNotes = true,
    bool includeDeleted = false,
  });
  Future<List<Quote>> getQuotesForSmartPush({
    int limit = 200,
    String orderBy = 'q.date DESC',
    bool includeDeleted = false,
  });
  Future<int> getQuotesCount({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool excludeHiddenNotes = true,
    bool includeDeleted = false,
  });

  /// 获取回收站中的已删除笔记列表，支持分页
  Future<List<Quote>> getDeletedQuotes({
    int offset = 0,
    int limit = 20,
    String orderBy = 'deleted_at DESC',
  });

  /// 获取回收站中已删除笔记的总数
  Future<int> getDeletedQuotesCount();

  /// 获取墓碑记录用于备份同步（永久删除的笔记 ID 列表）
  Future<List<Map<String, dynamic>>> getTombstonesForBackup();

  /// 从回收站恢复指定笔记
  Future<void> restoreQuote(String id);

  /// 永久删除指定笔记（不可恢复）
  Future<void> permanentlyDeleteQuote(String id);

  /// 清空回收站（永久删除所有已删除笔记）
  Future<void> emptyTrash();

  /// 自动清理超过保留期限的已删除笔记，返回清理数量
  Future<int> autoCleanupExpiredTrash({required int retentionDays});

  Future<void> incrementFavoriteCount(String quoteId);
  Future<void> resetFavoriteCount(String quoteId);
  Future<List<Quote>> getMostFavoritedQuotesThisWeek({int limit = 5});

  Future<List<Map<String, dynamic>>> getAllCategories();
  Future<List<NoteCategory>> getCategories();
  Future<void> addCategory(String name, {String? iconName});
  Future<void> addCategoryWithId(String id, String name, {String? iconName});
  Stream<List<NoteCategory>> watchCategories();
  Future<void> deleteCategory(String id);
  Future<void> updateCategory(String id, String name, {String? iconName});
  Future<NoteCategory?> getCategoryById(String id);

  Future<void> initDefaultHitokotoCategories();
  Future<NoteCategory?> getOrCreateHiddenTag();
  bool isHiddenTag(String tagId);
  Future<void> removeHiddenTag();
  Future<bool> isQuoteHidden(String quoteId);
  Future<List<String>> getHiddenQuoteIds();

  void refreshQuotes();
  Stream<List<Quote>> watchQuotes({
    List<String>? tagIds,
    String? categoryId,
    int limit = 20,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool includeDeleted = false,
  });
  Future<void> loadMoreQuotes({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool? includeDeleted,
  });

  Future<Map<String, dynamic>> exportDataAsMap();
  Future<String> exportAllData({String? customPath});
  Future<void> importDataFromMap(
    Map<String, dynamic> data, {
    bool clearExisting = true,
  });
  Future<void> importData(String filePath, {bool clearExisting = true});
  Future<bool> checkCanExport();
  Future<bool> validateBackupFile(String filePath);
  Future<MergeReport> importDataWithLWWMerge(
    Map<String, dynamic> data, {
    String? sourceDevice,
  });

  Future<void> patchQuotesDayPeriod();
  Future<void> migrateDayPeriodToKey();
  Future<void> migrateWeatherToKey();
  Future<Map<String, dynamic>> checkTagDataConsistency();
  Future<bool> cleanupTagDataInconsistencies();
  Future<List<int>> getHourDistributionForSmartPush();
  Map<String, dynamic> getQueryPerformanceReport();
  Future<Map<String, dynamic>?> getLocalDailyQuote({String offlineQuoteSource});
  Future<Map<String, dynamic>> performDatabaseMaintenance({
    Function(String)? onProgress,
  });
  Future<Map<String, dynamic>> getDatabaseHealthInfo();

  Future<List<Quote>> _directGetQuotes({
    List<String>? tagIds,
    String? categoryId,
    int offset = 0,
    int limit = 10,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool includeDeleted = false,
  });

  /// 修复：验证排序参数，防止 SQL 注入
  @visibleForTesting
  String sanitizeOrderBy(String orderBy, {String prefix = ''}) {
    final defaultOrder = prefix.isNotEmpty ? '$prefix.date DESC' : 'date DESC';
    if (orderBy.isEmpty) return defaultOrder;

    // 允许的排序字段
    const allowedColumns = [
      'id',
      'date',
      'favorite_count',
      'content',
      'category_id',
      'weather',
      'day_period',
      'last_modified',
      'color_hex',
      'deleted_at',
    ];

    final validTerms = <String>[];
    final terms = orderBy.split(',');

    for (var term in terms) {
      term = term.trim();
      if (term.isEmpty) continue;

      // 清除前缀（如 q. 或 qt.）
      String cleanTerm = term;
      if (cleanTerm.startsWith('q.')) {
        cleanTerm = cleanTerm.substring(2);
      } else if (cleanTerm.startsWith('qt.')) {
        cleanTerm = cleanTerm.substring(3);
      }

      final parts = cleanTerm.split(RegExp(r'\s+'));
      if (parts.isEmpty) continue;

      final column = parts[0].toLowerCase();

      // 验证列名
      if (!allowedColumns.contains(column)) {
        logDebug('发现不合法的排序字段: $column, 跳过该字段');
        continue;
      }

      // 验证排序方向
      String direction = 'DESC';
      if (parts.length > 1) {
        final dir = parts[1].toUpperCase();
        if (dir == 'ASC' || dir == 'DESC') {
          direction = dir;
        }
      } else if (term.toUpperCase().contains('ASC')) {
        direction = 'ASC';
      }

      final colWithPrefix = prefix.isNotEmpty ? '$prefix.$column' : column;
      validTerms.add('$colWithPrefix $direction');
    }

    if (validTerms.isEmpty) {
      return defaultOrder;
    }

    return validTerms.join(', ');
  }

  Future<void> _checkAndFixDatabaseStructure();
  void _scheduleCacheCleanup();
  void _clearAllCache();
  void _safeNotifyQuotesStream();
  void _refreshQuotesStream();
  Future<void> _updateCategoriesStream();

  /// 应用搜索查询条件
  void _applySearchQuery(
    String? searchQuery,
    List<String> conditions,
    List<dynamic> args,
  ) {
    if (searchQuery != null && searchQuery.isNotEmpty) {
      conditions.add(
        '(q.content LIKE ? OR (q.source LIKE ? OR q.source_author LIKE ? OR q.source_work LIKE ?))',
      );
      final searchParam = '%$searchQuery%';
      args.addAll([searchParam, searchParam, searchParam, searchParam]);
    }
  }

  static void setTestDatabase(Database testDb) {
    _database = testDb;
  }

  @visibleForTesting
  static void clearTestDatabase() {
    _database = null;
  }

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

  // TODO(low): 以下 5 个 Map 手动实现 LRU + 过期缓存，可提取为通用 LRU 缓存类简化维护。
  /// 修复：优化查询缓存，实现更好的LRU机制
  final Map<String, List<Quote>> _filterCache = {};
  final Map<String, DateTime> _cacheTimestamps = {}; // 缓存时间戳
  // _cacheAccessTimes and _maxCacheEntries removed: LRU eviction was never wired up
  final Duration _cacheExpiration = const Duration(minutes: 5); // 调整缓存过期时间

  // 优化：查询结果缓存
  final Map<String, int> _countCache = {}; // 计数查询缓存
  final Map<String, DateTime> _countCacheTimestamps = {};

  /// 修复：添加查询性能统计

  // 优化：缓存清理定时器，避免每次查询都清理
  Timer? _cacheCleanupTimer;
  DateTime _lastCacheCleanup = DateTime.now();
  // 添加存储天气筛选条件的变量
  List<String>? _watchSelectedWeathers;

  // 添加存储时间段筛选条件的变量
  List<String>? _watchSelectedDayPeriods;
  bool _watchIncludeDeleted = false;

  // 添加初始化状态标志
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // 添加并发访问控制
  Completer<void>? _initCompleter;
  bool _isInitializing = false;
  final _databaseLock = <String, Completer<void>>{};

  // 添加存储加载状态的变量
  bool _isLoading = false;

  // 添加存储当前加载的笔记列表的变量
  List<Quote> _currentQuotes = [];

  // 性能优化：增量维护的 ID Set，避免每次去重时遍历
  final Set<String> _currentQuoteIds = {};

  @protected
  void clearAllCacheForParts() => _clearAllCache();

  @protected
  void refreshQuotesStreamForParts() => _refreshQuotesStream();

  @protected
  void scheduleCacheCleanupForParts() => _scheduleCacheCleanup();

  @protected
  Future<void> updateCategoriesStreamForParts() => _updateCategoriesStream();

  @protected
  void safeNotifyQuotesStreamForParts() => _safeNotifyQuotesStream();

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

  /// 修复：初始化数据库，增加并发控制
  Future<void> init() async {
    // 单例在测试/恢复场景可能会被 dispose；此时允许通过 init 触发重新初始化。
    if (_isDisposed) {
      logDebug('DatabaseService 已被销毁，重新初始化单例状态');
      reinitialize();
    }

    // 修复：添加严格的重复初始化检查
    if (_isInitialized) {
      logDebug('数据库已初始化，跳过重复初始化');
      return;
    }

    // 防止并发初始化
    if (_isInitializing && _initCompleter != null) {
      await _initCompleter!.future;
      return;
    }

    _isInitializing = true;
    _initCompleter = Completer<void>();

    if (kIsWeb) {
      _isInitialized = true;
      _isInitializing = false;
      if (_initCompleter != null && !_initCompleter!.isCompleted) {
        _initCompleter!.complete();
      }
      _initCompleter = null;
      logInfo('Web平台使用内存模式，DatabaseService 初始化完成', source: 'DatabaseService');
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed) notifyListeners();
      });
      _scheduleTrashAutoCleanup();
      return;
    }

    // 修复：更严格的数据库初始化检查
    if (_database != null && _database!.isOpen) {
      logDebug('数据库已存在且打开，跳过重复初始化');
      _isInitialized = true;
      _isInitializing = false;
      if (_initCompleter != null && !_initCompleter!.isCompleted) {
        _initCompleter!.complete();
      }
      _initCompleter = null;
      return;
    }

    logDebug('初始化数据库...');
    try {
      // 修复：确保平台初始化在数据库操作之前完成
      if (!kIsWeb) {
        DatabasePlatformInit.initialize();
        logDebug('数据库平台初始化完成');
      }

      // FFI初始化已在main.dart中统一处理，这里不再重复初始化
      // 获取数据库存储路径，由 main.dart 已设置好路径
      final dbPath = await getDatabasesPath();
      final oldPath = join(dbPath, 'mind_trace.db');
      final path = join(dbPath, 'thoughtecho.db');

      // 自动迁移旧数据库文件
      final oldFile = File(oldPath);
      final newFile = File(path);
      if (!await newFile.exists() && await oldFile.exists()) {
        try {
          await oldFile.copy(path); // 用copy更安全，保留原文件
          logDebug('已自动迁移旧数据库文件到新文件名');
        } catch (e) {
          logDebug('自动迁移旧数据库文件失败: $e');
        }
      }

      // 数据库初始化核心逻辑
      _database = await _initDatabase(path);

      // 检查并修复数据库结构
      await _checkAndFixDatabaseStructure();

      // 优化：在初始化阶段执行所有数据迁移，避免运行时重复检查
      await _performAllDataMigrations();

      // 初始化默认分类/标签
      await initDefaultHitokotoCategories();
      logDebug('默认分类初始化检查完成');

      // 隐藏标签：系统标签，始终确保存在
      await getOrCreateHiddenTag();

      // 更新分类流数据
      await _updateCategoriesStream();

      // 修复：确保笔记流控制器在预加载前被正确初始化
      if (_quotesController == null || _quotesController!.isClosed) {
        _quotesController = StreamController<List<Quote>>.broadcast();
        logDebug('笔记流控制器已初始化');
      }

      // 修复：先设置初始化完成状态，再预加载数据，避免循环依赖
      _isInitialized = true; // 数据库初始化完成
      _isInitializing = false;
      if (_initCompleter != null && !_initCompleter!.isCompleted) {
        _initCompleter!.complete();
      }
      _initCompleter = null;

      // 修复：恢复简化的预加载逻辑，确保首次加载能正常工作
      logDebug('数据库初始化完成，准备预加载数据...');

      // 重置流相关状态
      _watchOffset = 0;
      _quotesCache = [];
      _filterCache.clear();
      _watchHasMore = true;

      // 新增：执行数据库健康检查
      await _performStartupHealthCheck();

      _scheduleTrashAutoCleanup();

      // 延迟通知监听者，让UI知道数据库已准备好
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed) notifyListeners();
      });
    } catch (e) {
      logDebug('数据库初始化失败: $e');
      _isInitializing = false;
      if (_initCompleter != null && !_initCompleter!.isCompleted) {
        _initCompleter!.completeError(e);
      }
      _initCompleter = null; // 修复：确保在错误时也清理 completer

      // 尝试基本的恢复措施
      try {
        await _attemptDatabaseRecovery();
      } catch (recoveryError) {
        logDebug('数据库恢复也失败: $recoveryError');
      }

      rethrow;
    }
  }

  // 抽取数据库初始化逻辑到单独方法，便于复用
  Future<Database> _initDatabase(String path) async {
    return await openDatabase(
      path,
      version: 20,
      onCreate: (db, version) async {
        await _schemaManager.createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _schemaManager.upgradeDatabase(db, oldVersion, newVersion);
      },
      onOpen: (db) async {
        // 关键：确保外键约束已启用（必须在事务外执行）
        await db.rawQuery('PRAGMA foreign_keys = ON');

        // 每次打开数据库时配置PRAGMA参数
        await _configureDatabasePragmas(db);

        // 验证外键约束状态
        await _verifyForeignKeysEnabled(db);
      },
    );
  }

  /// 验证外键约束是否已启用
  Future<void> _verifyForeignKeysEnabled(Database db) async {
    await _schemaManager.verifyForeignKeysEnabled(db);
  }

  /// 配置数据库安全和性能PRAGMA参数
  /// [inTransaction] 是否在事务内执行（onCreate/onUpgrade为true，onOpen为false）
  Future<void> _configureDatabasePragmas(
    Database db, {
    bool inTransaction = false,
  }) async {
    await _schemaManager.configureDatabasePragmas(
      db,
      inTransaction: inTransaction,
    );
  }

  /// 修复：创建升级备份

  /// 修复：创建升级备份

  // 新增初始化新数据库方法，用于在迁移失败时创建新的数据库
  Future<void> initializeNewDatabase() async {
    if (_isInitialized) return;

    try {
      // FFI初始化已在main.dart中统一处理，这里不再重复初始化
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'thoughtecho.db');

      // 如果文件已存在但可能损坏，先备份再删除
      final file = File(path);
      if (await file.exists()) {
        try {
          final backupPath = join(
            dbPath,
            'thoughtecho_backup_${DateTime.now().millisecondsSinceEpoch}.db',
          );
          await file.copy(backupPath);
          logDebug('已将可能损坏的数据库备份到 $backupPath');
          await file.delete();
          logDebug('已删除可能损坏的数据库文件');
        } catch (e) {
          logDebug('备份或删除损坏数据库失败: $e');
        }
      }

      // 初始化新数据库
      _database = await _initDatabase(path);

      // 创建默认分类
      await initDefaultHitokotoCategories();

      _isInitialized = true;

      // 修复：延迟通知，避免在build期间调用setState
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed) notifyListeners();
      });
      logDebug('成功初始化新数据库');
    } catch (e) {
      logDebug('初始化新数据库失败: $e');
      rethrow;
    }
  }

  /// 修复：在初始化时预加载笔记数据，避免循环依赖
  Future<void> _prefetchInitialQuotes() async {
    try {
      // 修复：重置状态，但不依赖流控制器
      _currentQuotes = [];
      _currentQuoteIds.clear(); // 性能优化：同步清空 ID Set
      _watchHasMore = true;
      _isLoading = false;
      _watchOffset = 0;

      // 修复：确保流控制器已初始化
      if (_quotesController == null || _quotesController!.isClosed) {
        _quotesController = StreamController<List<Quote>>.broadcast();
        logDebug('预加载时初始化流控制器');
      }

      // 修复：直接查询数据库，绕过getUserQuotes的初始化检查，避免循环依赖
      final quotes = await _directGetQuotes(
        tagIds: null,
        categoryId: null,
        offset: 0,
        limit: _watchLimit,
        orderBy: 'date DESC',
        searchQuery: null,
        selectedWeathers: null,
        selectedDayPeriods: null,
        includeDeleted: false,
      );

      _currentQuotes = quotes;
      _watchHasMore = quotes.length >= _watchLimit;

      // 修复：针对安卓平台的特殊处理
      if (!kIsWeb && Platform.isAndroid) {
        // 安卓平台延迟通知，确保UI完全准备好
        await Future.delayed(const Duration(milliseconds: 100));
        _safeNotifyQuotesStream();
        logDebug('安卓平台预加载完成，延迟通知UI，获取到 ${quotes.length} 条笔记');
      } else {
        // 其他平台立即通知
        _safeNotifyQuotesStream();
        logDebug('预加载完成，获取到 ${quotes.length} 条笔记，已通知UI更新');
      }
    } catch (e) {
      logDebug('预加载笔记时出错: $e');
      // 确保状态一致
      _currentQuotes = [];
      _currentQuoteIds.clear(); // 性能优化：同步清空 ID Set
      _watchHasMore = false;

      // 修复：确保流控制器存在
      if (_quotesController == null || _quotesController!.isClosed) {
        _quotesController = StreamController<List<Quote>>.broadcast();
      }

      // 即使出错也要通知流，确保UI状态正确
      _safeNotifyQuotesStream();
    }
  }

  /// 启动时执行数据库健康检查
  Future<void> _performStartupHealthCheck() async {
    await _healthService.performStartupHealthCheck(await safeDatabase);
  }

  /// 优化：在初始化阶段执行所有数据迁移
  /// 兼容性保证：所有迁移都是向后兼容的，不会破坏现有数据
  Future<void> _performAllDataMigrations() async {
    await _schemaManager.performAllDataMigrations(database);
  }

  /// 外部调用的统一刷新入口（同步/恢复后使用）
  void refreshAllData() {
    _clearAllCache();
    notifyListeners();
    _refreshQuotesStream();
  }

  /// 优化：添加dispose方法，确保资源正确释放
  /// 注意：这是新增方法，现有代码调用时需要确保在适当时机调用dispose()
  @override
  // ignore: must_call_super
  void dispose() {
    if (_isDisposed) return;

    _isDisposed = true;

    // 关闭所有StreamController
    if (!_categoriesController.isClosed) {
      _categoriesController.close();
    }

    if (_quotesController != null && !_quotesController!.isClosed) {
      _quotesController!.close();
      _quotesController = null;
    }

    // 取消定时器
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = null;

    // 清理缓存
    _filterCache.clear();
    _cacheTimestamps.clear();
    _countCache.clear();
    _countCacheTimestamps.clear();

    // 清理内存存储
    _memoryStore.clear();
    _categoryStore.clear();

    logDebug('DatabaseService资源已释放');

    // 注意：单例模式下不调用 super.dispose()，因为 ChangeNotifier 需要保持可用
    // ignore: must_call_super
    // super.dispose();
  }

  /// 重新初始化单例状态（用于紧急恢复场景）
  /// 在 dispose() 后调用此方法可以重置单例状态，使其可以重新初始化
  void reinitialize() {
    _isDisposed = false;
    _isInitialized = false;
    _isInitializing = false;
    _initCompleter = null;
    _databaseLock.clear();

    // 重新创建已关闭的 StreamController（dispose 后需要可恢复）。
    if (_categoriesController.isClosed) {
      _categoriesController = StreamController<List<NoteCategory>>.broadcast();
    }
    if (_quotesController == null || _quotesController!.isClosed) {
      _quotesController = StreamController<List<Quote>>.broadcast();
    }

    // 清理缓存，避免跨生命周期残留
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = null;
    _clearAllCache();
    _quotesCache = [];
    _watchOffset = 0;
    _watchHasMore = true;
    _watchIncludeDeleted = false;
    _isLoading = false;

    logDebug('DatabaseService 单例状态已重置');
  }

  /// 尝试数据库恢复
  Future<void> _attemptDatabaseRecovery() async {
    try {
      logDebug('尝试数据库恢复...');

      // 确保StreamController被正确初始化
      if (_quotesController == null || _quotesController!.isClosed) {
        _quotesController = StreamController<List<Quote>>.broadcast();
      }

      // 重置状态
      _quotesCache = [];
      _watchOffset = 0;
      _watchHasMore = true;
      _watchIncludeDeleted = false;
      _isLoading = false;

      // 清理缓存
      _clearAllCache();

      logDebug('数据库恢复措施已执行');
    } catch (e) {
      logDebug('数据库恢复失败: $e');
      rethrow;
    }
  }

  void _scheduleTrashAutoCleanup() {
    Future<void>.microtask(() async {
      if (_isDisposed) {
        return;
      }
      try {
        final retentionDays = await _resolveTrashRetentionDays();
        if (retentionDays == null) {
          logWarning('读取回收站保留期失败，跳过启动自动清理', source: 'DatabaseService');
          return;
        }
        final cleanedCount = await autoCleanupExpiredTrash(
          retentionDays: retentionDays,
        );
        if (cleanedCount > 0) {
          logInfo(
            '回收站自动清理完成: 删除 $cleanedCount 条过期笔记 (保留 $retentionDays 天)',
            source: 'DatabaseService',
          );
        }
      } catch (e, stackTrace) {
        logError(
          '回收站自动清理失败: $e',
          error: e,
          stackTrace: stackTrace,
          source: 'DatabaseService',
        );
        await _runBestEffortCleanupFailureHealthCheck();
      }
    });
  }

  Future<int?> _resolveTrashRetentionDays() async {
    try {
      final mmkv = MMKVService();
      await mmkv.init();
      var appSettingsJson = mmkv.getString('app_settings');
      if (appSettingsJson == null || appSettingsJson.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        appSettingsJson = prefs.getString('app_settings');
      }
      if (appSettingsJson == null || appSettingsJson.isEmpty) {
        return 30;
      }

      final map = json.decode(appSettingsJson) as Map<String, dynamic>;
      return AppSettings.fromJson(map).trashRetentionDays;
    } catch (e, stackTrace) {
      logError(
        '读取回收站保留期失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'DatabaseService',
      );
      return null;
    }
  }

  Future<void> _runBestEffortCleanupFailureHealthCheck() async {
    try {
      await _performStartupHealthCheck();
    } catch (e, stackTrace) {
      logError(
        '自动清理失败后的健康检查执行失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'DatabaseService',
      );
    }
  }
}

class DatabaseService extends _DatabaseServiceBase
    with
        _DatabaseCacheMixin,
        _DatabaseQueryHelpersMixin,
        _DatabaseQueryMixin,
        _DatabaseQuoteCrudMixin,
        _DatabaseFavoriteMixin,
        _DatabaseCategoryMixin,
        _DatabaseCategoryInitMixin,
        _DatabaseHiddenTagMixin,
        _DatabaseTrashMixin,
        _DatabasePaginationMixin,
        _DatabaseImportExportMixin,
        _DatabaseMigrationMixin {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;

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
  static const String hiddenTagId = 'system_hidden_tag';
  static const String hiddenTagIconName = '🔒';

  static Database? get rawDatabaseInstance => _DatabaseServiceBase._database;

  static void setTestDatabase(Database testDb) {
    _DatabaseServiceBase.setTestDatabase(testDb);
  }

  static void clearTestDatabase() {
    _DatabaseServiceBase.clearTestDatabase();
  }

  DatabaseService._internal() : super._internal();

  @visibleForTesting
  DatabaseService.forTesting() : super.forTesting();
}
