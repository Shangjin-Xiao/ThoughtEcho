// ignore_for_file: unused_element, unused_field
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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

  /// 优化：定期清理过期缓存，而不是每次查询都清理
  /// 兼容性说明：这个变更不影响外部API，只是内部优化
  void _scheduleCacheCleanup() {
    // 如果距离上次清理不到1分钟，跳过
    if (DateTime.now().difference(_lastCacheCleanup).inMinutes < 1) {
      return;
    }

    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = Timer(const Duration(seconds: 30), () {
      _cleanExpiredCache();
      _lastCacheCleanup = DateTime.now();
    });
  }

  /// 优化：检查并清理过期缓存
  void _cleanExpiredCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    final expiredCountKeys = <String>[];

    // 清理查询缓存
    for (final entry in _cacheTimestamps.entries) {
      if (now.difference(entry.value) > _cacheExpiration) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _filterCache.remove(key);
      _cacheTimestamps.remove(key);
      _cacheAccessTimes.remove(key); // 同时清理访问时间
    }

    // 清理计数缓存
    for (final entry in _countCacheTimestamps.entries) {
      if (now.difference(entry.value) > _cacheExpiration) {
        expiredCountKeys.add(entry.key);
      }
    }

    for (final key in expiredCountKeys) {
      _countCache.remove(key);
      _countCacheTimestamps.remove(key);
    }

    logDebug(
      '缓存清理完成，移除 ${expiredKeys.length} 个查询缓存和 ${expiredCountKeys.length} 个计数缓存',
    );
  }

  /// 优化：清空所有缓存（在数据变更时调用）
  void _clearAllCache() {
    _filterCache.clear();
    _cacheTimestamps.clear();
    _countCache.clear();
    _countCacheTimestamps.clear();
  }

  /// 修复：安全地通知笔记流订阅者
  /// 性能优化：由于 _currentQuotes 已通过 _currentQuoteIds 保证唯一性，
  /// 此处直接发送，无需再次遍历去重
  void _safeNotifyQuotesStream() {
    // 修复：检查服务是否已销毁
    if (_isDisposed) return;

    if (_quotesController != null && !_quotesController!.isClosed) {
      // 直接发送当前列表的副本，已保证唯一性
      _quotesController!.add(List.from(_currentQuotes));
    }
  }

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

  /// 修复：带锁和超时的数据库操作执行器，防止死锁
  Future<T> _executeWithLock<T>(
    String operationId,
    Future<T> Function() action,
  ) async {
    // 如果已有相同操作在执行，等待其完成
    if (_databaseLock.containsKey(operationId)) {
      await _databaseLock[operationId]!.future;
    }

    final completer = Completer<void>();
    _databaseLock[operationId] = completer;

    try {
      // 添加超时机制（30秒超时）
      final result = await action().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException(
            '数据库操作超时: $operationId',
            const Duration(seconds: 30),
          );
        },
      );
      completer.complete();
      _databaseLock.remove(operationId);
      return result;
    } catch (e) {
      completer.completeError(e);
      _databaseLock.remove(operationId);
      logError('数据库操作失败: $operationId', error: e);
      rethrow;
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
      // Web平台特定的初始化
      logDebug('在Web平台初始化内存存储');
      // 添加足够的示例数据以便Web平台测试分页功能
      if (_memoryStore.isEmpty) {
        final now = DateTime.now();
        for (int i = 0; i < 25; i++) {
          final quote = Quote(
            id: _uuid.v4(),
            content: '这是第${i + 1}条示例笔记 - Web版测试数据',
            date: now.subtract(Duration(hours: i)).toIso8601String(),
            source: '示例来源${i + 1}',
            aiAnalysis: '这是第${i + 1}条Web平台示例笔记的AI分析',
          );
          _memoryStore.add(quote);
          logDebug(
            '生成示例数据${i + 1}: id=${quote.id?.substring(0, 8)}, content=${quote.content}',
          );
        }
        logDebug('Web平台已生成${_memoryStore.length}条示例数据');
      }

      if (_categoryStore.isEmpty) {
        _categoryStore.add(
          NoteCategory(
            id: _uuid.v4(),
            name: '默认分类',
            isDefault: true,
            iconName: 'bookmark',
          ),
        );
      }

      // 隐藏标签：系统标签，始终确保存在（Web内存存储）
      await getOrCreateHiddenTag();

      // 触发更新
      _categoriesController.add(_categoryStore);
      _isInitialized = true; // 标记为已初始化
      _isInitializing = false;
      if (_initCompleter != null && !_initCompleter!.isCompleted) {
        _initCompleter!.complete();
      }
      _initCompleter = null;
      notifyListeners();
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

      // 延迟通知监听者，让UI知道数据库已准备好
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
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
      version: 19, // 版本号升级至19，添加latitude/longitude字段支持离线位置存储
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
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

  /// 修复：直接查询数据库，不进行初始化状态检查，用于内部调用
  Future<List<Quote>> _directGetQuotes({
    List<String>? tagIds,
    String? categoryId,
    int offset = 0,
    int limit = 10,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
  }) async {
    if (kIsWeb) {
      // Web平台的完整筛选逻辑
      var filtered = _memoryStore;
      if (tagIds != null && tagIds.isNotEmpty) {
        filtered = filtered
            .where((q) => q.tagIds.any((tag) => tagIds.contains(tag)))
            .toList();
      }
      if (categoryId != null && categoryId.isNotEmpty) {
        filtered = filtered.where((q) => q.categoryId == categoryId).toList();
      }
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final query = searchQuery.toLowerCase();
        filtered = filtered
            .where(
              (q) =>
                  q.content.toLowerCase().contains(query) ||
                  (q.source?.toLowerCase().contains(query) ?? false) ||
                  (q.sourceAuthor?.toLowerCase().contains(query) ?? false) ||
                  (q.sourceWork?.toLowerCase().contains(query) ?? false),
            )
            .toList();
      }

      // 排序
      if (orderBy.contains('date')) {
        filtered.sort((a, b) {
          final aDate = DateTime.tryParse(a.date) ?? DateTime.now();
          final bDate = DateTime.tryParse(b.date) ?? DateTime.now();
          return orderBy.contains('DESC')
              ? bDate.compareTo(aDate)
              : aDate.compareTo(bDate);
        });
      } else if (orderBy.contains('content')) {
        filtered.sort((a, b) {
          return orderBy.contains('DESC')
              ? b.content.compareTo(a.content)
              : a.content.compareTo(b.content);
        });
      }

      // 分页
      final start = offset;
      final end = (start + limit).clamp(0, filtered.length);
      return filtered.sublist(start, end);
    }

    // 非Web平台直接查询数据库
    final db = _database!; // 直接使用数据库，不进行安全检查

    // 构建查询条件
    final conditions = <String>[];
    final args = <dynamic>[];

    // 标签筛选
    if (tagIds != null && tagIds.isNotEmpty) {
      final tagPlaceholders = tagIds.map((_) => '?').join(',');
      conditions.add(
        'q.id IN (SELECT quote_id FROM quote_tags WHERE tag_id IN ($tagPlaceholders))',
      );
      args.addAll(tagIds);
    }

    // 分类筛选
    if (categoryId != null && categoryId.isNotEmpty) {
      conditions.add('q.category_id = ?');
      args.add(categoryId);
    }

    // 搜索查询
    // TODO(low): 该 LIKE 搜索模式在第 696、1992、2430 行重复了 3 次，
    // 可提取为共享方法。当前量级（个人笔记）性能足够，暂不需要 FTS5。
    if (searchQuery != null && searchQuery.isNotEmpty) {
      conditions.add(
        '(q.content LIKE ? OR (q.source LIKE ? OR q.source_author LIKE ? OR q.source_work LIKE ?))',
      );
      final searchParam = '%$searchQuery%';
      args.addAll([searchParam, searchParam, searchParam, searchParam]);
    }

    // 天气筛选
    if (selectedWeathers != null && selectedWeathers.isNotEmpty) {
      final weatherPlaceholders = selectedWeathers.map((_) => '?').join(',');
      conditions.add('q.weather IN ($weatherPlaceholders)');
      args.addAll(selectedWeathers);
    }

    // 时间段筛选
    if (selectedDayPeriods != null && selectedDayPeriods.isNotEmpty) {
      final dayPeriodPlaceholders =
          selectedDayPeriods.map((_) => '?').join(',');
      conditions.add('q.day_period IN ($dayPeriodPlaceholders)');
      args.addAll(selectedDayPeriods);
    }

    final whereClause =
        conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

    // 优化：使用JOIN一次性获取所有数据，避免N+1查询问题
    final query = '''
      SELECT 
        q.*,
        GROUP_CONCAT(qt.tag_id) as tag_ids_joined
      FROM quotes q
      LEFT JOIN quote_tags qt ON q.id = qt.quote_id
      $whereClause
      GROUP BY q.id
      ORDER BY q.$orderBy
      LIMIT ? OFFSET ?
    ''';

    args.addAll([limit, offset]);

    final List<Map<String, dynamic>> maps = await db.rawQuery(query, args);
    final quotes = <Quote>[];

    for (final map in maps) {
      try {
        // 解析聚合的标签ID
        final tagIdsJoined = map['tag_ids_joined'];
        final tagIds = <String>{
          if (tagIdsJoined != null && tagIdsJoined.toString().isNotEmpty)
            ...tagIdsJoined
                .toString()
                .split(',')
                .map((id) => id.trim())
                .where((id) => id.isNotEmpty),
        }.toList();

        // 创建Quote对象（移除临时字段）
        final quoteData = Map<String, dynamic>.from(map);
        quoteData.remove('tag_ids_joined');

        final quote = Quote.fromJson({...quoteData, 'tag_ids': tagIds});
        quotes.add(quote);
      } catch (e) {
        logDebug('解析笔记数据失败: $e, 数据: $map');
      }
    }

    return quotes;
  }

  /// 获取所有分类列表
  Future<List<Map<String, dynamic>>> getAllCategories() async {
    try {
      if (kIsWeb) {
        return _categoryStore.map((c) => c.toJson()).toList();
      }
      final db = database;
      return await db.query('categories');
    } catch (e) {
      logDebug('获取所有分类失败: $e');
      return [];
    }
  }

  /// 检查并修复数据库结构，确保所有必要的列都存在
  /// 修复：检查并修复数据库结构，包括字段和索引
  Future<void> _checkAndFixDatabaseStructure() async {
    await _schemaManager.checkAndFixDatabaseStructure(database);
  }

  /// 初始化默认一言分类标签
  Future<void> initDefaultHitokotoCategories() async {
    if (kIsWeb) {
      // Web 平台逻辑：检查内存中的 _categoryStore
      final defaultCategories = _getDefaultHitokotoCategories();
      final existingNamesLower =
          _categoryStore.map((c) => c.name.toLowerCase()).toSet();
      for (final category in defaultCategories) {
        if (!existingNamesLower.contains(category.name.toLowerCase())) {
          _categoryStore.add(category);
        }
      }
      // 确保流更新
      if (!_categoriesController.isClosed) {
        _categoriesController.add(List.unmodifiable(_categoryStore));
      }
      return;
    }

    try {
      // 首先确保数据库已初始化
      if (_database == null) {
        logDebug('数据库尚未初始化，尝试先进行初始化');
        try {
          await init();
        } catch (e) {
          logDebug('数据库初始化失败，但仍将尝试创建默认标签: $e');
        }
      }

      // 即使init()失败，也尝试获取数据库，如果還是null則提前返回
      if (_database == null) {
        logDebug('数据库仍为null，无法创建默认标签');
        return;
      }

      final db = database;
      final defaultCategories = _getDefaultHitokotoCategories();

      // 1. 一次性查询所有现有分类名称（小写）
      final existingCategories = await db.query(
        'categories',
        columns: ['name', 'id'],
      );
      final existingNamesLower = existingCategories
          .map((row) => (row['name'] as String?)?.toLowerCase())
          .where((name) => name != null)
          .toSet();

      // 同时创建ID到名称的映射，用于检查默认ID是否已被其它名称使用
      final existingIdToName = {
        for (var row in existingCategories)
          row['id'] as String: row['name'] as String,
      };

      // 2. 筛选出数据库中尚不存在的默认分类
      final categoriesToAdd = defaultCategories
          .where(
            (category) =>
                !existingNamesLower.contains(category.name.toLowerCase()),
          )
          .toList();

      // 3. 检查默认ID是否已被其他名称使用，如果是，需要更新名称
      final idsToUpdate = <String, String>{};
      for (final category in defaultCategories) {
        if (existingIdToName.containsKey(category.id) &&
            existingIdToName[category.id]!.toLowerCase() !=
                category.name.toLowerCase()) {
          // 已存在此ID但名称不同，需要更新
          idsToUpdate[category.id] = category.name;
        }
      }

      // 4. 如果有需要添加的分类，则使用批处理插入
      final batch = db.batch();

      // 先处理更新
      for (final entry in idsToUpdate.entries) {
        batch.update(
          'categories',
          {'name': entry.value, 'is_default': 1},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
        logDebug('更新ID为${entry.key}的分类名称为: ${entry.value}');
      }

      // 再处理新增
      for (final category in categoriesToAdd) {
        // 跳过ID已经存在但名称不同的情况（已在上面处理）
        if (idsToUpdate.containsKey(category.id)) {
          continue;
        }
        batch.insert(
            'categories',
            {
              'id': category.id,
              'name': category.name,
              'is_default': category.isDefault ? 1 : 0,
              'icon_name': category.iconName,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        logDebug('添加默认一言分类: ${category.name}');
      }

      // 提交批处理
      if (categoriesToAdd.isNotEmpty || idsToUpdate.isNotEmpty) {
        await batch.commit(noResult: true);
        logDebug(
          '批量处理了 ${categoriesToAdd.length} 个新分类和 ${idsToUpdate.length} 个更新',
        );
      } else {
        logDebug('所有默认分类已存在，无需添加');
      }

      // 更新分类流
      await _updateCategoriesStream();
    } catch (e) {
      logDebug('初始化默认一言分类出错: $e');
    }
  }

  /// 获取默认一言分类列表
  List<NoteCategory> _getDefaultHitokotoCategories() {
    return [
      NoteCategory(
        id: defaultCategoryIdHitokoto, // 使用固定 ID
        name: '每日一言',
        isDefault: true,
        iconName: 'format_quote',
      ),
      NoteCategory(
        id: defaultCategoryIdAnime, // 使用固定 ID
        name: '动画',
        isDefault: true,
        iconName: '🎬',
      ),
      NoteCategory(
        id: defaultCategoryIdComic, // 使用固定 ID
        name: '漫画',
        isDefault: true,
        iconName: '📚',
      ),
      NoteCategory(
        id: defaultCategoryIdGame, // 使用固定 ID
        name: '游戏',
        isDefault: true,
        iconName: '🎮',
      ),
      NoteCategory(
        id: defaultCategoryIdNovel, // 使用固定 ID
        name: '文学',
        isDefault: true,
        iconName: '📖',
      ),
      NoteCategory(
        id: defaultCategoryIdOriginal, // 使用固定 ID
        name: '原创',
        isDefault: true,
        iconName: '✨',
      ),
      NoteCategory(
        id: defaultCategoryIdInternet, // 使用固定 ID
        name: '来自网络',
        isDefault: true,
        iconName: '🌐',
      ),
      NoteCategory(
        id: defaultCategoryIdOther, // 使用固定 ID
        name: '其他',
        isDefault: true,
        iconName: '📦',
      ),
      NoteCategory(
        id: defaultCategoryIdMovie, // 使用固定 ID
        name: '影视',
        isDefault: true,
        iconName: '🎞️',
      ),
      NoteCategory(
        id: defaultCategoryIdPoem, // 使用固定 ID
        name: '诗词',
        isDefault: true,
        iconName: '🪶',
      ),
      NoteCategory(
        id: defaultCategoryIdMusic, // 使用固定 ID
        name: '网易云',
        isDefault: true,
        iconName: '🎧',
      ),
      NoteCategory(
        id: defaultCategoryIdPhilosophy, // 使用固定 ID
        name: '哲学',
        isDefault: true,
        iconName: '🤔',
      ),
    ];
  }

  /// 将所有笔记和分类数据导出为Map对象
  Future<Map<String, dynamic>> exportDataAsMap() async {
    return _backupService.exportDataAsMap(database);
  }

  /// 导出全部数据到 JSON 格式
  ///
  /// [customPath] - 可选的自定义保存路径。如果提供，将保存到指定路径；否则保存到应用文档目录
  /// 返回保存的文件路径
  Future<String> exportAllData({String? customPath}) async {
    return _backupService.exportAllData(
      database,
      customPath: customPath,
    );
  }

  /// 从Map对象导入数据
  Future<void> importDataFromMap(
    Map<String, dynamic> data, {
    bool clearExisting = true,
  }) async {
    await _backupService.importDataFromMap(
      database,
      data,
      clearExisting: clearExisting,
    );
    await _updateCategoriesStream();
    notifyListeners();
    await patchQuotesDayPeriod();
    await migrateWeatherToKey();
    await migrateDayPeriodToKey();
  }

  /// 从 JSON 文件导入数据
  ///
  /// [filePath] - 导入文件的路径
  /// [clearExisting] - 是否清空现有数据，默认为 true
  Future<void> importData(String filePath, {bool clearExisting = true}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('备份文件不存在: $filePath');
      }
      // 使用流式JSON解析避免大文件OOM
      final data = await LargeFileManager.decodeJsonFromFileStreaming(file);

      // 调用新的核心导入逻辑
      await importDataFromMap(data, clearExisting: clearExisting);
    } catch (e) {
      logDebug('数据导入失败: $e');
      rethrow;
    }
  }

  /// 检查是否可以导出数据（检测数据库是否可访问）
  Future<bool> checkCanExport() async {
    return _backupService.checkCanExport(_database);
  }

  /// 验证备份文件是否有效
  Future<bool> validateBackupFile(String filePath) async {
    return _backupService.validateBackupFile(filePath);
  }

  Future<List<NoteCategory>> getCategories() async {
    if (kIsWeb) {
      return _moveHiddenCategoryToBottom(
          List<NoteCategory>.from(_categoryStore));
    }
    try {
      final db = await safeDatabase;
      final maps = await db.query('categories');
      final categories = maps.map((map) => NoteCategory.fromMap(map)).toList();
      return _moveHiddenCategoryToBottom(categories);
    } catch (e) {
      logDebug('获取分类错误: $e');
      return [];
    }
  }

  List<NoteCategory> _moveHiddenCategoryToBottom(
      List<NoteCategory> categories) {
    final hiddenCategories =
        categories.where((category) => category.id == hiddenTagId).toList();
    final normalCategories =
        categories.where((category) => category.id != hiddenTagId).toList();
    return [...normalCategories, ...hiddenCategories];
  }

  /// 获取或创建隐藏标签
  /// 当启用隐藏笔记功能时，确保隐藏标签存在
  /// 隐藏标签是系统标签，不可编辑或删除
  Future<NoteCategory?> getOrCreateHiddenTag() async {
    try {
      // 先尝试获取现有的隐藏标签
      final categories = await getCategories();
      final existingHiddenTag = categories.where((c) => c.id == hiddenTagId);
      if (existingHiddenTag.isNotEmpty) {
        // 检查并更新旧版隐藏标签（如果需要）
        final existing = existingHiddenTag.first;
        if (!existing.isDefault || existing.iconName != hiddenTagIconName) {
          // 更新为新的系统标签格式
          await _updateHiddenTagFormat();
          // 返回更新后的标签
          return NoteCategory(
            id: hiddenTagId,
            name: '隐藏',
            isDefault: true,
            iconName: hiddenTagIconName,
          );
        }
        return existing;
      }

      // 如果不存在，创建隐藏标签（系统标签，使用锁图标）
      if (kIsWeb) {
        final hiddenTag = NoteCategory(
          id: hiddenTagId,
          name: '隐藏', // UI层会根据语言显示本地化名称
          isDefault: true, // 系统标签，不可删除/编辑
          iconName: hiddenTagIconName, // 使用 emoji 小锁
        );
        _categoryStore.add(hiddenTag);
        _categoriesController.add(_categoryStore);
        notifyListeners();
        return hiddenTag;
      }

      final db = await safeDatabase;
      final categoryMap = {
        'id': hiddenTagId,
        'name': '隐藏',
        'is_default': 1, // 系统标签
        'icon_name': hiddenTagIconName, // emoji 小锁
        'last_modified': DateTime.now().toUtc().toIso8601String(),
      };

      await db.insert(
        'categories',
        categoryMap,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await _updateCategoriesStream();
      notifyListeners();

      return NoteCategory(
        id: hiddenTagId,
        name: '隐藏',
        isDefault: true,
        iconName: hiddenTagIconName,
      );
    } catch (e) {
      logDebug('获取或创建隐藏标签错误: $e');
      return null;
    }
  }

  /// 更新旧版隐藏标签为新格式（系统标签+锁图标）
  Future<void> _updateHiddenTagFormat() async {
    try {
      if (kIsWeb) {
        final index = _categoryStore.indexWhere((c) => c.id == hiddenTagId);
        if (index >= 0) {
          _categoryStore[index] = NoteCategory(
            id: hiddenTagId,
            name: '隐藏',
            isDefault: true,
            iconName: hiddenTagIconName,
          );
          _categoriesController.add(_categoryStore);
          notifyListeners();
        }
        return;
      }

      final db = await safeDatabase;
      await db.update(
        'categories',
        {
          'is_default': 1,
          'icon_name': hiddenTagIconName,
          'last_modified': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [hiddenTagId],
      );
      await _updateCategoriesStream();
      notifyListeners();
    } catch (e) {
      logDebug('更新隐藏标签格式错误: $e');
    }
  }

  /// 检查标签是否是隐藏标签
  bool isHiddenTag(String tagId) {
    return tagId == hiddenTagId;
  }

  /// 删除隐藏标签（当关闭隐藏笔记功能时）
  Future<void> removeHiddenTag() async {
    try {
      if (kIsWeb) {
        _categoryStore.removeWhere((c) => c.id == hiddenTagId);
        _categoriesController.add(_categoryStore);
        notifyListeners();
        return;
      }

      final db = await safeDatabase;
      // 先删除所有笔记与隐藏标签的关联
      await db.delete(
        'quote_tags',
        where: 'tag_id = ?',
        whereArgs: [hiddenTagId],
      );
      // 再删除隐藏标签本身
      await db.delete(
        'categories',
        where: 'id = ?',
        whereArgs: [hiddenTagId],
      );
      await _updateCategoriesStream();
      notifyListeners();
    } catch (e) {
      logDebug('删除隐藏标签错误: $e');
    }
  }

  /// 检查笔记是否被隐藏（是否带有隐藏标签）
  Future<bool> isQuoteHidden(String quoteId) async {
    try {
      if (kIsWeb) {
        final quote = _memoryStore.where((q) => q.id == quoteId);
        if (quote.isNotEmpty) {
          return quote.first.tagIds.contains(hiddenTagId);
        }
        return false;
      }

      final db = database;
      final result = await db.query(
        'quote_tags',
        where: 'quote_id = ? AND tag_id = ?',
        whereArgs: [quoteId, hiddenTagId],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      logDebug('检查笔记是否隐藏错误: $e');
      return false;
    }
  }

  /// 获取所有隐藏笔记的ID列表
  Future<List<String>> getHiddenQuoteIds() async {
    try {
      if (kIsWeb) {
        return _memoryStore
            .where((q) => q.tagIds.contains(hiddenTagId))
            .map((q) => q.id ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
      }

      final db = database;
      final result = await db.query(
        'quote_tags',
        columns: ['quote_id'],
        where: 'tag_id = ?',
        whereArgs: [hiddenTagId],
      );
      return result.map((row) => row['quote_id'] as String).toList();
    } catch (e) {
      logDebug('获取隐藏笔记ID列表错误: $e');
      return [];
    }
  }

  /// 修复：添加一条分类，统一名称唯一性检查
  Future<void> addCategory(String name, {String? iconName}) async {
    // 统一的参数验证
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('分类名称不能为空');
    }
    if (trimmedName.length > 50) {
      throw Exception('分类名称不能超过50个字符');
    }

    if (kIsWeb) {
      // 检查是否已存在同名分类（不区分大小写）
      final exists = _categoryStore.any(
        (c) => c.name.toLowerCase() == trimmedName.toLowerCase(),
      );
      if (exists) {
        throw Exception('已存在相同名称的分类');
      }

      final newCategory = NoteCategory(
        id: _uuid.v4(),
        name: trimmedName,
        isDefault: false,
        iconName: iconName?.trim() ?? "",
      );
      _categoryStore.add(newCategory);
      _categoriesController.add(_categoryStore);
      notifyListeners();
      return;
    }

    final db = database;

    // 统一的唯一性检查逻辑
    await _validateCategoryNameUnique(db, trimmedName);

    final id = _uuid.v4();
    final categoryMap = {
      'id': id,
      'name': trimmedName,
      'is_default': 0,
      'icon_name': iconName?.trim() ?? "",
      'last_modified': DateTime.now().toUtc().toIso8601String(),
    };
    await db.insert(
      'categories',
      categoryMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _updateCategoriesStream();
    notifyListeners();
  }

  /// 修复：统一的分类名称唯一性验证
  Future<void> _validateCategoryNameUnique(
    Database db,
    String name, {
    String? excludeId,
  }) async {
    final whereClause =
        excludeId != null ? 'LOWER(name) = ? AND id != ?' : 'LOWER(name) = ?';
    final whereArgs = excludeId != null
        ? [name.toLowerCase(), excludeId]
        : [name.toLowerCase()];

    final existing = await db.query(
      'categories',
      where: whereClause,
      whereArgs: whereArgs,
      limit: 1,
    );

    if (existing.isNotEmpty) {
      throw Exception('已存在相同名称的分类');
    }
  }

  /// 添加一条分类（使用指定ID）
  Future<void> addCategoryWithId(
    String id,
    String name, {
    String? iconName,
  }) async {
    // 检查参数
    if (name.trim().isEmpty) {
      throw Exception('分类名称不能为空');
    }
    if (id.trim().isEmpty) {
      throw Exception('分类ID不能为空');
    }

    if (kIsWeb) {
      // 检查是否已存在同名分类
      final exists = _categoryStore.any(
        (c) => c.name.toLowerCase() == name.toLowerCase(),
      );
      if (exists) {
        logDebug('Web平台: 已存在相同名称的分类 "$name"，但将继续使用');
      }

      // 检查ID是否已被占用
      final idExists = _categoryStore.any((c) => c.id == id);
      if (idExists) {
        // 如果ID已存在，不报错，静默更新此分类
        final index = _categoryStore.indexWhere((c) => c.id == id);
        if (index != -1) {
          _categoryStore[index] = NoteCategory(
            id: id,
            name: name,
            isDefault: _categoryStore[index].isDefault,
            iconName: iconName ?? _categoryStore[index].iconName,
          );
        }
      } else {
        // 创建新分类
        final newCategory = NoteCategory(
          id: id,
          name: name,
          isDefault: false,
          iconName: iconName ?? "",
        );
        _categoryStore.add(newCategory);
      }

      _categoriesController.add(_categoryStore);
      notifyListeners();
      return;
    }

    // 确保数据库已初始化
    if (_database == null) {
      try {
        await init();
      } catch (e) {
        logDebug('添加分类前初始化数据库失败: $e');
        throw Exception('数据库未初始化，无法添加分类');
      }
    }

    final db = database;

    try {
      // 使用事务确保操作的原子性
      await db.transaction((txn) async {
        // 检查是否已存在同名分类
        final existing = await txn.query(
          'categories',
          where: 'LOWER(name) = ?',
          whereArgs: [name.toLowerCase()],
        );

        if (existing.isNotEmpty) {
          // 如果存在同名分类但ID不同，记录警告但继续
          final existingId = existing.first['id'] as String;
          if (existingId != id) {
            logDebug('警告: 已存在相同名称的分类 "$name"，但将继续使用指定ID创建');
          }
        }

        // 检查ID是否已被占用
        final existingById = await txn.query(
          'categories',
          where: 'id = ?',
          whereArgs: [id],
        );

        if (existingById.isNotEmpty) {
          // 如果ID已存在，更新此分类
          final categoryMap = {
            'name': name,
            'icon_name': iconName ?? "",
            'last_modified': DateTime.now().toUtc().toIso8601String(),
          };
          await txn.update(
            'categories',
            categoryMap,
            where: 'id = ?',
            whereArgs: [id],
          );
          logDebug('更新ID为 $id 的现有分类为 "$name"');
        } else {
          // 创建新分类，使用指定的ID
          final categoryMap = {
            'id': id,
            'name': name,
            'is_default': 0,
            'icon_name': iconName ?? "",
            'last_modified': DateTime.now().toUtc().toIso8601String(),
          };
          await txn.insert(
            'categories',
            categoryMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          logDebug('使用ID $id 创建新分类 "$name"');
        }
      });

      // 操作成功后更新流和通知侦听器
      await _updateCategoriesStream();
      notifyListeners();
    } catch (e) {
      logDebug('添加指定ID分类失败: $e');
      // 重试一次作为回退方案
      try {
        final categoryMap = {
          'id': id,
          'name': name,
          'is_default': 0,
          'icon_name': iconName ?? "",
          'last_modified': DateTime.now().toUtc().toIso8601String(),
        };
        await db.insert(
          'categories',
          categoryMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _updateCategoriesStream();

        // 修复：导入/恢复完成后必须重建媒体引用，确保引用表准确
        logInfo('导入完成，开始重建媒体引用记录...');
        await MediaReferenceService.migrateExistingQuotes();

        notifyListeners();
        logDebug('通过回退方式成功添加分类');
      } catch (retryError) {
        logDebug('重试添加分类也失败: $retryError');
        throw Exception('无法添加分类: $e');
      }
    }
  }

  /// 监听分类流
  Stream<List<NoteCategory>> watchCategories() {
    _updateCategoriesStream();
    return _categoriesController.stream;
  }

  /// 修复：删除指定分类，增加级联删除和孤立数据清理
  Future<void> deleteCategory(String id) async {
    // 系统标签（如隐藏标签）不允许删除
    if (id == hiddenTagId) {
      throw Exception('系统标签不允许删除');
    }

    if (kIsWeb) {
      _categoryStore.removeWhere((category) => category.id == id);
      _categoriesController.add(_categoryStore);
      notifyListeners();
      return;
    }

    final db = database;

    await db.transaction((txn) async {
      // 1. 检查是否有笔记使用此分类
      final quotesUsingCategory = await txn.query(
        'quotes',
        where: 'category_id = ?',
        whereArgs: [id],
        columns: ['id'],
      );

      // 2. 清理使用此分类的笔记的category_id字段
      if (quotesUsingCategory.isNotEmpty) {
        await txn.update(
          'quotes',
          {'category_id': null},
          where: 'category_id = ?',
          whereArgs: [id],
        );
        logDebug('已清理 ${quotesUsingCategory.length} 条笔记的分类关联');
      }

      // 3. 删除quote_tags表中的相关记录（CASCADE会自动处理，但为了确保一致性）
      final deletedTagRelations = await txn.delete(
        'quote_tags',
        where: 'tag_id = ?',
        whereArgs: [id],
      );

      if (deletedTagRelations > 0) {
        logDebug('已删除 $deletedTagRelations 条标签关联记录');
      }

      // 4. 最后删除分类本身
      await txn.delete('categories', where: 'id = ?', whereArgs: [id]);
    });

    // 清理缓存
    _clearAllCache();

    await _updateCategoriesStream();
    notifyListeners();

    logDebug('分类删除完成，ID: $id');
  }

  Future<void> _updateCategoriesStream() async {
    final categories = await getCategories();
    if (_categoriesController.isClosed) return;
    _categoriesController.add(categories);
  }

  /// 修复：添加一条引用（笔记），增加数据验证和并发控制
  Future<void> addQuote(Quote quote) async {
    // 修复：添加数据验证
    if (!quote.isValid) {
      throw ArgumentError('笔记数据无效，请检查内容、日期和其他字段');
    }

    if (kIsWeb) {
      _memoryStore.add(quote);
      notifyListeners();
      return;
    }

    return _executeWithLock('addQuote_${quote.id ?? 'new'}', () async {
      try {
        final db = await safeDatabase;
        final newQuoteId = quote.id ?? _uuid.v4();
        final quoteWithId =
            quote.id == null ? quote.copyWith(id: newQuoteId) : quote;

        await db.transaction((txn) async {
          final quoteMap = quoteWithId.toJson();
          quoteMap['id'] = newQuoteId;

          // 自动设置 last_modified 时间戳
          final now = DateTime.now().toUtc().toIso8601String();
          if (quoteMap['last_modified'] == null ||
              quoteMap['last_modified'].toString().isEmpty) {
            quoteMap['last_modified'] = now;
          }

          // 自动补全 day_period 字段
          if (quoteMap['date'] != null) {
            final dt = DateTime.tryParse(quoteMap['date']);
            if (dt != null) {
              final hour = dt.hour;
              String dayPeriodKey;
              if (hour >= 5 && hour < 8) {
                dayPeriodKey = 'dawn';
              } else if (hour >= 8 && hour < 12) {
                dayPeriodKey = 'morning';
              } else if (hour >= 12 && hour < 17) {
                dayPeriodKey = 'afternoon';
              } else if (hour >= 17 && hour < 20) {
                dayPeriodKey = 'dusk';
              } else if (hour >= 20 && hour < 23) {
                dayPeriodKey = 'evening';
              } else {
                dayPeriodKey = 'midnight';
              }
              quoteMap['day_period'] = dayPeriodKey;
            }
          }

          // 插入笔记
          await txn.insert(
            'quotes',
            quoteMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          // 修复：插入标签关联，避免事务嵌套
          if (quote.tagIds.isNotEmpty) {
            for (final tagId in quote.tagIds) {
              await txn.insert(
                  'quote_tags',
                  {
                    'quote_id': newQuoteId,
                    'tag_id': tagId,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
        });

        logDebug('笔记已成功保存到数据库，ID: ${quoteWithId.id}');

        // 同步媒体文件引用
        await MediaReferenceService.syncQuoteMediaReferences(quoteWithId);

        // 优化：数据变更后清空缓存
        _clearAllCache();

        // 修复：避免直接操作_currentQuotes，使用刷新机制确保数据一致性
        _refreshQuotesStream();
        notifyListeners(); // 通知其他监听者（如Homepage的FAB）
      } catch (e) {
        logDebug('保存笔记到数据库时出错: $e');
        rethrow; // 重新抛出异常，让调用者处理
      }
    });
  }

  /// 刷新笔记流数据（公开方法）
  void refreshQuotes() {
    _refreshQuotesStream();
  }

  // 在增删改后刷新分页流数据
  void _refreshQuotesStream() {
    if (_quotesController != null && !_quotesController!.isClosed) {
      logDebug('刷新笔记流数据');
      // 优化：清除所有缓存，确保获取最新数据
      _clearAllCache();

      // 重置状态并加载新数据
      _watchOffset = 0;
      _quotesCache = [];
      _watchHasMore = true;
      _currentQuotes = [];
      _currentQuoteIds.clear(); // 性能优化：同步清空 ID Set

      // 触发重新加载
      loadMoreQuotes();
    } else {
      logDebug('笔记流无监听器或已关闭，跳过刷新');
    }
  }

  /// 根据ID获取单个笔记的完整信息
  Future<Quote?> getQuoteById(String id) async {
    if (kIsWeb) {
      try {
        return _memoryStore.firstWhere((q) => q.id == id);
      } catch (e) {
        return null;
      }
    }

    try {
      final db = await safeDatabase;

      // 使用 GROUP_CONCAT 获取关联标签
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT q.*, GROUP_CONCAT(qt.tag_id) as tag_ids
        FROM quotes q
        LEFT JOIN quote_tags qt ON q.id = qt.quote_id
        WHERE q.id = ?
        GROUP BY q.id
      ''', [id]);

      if (maps.isEmpty) {
        return null;
      }

      return Quote.fromJson(maps.first);
    } catch (e) {
      logDebug('获取指定ID笔记失败: $e');
      return null;
    }
  }

  /// 获取笔记列表，支持标签、分类、搜索、天气和时间段筛选
  /// 修复：获取用户笔记，增加初始化状态检查
  Future<List<Quote>> getUserQuotes({
    List<String>? tagIds,
    String? categoryId,
    int offset = 0,
    int limit = 10,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers, // 天气筛选
    List<String>? selectedDayPeriods, // 时间段筛选
    bool excludeHiddenNotes = true, // 默认排除隐藏笔记
  }) async {
    try {
      // 修复：确保数据库已完全初始化
      if (!_isInitialized) {
        logDebug('数据库尚未初始化，等待初始化完成...');
        if (_isInitializing && _initCompleter != null) {
          await _initCompleter!.future;
        } else {
          await init();
        }
      }

      // 优化：定期清理缓存而不是每次查询都清理
      _scheduleCacheCleanup();

      // 判断是否正在查询隐藏标签
      final isQueryingHiddenTag =
          tagIds != null && tagIds.contains(hiddenTagId);
      // 如果正在查询隐藏标签，则不排除隐藏笔记
      final shouldExcludeHidden = excludeHiddenNotes && !isQueryingHiddenTag;

      if (kIsWeb) {
        // Web平台的完整筛选逻辑
        var filtered = _memoryStore;

        // 排除隐藏笔记（除非正在查询隐藏标签）
        if (shouldExcludeHidden) {
          filtered =
              filtered.where((q) => !q.tagIds.contains(hiddenTagId)).toList();
        }

        if (tagIds != null && tagIds.isNotEmpty) {
          filtered = filtered
              .where((q) => q.tagIds.any((tag) => tagIds.contains(tag)))
              .toList();
        }
        if (categoryId != null && categoryId.isNotEmpty) {
          filtered = filtered.where((q) => q.categoryId == categoryId).toList();
        }
        if (searchQuery != null && searchQuery.isNotEmpty) {
          final query = searchQuery.toLowerCase();
          filtered = filtered
              .where(
                (q) =>
                    q.content.toLowerCase().contains(query) ||
                    (q.source?.toLowerCase().contains(query) ?? false) ||
                    (q.sourceAuthor?.toLowerCase().contains(query) ?? false) ||
                    (q.sourceWork?.toLowerCase().contains(query) ?? false),
              )
              .toList();
        }
        if (selectedWeathers != null && selectedWeathers.isNotEmpty) {
          filtered = filtered
              .where(
                (q) =>
                    q.weather != null && selectedWeathers.contains(q.weather),
              )
              .toList();
        }
        if (selectedDayPeriods != null && selectedDayPeriods.isNotEmpty) {
          filtered = filtered
              .where(
                (q) =>
                    q.dayPeriod != null &&
                    selectedDayPeriods.contains(q.dayPeriod),
              )
              .toList();
        }

        // 排序（支持日期、喜爱度、名称）
        filtered.sort((a, b) {
          if (orderBy.startsWith('date')) {
            final dateA = DateTime.tryParse(a.date) ?? DateTime.now();
            final dateB = DateTime.tryParse(b.date) ?? DateTime.now();
            return orderBy.contains('ASC')
                ? dateA.compareTo(dateB)
                : dateB.compareTo(dateA);
          } else if (orderBy.startsWith('favorite_count')) {
            return orderBy.contains('ASC')
                ? a.favoriteCount.compareTo(b.favoriteCount)
                : b.favoriteCount.compareTo(a.favoriteCount);
          } else {
            return orderBy.contains('ASC')
                ? a.content.compareTo(b.content)
                : b.content.compareTo(a.content);
          }
        });

        // 分页 - 修复：确保正确处理边界情况
        final start = offset.clamp(0, filtered.length);
        final end = (offset + limit).clamp(0, filtered.length);

        logDebug(
          'Web分页：总数据${filtered.length}条，offset=$offset，limit=$limit，start=$start，end=$end',
        );

        // 如果起始位置已经超出数据范围，直接返回空列表
        if (start >= filtered.length) {
          logDebug('起始位置超出范围，返回空列表');
          return [];
        }

        final result = filtered.sublist(start, end);
        logDebug('Web分页返回${result.length}条数据');
        return result;
      }

      // 修复：统一查询超时时间和重试机制
      return await _executeQueryWithRetry(() async {
        final db = await safeDatabase; // 使用安全的数据库访问
        return await _performDatabaseQuery(
          db: db,
          tagIds: tagIds,
          categoryId: categoryId,
          searchQuery: searchQuery,
          selectedWeathers: selectedWeathers,
          selectedDayPeriods: selectedDayPeriods,
          orderBy: orderBy,
          limit: limit,
          offset: offset,
          excludeHiddenNotes: shouldExcludeHidden,
        );
      });
    } catch (e) {
      logError('获取笔记失败: $e', error: e, source: 'DatabaseService');
      return [];
    }
  }

  /// 修复：带重试机制的查询执行
  Future<T> _executeQueryWithRetry<T>(
    Future<T> Function() query, {
    int maxRetries = 2,
    Duration? timeout,
  }) async {
    // 修复：根据平台调整超时时间
    timeout ??= _getOptimalTimeout();
    final actualTimeout = timeout; // 确保非空

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final completer = Completer<T>();
        Timer? timeoutTimer;

        timeoutTimer = Timer(actualTimeout, () {
          if (!completer.isCompleted) {
            logError(
              '数据库查询超时（${actualTimeout.inSeconds}秒）',
              source: 'DatabaseService',
            );
            completer.completeError(TimeoutException('数据库查询超时', actualTimeout));
          }
        });

        // 异步执行查询
        query().then((result) {
          timeoutTimer?.cancel();
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        }).catchError((error) {
          timeoutTimer?.cancel();
          if (!completer.isCompleted) {
            logError(
              '数据库查询失败: $error',
              error: error,
              source: 'DatabaseService',
            );
            completer.completeError(error);
          }
        });

        final result = await completer.future;
        timeoutTimer.cancel();
        return result;
      } catch (e) {
        if (attempt == maxRetries - 1) {
          // 最后一次尝试失败
          if (e is TimeoutException) {
            rethrow;
          }
          rethrow;
        }

        // 如果是超时异常，等待后重试
        if (e is TimeoutException) {
          logDebug('查询超时，准备重试 (${attempt + 1}/$maxRetries)');
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        } else {
          // 其他异常直接抛出
          rethrow;
        }
      }
    }

    throw Exception('查询重试失败');
  }

  /// 修复：根据平台和设备性能获取最优超时时间
  Duration _getOptimalTimeout() {
    if (kIsWeb) {
      return const Duration(seconds: 8); // Web平台网络延迟较高
    } else if (Platform.isAndroid) {
      return const Duration(seconds: 10); // Android设备性能差异较大
    } else if (Platform.isIOS) {
      return const Duration(seconds: 6); // iOS设备性能相对稳定
    } else {
      return const Duration(seconds: 8); // 桌面平台
    }
  }

  /// 执行实际的数据库查询（修复版本）
  Future<List<Quote>> _performDatabaseQuery({
    required Database db,
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    required String orderBy,
    required int limit,
    required int offset,
    bool excludeHiddenNotes = true,
  }) async {
    // 修复：添加数据库连接状态检查
    if (!db.isOpen) {
      throw Exception('数据库连接已关闭');
    }
    // 优化：使用单一查询替代两步查询，减少数据库往返
    List<String> conditions = [];
    List<dynamic> args = [];
    String fromClause = 'FROM quotes q';
    String joinClause = '';
    String groupByClause = '';
    String havingClause = '';

    // 排除隐藏笔记（如果需要）
    if (excludeHiddenNotes) {
      conditions.add('''
        NOT EXISTS (
          SELECT 1 FROM quote_tags qt_hidden
          WHERE qt_hidden.quote_id = q.id
          AND qt_hidden.tag_id = ?
        )
      ''');
      args.add(hiddenTagId);
    }

    // 分类筛选
    if (categoryId != null && categoryId.isNotEmpty) {
      conditions.add('q.category_id = ?');
      args.add(categoryId);
    }

    // 优化：搜索查询使用FTS（全文搜索）如果可用，否则使用优化的LIKE查询
    if (searchQuery != null && searchQuery.isNotEmpty) {
      // 使用更高效的搜索策略：优先匹配内容，然后匹配其他字段
      conditions.add(
        '(q.content LIKE ? OR (q.source LIKE ? OR q.source_author LIKE ? OR q.source_work LIKE ?))',
      );
      final searchParam = '%$searchQuery%';
      args.addAll([searchParam, searchParam, searchParam, searchParam]);
    }

    // 天气筛选
    if (selectedWeathers != null && selectedWeathers.isNotEmpty) {
      final weatherPlaceholders = selectedWeathers.map((_) => '?').join(',');
      conditions.add('q.weather IN ($weatherPlaceholders)');
      args.addAll(selectedWeathers);
    }

    // 时间段筛选
    if (selectedDayPeriods != null && selectedDayPeriods.isNotEmpty) {
      final dayPeriodPlaceholders =
          selectedDayPeriods.map((_) => '?').join(',');
      conditions.add('q.day_period IN ($dayPeriodPlaceholders)');
      args.addAll(selectedDayPeriods);
    }

    /// 修复：优化标签筛选查询，减少复杂度
    /// 关键修复：始终使用独立的 LEFT JOIN 获取所有标签，不受筛选条件影响
    if (tagIds != null && tagIds.isNotEmpty) {
      if (tagIds.length == 1) {
        // 单标签查询：使用简单的INNER JOIN筛选，但用另一个JOIN获取所有标签
        conditions.add('''
          EXISTS (
            SELECT 1 FROM quote_tags qt_filter
            WHERE qt_filter.quote_id = q.id
            AND qt_filter.tag_id = ?
          )
        ''');
        args.add(tagIds.first);
      } else {
        // 多标签查询：使用EXISTS确保所有标签都匹配
        final tagPlaceholders = tagIds.map((_) => '?').join(',');
        conditions.add('''
          EXISTS (
            SELECT 1 FROM quote_tags qt_filter
            WHERE qt_filter.quote_id = q.id
            AND qt_filter.tag_id IN ($tagPlaceholders)
            GROUP BY qt_filter.quote_id
            HAVING COUNT(DISTINCT qt_filter.tag_id) = ?
          )
        ''');
        args.addAll(tagIds);
        args.add(tagIds.length);
      }
    }

    // 始终使用独立的 LEFT JOIN 来获取所有标签（不受筛选条件影响）
    joinClause = 'LEFT JOIN quote_tags qt ON q.id = qt.quote_id';
    groupByClause = 'GROUP BY q.id';

    final where =
        conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

    final orderByParts = orderBy.split(' ');
    final correctedOrderBy =
        'q.${orderByParts[0]} ${orderByParts.length > 1 ? orderByParts[1] : ''}';

    /// 修复：始终使用 qt.tag_id 获取所有标签
    // 优化：指定查询列，排除大文本字段(ai_analysis, summary等)以提升列表加载性能
    // 注意：delta_content 必须保留！列表卡片通过 QuoteContent 组件渲染富文本（加粗、图片等）
    final query = '''
      SELECT
        q.id, q.content, q.date, q.source, q.source_author, q.source_work,
        q.category_id, q.color_hex, q.location, q.latitude, q.longitude,
        q.weather, q.temperature, q.edit_source, q.delta_content, q.day_period,
        q.last_modified, q.favorite_count,
        GROUP_CONCAT(qt.tag_id) as tag_ids
      $fromClause
      $joinClause
      $where
      $groupByClause
      $havingClause
      ORDER BY $correctedOrderBy
      LIMIT ? OFFSET ?
    ''';

    args.addAll([limit, offset]);

    logDebug('执行优化查询: $query\n参数: $args');

    /// 修复：增强查询性能监控和慢查询检测
    final stopwatch = Stopwatch()..start();
    final maps = await db.rawQuery(query, args);
    stopwatch.stop();

    final queryTime = stopwatch.elapsedMilliseconds;

    // 记录查询统计（用于性能分析）
    _recordQueryStats('getQuotesCount', queryTime);

    // 慢查询检测和警告（阈值降低到100ms，更敏感）
    if (queryTime > 100) {
      final level = queryTime > 1000
          ? '🔴 严重慢查询'
          : queryTime > 500
              ? '⚠️ 慢查询警告'
              : 'ℹ️ 性能提示';
      logDebug('$level: 查询耗时 ${queryTime}ms');

      if (queryTime > 500) {
        logDebug('慢查询SQL: $query');
        logDebug('查询参数: $args');

        // 可选：记录查询执行计划用于优化
        try {
          final plan = await db.rawQuery('EXPLAIN QUERY PLAN $query', args);
          logDebug('查询执行计划:');
          for (final step in plan) {
            logDebug('  ${step['detail']}');
          }
        } catch (e) {
          logDebug('获取查询执行计划失败: $e');
        }
      }
    }

    logDebug('查询完成，耗时: ${queryTime}ms，结果数量: ${maps.length}');

    // 更新性能统计
    _updateQueryStats('getUserQuotes', queryTime);

    return maps.map((m) => Quote.fromJson(m)).toList();
  }

  /// 修复：更新查询性能统计
  void _updateQueryStats(String queryType, int timeMs) {
    _healthService.recordQueryStats(queryType, timeMs);
  }

  /// 记录查询统计（_updateQueryStats的别名，保持代码一致性）
  void _recordQueryStats(String queryType, int timeMs) {
    _updateQueryStats(queryType, timeMs);
  }

  /// 智能推送专用轻量查询
  ///
  /// 不加载大字段（delta_content, ai_analysis, summary, keywords），
  /// 不 JOIN tag 表，专为后台 isolate 设计，低内存开销。
  Future<List<Quote>> getQuotesForSmartPush({
    String? whereSql,
    List<Object?>? whereArgs,
    int limit = 200,
    String orderBy = 'q.date DESC',
  }) async {
    try {
      if (!_isInitialized) {
        if (_isInitializing && _initCompleter != null) {
          await _initCompleter!.future;
        } else {
          await init();
        }
      }

      if (kIsWeb) {
        // Web 平台降级：使用内存存储
        var filtered = _memoryStore;
        filtered.sort((a, b) {
          final dateA = DateTime.tryParse(a.date) ?? DateTime.now();
          final dateB = DateTime.tryParse(b.date) ?? DateTime.now();
          return dateB.compareTo(dateA);
        });
        return filtered.take(limit).toList();
      }

      final db = await safeDatabase;

      final conditions = <String>[];
      final args = <Object?>[];

      // 排除隐藏笔记
      conditions.add('''
        NOT EXISTS (
          SELECT 1 FROM quote_tags qt_hidden
          WHERE qt_hidden.quote_id = q.id
          AND qt_hidden.tag_id = ?
        )
      ''');
      args.add(hiddenTagId);

      if (whereSql != null && whereSql.isNotEmpty) {
        conditions.add(whereSql);
        if (whereArgs != null) {
          args.addAll(whereArgs);
        }
      }

      final where =
          conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

      // 只取必要列，不取 delta_content/ai_analysis/summary/keywords
      final query = '''
        SELECT q.id, q.content, q.date, q.source, q.source_author, q.source_work,
               q.category_id, q.color_hex, q.location, q.latitude, q.longitude,
               q.weather, q.temperature, q.edit_source, q.day_period,
               q.last_modified, q.favorite_count
        FROM quotes q
        $where
        ORDER BY $orderBy
        LIMIT ?
      ''';
      args.add(limit);

      final maps = await db.rawQuery(query, args.whereType<Object>().toList());
      return maps.map((m) => Quote.fromJson(m)).toList();
    } catch (e) {
      logError('getQuotesForSmartPush 失败: $e',
          error: e, source: 'DatabaseService');
      return [];
    }
  }

  /// 智能推送专用：获取笔记创建时间的小时分布（纯聚合，不加载内容）
  Future<List<int>> getHourDistributionForSmartPush() async {
    final distribution = List<int>.filled(24, 0);
    try {
      if (!_isInitialized) {
        if (_isInitializing && _initCompleter != null) {
          await _initCompleter!.future;
        } else {
          await init();
        }
      }

      if (kIsWeb) {
        for (final note in _memoryStore) {
          final d = DateTime.tryParse(note.date);
          if (d != null) distribution[d.hour]++;
        }
        return distribution;
      }

      final db = await safeDatabase;
      final maps = await db.rawQuery('''
        SELECT CAST(substr(date, 12, 2) AS INTEGER) AS h, COUNT(*) AS c
        FROM quotes
        GROUP BY h
      ''');
      for (final row in maps) {
        final h = (row['h'] as int?) ?? 0;
        final c = (row['c'] as int?) ?? 0;
        if (h >= 0 && h < 24) {
          distribution[h] = c;
        }
      }
    } catch (e) {
      logError('getHourDistributionForSmartPush 失败: $e',
          error: e, source: 'DatabaseService');
    }
    return distribution;
  }

  /// 修复：获取查询性能报告
  Map<String, dynamic> getQueryPerformanceReport() {
    return _healthService.getQueryPerformanceReport();
  }

  /// 修复：安全地创建索引，检查列是否存在
  Future<void> _createIndexSafely(
    Database db,
    String tableName,
    String columnName,
    String indexName,
  ) async {
    await _healthService.createIndexSafely(
      db,
      tableName,
      columnName,
      indexName,
    );
  }

  /// 修复：检查列是否存在
  Future<bool> _checkColumnExists(
    Database db,
    String tableName,
    String columnName,
  ) async {
    return _healthService.checkColumnExists(db, tableName, columnName);
  }

  /// 启动时执行数据库健康检查
  Future<void> _performStartupHealthCheck() async {
    await _healthService.performStartupHealthCheck(await safeDatabase);
  }

  /// 修复：标签数据一致性检查
  Future<Map<String, dynamic>> checkTagDataConsistency() async {
    return _healthService.checkTagDataConsistency(await safeDatabase);
  }

  /// 修复：清理标签数据不一致问题
  Future<bool> cleanupTagDataInconsistencies() async {
    final result =
        await _healthService.cleanupTagDataInconsistencies(await safeDatabase);
    _clearAllCache();
    return result;
  }

  /// 获取所有笔记
  /// [excludeHiddenNotes] 是否排除隐藏笔记，默认为 true
  /// 注意：媒体引用迁移等需要访问全部数据的场景应传入 false
  Future<List<Quote>> getAllQuotes({bool excludeHiddenNotes = true}) async {
    if (kIsWeb) {
      var result = List<Quote>.from(_memoryStore);
      if (excludeHiddenNotes) {
        result = result.where((q) => !q.tagIds.contains(hiddenTagId)).toList();
      }
      return result;
    }

    try {
      final db = await safeDatabase;

      // 修复：使用 LEFT JOIN 获取笔记及其关联的标签
      // 这样可以正确获取每个笔记的 tagIds
      final String query = '''
        SELECT q.*, GROUP_CONCAT(qt.tag_id) as tag_ids
        FROM quotes q
        LEFT JOIN quote_tags qt ON q.id = qt.quote_id
        ${excludeHiddenNotes ? '''
        WHERE NOT EXISTS (
          SELECT 1 FROM quote_tags qt_hidden
          WHERE qt_hidden.quote_id = q.id
          AND qt_hidden.tag_id = ?
        )
        ''' : ''}
        GROUP BY q.id
      ''';

      final List<Map<String, dynamic>> maps = excludeHiddenNotes
          ? await db.rawQuery(query, [hiddenTagId])
          : await db.rawQuery(query);

      return maps.map((m) => Quote.fromJson(m)).toList();
    } catch (e) {
      logDebug('获取所有笔记失败: $e');
      return [];
    }
  }

  /// 获取笔记总数，用于分页
  /// [excludeHiddenNotes] 是否排除隐藏笔记，默认为 true
  Future<int> getQuotesCount({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool excludeHiddenNotes = true,
  }) async {
    // 判断是否正在查询隐藏标签
    final isQueryingHiddenTag = tagIds != null && tagIds.contains(hiddenTagId);
    // 如果正在查询隐藏标签，则不排除隐藏笔记
    final shouldExcludeHidden = excludeHiddenNotes && !isQueryingHiddenTag;

    if (kIsWeb) {
      // 优化：Web平台直接在内存中应用筛选逻辑计算数量，避免加载大量数据
      var filtered = _memoryStore;

      // 排除隐藏笔记
      if (shouldExcludeHidden) {
        filtered =
            filtered.where((q) => !q.tagIds.contains(hiddenTagId)).toList();
      }

      if (tagIds != null && tagIds.isNotEmpty) {
        filtered = filtered
            .where((q) => q.tagIds.any((tag) => tagIds.contains(tag)))
            .toList();
      }

      if (categoryId != null && categoryId.isNotEmpty) {
        filtered = filtered.where((q) => q.categoryId == categoryId).toList();
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final query = searchQuery.toLowerCase();
        filtered = filtered
            .where(
              (q) =>
                  q.content.toLowerCase().contains(query) ||
                  (q.source?.toLowerCase().contains(query) ?? false) ||
                  (q.sourceAuthor?.toLowerCase().contains(query) ?? false) ||
                  (q.sourceWork?.toLowerCase().contains(query) ?? false),
            )
            .toList();
      }

      if (selectedWeathers != null && selectedWeathers.isNotEmpty) {
        filtered = filtered
            .where(
              (q) => q.weather != null && selectedWeathers.contains(q.weather),
            )
            .toList();
      }

      if (selectedDayPeriods != null && selectedDayPeriods.isNotEmpty) {
        filtered = filtered
            .where(
              (q) =>
                  q.dayPeriod != null &&
                  selectedDayPeriods.contains(q.dayPeriod),
            )
            .toList();
      }

      return filtered.length;
    }
    try {
      final db = await safeDatabase;
      List<String> conditions = [];
      List<dynamic> args = [];

      // 排除隐藏笔记（通过 NOT EXISTS 子查询排除带有隐藏标签的笔记）
      if (shouldExcludeHidden) {
        conditions.add('''
          NOT EXISTS (
            SELECT 1 FROM quote_tags ht 
            WHERE ht.quote_id = q.id AND ht.tag_id = ?
          )
        ''');
        args.add(hiddenTagId);
      }

      // 分类筛选
      if (categoryId != null && categoryId.isNotEmpty) {
        conditions.add('q.category_id = ?');
        args.add(categoryId);
      }

      // 搜索查询
      if (searchQuery != null && searchQuery.isNotEmpty) {
        conditions.add(
          '(q.content LIKE ? OR q.source LIKE ? OR q.source_author LIKE ? OR q.source_work LIKE ?)',
        );
        final searchParam = '%$searchQuery%';
        args.addAll([searchParam, searchParam, searchParam, searchParam]);
      }

      // 天气筛选
      if (selectedWeathers != null && selectedWeathers.isNotEmpty) {
        final weatherPlaceholders = selectedWeathers.map((_) => '?').join(',');
        conditions.add('q.weather IN ($weatherPlaceholders)');
        args.addAll(selectedWeathers);
      }

      // 时间段筛选
      if (selectedDayPeriods != null && selectedDayPeriods.isNotEmpty) {
        final dayPeriodPlaceholders =
            selectedDayPeriods.map((_) => '?').join(',');
        conditions.add('q.day_period IN ($dayPeriodPlaceholders)');
        args.addAll(selectedDayPeriods);
      }

      String query;
      List<dynamic> finalArgs = List.from(args);

      if (tagIds != null && tagIds.isNotEmpty) {
        // 使用 INNER JOIN 和 GROUP BY 来进行计数
        final tagPlaceholders = tagIds.map((_) => '?').join(',');

        String subQuery = '''
          SELECT 1
          FROM quotes q
          INNER JOIN quote_tags qt ON q.id = qt.quote_id
        ''';

        conditions.add('qt.tag_id IN ($tagPlaceholders)');
        finalArgs.addAll(tagIds);

        final whereClause =
            conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

        String havingClause = 'HAVING COUNT(DISTINCT qt.tag_id) = ?';
        finalArgs.add(tagIds.length);

        query = '''
          SELECT COUNT(*) FROM (
            $subQuery
            $whereClause
            GROUP BY q.id
            $havingClause
          )
        ''';
      } else {
        // 没有标签筛选，使用简单的 COUNT
        final whereClause =
            conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';
        query = 'SELECT COUNT(*) as count FROM quotes q $whereClause';
      }

      logDebug('执行计数查询: $query\n参数: $finalArgs');
      final result = await db.rawQuery(query, finalArgs);
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      logDebug('获取笔记总数错误: $e');
      return 0;
    }
  }

  /// 修复：删除指定的笔记，增加数据验证和错误处理
  Future<void> deleteQuote(String id) async {
    // 修复：添加参数验证
    if (id.isEmpty) {
      throw ArgumentError('笔记ID不能为空');
    }

    if (kIsWeb) {
      _memoryStore.removeWhere((quote) => quote.id == id);
      notifyListeners();
      _refreshQuotesStream();
      return;
    }

    return _executeWithLock('deleteQuote_$id', () async {
      try {
        final db = await safeDatabase;

        // 先检查笔记是否存在
        final existingQuote = await db.query(
          'quotes',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );

        if (existingQuote.isEmpty) {
          logDebug('要删除的笔记不存在: $id');
          return; // 笔记不存在，直接返回
        }

        // 先获取笔记引用的媒体文件列表（来自引用表）
        final referencedFiles = await MediaReferenceService.getReferencedFiles(
          id,
        );

        // 同时从笔记内容本身提取媒体路径，避免引用表不同步导致遗漏
        final Set<String> mediaPathsToCheck = {...referencedFiles};
        try {
          final quoteRow = existingQuote.first;
          final quoteFromDb = Quote.fromJson(quoteRow);
          final extracted =
              await MediaReferenceService.extractMediaPathsFromQuote(
            quoteFromDb,
          );
          mediaPathsToCheck.addAll(extracted);
        } catch (e) {
          logDebug('从笔记内容提取媒体路径失败，继续使用引用表: $e');
        }

        await db.transaction((txn) async {
          // 由于设置了 ON DELETE CASCADE，quote_tags 表中的相关条目会自动删除
          // 但为了明确起见，我们也可以手动删除
          // await txn.delete('quote_tags', where: 'quote_id = ?', whereArgs: [id]);
          await txn.delete('quotes', where: 'id = ?', whereArgs: [id]);
        });

        // 移除媒体文件引用（CASCADE会自动删除，但为了确保一致性）
        await MediaReferenceService.removeAllReferencesForQuote(id);

        // 使用轻量级检查机制清理孤儿媒体文件（合并来源：引用表 + 内容提取）
        // 注：removeAllReferencesForQuote 已经清理了引用表，这里只需查引用计数
        for (final storedPath in mediaPathsToCheck) {
          try {
            // storedPath 可能是相对路径（相对于应用文档目录）
            String absolutePath = storedPath;
            try {
              // 使用 path.isAbsolute 来判断是否为绝对路径，兼容 Windows/Linux/macOS
              if (!isAbsolute(absolutePath)) {
                // 简单判断相对路径
                final appDir = await getApplicationDocumentsDirectory();
                absolutePath = join(appDir.path, storedPath);
              }
            } catch (_) {}

            // 使用轻量级检查（仅查引用表计数）
            final deleted =
                await MediaReferenceService.quickCheckAndDeleteIfOrphan(
              absolutePath,
            );
            if (deleted) {
              logDebug('已清理孤儿媒体文件: $absolutePath (原始记录: $storedPath)');
            }
          } catch (e) {
            logDebug('清理孤儿媒体文件失败: $storedPath, 错误: $e');
          }
        }

        // 清理缓存
        _clearAllCache();

        // 修复问题1：清理富文本控制器缓存
        QuoteContent.removeCacheForQuote(id);

        // 直接从内存中移除并通知
        _currentQuotes.removeWhere((quote) => quote.id == id);
        if (_quotesController != null && !_quotesController!.isClosed) {
          _quotesController!.add(List.from(_currentQuotes));
        }
        notifyListeners();

        logDebug('笔记删除完成，ID: $id');
      } catch (e) {
        logDebug('删除笔记时出错: $e');
        rethrow;
      }
    });
  }

  /// 根据内容搜索笔记（用于媒体引用校验等内部逻辑）
  Future<List<Quote>> searchQuotesByContent(String query) async {
    if (kIsWeb) {
      return _memoryStore
          .where((q) =>
              (q.content.contains(query)) ||
              (q.deltaContent != null && q.deltaContent!.contains(query)))
          .toList();
    }

    final db = await safeDatabase;
    final List<Map<String, dynamic>> results = await db.query(
      'quotes',
      where: 'content LIKE ? OR delta_content LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
    );

    return results.map((map) => Quote.fromJson(map)).toList();
  }

  /// 修复：更新笔记内容，增加数据验证和并发控制
  Future<void> updateQuote(Quote quote) async {
    // 修复：添加数据验证
    if (quote.id == null || quote.id!.isEmpty) {
      throw ArgumentError('更新笔记时ID不能为空');
    }

    if (!quote.isValid) {
      throw ArgumentError('笔记数据无效，请检查内容、日期和其他字段');
    }

    if (kIsWeb) {
      final index = _memoryStore.indexWhere((q) => q.id == quote.id);
      if (index != -1) {
        _memoryStore[index] = quote;
        notifyListeners();
      }
      return;
    }

    return _executeWithLock('updateQuote_${quote.id}', () async {
      try {
        final db = await safeDatabase;
        // 在更新前记录旧的媒体引用，用于更新后判断是否需要清理文件
        final List<String> oldReferencedFiles =
            await MediaReferenceService.getReferencedFiles(quote.id!);
        await db.transaction((txn) async {
          final quoteMap = quote.toJson();

          // 更新时总是刷新 last_modified 时间戳
          final now = DateTime.now().toUtc().toIso8601String();
          quoteMap['last_modified'] = now;

          // 自动补全 day_period 字段
          if (quoteMap['date'] != null) {
            final dt = DateTime.tryParse(quoteMap['date']);
            if (dt != null) {
              final hour = dt.hour;
              String dayPeriodKey;
              if (hour >= 5 && hour < 8) {
                dayPeriodKey = 'dawn';
              } else if (hour >= 8 && hour < 12) {
                dayPeriodKey = 'morning';
              } else if (hour >= 12 && hour < 17) {
                dayPeriodKey = 'afternoon';
              } else if (hour >= 17 && hour < 20) {
                dayPeriodKey = 'dusk';
              } else if (hour >= 20 && hour < 23) {
                dayPeriodKey = 'evening';
              } else {
                dayPeriodKey = 'midnight';
              }
              quoteMap['day_period'] = dayPeriodKey;
            }
          }

          // 1. 更新笔记本身
          await txn.update(
            'quotes',
            quoteMap,
            where: 'id = ?',
            whereArgs: [quote.id],
          );

          // 2. 删除旧的标签关联
          await txn.delete(
            'quote_tags',
            where: 'quote_id = ?',
            whereArgs: [quote.id],
          );

          /// 修复：插入新的标签关联，避免事务嵌套
          if (quote.tagIds.isNotEmpty) {
            for (final tagId in quote.tagIds) {
              await txn.insert(
                  'quote_tags',
                  {
                    'quote_id': quote.id!,
                    'tag_id': tagId,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }

          // 3. 同步媒体引用，确保与内容更新保持原子性
          await MediaReferenceService.syncQuoteMediaReferencesWithTransaction(
            txn,
            quote,
          );
        });

        logDebug('笔记已成功更新，ID: ${quote.id}');

        // 使用轻量级检查机制清理因内容变更而不再被引用的媒体文件
        for (final storedPath in oldReferencedFiles) {
          try {
            String absolutePath = storedPath;
            if (!absolutePath.startsWith('/') && !absolutePath.contains(':')) {
              final appDir = await getApplicationDocumentsDirectory();
              absolutePath = join(appDir.path, storedPath);
            }

            // 使用增强版的 quickCheckAndDeleteIfOrphan（包含内容二次校验）
            final deleted =
                await MediaReferenceService.quickCheckAndDeleteIfOrphan(
              absolutePath,
            );
            if (deleted) {
              logDebug('已清理无引用媒体文件: $absolutePath');
            }
          } catch (e) {
            logDebug('清理无引用媒体文件失败: $storedPath, 错误: $e');
          }
        }

        // 更新内存中的笔记列表
        final index = _currentQuotes.indexWhere((q) => q.id == quote.id);
        if (index != -1) {
          _currentQuotes[index] = quote;
        }

        // 修复问题1：更新笔记后清理旧缓存，确保显示最新内容
        QuoteContent.removeCacheForQuote(quote.id!);

        if (_quotesController != null && !_quotesController!.isClosed) {
          _quotesController!.add(List.from(_currentQuotes));
        }
        notifyListeners(); // 通知其他监听者
      } catch (e) {
        logDebug('更新笔记时出错: $e');
        rethrow; // 重新抛出异常，让调用者处理
      }
    });
  }

  /// 增加笔记的心形点击次数
  Future<void> incrementFavoriteCount(String quoteId) async {
    if (quoteId.isEmpty) {
      throw ArgumentError('笔记ID不能为空');
    }

    if (kIsWeb) {
      final index = _memoryStore.indexWhere((q) => q.id == quoteId);
      if (index != -1) {
        final oldCount = _memoryStore[index].favoriteCount;
        _memoryStore[index] = _memoryStore[index].copyWith(
          favoriteCount: oldCount + 1,
        );
        logDebug(
          'Web平台收藏操作: quoteId=$quoteId, 旧值=$oldCount, 新值=${oldCount + 1}',
          source: 'IncrementFavorite',
        );

        // 同步更新当前流缓存并推送
        final curIndex = _currentQuotes.indexWhere((q) => q.id == quoteId);
        if (curIndex != -1) {
          _currentQuotes[curIndex] = _currentQuotes[curIndex].copyWith(
            favoriteCount: _currentQuotes[curIndex].favoriteCount + 1,
          );
          if (_quotesController != null && !_quotesController!.isClosed) {
            _quotesController!.add(List.from(_currentQuotes));
          }
        }
        notifyListeners();
      } else {
        logWarning(
          'Web平台收藏操作失败: 未找到quoteId=$quoteId',
          source: 'IncrementFavorite',
        );
      }
      return;
    }

    return _executeWithLock('incrementFavorite_$quoteId', () async {
      try {
        // 记录操作前的状态
        final index = _currentQuotes.indexWhere((q) => q.id == quoteId);
        final oldCount =
            index != -1 ? _currentQuotes[index].favoriteCount : null;
        logDebug(
          '收藏操作开始: quoteId=$quoteId, 内存旧值=$oldCount',
          source: 'IncrementFavorite',
        );

        final db = await safeDatabase;
        await db.transaction((txn) async {
          // 原子性地增加计数
          final updateCount = await txn.rawUpdate(
            'UPDATE quotes SET favorite_count = favorite_count + 1, last_modified = ? WHERE id = ?',
            [DateTime.now().toUtc().toIso8601String(), quoteId],
          );

          if (updateCount == 0) {
            logWarning(
              '收藏操作失败: 数据库中未找到quoteId=$quoteId',
              source: 'IncrementFavorite',
            );
          } else {
            // 查询更新后的值进行验证
            final result = await txn.rawQuery(
              'SELECT favorite_count FROM quotes WHERE id = ?',
              [quoteId],
            );
            final newCount = result.isNotEmpty
                ? (result.first['favorite_count'] as int?) ?? 0
                : 0;
            logInfo(
              '收藏操作成功: quoteId=$quoteId, 旧值=$oldCount, 数据库新值=$newCount',
              source: 'IncrementFavorite',
            );
          }
        });

        // 更新内存中的笔记列表
        if (index != -1) {
          _currentQuotes[index] = _currentQuotes[index].copyWith(
            favoriteCount: _currentQuotes[index].favoriteCount + 1,
          );
          logDebug(
            '内存缓存已更新: 新值=${_currentQuotes[index].favoriteCount}',
            source: 'IncrementFavorite',
          );
        }
        if (_quotesController != null && !_quotesController!.isClosed) {
          _quotesController!.add(List.from(_currentQuotes));
        }
        notifyListeners();
      } catch (e) {
        logError(
          '增加心形点击次数时出错: quoteId=$quoteId, error=$e',
          error: e,
          source: 'IncrementFavorite',
        );
        rethrow;
      }
    });
  }

  /// 重置心形点击次数为0（清除收藏）
  Future<void> resetFavoriteCount(String quoteId) async {
    if (quoteId.isEmpty) {
      throw ArgumentError('笔记ID不能为空');
    }

    if (kIsWeb) {
      final index = _memoryStore.indexWhere((q) => q.id == quoteId);
      if (index != -1) {
        _memoryStore[index] = _memoryStore[index].copyWith(
          favoriteCount: 0,
        );
        logDebug(
          'Web平台清除收藏: quoteId=$quoteId',
          source: 'ResetFavorite',
        );
      }

      final curIndex = _currentQuotes.indexWhere((q) => q.id == quoteId);
      if (curIndex != -1) {
        _currentQuotes[curIndex] = _currentQuotes[curIndex].copyWith(
          favoriteCount: 0,
        );
      }

      if (_quotesController != null && !_quotesController!.isClosed) {
        _quotesController!.add(List.from(_currentQuotes));
      }
      notifyListeners();
      return;
    }

    return _executeWithLock('resetFavorite_$quoteId', () async {
      try {
        final index = _currentQuotes.indexWhere((q) => q.id == quoteId);
        final oldCount =
            index != -1 ? _currentQuotes[index].favoriteCount : null;
        logDebug(
          '清除收藏操作开始: quoteId=$quoteId, 内存旧值=$oldCount',
          source: 'ResetFavorite',
        );

        final db = await safeDatabase;
        await db.transaction((txn) async {
          final updateCount = await txn.rawUpdate(
            'UPDATE quotes SET favorite_count = 0, last_modified = ? WHERE id = ?',
            [DateTime.now().toUtc().toIso8601String(), quoteId],
          );

          if (updateCount == 0) {
            logWarning(
              '清除收藏失败: 数据库中未找到quoteId=$quoteId',
              source: 'ResetFavorite',
            );
          } else {
            logInfo(
              '清除收藏成功: quoteId=$quoteId, 旧值=$oldCount, 新值=0',
              source: 'ResetFavorite',
            );
          }
        });

        // 更新内存中的笔记列表
        if (index != -1) {
          _currentQuotes[index] = _currentQuotes[index].copyWith(
            favoriteCount: 0,
          );
          logDebug(
            '内存缓存已更新: 新值=0',
            source: 'ResetFavorite',
          );
        }
        if (_quotesController != null && !_quotesController!.isClosed) {
          _quotesController!.add(List.from(_currentQuotes));
        }
        notifyListeners();
      } catch (e) {
        logError(
          '清除收藏时出错: quoteId=$quoteId, error=$e',
          error: e,
          source: 'ResetFavorite',
        );
        rethrow;
      }
    });
  }

  /// 获取本周期内点心最多的笔记
  Future<List<Quote>> getMostFavoritedQuotesThisWeek({int limit = 5}) async {
    if (kIsWeb) {
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartString = weekStart.toIso8601String().substring(0, 10);

      return _memoryStore
          .where(
            (q) =>
                q.date.compareTo(weekStartString) >= 0 && q.favoriteCount > 0,
          )
          .toList()
        ..sort((a, b) => b.favoriteCount.compareTo(a.favoriteCount))
        ..take(limit).toList();
    }

    try {
      final db = await safeDatabase;
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartString = weekStart.toIso8601String().substring(0, 10);

      final List<Map<String, dynamic>> results = await db.query(
        'quotes',
        where: 'date >= ? AND favorite_count > 0',
        whereArgs: [weekStartString],
        orderBy: 'favorite_count DESC, date DESC',
        limit: limit,
      );

      return results.map((map) => Quote.fromJson(map)).toList();
    } catch (e) {
      logError('获取本周最受喜爱笔记时出错: $e', error: e, source: 'GetMostFavorited');
      return [];
    }
  }

  /// 监听笔记列表，支持分页加载和筛选

  /// 修复：监听笔记列表，支持分页加载和筛选
  /// 修复：观察笔记流，增加初始化状态检查
  Stream<List<Quote>> watchQuotes({
    List<String>? tagIds,
    String? categoryId,
    int limit = 20,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers, // 天气筛选
    List<String>? selectedDayPeriods, // 时间段筛选
  }) {
    // 修复：如果数据库未初始化，先返回空流并等待初始化
    if (!_isInitialized) {
      logDebug('数据库尚未初始化，返回空流并等待初始化...');

      // 创建一个临时的流控制器
      final tempController = StreamController<List<Quote>>.broadcast();
      tempController.add([]); // 立即发送空列表

      // 异步等待初始化完成后重新调用
      Future.microtask(() async {
        try {
          if (_isInitializing && _initCompleter != null) {
            await _initCompleter!.future;
          } else if (!_isInitialized) {
            await init();
          }

          // 修复：初始化完成后，通知UI重新订阅
          logDebug('数据库初始化完成，通知UI重新订阅数据流');
          tempController.close();

          // 针对安卓平台的特殊处理
          if (!kIsWeb && Platform.isAndroid) {
            // 安卓平台延迟更长时间通知，确保UI完全准备好
            Future.delayed(const Duration(milliseconds: 300), () {
              notifyListeners();
            });
          } else {
            // 其他平台立即通知
            WidgetsBinding.instance.addPostFrameCallback((_) {
              notifyListeners();
            });
          }
        } catch (e) {
          logError('等待数据库初始化失败: $e', error: e, source: 'watchQuotes');
          tempController.addError(e);
        }
      });

      return tempController.stream;
    }
    // 检查是否有筛选条件改变
    bool hasFilterChanged = false;

    // 修复：检查是否是首次调用
    bool isFirstCall =
        (_quotesController == null || _quotesController!.isClosed) ||
            (_currentQuotes.isEmpty);

    logDebug(
      'watchQuotes调用 - isFirstCall: $isFirstCall, hasController: ${_quotesController != null}, '
      'currentQuotesCount: ${_currentQuotes.length}, tagIds: $tagIds, categoryId: $categoryId',
    );

    // 检查标签是否变更
    if (_watchTagIds != null && tagIds != null) {
      if (_watchTagIds!.length != tagIds.length) {
        hasFilterChanged = true;
        logDebug('标签数量变更: ${_watchTagIds!.length} -> ${tagIds.length}');
      } else {
        // 比较标签内容是否一致
        for (int i = 0; i < _watchTagIds!.length; i++) {
          if (!tagIds.contains(_watchTagIds![i])) {
            hasFilterChanged = true;
            logDebug('标签内容变更');
            break;
          }
        }
      }
    } else if ((_watchTagIds == null) != (tagIds == null)) {
      hasFilterChanged = true;
      logDebug(
        '标签筛选条件状态变更: ${_watchTagIds == null ? "无" : "有"} -> ${tagIds == null ? "无" : "有"}',
      );
    }

    // 检查分类是否变更
    if (_watchCategoryId != categoryId) {
      hasFilterChanged = true;
      logDebug('分类变更: $_watchCategoryId -> $categoryId');
    }

    // 检查排序是否变更
    if (_watchOrderBy != orderBy) {
      hasFilterChanged = true;
      logDebug('排序变更: $_watchOrderBy -> $orderBy');
    }

    // 检查搜索条件是否变更
    final normalizedSearchQuery =
        (searchQuery != null && searchQuery.isNotEmpty) ? searchQuery : null;
    if (_watchSearchQuery != normalizedSearchQuery) {
      hasFilterChanged = true;
      logDebug('搜索条件变更: $_watchSearchQuery -> $normalizedSearchQuery');
    }

    // 检查天气筛选条件是否变更
    if (_watchSelectedWeathers != null && selectedWeathers != null) {
      if (_watchSelectedWeathers!.length != selectedWeathers.length) {
        hasFilterChanged = true;
        logDebug(
          '天气筛选数量变更: ${_watchSelectedWeathers!.length} -> ${selectedWeathers.length}',
        );
      } else {
        // 比较天气筛选内容是否一致
        for (int i = 0; i < _watchSelectedWeathers!.length; i++) {
          if (!selectedWeathers.contains(_watchSelectedWeathers![i])) {
            hasFilterChanged = true;
            logDebug('天气筛选内容变更');
            break;
          }
        }
      }
    } else if ((_watchSelectedWeathers == null) != (selectedWeathers == null)) {
      hasFilterChanged = true;
      logDebug('天气筛选条件状态变更');
    }

    // 检查时间段筛选条件是否变更
    if (_watchSelectedDayPeriods != null && selectedDayPeriods != null) {
      if (_watchSelectedDayPeriods!.length != selectedDayPeriods.length) {
        hasFilterChanged = true;
        logDebug(
          '时间段筛选数量变更: ${_watchSelectedDayPeriods!.length} -> ${selectedDayPeriods.length}',
        );
      } else {
        // 比较时间段筛选内容是否一致
        for (int i = 0; i < _watchSelectedDayPeriods!.length; i++) {
          if (!selectedDayPeriods.contains(_watchSelectedDayPeriods![i])) {
            hasFilterChanged = true;
            logDebug('时间段筛选内容变更');
            break;
          }
        }
      }
    } else if ((_watchSelectedDayPeriods == null) !=
        (selectedDayPeriods == null)) {
      hasFilterChanged = true;
      logDebug('时间段筛选条件状态变更');
    }

    // 更新当前的筛选参数
    _watchOffset = 0;
    _watchLimit = limit;
    _watchTagIds = tagIds;
    _watchCategoryId = categoryId;
    _watchOrderBy = orderBy;
    _watchSearchQuery = normalizedSearchQuery;
    _watchSelectedWeathers = selectedWeathers; // 保存天气筛选条件
    _watchSelectedDayPeriods = selectedDayPeriods; // 保存时间段筛选条件

    // 修复：筛选条件变化时重置_watchHasMore状态
    if (hasFilterChanged || isFirstCall) {
      _watchHasMore = true;
      if (isFirstCall) {
        logDebug('首次调用watchQuotes，准备加载初始数据');
      } else {
        logDebug('筛选条件变化，重置_watchHasMore=true');
      }
    }

    // 修复：如果有筛选条件变更、首次调用或未初始化，重新创建流
    if (hasFilterChanged ||
        isFirstCall ||
        _quotesController == null ||
        _quotesController!.isClosed) {
      // 安全关闭现有控制器
      if (_quotesController != null && !_quotesController!.isClosed) {
        _quotesController!.close();
      }
      _quotesController = StreamController<List<Quote>>.broadcast();

      // 修复：在重置状态时确保原子性操作，避免竞态条件
      _currentQuotes = [];
      _currentQuoteIds.clear(); // 性能优化：同步清空 ID Set
      _isLoading = false;
      _watchHasMore = true; // 重置分页状态

      // 修复：使用同步方式立即发送空列表，然后异步加载数据
      _quotesController!.add([]);

      // 在新的异步上下文中执行初始化
      Future.microtask(() async {
        try {
          // 优化：移除重复的数据迁移检查，这些已在初始化阶段完成

          // 加载第一页数据
          await loadMoreQuotes(
            tagIds: tagIds,
            categoryId: categoryId,
            searchQuery: searchQuery,
            selectedWeathers: selectedWeathers,
            selectedDayPeriods: selectedDayPeriods,
          );
        } catch (e) {
          logError('数据初始化或加载失败: $e', error: e, source: 'DatabaseService');
          // 即使失败也发送空列表，避免UI挂起
          if (_quotesController != null && !_quotesController!.isClosed) {
            _quotesController!.add([]);
          }
        }
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          logError('数据加载超时（10秒）', source: 'DatabaseService');
          // 超时时发送空列表，确保UI不会永远卡住
          if (_quotesController != null && !_quotesController!.isClosed) {
            _quotesController!.add([]);
          }
        },
      );
    }

    return _quotesController!.stream;
  }

  /// 修复：加载更多笔记数据（用于分页）
  Future<void> loadMoreQuotes({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
  }) async {
    // 使用当前观察的参数作为默认值
    tagIds ??= _watchTagIds;
    categoryId ??= _watchCategoryId;
    searchQuery ??= _watchSearchQuery;
    selectedWeathers ??= _watchSelectedWeathers;
    selectedDayPeriods ??= _watchSelectedDayPeriods;

    // 修复：防止重复加载和检查是否还有更多数据
    if (_isLoading || !_watchHasMore) {
      logDebug('跳过加载：正在加载($_isLoading) 或无更多数据(!$_watchHasMore)');
      return;
    }

    _isLoading = true;
    logDebug(
      '开始加载更多笔记，当前已有 ${_currentQuotes.length} 条，offset=${_currentQuotes.length}，limit=$_watchLimit',
    );

    try {
      final quotes = await getUserQuotes(
        tagIds: tagIds,
        categoryId: categoryId,
        offset: _currentQuotes.length,
        limit: _watchLimit,
        orderBy: _watchOrderBy,
        searchQuery: searchQuery,
        selectedWeathers: selectedWeathers,
        selectedDayPeriods: selectedDayPeriods,
      ).timeout(
        const Duration(seconds: 5), // 缩短超时时间
        onTimeout: () {
          logError('getUserQuotes 查询超时（5秒）', source: 'DatabaseService');
          throw TimeoutException('数据库查询超时', const Duration(seconds: 5));
        },
      );

      if (quotes.isEmpty) {
        // 没有更多数据了
        _watchHasMore = false;
        logDebug('没有更多笔记数据，设置_watchHasMore=false');
      } else {
        // 性能优化：使用增量维护的 _currentQuoteIds 进行去重
        // 避免每次都遍历 _currentQuotes 构建 Set
        final newQuotes = <Quote>[];
        for (final quote in quotes) {
          if (quote.id != null && !_currentQuoteIds.contains(quote.id)) {
            _currentQuoteIds.add(quote.id!);
            newQuotes.add(quote);
          }
        }

        if (newQuotes.isNotEmpty) {
          _currentQuotes.addAll(newQuotes);
          logDebug(
            '本次加载${quotes.length}条，去重后添加${newQuotes.length}条，总计${_currentQuotes.length}条',
          );
        } else {
          logDebug('本次加载${quotes.length}条，但全部为重复数据，已过滤');
        }

        // 简化：统一的_watchHasMore判断逻辑
        _watchHasMore = quotes.length >= _watchLimit;
      }

      // 通知状态变化
      notifyListeners();

      // 修复：使用安全的方式通知订阅者
      _safeNotifyQuotesStream();
    } catch (e) {
      logError('加载更多笔记失败: $e', error: e, source: 'DatabaseService');
      // 确保即使出错也通知UI，避免无限加载状态
      _safeNotifyQuotesStream();

      // 如果是超时错误，重新抛出让UI处理
      if (e is TimeoutException) {
        rethrow;
      }
    } finally {
      _isLoading = false; // 确保加载状态总是被重置
    }
  }

  /// 优化：生成更可靠的缓存键，避免冲突
  String _generateCacheKey({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    String orderBy = 'date DESC',
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
  }) {
    // 使用更安全的分隔符避免冲突
    final tagKey = tagIds?.join('|') ?? 'NULL';
    final categoryKey = categoryId ?? 'NULL';
    final searchKey = searchQuery ?? 'NULL';
    final weatherKey = selectedWeathers?.join('|') ?? 'NULL';
    final dayPeriodKey = selectedDayPeriods?.join('|') ?? 'NULL';

    // 使用不同的分隔符确保唯一性
    return '$tagKey@@$categoryKey@@$searchKey@@$orderBy@@$weatherKey@@$dayPeriodKey';
  }

  /// 修复：从缓存中获取数据，更新LRU访问时间
  List<Quote>? _getFromCache(String cacheKey, int offset, int limit) {
    final cachedData = _filterCache[cacheKey];
    if (cachedData == null || cachedData.isEmpty) {
      return null;
    }

    // 更新LRU访问时间和缓存命中统计
    _cacheAccessTimes[cacheKey] = DateTime.now();
    _healthService.recordCacheHit();

    // 优化：改进边界检查逻辑
    if (offset >= cachedData.length) {
      // 如果偏移量超过缓存数据长度，返回空列表而不是null
      return [];
    }

    final end = (offset + limit).clamp(0, cachedData.length);
    final result = cachedData.sublist(offset, end);

    logDebug('从缓存获取数据: offset=$offset, limit=$limit, 实际返回=${result.length}条');
    return result;
  }

  /// 修复：更智能的LRU缓存管理
  void _addToCache(String cacheKey, List<Quote> quotes, int offset) {
    final now = DateTime.now();

    if (!_filterCache.containsKey(cacheKey)) {
      // 如果缓存已满，使用真正的LRU策略移除最久未访问的条目
      if (_filterCache.length >= _maxCacheEntries) {
        _evictLRUCache();
      }
      _filterCache[cacheKey] = [];
    }

    // 更新缓存时间戳
    _cacheTimestamps[cacheKey] = now;
    _cacheAccessTimes[cacheKey] = now;

    // 如果是第一页，则清空缓存重新开始
    if (offset == 0) {
      _filterCache[cacheKey] = List.from(quotes);
      logDebug('缓存第一页数据，共 ${quotes.length} 条');
    } else {
      // 否则追加到现有缓存
      _filterCache[cacheKey]!.addAll(quotes);
      logDebug(
        '追加缓存数据，新增 ${quotes.length} 条，总计 ${_filterCache[cacheKey]!.length} 条',
      );
    }
  }

  /// 修复：实现真正的LRU缓存淘汰策略
  void _evictLRUCache() {
    if (_cacheAccessTimes.isEmpty) return;

    // 找到最久未访问的缓存条目
    String? lruKey;
    DateTime? oldestAccess;

    for (final entry in _cacheAccessTimes.entries) {
      if (oldestAccess == null || entry.value.isBefore(oldestAccess)) {
        oldestAccess = entry.value;
        lruKey = entry.key;
      }
    }

    if (lruKey != null) {
      _filterCache.remove(lruKey);
      _cacheTimestamps.remove(lruKey);
      _cacheAccessTimes.remove(lruKey);
      logDebug('LRU缓存淘汰，移除缓存条目: $lruKey');
    }
  }

  // 添加存储加载状态的变量
  bool _isLoading = false;

  // 添加存储当前加载的笔记列表的变量
  List<Quote> _currentQuotes = [];

  // 性能优化：增量维护的 ID Set，避免每次去重时遍历
  final Set<String> _currentQuoteIds = {};

  /// 更新分类信息
  Future<void> updateCategory(
    String id,
    String name, {
    String? iconName,
  }) async {
    // 系统标签（如隐藏标签）不允许修改
    if (id == hiddenTagId) {
      throw Exception('系统标签不允许修改');
    }

    // 检查参数
    if (name.trim().isEmpty) {
      throw Exception('分类名称不能为空');
    }
    // 查找是否是默认分类 - 注释掉未使用的变量
    // final List<NoteCategory> defaultCats = _getDefaultHitokotoCategories();

    // // 如果是默认分类，不允许修改名称？(或者只允许修改图标) - 根据产品决定
    // if (_defaultCats.any((cat) => cat.id == id)) {
    //   // 暂时允许修改默认分类的名称和图标，但ID不变
    //   // 如果不允许修改名称，可以在这里抛出异常或只更新图标
    //   // throw Exception('不允许修改默认分类的名称');
    // }

    if (kIsWeb) {
      // Web 平台逻辑
      final index = _categoryStore.indexWhere((c) => c.id == id);
      if (index == -1) {
        throw Exception('找不到指定的分类');
      }
      // 检查新名称是否与 *其他* 分类冲突
      final newNameLower = name.toLowerCase();
      final conflict = _categoryStore.any(
        (c) => c.id != id && c.name.toLowerCase() == newNameLower,
      );
      if (conflict) {
        throw Exception('已存在相同名称的分类');
      }
      final updatedCategory = NoteCategory(
        id: id, // ID 保持不变
        name: name,
        isDefault: _categoryStore[index].isDefault, // isDefault 状态保持不变
        iconName: iconName ?? _categoryStore[index].iconName,
      );
      _categoryStore[index] = updatedCategory;
      _categoriesController.add(_categoryStore);
      notifyListeners();
      return;
    }

    final db = database;

    // 检查要更新的分类是否存在
    final currentCategories = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (currentCategories.isEmpty) {
      throw Exception('找不到指定的分类');
    }

    final currentCategory = NoteCategory.fromMap(currentCategories.first);

    /// 修复：使用统一的名称唯一性验证
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('分类名称不能为空');
    }
    if (trimmedName.length > 50) {
      throw Exception('分类名称不能超过50个字符');
    }

    // 只有当新名称与当前名称不同时，才检查重复
    if (trimmedName.toLowerCase() != currentCategory.name.toLowerCase()) {
      await _validateCategoryNameUnique(db, trimmedName, excludeId: id);
    }

    final categoryMap = {
      'name': trimmedName,
      'icon_name':
          iconName?.trim() ?? currentCategory.iconName, // 如果未提供新图标，则保留旧图标
      'last_modified': DateTime.now().toUtc().toIso8601String(),
      // 'is_default' 字段不应在此处更新，它在创建时确定
    };

    await db.update(
      'categories',
      categoryMap,
      where: 'id = ?',
      whereArgs: [id],
    );

    await _updateCategoriesStream();
    notifyListeners();
  }

  /// 批量为旧笔记补全 dayPeriod 字段（根据 date 字段推算并写入）
  Future<void> patchQuotesDayPeriod() async {
    await _schemaManager.patchQuotesDayPeriod(database);
  }

  /// 修复：安全迁移旧数据dayPeriod字段为英文key
  Future<void> migrateDayPeriodToKey() async {
    await _schemaManager.migrateDayPeriodToKey(database);
  }

  /// 修复：安全迁移旧数据weather字段为英文key
  Future<void> migrateWeatherToKey() async {
    await _schemaManager.migrateWeatherToKey(
      database,
      memoryStore: _memoryStore,
    );
  }

  Future<void> _cleanupLegacyTagIdsColumn() async {
    await _schemaManager.cleanupLegacyTagIdsColumn(database);
  }

  /// 根据 ID 获取分类
  Future<NoteCategory?> getCategoryById(String id) async {
    if (kIsWeb) {
      try {
        return _categoryStore.firstWhere((cat) => cat.id == id);
      } catch (e) {
        logDebug('在内存中找不到 ID 为 $id 的分类: $e');
        return null;
      }
    }

    try {
      final db = database;
      final maps = await db.query(
        'categories',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (maps.isEmpty) {
        return null;
      }

      return NoteCategory.fromMap(maps.first);
    } catch (e) {
      logDebug('根据 ID 获取分类失败: $e');
      return null;
    }
  }

  /// 优化：在初始化阶段执行所有数据迁移
  /// 兼容性保证：所有迁移都是向后兼容的，不会破坏现有数据
  Future<void> _performAllDataMigrations() async {
    await _schemaManager.performAllDataMigrations(database);
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
      _isLoading = false;

      // 清理缓存
      _clearAllCache();

      logDebug('数据库恢复措施已执行');
    } catch (e) {
      logDebug('数据库恢复失败: $e');
      rethrow;
    }
  }

  /// LWW (Last-Write-Wins) 合并导入数据
  ///
  /// 使用时间戳比较来决定是否覆盖本地数据
  /// [data] - 远程数据Map
  /// [sourceDevice] - 源设备标识符（可选）
  /// 返回 [MergeReport] 包含合并统计信息
  Future<MergeReport> importDataWithLWWMerge(
    Map<String, dynamic> data, {
    String? sourceDevice,
  }) async {
    final report = await _backupService.importDataWithLWWMerge(
      database,
      data,
      sourceDevice: sourceDevice,
    );
    await MediaReferenceService.migrateExistingQuotes();
    _clearAllCache();
    notifyListeners();
    _refreshQuotesStream();
    return report;
  }

  /// 外部调用的统一刷新入口（同步/恢复后使用）
  void refreshAllData() {
    _clearAllCache();
    notifyListeners();
    _refreshQuotesStream();
  }

  /// 获取适合作为每日一言的本地笔记
  /// 优先选择带有"每日一言"标签的笔记，然后选择较短的笔记
  Future<Map<String, dynamic>?> getLocalDailyQuote() async {
    if (!_isInitialized) {
      await init();
    }
    return _healthService.getLocalDailyQuote(
      database,
      memoryStore: _memoryStore,
      categoryStore: _categoryStore,
    );
  }

  /// 手动触发数据库维护（VACUUM + ANALYZE）
  /// 应在存储管理页面由用户主动触发，带进度提示
  /// 返回维护结果和统计信息
  Future<Map<String, dynamic>> performDatabaseMaintenance({
    Function(String)? onProgress,
  }) async {
    return _executeWithLock<Map<String, dynamic>>('databaseMaintenance',
        () async {
      return _healthService.performDatabaseMaintenance(
        await safeDatabase,
        onProgress: onProgress,
      );
    });
  }

  /// 获取数据库健康状态信息
  Future<Map<String, dynamic>> getDatabaseHealthInfo() async {
    return _healthService.getDatabaseHealthInfo(
      await safeDatabase,
      webQuoteCount: _memoryStore.length,
      webCategoryCount: _categoryStore.length,
    );
  }
}
