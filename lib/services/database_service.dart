// ignore_for_file: unused_element, unused_field
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
// 仅在 Windows 平台下使用 sqflite_common_ffi，其它平台直接使用 sqflite 默认实现
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/note_category.dart';
import '../models/quote_model.dart';
import 'package:uuid/uuid.dart';
import '../services/weather_service.dart';
import '../utils/time_utils.dart';
import '../utils/app_logger.dart';
import '../utils/database_platform_init.dart';
import 'large_file_manager.dart';
import 'media_reference_service.dart';
import '../models/merge_report.dart';
import '../utils/lww_utils.dart';

class DatabaseService extends ChangeNotifier {
  static Database? _database;
  final _categoriesController =
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
  final Map<String, int> _queryStats = {}; // 查询次数统计
  final Map<String, int> _queryTotalTime = {}; // 查询总耗时统计
  int _totalQueries = 0;
  int _cacheHits = 0;

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
  void _safeNotifyQuotesStream() {
    if (_quotesController != null && !_quotesController!.isClosed) {
      // 创建去重的副本
      final uniqueQuotes = <Quote>[];
      final seenIds = <String>{};

      for (final quote in _currentQuotes) {
        if (quote.id != null && !seenIds.contains(quote.id)) {
          seenIds.add(quote.id!);
          uniqueQuotes.add(quote);
        }
      }

      _quotesController!.add(List.from(uniqueQuotes));
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
    // 如果正在初始化，等待初始化完成
    if (_isInitializing && _initCompleter != null) {
      await _initCompleter!.future;
    }

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
      String operationId, Future<T> Function() action) async {
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
              '数据库操作超时: $operationId', const Duration(seconds: 30));
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

  /// 修复：初始化数据库，增加并发控制
  Future<void> init() async {
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
              '生成示例数据${i + 1}: id=${quote.id?.substring(0, 8)}, content=${quote.content}');
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

      // 触发更新
      _categoriesController.add(_categoryStore);
      _isInitialized = true; // 标记为已初始化
      notifyListeners();
      return;
    }

    // 修复：更严格的数据库初始化检查
    if (_database != null && _database!.isOpen) {
      logDebug('数据库已存在且打开，跳过重复初始化');
      _isInitialized = true;
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

      // 修复：恢复简化的预加载逻辑，确保首次加载能正常工作
      logDebug('数据库初始化完成，准备预加载数据...');

      // 重置流相关状态
      _watchOffset = 0;
      _quotesCache = [];
      _filterCache.clear();
      _watchHasMore = true;

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
      version: 16, // 版本号升级至16，为分类表新增 last_modified 字段
      onCreate: (db, version) async {
        // 创建分类表：包含 id、名称、是否为默认、图标名称等字段
        await db.execute('''
          CREATE TABLE categories(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            is_default BOOLEAN DEFAULT 0,
            icon_name TEXT,
            last_modified TEXT
          )
        ''');
        // 创建引用（笔记）表，新增 category_id、source、source_author、source_work、color_hex、edit_source、delta_content、day_period、last_modified 字段
        await db.execute('''
          CREATE TABLE quotes(
            id TEXT PRIMARY KEY,
            content TEXT NOT NULL,
            date TEXT NOT NULL,
            source TEXT,
            source_author TEXT,
            source_work TEXT,
            ai_analysis TEXT,
            sentiment TEXT,
            keywords TEXT,
            summary TEXT,
            category_id TEXT DEFAULT '',
            color_hex TEXT,
            location TEXT,
            weather TEXT,
            temperature TEXT,
            edit_source TEXT,
            delta_content TEXT,
      day_period TEXT,
      last_modified TEXT
          )
        ''');

        /// 修复：创建优化的索引以加速常用查询
        // 基础索引
        await db.execute(
          'CREATE INDEX idx_quotes_category_id ON quotes(category_id)',
        );
        await db.execute('CREATE INDEX idx_quotes_date ON quotes(date)');

        // 复合索引优化复杂查询
        await db.execute(
          'CREATE INDEX idx_quotes_date_category ON quotes(date DESC, category_id)',
        );
        await db.execute(
          'CREATE INDEX idx_quotes_category_date ON quotes(category_id, date DESC)',
        );

        // 搜索优化索引
        await db.execute(
          'CREATE INDEX idx_quotes_content_fts ON quotes(content)',
        );

        // 天气和时间段查询索引
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_quotes_weather ON quotes(weather)',
        );
        // 修复：安全地创建day_period索引
        await _createIndexSafely(
            db, 'quotes', 'day_period', 'idx_quotes_day_period');
        // 新增：last_modified 索引用于同步增量查询
        await _createIndexSafely(
            db, 'quotes', 'last_modified', 'idx_quotes_last_modified');

        // 创建新的 quote_tags 关联表
        await db.execute('''
          CREATE TABLE quote_tags(
            quote_id TEXT NOT NULL,
            tag_id TEXT NOT NULL,
            PRIMARY KEY (quote_id, tag_id),
            FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE,
            FOREIGN KEY (tag_id) REFERENCES categories(id) ON DELETE CASCADE
          )
        ''');

        /// 修复：优化quote_tags表的索引
        await db.execute(
          'CREATE INDEX idx_quote_tags_quote_id ON quote_tags(quote_id)',
        );
        await db.execute(
          'CREATE INDEX idx_quote_tags_tag_id ON quote_tags(tag_id)',
        );
        // 复合索引优化JOIN查询
        await db.execute(
          'CREATE INDEX idx_quote_tags_composite ON quote_tags(tag_id, quote_id)',
        );

        // 创建媒体文件引用表
        await MediaReferenceService.initializeTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        logDebug('开始数据库升级: $oldVersion -> $newVersion');

        try {
          // 修复：使用事务保护整个升级过程
          await db.transaction((txn) async {
            // 创建升级备份
            await _createUpgradeBackup(txn, oldVersion);

            // 按版本顺序执行升级
            await _performVersionUpgrades(txn, oldVersion, newVersion);

            // 验证升级结果
            await _validateUpgradeResult(txn);
          });

          logDebug('数据库升级成功完成');
        } catch (e) {
          logError('数据库升级失败: $e', error: e, source: 'DatabaseUpgrade');
          rethrow;
        }
      },
    );
  }

  /// 修复：创建升级备份
  Future<void> _createUpgradeBackup(Transaction txn, int oldVersion) async {
    try {
      logDebug('创建数据库升级备份...');

      // 备份quotes表
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS quotes_backup_v$oldVersion AS 
        SELECT * FROM quotes
      ''');

      // 备份categories表
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS categories_backup_v$oldVersion AS 
        SELECT * FROM categories
      ''');

      // 如果quote_tags表存在，也备份
      final tables = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='quote_tags'",
      );
      if (tables.isNotEmpty) {
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS quote_tags_backup_v$oldVersion AS 
          SELECT * FROM quote_tags
        ''');
      }

      logDebug('升级备份创建完成');
    } catch (e) {
      logDebug('创建升级备份失败: $e');
      // 备份失败不应阻止升级，但要记录警告
    }
  }

  /// 修复：执行版本升级
  Future<void> _performVersionUpgrades(
    Transaction txn,
    int oldVersion,
    int newVersion,
  ) async {
    logDebug('在事务中执行版本升级...');

    // 如果数据库版本低于 2，添加 tag_ids 字段（以前可能不存在，但在本版本中创建表时已包含）
    if (oldVersion < 2) {
      await txn.execute(
        'ALTER TABLE quotes ADD COLUMN tag_ids TEXT DEFAULT ""',
      );
    }
    // 如果数据库版本低于 3，添加 categories 表中的 icon_name 字段（在本版本中创建表时已包含）
    if (oldVersion < 3) {
      await txn.execute('ALTER TABLE categories ADD COLUMN icon_name TEXT');
    }
    // 如果数据库版本低于 4，添加 quotes 表中的 category_id 字段
    if (oldVersion < 4) {
      await txn.execute(
        'ALTER TABLE quotes ADD COLUMN category_id TEXT DEFAULT ""',
      );
    }

    // 如果数据库版本低于 5，添加 quotes 表中的 source 字段
    if (oldVersion < 5) {
      await txn.execute('ALTER TABLE quotes ADD COLUMN source TEXT');
    }

    // 如果数据库版本低于 6，添加 quotes 表中的 color_hex 字段
    if (oldVersion < 6) {
      await txn.execute('ALTER TABLE quotes ADD COLUMN color_hex TEXT');
    }

    // 如果数据库版本低于 7，添加 quotes 表中的 source_author 和 source_work 字段
    if (oldVersion < 7) {
      await txn.execute('ALTER TABLE quotes ADD COLUMN source_author TEXT');
      await txn.execute('ALTER TABLE quotes ADD COLUMN source_work TEXT');

      // 将现有的 source 字段数据拆分到新字段中
      final quotes = await txn.query(
        'quotes',
        where: 'source IS NOT NULL AND source != ""',
      );

      for (final quote in quotes) {
        final source = quote['source'] as String?;
        if (source != null && source.isNotEmpty) {
          String? sourceAuthor;
          String? sourceWork;

          // 尝试解析 source 字段
          if (source.contains('《') && source.contains('》')) {
            // 格式：作者《作品》
            final workMatch = RegExp(r'《(.+?)》').firstMatch(source);
            if (workMatch != null) {
              sourceWork = workMatch.group(1);
              sourceAuthor = source.replaceAll(RegExp(r'《.+?》'), '').trim();
              if (sourceAuthor.isEmpty) sourceAuthor = null;
            }
          } else if (source.contains(' - ')) {
            // 格式：作者 - 作品
            final parts = source.split(' - ');
            if (parts.length >= 2) {
              sourceAuthor = parts[0].trim();
              sourceWork = parts.sublist(1).join(' - ').trim();
            }
          } else {
            // 默认作为作者
            sourceAuthor = source.trim();
          }

          // 更新记录
          await txn.update(
            'quotes',
            {
              'source_author': sourceAuthor,
              'source_work': sourceWork,
            },
            where: 'id = ?',
            whereArgs: [quote['id']],
          );
        }
      }
    }

    // 如果数据库版本低于 8，添加位置和天气相关字段
    if (oldVersion < 8) {
      logDebug(
        '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 location, weather, temperature 字段',
      );
      await txn.execute('ALTER TABLE quotes ADD COLUMN location TEXT');
      await txn.execute('ALTER TABLE quotes ADD COLUMN weather TEXT');
      await txn.execute('ALTER TABLE quotes ADD COLUMN temperature TEXT');
      logDebug('数据库升级：location, weather, temperature 字段添加完成');
    }

    // 如果数据库版本低于 9，添加索引以提高查询性能
    if (oldVersion < 9) {
      logDebug('数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加索引');
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_category_id ON quotes(category_id)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_date ON quotes(date)',
      );
      // 修复：不再为tag_ids列创建索引，因为该列已被quote_tags表替代
      // await txn.execute(
      //   'CREATE INDEX IF NOT EXISTS idx_quotes_tag_ids ON quotes(tag_ids)',
      // );
      logDebug('数据库升级：索引添加完成');
    }

    // 如果数据库版本低于 10，添加 edit_source 字段用于记录编辑来源
    if (oldVersion < 10) {
      logDebug(
        '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 edit_source 字段',
      );
      await txn.execute('ALTER TABLE quotes ADD COLUMN edit_source TEXT');
      logDebug('数据库升级：edit_source 字段添加完成');
    }
    // 如果数据库版本低于 11，添加 delta_content 字段用于存储富文本Delta JSON
    if (oldVersion < 11) {
      logDebug(
        '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 delta_content 字段',
      );
      await txn.execute('ALTER TABLE quotes ADD COLUMN delta_content TEXT');
      logDebug('数据库升级：delta_content 字段添加完成');
    }

    // 修复：如果数据库版本低于 12，安全地创建 quote_tags 表并迁移数据
    if (oldVersion < 12) {
      logDebug(
        '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，创建 quote_tags 表并迁移数据',
      );

      await _upgradeToVersion12SafelyInTransaction(txn);
    }

    // 如果数据库版本低于 13，创建媒体文件引用表
    if (oldVersion < 13) {
      logDebug(
        '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，创建媒体文件引用表',
      );

      await _initializeMediaReferenceTableInTransaction(txn);
      logDebug('数据库升级：媒体文件引用表创建完成');
    }

    // 修复：如果数据库版本低于 14，安全地添加 day_period 字段
    if (oldVersion < 14) {
      logDebug(
        '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 day_period 字段',
      );

      try {
        // 先检查字段是否已存在
        final columns = await txn.rawQuery('PRAGMA table_info(quotes)');
        final hasColumn = columns.any((col) => col['name'] == 'day_period');

        if (!hasColumn) {
          await txn.execute('ALTER TABLE quotes ADD COLUMN day_period TEXT');
          logDebug('数据库升级：day_period 字段添加完成');
        } else {
          logDebug('数据库升级：day_period 字段已存在，跳过添加');
        }

        // 为新添加的字段创建索引（使用 IF NOT EXISTS 确保安全）
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_quotes_day_period ON quotes(day_period)',
        );
        logDebug('数据库升级：day_period 索引创建完成');
      } catch (e) {
        logError('day_period 字段升级失败: $e', error: e, source: 'DatabaseUpgrade');
        // 不要重新抛出异常，允许升级继续
      }
    }

    // 如果数据库版本低于15，添加 last_modified 字段（用于同步与更新追踪）
    if (oldVersion < 15) {
      logDebug(
        '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，添加 last_modified 字段',
      );
      try {
        final columns = await txn.rawQuery('PRAGMA table_info(quotes)');
        final hasColumn = columns.any((col) => col['name'] == 'last_modified');
        if (!hasColumn) {
          await txn.execute('ALTER TABLE quotes ADD COLUMN last_modified TEXT');
          logDebug('数据库升级：last_modified 字段添加完成');
          // 回填已有数据的last_modified，使用其date或当前时间
          final nowIso = DateTime.now().toIso8601String();
          // 使用COALESCE保证date为空时写入当前时间
          await txn.execute(
              "UPDATE quotes SET last_modified = COALESCE(date, ?)", [nowIso]);
        } else {
          logDebug('数据库升级：last_modified 字段已存在，跳过添加');
        }
        await txn.execute(
            'CREATE INDEX IF NOT EXISTS idx_quotes_last_modified ON quotes(last_modified)');
      } catch (e) {
        logError('last_modified 字段升级失败: $e',
            error: e, source: 'DatabaseUpgrade');
      }
    }

    // 版本16：为分类表添加last_modified字段
    if (oldVersion < 16) {
      logDebug(
        '数据库升级：从版本 $oldVersion 升级到版本 $newVersion，为分类表添加 last_modified 字段',
      );
      try {
        final columns = await txn.rawQuery('PRAGMA table_info(categories)');
        final hasColumn = columns.any((col) => col['name'] == 'last_modified');
        if (!hasColumn) {
          await txn
              .execute('ALTER TABLE categories ADD COLUMN last_modified TEXT');
          logDebug('数据库升级：categories表 last_modified 字段添加完成');
          // 回填已有分类数据的last_modified
          final nowIso = DateTime.now().toIso8601String();
          await txn
              .execute("UPDATE categories SET last_modified = ?", [nowIso]);
        } else {
          logDebug('数据库升级：categories表 last_modified 字段已存在，跳过添加');
        }
        await txn.execute(
            'CREATE INDEX IF NOT EXISTS idx_categories_last_modified ON categories(last_modified)');
      } catch (e) {
        logError('categories表 last_modified 字段升级失败: $e',
            error: e, source: 'DatabaseUpgrade');
      }
    }
  }

  /// 修复：验证升级结果
  Future<void> _validateUpgradeResult(Transaction txn) async {
    try {
      // 验证关键表是否存在
      final tables = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final tableNames = tables.map((t) => t['name'] as String).toSet();

      final requiredTables = {'quotes', 'categories'};
      final missingTables = requiredTables.difference(tableNames);

      if (missingTables.isNotEmpty) {
        throw Exception('升级后缺少必要的表: $missingTables');
      }

      logDebug('数据库升级验证通过');
    } catch (e) {
      logError('数据库升级验证失败: $e', error: e, source: 'DatabaseUpgrade');
      rethrow;
    }
  }

  /// 修复：安全的版本12升级
  Future<void> _upgradeToVersion12Safely(Database db) async {
    await db.transaction((txn) async {
      try {
        // 1. 创建新的关联表
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS quote_tags(
            quote_id TEXT NOT NULL,
            tag_id TEXT NOT NULL,
            PRIMARY KEY (quote_id, tag_id),
            FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE,
            FOREIGN KEY (tag_id) REFERENCES categories(id) ON DELETE CASCADE
          )
        ''');

        // 2. 创建索引
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_quote_tags_quote_id ON quote_tags(quote_id)',
        );
        await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_quote_tags_tag_id ON quote_tags(tag_id)',
        );

        // 3. 安全迁移数据
        await _migrateTagDataSafely(txn);

        logDebug('版本12升级安全完成');
      } catch (e) {
        logError('版本12升级失败: $e', error: e, source: 'DatabaseUpgrade');
        rethrow;
      }
    });
  }

  /// 修复：安全的标签数据迁移
  Future<void> _migrateTagDataSafely(Transaction txn) async {
    // 首先检查tag_ids列是否存在
    final tableInfo = await txn.rawQuery('PRAGMA table_info(quotes)');
    final hasTagIdsColumn = tableInfo.any((col) => col['name'] == 'tag_ids');

    if (!hasTagIdsColumn) {
      logDebug('tag_ids列不存在，跳过标签数据迁移');
      return;
    }

    // 获取所有有标签的笔记
    final quotesWithTags = await txn.query(
      'quotes',
      columns: ['id', 'tag_ids'],
      where: 'tag_ids IS NOT NULL AND tag_ids != ""',
    );

    if (quotesWithTags.isEmpty) {
      logDebug('没有需要迁移的标签数据');
      return;
    }

    int migratedCount = 0;
    int errorCount = 0;

    for (final quote in quotesWithTags) {
      try {
        final quoteId = quote['id'] as String;
        final tagIdsString = quote['tag_ids'] as String?;

        if (tagIdsString == null || tagIdsString.isEmpty) continue;

        // 解析标签ID
        final tagIds = tagIdsString
            .split(',')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toList();

        if (tagIds.isEmpty) continue;

        // 验证标签ID是否存在
        final validTagIds = <String>[];
        for (final tagId in tagIds) {
          final categoryExists = await txn.query(
            'categories',
            where: 'id = ?',
            whereArgs: [tagId],
            limit: 1,
          );

          if (categoryExists.isNotEmpty) {
            validTagIds.add(tagId);
          } else {
            logDebug('警告：标签ID $tagId 不存在，跳过');
          }
        }

        // 插入有效的标签关联
        for (final tagId in validTagIds) {
          await txn.insert(
              'quote_tags',
              {
                'quote_id': quoteId,
                'tag_id': tagId,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        migratedCount++;
      } catch (e) {
        errorCount++;
        logDebug('迁移笔记 ${quote['id']} 的标签时出错: $e');
      }
    }

    logDebug('标签数据迁移完成：成功 $migratedCount 条，错误 $errorCount 条');
  }

  /// 安全地删除tag_ids列（通过重建表）
  Future<void> _removeTagIdsColumnSafely(Transaction txn) async {
    try {
      // 首先检查tag_ids列是否存在
      final tableInfo = await txn.rawQuery('PRAGMA table_info(quotes)');
      final hasTagIdsColumn = tableInfo.any((col) => col['name'] == 'tag_ids');

      if (!hasTagIdsColumn) {
        logDebug('tag_ids列已不存在，跳过删除');
        return;
      }

      logDebug('开始删除tag_ids列...');

      // 1. 创建新的quotes表（不包含tag_ids列）
      await txn.execute('''
        CREATE TABLE quotes_new(
          id TEXT PRIMARY KEY,
          content TEXT NOT NULL,
          date TEXT NOT NULL,
          source TEXT,
          source_author TEXT,
          source_work TEXT,
          ai_analysis TEXT,
          sentiment TEXT,
          keywords TEXT,
          summary TEXT,
          category_id TEXT DEFAULT '',
          color_hex TEXT,
          location TEXT,
          weather TEXT,
          temperature TEXT,
          edit_source TEXT,
          delta_content TEXT,
          day_period TEXT,
          last_modified TEXT
        )
      ''');

      // 2. 复制数据（排除tag_ids列）
      await txn.execute('''
        INSERT INTO quotes_new (
          id, content, date, source, source_author, source_work,
          ai_analysis, sentiment, keywords, summary, category_id,
          color_hex, location, weather, temperature, edit_source,
          delta_content, day_period, last_modified
        )
        SELECT
          id, content, date, source, source_author, source_work,
          ai_analysis, sentiment, keywords, summary, category_id,
          color_hex, location, weather, temperature, edit_source,
          delta_content, day_period, last_modified
        FROM quotes
      ''');

      // 3. 删除旧表
      await txn.execute('DROP TABLE quotes');

      // 4. 重命名新表
      await txn.execute('ALTER TABLE quotes_new RENAME TO quotes');

      // 5. 重新创建索引
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_category_id ON quotes(category_id)',
      );
      await txn.execute(
          'CREATE INDEX IF NOT EXISTS idx_quotes_date ON quotes(date)');
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_date_category ON quotes(date DESC, category_id)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_category_date ON quotes(category_id, date DESC)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_content_fts ON quotes(content)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_weather ON quotes(weather)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_day_period ON quotes(day_period)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quotes_last_modified ON quotes(last_modified)',
      );

      logDebug('tag_ids列删除完成');
    } catch (e) {
      logError('删除tag_ids列失败: $e', error: e, source: 'DatabaseUpgrade');
      // 不重新抛出异常，让升级继续
    }
  }

  /// 清理遗留的tag_ids列
  Future<void> _cleanupLegacyTagIdsColumn() async {
    try {
      final db = database;

      // 检查quotes表是否还有tag_ids列
      final tableInfo = await db.rawQuery('PRAGMA table_info(quotes)');
      final hasTagIdsColumn = tableInfo.any((col) => col['name'] == 'tag_ids');

      if (!hasTagIdsColumn) {
        logDebug('tag_ids列已不存在，无需清理');
        return;
      }

      logDebug('检测到遗留的tag_ids列，开始清理...');

      // 在事务中执行清理
      await db.transaction((txn) async {
        // 首先确保数据已迁移到quote_tags表
        await _migrateTagDataSafely(txn);

        // 然后删除tag_ids列
        await _removeTagIdsColumnSafely(txn);
      });

      logDebug('遗留tag_ids列清理完成');
    } catch (e) {
      logError('清理遗留tag_ids列失败: $e', error: e, source: 'DatabaseService');
      // 不重新抛出异常，避免影响应用启动
    }
  }

  /// 修复：在事务中安全地执行版本12升级
  Future<void> _upgradeToVersion12SafelyInTransaction(Transaction txn) async {
    try {
      // 1. 创建新的关联表
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS quote_tags(
          quote_id TEXT NOT NULL,
          tag_id TEXT NOT NULL,
          PRIMARY KEY (quote_id, tag_id),
          FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE,
          FOREIGN KEY (tag_id) REFERENCES categories(id) ON DELETE CASCADE
        )
      ''');

      // 2. 创建索引
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quote_tags_quote_id ON quote_tags(quote_id)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_quote_tags_tag_id ON quote_tags(tag_id)',
      );

      // 3. 安全迁移数据
      await _migrateTagDataSafely(txn);

      // 4. 迁移完成后，删除旧的tag_ids列（SQLite不支持直接删除列，需要重建表）
      await _removeTagIdsColumnSafely(txn);

      logDebug('版本12升级在事务中安全完成');
    } catch (e) {
      logError('版本12升级失败: $e', error: e, source: 'DatabaseUpgrade');
      rethrow;
    }
  }

  /// 修复：在事务中初始化媒体引用表
  Future<void> _initializeMediaReferenceTableInTransaction(
      Transaction txn) async {
    await txn.execute('''
      CREATE TABLE IF NOT EXISTS media_references (
        id TEXT PRIMARY KEY,
        file_path TEXT NOT NULL,
        quote_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (quote_id) REFERENCES quotes (id) ON DELETE CASCADE,
        UNIQUE(file_path, quote_id)
      )
    ''');

    // 创建索引以提高查询性能
    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_media_references_file_path
      ON media_references (file_path)
    ''');

    await txn.execute('''
      CREATE INDEX IF NOT EXISTS idx_media_references_quote_id
      ON media_references (quote_id)
    ''');

    logDebug('媒体引用表在事务中初始化完成');
  }

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
          'q.id IN (SELECT quote_id FROM quote_tags WHERE tag_id IN ($tagPlaceholders))');
      args.addAll(tagIds);
    }

    // 分类筛选
    if (categoryId != null && categoryId.isNotEmpty) {
      conditions.add('q.category_id = ?');
      args.add(categoryId);
    }

    // 搜索查询
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

    final query = '''
      SELECT DISTINCT q.* FROM quotes q
      $whereClause
      ORDER BY q.$orderBy
      LIMIT ? OFFSET ?
    ''';

    args.addAll([limit, offset]);

    final List<Map<String, dynamic>> maps = await db.rawQuery(query, args);
    final quotes = <Quote>[];

    for (final map in maps) {
      try {
        // 获取标签ID
        final tagMaps = await db.query(
          'quote_tags',
          where: 'quote_id = ?',
          whereArgs: [map['id']],
        );
        final tagIds = tagMaps.map((m) => m['tag_id'] as String).toList();

        // 创建包含标签ID的Quote对象
        final quote = Quote.fromJson({...map, 'tag_ids': tagIds});
        quotes.add(quote);
      } catch (e) {
        logDebug('解析笔记数据失败: $e, 数据: $map');
      }
    }

    return quotes;
  }

  /// 检查并修复数据库结构，确保所有必要的列都存在
  /// 修复：检查并修复数据库结构，包括字段和索引
  Future<void> _checkAndFixDatabaseStructure() async {
    try {
      final db = database;

      // 获取quotes表的列信息
      final tableInfo = await db.rawQuery("PRAGMA table_info(quotes)");
      final columnNames = tableInfo.map((col) => col['name'] as String).toSet();

      logDebug('当前quotes表列: $columnNames');

      // 检查是否缺少必要的字段
      final requiredColumns = {
        'location',
        'weather',
        'temperature',
        'edit_source',
        'delta_content',
        'day_period', // 添加时间段字段
      };
      final missingColumns = requiredColumns.difference(columnNames);

      if (missingColumns.isNotEmpty) {
        logDebug('检测到缺少列: $missingColumns，正在添加...');

        // 添加缺少的列
        for (final column in missingColumns) {
          try {
            await db.execute('ALTER TABLE quotes ADD COLUMN $column TEXT');
            logDebug('成功添加列: $column');
          } catch (e) {
            logDebug('添加列 $column 时出错: $e');
          }
        }
      } else {
        logDebug('数据库结构完整，无需修复');
      }

      // 修复：检查并创建必要的索引
      await _ensureRequiredIndexes(db);
    } catch (e) {
      logDebug('检查数据库结构时出错: $e');
    }
  }

  /// 修复：确保必要的索引存在
  Future<void> _ensureRequiredIndexes(Database db) async {
    try {
      final requiredIndexes = {
        'idx_quotes_category_id':
            'CREATE INDEX IF NOT EXISTS idx_quotes_category_id ON quotes(category_id)',
        'idx_quotes_date':
            'CREATE INDEX IF NOT EXISTS idx_quotes_date ON quotes(date)',
        'idx_quotes_weather':
            'CREATE INDEX IF NOT EXISTS idx_quotes_weather ON quotes(weather)',
        'idx_quotes_day_period':
            'CREATE INDEX IF NOT EXISTS idx_quotes_day_period ON quotes(day_period)',
      };

      // 获取当前存在的索引
      final existingIndexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='quotes'",
      );
      final existingIndexNames = existingIndexes
          .map((idx) => idx['name'] as String)
          .where((name) => !name.startsWith('sqlite_')) // 排除系统索引
          .toSet();

      logDebug('当前存在的索引: $existingIndexNames');

      // 创建缺失的索引
      for (final entry in requiredIndexes.entries) {
        if (!existingIndexNames.contains(entry.key)) {
          try {
            await db.execute(entry.value);
            logDebug('成功创建索引: ${entry.key}');
          } catch (e) {
            logDebug('创建索引 ${entry.key} 失败: $e');
          }
        }
      }
    } catch (e) {
      logError('检查索引时出错: $e', error: e, source: 'DatabaseStructureCheck');
    }
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
        iconName: 'movie',
      ),
      NoteCategory(
        id: defaultCategoryIdComic, // 使用固定 ID
        name: '漫画',
        isDefault: true,
        iconName: 'menu_book',
      ),
      NoteCategory(
        id: defaultCategoryIdGame, // 使用固定 ID
        name: '游戏',
        isDefault: true,
        iconName: 'sports_esports',
      ),
      NoteCategory(
        id: defaultCategoryIdNovel, // 使用固定 ID
        name: '文学',
        isDefault: true,
        iconName: 'auto_stories',
      ),
      NoteCategory(
        id: defaultCategoryIdOriginal, // 使用固定 ID
        name: '原创',
        isDefault: true,
        iconName: 'create',
      ),
      NoteCategory(
        id: defaultCategoryIdInternet, // 使用固定 ID
        name: '来自网络',
        isDefault: true,
        iconName: 'public',
      ),
      NoteCategory(
        id: defaultCategoryIdOther, // 使用固定 ID
        name: '其他',
        isDefault: true,
        iconName: 'category',
      ),
      NoteCategory(
        id: defaultCategoryIdMovie, // 使用固定 ID
        name: '影视',
        isDefault: true,
        iconName: 'theaters',
      ),
      NoteCategory(
        id: defaultCategoryIdPoem, // 使用固定 ID
        name: '诗词',
        isDefault: true,
        iconName: 'brush',
      ),
      NoteCategory(
        id: defaultCategoryIdMusic, // 使用固定 ID
        name: '网易云',
        isDefault: true,
        iconName: 'music_note',
      ),
      NoteCategory(
        id: defaultCategoryIdPhilosophy, // 使用固定 ID
        name: '哲学',
        isDefault: true,
        iconName: 'psychology',
      ),
    ];
  }

  /// 将所有笔记和分类数据导出为Map对象
  Future<Map<String, dynamic>> exportDataAsMap() async {
    try {
      final db = database;
      final dbVersion = await db.getVersion();

      // 查询所有分类数据
      final categories = await db.query('categories');

      // 查询笔记数据并重建tag_ids字段以保持向后兼容
      final quotesWithTags = await db.rawQuery('''
        SELECT q.*, GROUP_CONCAT(qt.tag_id) as tag_ids
        FROM quotes q
        LEFT JOIN quote_tags qt ON q.id = qt.quote_id
        GROUP BY q.id
        ORDER BY q.date DESC
      ''');

      // 构建与旧版exportAllData兼容的JSON结构
      return {
        'metadata': {
          'app': '心迹',
          'version': dbVersion,
          'exportTime': DateTime.now().toIso8601String(),
        },
        'categories': categories,
        'quotes': quotesWithTags,
      };
    } catch (e) {
      logDebug('数据导出为Map时失败: $e');
      rethrow;
    }
  }

  /// 导出全部数据到 JSON 格式
  ///
  /// [customPath] - 可选的自定义保存路径。如果提供，将保存到指定路径；否则保存到应用文档目录
  /// 返回保存的文件路径
  Future<String> exportAllData({String? customPath}) async {
    try {
      // 调用新方法获取数据
      final jsonData = await exportDataAsMap();

      // 转换为格式化的 JSON 字符串
      final jsonStr = const JsonEncoder.withIndent('  ').convert(jsonData);

      String filePath;
      if (customPath != null) {
        // 使用自定义路径
        filePath = customPath;
      } else {
        // 使用默认路径
        final dir = await getApplicationDocumentsDirectory();
        final fileName = '心迹_${DateTime.now().millisecondsSinceEpoch}.json';
        filePath = '${dir.path}/$fileName';
      }

      final file = File(filePath);
      await file.writeAsString(jsonStr);
      return file.path;
    } catch (e) {
      logDebug('数据导出失败: $e');
      rethrow;
    }
  }

  /// 从Map对象导入数据
  Future<void> importDataFromMap(
    Map<String, dynamic> data, {
    bool clearExisting = true,
  }) async {
    try {
      final db = database;

      // 验证数据格式
      if (!data.containsKey('categories') || !data.containsKey('quotes')) {
        throw Exception('备份数据格式无效，缺少 "categories" 或 "quotes" 键');
      }

      // 开始事务
      await db.transaction((txn) async {
        if (clearExisting) {
          logDebug('清空现有数据并导入新数据');
          await txn.delete('quote_tags'); // 先删除关联表
          await txn.delete('categories');
          await txn.delete('quotes');
        }

        // 恢复分类数据
        final categories = data['categories'] as List;
        for (final c in categories) {
          final categoryData = Map<String, dynamic>.from(
            c as Map<String, dynamic>,
          );

          // 修复：处理旧版分类数据字段名兼容性
          final categoryFieldMappings = {
            'isDefault': 'is_default',
            'iconName': 'icon_name',
          };

          for (final mapping in categoryFieldMappings.entries) {
            if (categoryData.containsKey(mapping.key)) {
              categoryData[mapping.value] = categoryData[mapping.key];
              categoryData.remove(mapping.key);
            }
          }

          // 确保必要字段存在
          categoryData['id'] ??= _uuid.v4();
          categoryData['name'] ??= '未命名分类';
          categoryData['is_default'] ??= 0;

          // 修复：安全插入分类记录，添加详细错误处理
          try {
            await txn.insert(
              'categories',
              categoryData,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } catch (e) {
            logError('插入分类数据失败: $e', error: e, source: 'BackupRestore');
            logDebug('问题分类数据: $categoryData');

            // 尝试使用最基本的数据插入
            final essentialCategoryData = {
              'id': categoryData['id'],
              'name': categoryData['name'],
              'is_default': categoryData['is_default'] ?? 0,
            };

            try {
              await txn.insert(
                'categories',
                essentialCategoryData,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              logDebug('使用精简数据成功插入分类: ${essentialCategoryData['id']}');
            } catch (e2) {
              logError(
                '即使使用精简数据也无法插入分类: $e2',
                error: e2,
                source: 'BackupRestore',
              );
              throw Exception('无法插入分类数据: ${categoryData['id']}, 错误: $e2');
            }
          }
        }

        // 恢复笔记数据
        final quotes = data['quotes'] as List;
        for (final q in quotes) {
          final quoteData = Map<String, dynamic>.from(
            q as Map<String, dynamic>,
          );

          // 修复：处理旧版笔记数据字段名兼容性
          String? tagIdsString;

          // 处理tag_ids字段的各种可能格式
          if (quoteData.containsKey('tag_ids')) {
            tagIdsString = quoteData['tag_ids'] as String?;
            quoteData.remove('tag_ids');
          } else if (quoteData.containsKey('taglds')) {
            // 处理错误的字段名 taglds -> tag_ids
            tagIdsString = quoteData['taglds'] as String?;
            quoteData.remove('taglds');
          }

          // 修复：处理字段名不匹配问题
          final fieldMappings = {
            // 旧字段名 -> 新字段名
            'sourceAuthor': 'source_author',
            'sourceWork': 'source_work',
            'categoryld': 'category_id', // 修复 categoryld -> category_id
            'categoryId': 'category_id',
            'aiAnalysis': 'ai_analysis',
            'colorHex': 'color_hex',
            'editSource': 'edit_source',
            'deltaContent': 'delta_content',
            'dayPeriod': 'day_period',
          };

          // 应用字段名映射
          for (final mapping in fieldMappings.entries) {
            if (quoteData.containsKey(mapping.key)) {
              quoteData[mapping.value] = quoteData[mapping.key];
              quoteData.remove(mapping.key);
            }
          }

          // 确保必要字段存在
          quoteData['id'] ??= _uuid.v4();
          quoteData['content'] ??= '';
          quoteData['date'] ??= DateTime.now().toIso8601String();

          // 修复：安全插入笔记记录，添加详细错误处理
          try {
            await txn.insert(
              'quotes',
              quoteData,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } catch (e) {
            logError('插入笔记数据失败: $e', error: e, source: 'BackupRestore');
            logDebug('问题数据: $quoteData');

            // 尝试移除可能有问题的字段后重新插入
            final essentialData = {
              'id': quoteData['id'],
              'content': quoteData['content'],
              'date': quoteData['date'],
            };

            // 逐个添加可选字段
            final optionalFields = [
              'source',
              'source_author',
              'source_work',
              'category_id',
              'color_hex',
              'location',
              'weather',
              'temperature',
              'ai_analysis',
              'sentiment',
              'keywords',
              'summary',
              'edit_source',
              'delta_content',
              'day_period',
            ];

            for (final field in optionalFields) {
              if (quoteData.containsKey(field) && quoteData[field] != null) {
                essentialData[field] = quoteData[field];
              }
            }

            try {
              await txn.insert(
                'quotes',
                essentialData,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              logDebug('使用精简数据成功插入笔记: ${essentialData['id']}');
            } catch (e2) {
              logError(
                '即使使用精简数据也无法插入笔记: $e2',
                error: e2,
                source: 'BackupRestore',
              );
              throw Exception('无法插入笔记数据: ${quoteData['id']}, 错误: $e2');
            }
          }

          // 如果有标签信息，创建标签关联记录
          if (tagIdsString != null && tagIdsString.isNotEmpty) {
            final quoteId = quoteData['id'] as String;
            final tagIds =
                tagIdsString.split(',').where((id) => id.trim().isNotEmpty);

            for (final tagId in tagIds) {
              await txn.insert(
                'quote_tags',
                {'quote_id': quoteId, 'tag_id': tagId.trim()},
                conflictAlgorithm: ConflictAlgorithm.ignore, // 避免重复插入
              );
            }
          }
        }
      });

      await _updateCategoriesStream();
      notifyListeners();

      // 导入后自动补全字段
      await patchQuotesDayPeriod();
      await migrateWeatherToKey();
      await migrateDayPeriodToKey();
    } catch (e) {
      logDebug('从Map导入数据失败: $e');
      rethrow;
    }
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
    try {
      // 尝试执行简单查询以验证数据库可访问
      if (_database == null) {
        logDebug('数据库未初始化');
        return false;
      }

      // 修正：将'quote'改为正确的表名'quotes'
      await _database!.query('quotes', limit: 1);
      return true;
    } catch (e) {
      logDebug('数据库访问检查失败: $e');
      return false;
    }
  }

  /// 验证备份文件是否有效
  Future<bool> validateBackupFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在: $filePath');
      }

      // 使用流式JSON解析避免大文件OOM
      final data = await LargeFileManager.decodeJsonFromFileStreaming(file);

      // --- 修改处 ---
      // 验证基本结构，应与 exportAllData 导出的结构一致
      final requiredKeys = {'metadata', 'categories', 'quotes'};
      if (!requiredKeys.every((key) => data.containsKey(key))) {
        // 提供更详细的错误信息，指出缺少哪些键
        final missingKeys = requiredKeys.difference(data.keys.toSet());
        throw Exception(
          '备份文件格式无效，缺少必要的顶层数据结构 (需要: metadata, categories, quotes; 缺少: ${missingKeys.join(', ')})',
        );
      }
      // --- 修改结束 ---

      // 可选：进一步验证内部结构，例如 metadata 是否包含 version
      if (data['metadata'] is! Map ||
          !(data['metadata'] as Map).containsKey('version')) {
        logDebug('警告：备份文件元数据 (metadata) 格式不正确或缺少版本信息');
        // 可以选择是否在这里抛出异常，取决于是否强制要求版本信息
      }

      // 可选：检查 categories 和 quotes 是否为列表类型
      if (data['categories'] is! List) {
        throw Exception('备份文件中的 \'categories\' 必须是一个列表');
      }
      if (data['quotes'] is! List) {
        throw Exception('备份文件中的 \'quotes\' 必须是一个列表');
      }

      // 检查至少需要有quotes或categories (可选，空备份也可能有效)
      final quotes = data['quotes'] as List?;
      final categories = data['categories'] as List?;

      if ((quotes == null || quotes.isEmpty) &&
          (categories == null || categories.isEmpty)) {
        logDebug('警告：备份文件不包含任何分类或笔记数据');
        // 空备份也是有效的，但可以记录警告
      }

      logDebug('备份文件验证通过: $filePath');
      return true; // 如果所有检查都通过，返回 true
    } catch (e) {
      logDebug('验证备份文件失败: $e');
      // 重新抛出更具体的错误信息给上层调用者
      // 保留原始异常类型，以便上层可以根据需要区分处理
      // 例如: throw FormatException('备份文件JSON格式错误');
      // 或: throw FileSystemException('无法读取备份文件', filePath);
      // 这里统一抛出 Exception，包含原始错误信息
      throw Exception('无法验证备份文件： $e');
    }
  }

  Future<List<NoteCategory>> getCategories() async {
    if (kIsWeb) {
      return _categoryStore;
    }
    try {
      final db = database;
      final maps = await db.query('categories');
      final categories = maps.map((map) => NoteCategory.fromMap(map)).toList();
      return categories;
    } catch (e) {
      logDebug('获取分类错误: $e');
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
  Future<void> _validateCategoryNameUnique(Database db, String name,
      {String? excludeId}) async {
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
        await db.transaction((txn) async {
          final id = quote.id ?? _uuid.v4();
          final quoteMap = quote.toJson();
          quoteMap['id'] = id;

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
                {'quote_id': id, 'tag_id': tagId},
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
          }
        });

        logDebug('笔记已成功保存到数据库，ID: ${quote.id}');

        // 同步媒体文件引用
        await MediaReferenceService.syncQuoteMediaReferences(quote);

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

      // 触发重新加载
      loadMoreQuotes();
    } else {
      logDebug('笔记流无监听器或已关闭，跳过刷新');
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

        // 排序
        filtered.sort((a, b) {
          if (orderBy.startsWith('date')) {
            final dateA = DateTime.tryParse(a.date) ?? DateTime.now();
            final dateB = DateTime.tryParse(b.date) ?? DateTime.now();
            return orderBy.contains('ASC')
                ? dateA.compareTo(dateB)
                : dateB.compareTo(dateA);
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
            'Web分页：总数据${filtered.length}条，offset=$offset，limit=$limit，start=$start，end=$end');

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
    if (tagIds != null && tagIds.isNotEmpty) {
      if (tagIds.length == 1) {
        // 单标签查询：使用简单的INNER JOIN，性能最佳
        joinClause = 'INNER JOIN quote_tags qt ON q.id = qt.quote_id';
        conditions.add('qt.tag_id = ?');
        args.add(tagIds.first);
        groupByClause = 'GROUP BY q.id';
      } else {
        // 多标签查询：使用EXISTS确保所有标签都匹配
        final tagPlaceholders = tagIds.map((_) => '?').join(',');
        conditions.add('''
          EXISTS (
            SELECT 1 FROM quote_tags qt
            WHERE qt.quote_id = q.id
            AND qt.tag_id IN ($tagPlaceholders)
            GROUP BY qt.quote_id
            HAVING COUNT(DISTINCT qt.tag_id) = ?
          )
        ''');
        args.addAll(tagIds);
        args.add(tagIds.length);

        // 获取标签信息的LEFT JOIN
        joinClause = 'LEFT JOIN quote_tags qt2 ON q.id = qt2.quote_id';
        groupByClause = 'GROUP BY q.id';
      }
    } else {
      // 没有标签筛选时也需要获取标签信息
      joinClause = 'LEFT JOIN quote_tags qt ON q.id = qt.quote_id';
      groupByClause = 'GROUP BY q.id';
    }

    final where =
        conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

    final orderByParts = orderBy.split(' ');
    final correctedOrderBy =
        'q.${orderByParts[0]} ${orderByParts.length > 1 ? orderByParts[1] : ''}';

    /// 修复：优化查询，根据JOIN类型选择正确的标签字段
    String tagField = 'qt.tag_id';
    if (tagIds != null && tagIds.isNotEmpty && tagIds.length > 1) {
      tagField = 'qt2.tag_id'; // 多标签查询使用qt2别名
    }

    final query = '''
      SELECT q.*, GROUP_CONCAT($tagField) as tag_ids
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

    // 慢查询检测和警告
    if (queryTime > 1000) {
      logDebug('⚠️ 慢查询检测: 查询耗时 ${queryTime}ms，超过1秒阈值');
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
    } else if (queryTime > 500) {
      logDebug('⚠️ 查询性能警告: 耗时 ${queryTime}ms，建议优化');
    }

    logDebug(
      '查询完成，耗时: ${queryTime}ms，结果数量: ${maps.length}',
    );

    // 更新性能统计
    _updateQueryStats('getUserQuotes', queryTime);

    return maps.map((m) => Quote.fromJson(m)).toList();
  }

  /// 修复：更新查询性能统计
  void _updateQueryStats(String queryType, int timeMs) {
    _totalQueries++;
    _queryStats[queryType] = (_queryStats[queryType] ?? 0) + 1;
    _queryTotalTime[queryType] = (_queryTotalTime[queryType] ?? 0) + timeMs;
  }

  /// 修复：获取查询性能报告
  Map<String, dynamic> getQueryPerformanceReport() {
    final report = <String, dynamic>{
      'totalQueries': _totalQueries,
      'cacheHits': _cacheHits,
      'cacheHitRate': _totalQueries > 0
          ? '${(_cacheHits / _totalQueries * 100).toStringAsFixed(2)}%'
          : '0%',
      'queryTypes': <String, dynamic>{},
    };

    for (final entry in _queryStats.entries) {
      final queryType = entry.key;
      final count = entry.value;
      final totalTime = _queryTotalTime[queryType] ?? 0;
      final avgTime = count > 0 ? (totalTime / count).toStringAsFixed(2) : '0';

      report['queryTypes'][queryType] = {
        'count': count,
        'totalTime': '${totalTime}ms',
        'avgTime': '${avgTime}ms',
      };
    }

    return report;
  }

  /// 修复：安全地创建索引，检查列是否存在
  Future<void> _createIndexSafely(Database db, String tableName,
      String columnName, String indexName) async {
    try {
      // 检查列是否存在
      final columnExists = await _checkColumnExists(db, tableName, columnName);
      if (!columnExists) {
        logDebug('列 $columnName 不存在于表 $tableName 中，跳过索引创建');
        return;
      }

      // 创建索引
      await db.execute(
          'CREATE INDEX IF NOT EXISTS $indexName ON $tableName($columnName)');
      logDebug('索引 $indexName 创建成功');
    } catch (e) {
      logDebug('创建索引 $indexName 失败: $e');
    }
  }

  /// 修复：检查列是否存在
  Future<bool> _checkColumnExists(
      Database db, String tableName, String columnName) async {
    try {
      final result = await db.rawQuery("PRAGMA table_info($tableName)");
      for (final row in result) {
        if (row['name'] == columnName) {
          return true;
        }
      }
      return false;
    } catch (e) {
      logDebug('检查列是否存在失败: $e');
      return false;
    }
  }

  /// 修复：标签数据一致性检查
  Future<Map<String, dynamic>> checkTagDataConsistency() async {
    try {
      final db = await safeDatabase;
      final report = <String, dynamic>{
        'orphanedQuoteTags': 0,
        'orphanedCategoryReferences': 0,
        'duplicateTagRelations': 0,
        'issues': <String>[],
      };

      // 1. 检查孤立的quote_tags记录（引用不存在的quote_id）
      final orphanedQuoteTags = await db.rawQuery('''
        SELECT qt.quote_id, qt.tag_id
        FROM quote_tags qt
        LEFT JOIN quotes q ON qt.quote_id = q.id
        WHERE q.id IS NULL
      ''');

      report['orphanedQuoteTags'] = orphanedQuoteTags.length;
      if (orphanedQuoteTags.isNotEmpty) {
        report['issues'].add('发现 ${orphanedQuoteTags.length} 条孤立的标签关联记录');
      }

      // 2. 检查孤立的quote_tags记录（引用不存在的tag_id）
      final orphanedTagRefs = await db.rawQuery('''
        SELECT qt.quote_id, qt.tag_id
        FROM quote_tags qt
        LEFT JOIN categories c ON qt.tag_id = c.id
        WHERE c.id IS NULL
      ''');

      report['orphanedCategoryReferences'] = orphanedTagRefs.length;
      if (orphanedTagRefs.isNotEmpty) {
        report['issues'].add('发现 ${orphanedTagRefs.length} 条引用不存在分类的标签关联');
      }

      // 3. 检查重复的标签关联
      final duplicateRelations = await db.rawQuery('''
        SELECT quote_id, tag_id, COUNT(*) as count
        FROM quote_tags
        GROUP BY quote_id, tag_id
        HAVING COUNT(*) > 1
      ''');

      report['duplicateTagRelations'] = duplicateRelations.length;
      if (duplicateRelations.isNotEmpty) {
        report['issues'].add('发现 ${duplicateRelations.length} 组重复的标签关联');
      }

      // 4. 检查笔记的category_id是否存在对应的分类
      final invalidCategoryRefs = await db.rawQuery('''
        SELECT q.id, q.category_id
        FROM quotes q
        LEFT JOIN categories c ON q.category_id = c.id
        WHERE q.category_id IS NOT NULL AND q.category_id != '' AND c.id IS NULL
      ''');

      if (invalidCategoryRefs.isNotEmpty) {
        report['issues'].add('发现 ${invalidCategoryRefs.length} 条笔记引用了不存在的分类');
      }

      return report;
    } catch (e) {
      logDebug('标签数据一致性检查失败: $e');
      return {
        'error': e.toString(),
        'issues': ['检查过程中发生错误'],
      };
    }
  }

  /// 修复：清理标签数据不一致问题
  Future<bool> cleanupTagDataInconsistencies() async {
    try {
      final db = await safeDatabase;
      int cleanedCount = 0;

      await db.transaction((txn) async {
        // 1. 清理孤立的quote_tags记录（引用不存在的quote_id）
        final orphanedQuoteTagsCount = await txn.rawDelete('''
          DELETE FROM quote_tags
          WHERE quote_id NOT IN (SELECT id FROM quotes)
        ''');
        cleanedCount += orphanedQuoteTagsCount;

        // 2. 清理孤立的quote_tags记录（引用不存在的tag_id）
        final orphanedTagRefsCount = await txn.rawDelete('''
          DELETE FROM quote_tags
          WHERE tag_id NOT IN (SELECT id FROM categories)
        ''');
        cleanedCount += orphanedTagRefsCount;

        // 3. 清理重复的标签关联（保留一条）
        await txn.rawDelete('''
          DELETE FROM quote_tags
          WHERE rowid NOT IN (
            SELECT MIN(rowid)
            FROM quote_tags
            GROUP BY quote_id, tag_id
          )
        ''');

        // 4. 清理笔记中无效的category_id引用
        final invalidCategoryCount = await txn.rawUpdate('''
          UPDATE quotes
          SET category_id = NULL
          WHERE category_id IS NOT NULL
          AND category_id != ''
          AND category_id NOT IN (SELECT id FROM categories)
        ''');
        cleanedCount += invalidCategoryCount;
      });

      logDebug('标签数据清理完成，共处理 $cleanedCount 条记录');

      // 清理缓存
      _clearAllCache();

      return true;
    } catch (e) {
      logDebug('标签数据清理失败: $e');
      return false;
    }
  }

  /// 获取所有笔记（用于媒体引用迁移）
  Future<List<Quote>> getAllQuotes() async {
    if (kIsWeb) {
      return List.from(_memoryStore);
    }

    try {
      final db = database;
      final List<Map<String, dynamic>> maps = await db.query('quotes');
      return maps.map((m) => Quote.fromJson(m)).toList();
    } catch (e) {
      logDebug('获取所有笔记失败: $e');
      return [];
    }
  }

  /// 获取笔记总数，用于分页
  Future<int> getQuotesCount({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
  }) async {
    if (kIsWeb) {
      // 优化：Web平台直接在内存中应用筛选逻辑计算数量，避免加载大量数据
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
      final db = database;
      List<String> conditions = [];
      List<dynamic> args = [];

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

        // 先获取笔记引用的媒体文件列表
        final referencedFiles =
            await MediaReferenceService.getReferencedFiles(id);

        await db.transaction((txn) async {
          // 由于设置了 ON DELETE CASCADE，quote_tags 表中的相关条目会自动删除
          // 但为了明确起见，我们也可以手动删除
          // await txn.delete('quote_tags', where: 'quote_id = ?', whereArgs: [id]);
          await txn.delete('quotes', where: 'id = ?', whereArgs: [id]);
        });

        // 移除媒体文件引用（CASCADE会自动删除，但为了确保一致性）
        await MediaReferenceService.removeAllReferencesForQuote(id);

        // 检查并清理孤儿媒体文件
        for (final storedPath in referencedFiles) {
          final refCount = await MediaReferenceService.getReferenceCount(storedPath);
          if (refCount == 0) {
            try {
              // storedPath 可能是相对路径（相对于应用文档目录）
              String absolutePath = storedPath;
              try {
                if (!absolutePath.startsWith('/')) { // 简单判断相对路径
                  final appDir = await getApplicationDocumentsDirectory();
                  absolutePath = join(appDir.path, storedPath);
                }
              } catch (_) {}

              final file = File(absolutePath);
              if (await file.exists()) {
                await file.delete();
                logDebug('已清理孤儿媒体文件: $absolutePath (原始记录: $storedPath)');
              } else {
                logDebug('孤儿媒体文件不存在或已被删除: $absolutePath');
              }
            } catch (e) {
              logDebug('清理孤儿媒体文件失败: $storedPath, 错误: $e');
            }
          }
        }

        // 清理缓存
        _clearAllCache();

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
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
          }
        });

        logDebug('笔记已成功更新，ID: ${quote.id}');

        // 同步媒体文件引用
        await MediaReferenceService.syncQuoteMediaReferences(quote);

        // 更新内存中的笔记列表
        final index = _currentQuotes.indexWhere((q) => q.id == quote.id);
        if (index != -1) {
          _currentQuotes[index] = quote;
        }
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

  /// 监听笔记列表，支持分页加载和筛选
  /// 检查并迁移天气数据
  Future<void> _checkAndMigrateWeatherData() async {
    try {
      final db = database;
      final weatherCheck = await db.query(
        'quotes',
        where: 'weather IS NOT NULL AND weather != ""',
        limit: 1,
      );

      if (weatherCheck.isNotEmpty) {
        final weather = weatherCheck.first['weather'] as String?;
        if (weather != null &&
            WeatherService.weatherKeyToLabel.values.contains(weather)) {
          logDebug('检测到未迁移的weather数据，开始迁移...');
          await migrateWeatherToKey();
        }
      }
    } catch (e) {
      logDebug('天气数据迁移检查失败: $e');
    }
  }

  /// 检查并迁移时间段数据
  Future<void> _checkAndMigrateDayPeriodData() async {
    try {
      final db = database;
      final dayPeriodCheck = await db.query(
        'quotes',
        where: 'day_period IS NOT NULL AND day_period != ""',
        limit: 1,
      );

      if (dayPeriodCheck.isNotEmpty) {
        final dayPeriod = dayPeriodCheck.first['day_period'] as String?;
        final labelToKey = TimeUtils.dayPeriodKeyToLabel.map(
          (k, v) => MapEntry(v, k),
        );
        if (dayPeriod != null && labelToKey.containsKey(dayPeriod)) {
          logDebug('检测到未迁移的day_period数据，开始迁移...');
          await migrateDayPeriodToKey();
        }
      }
    } catch (e) {
      logDebug('时间段数据迁移检查失败: $e');
    }
  }

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
        'currentQuotesCount: ${_currentQuotes.length}, tagIds: $tagIds, categoryId: $categoryId');

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
        '开始加载更多笔记，当前已有 ${_currentQuotes.length} 条，offset=${_currentQuotes.length}，limit=$_watchLimit');

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
        // 修复：添加去重逻辑，防止重复数据
        final existingIds = _currentQuotes.map((q) => q.id).toSet();
        final newQuotes =
            quotes.where((q) => !existingIds.contains(q.id)).toList();

        if (newQuotes.isNotEmpty) {
          _currentQuotes.addAll(newQuotes);
          logDebug(
              '本次加载${quotes.length}条，去重后添加${newQuotes.length}条，总计${_currentQuotes.length}条');
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
    _cacheHits++;

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

  /// 更新分类信息
  Future<void> updateCategory(
    String id,
    String name, {
    String? iconName,
  }) async {
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
    try {
      // 检查数据库是否已初始化 - 在初始化过程中允许执行
      if (_database == null) {
        throw Exception('数据库未初始化，无法执行 day_period 字段补全');
      }

      final db = _database!;
      final List<Map<String, dynamic>> maps = await db.query('quotes');

      if (maps.isEmpty) {
        logDebug('没有需要补全 day_period 字段的记录');
        return;
      }

      int patchedCount = 0;
      for (final map in maps) {
        if (map['day_period'] == null ||
            (map['day_period'] as String).isEmpty) {
          // 解析时间
          String? dateStr = map['date'];
          if (dateStr == null || dateStr.isEmpty) continue;
          DateTime? dt;
          try {
            dt = DateTime.parse(dateStr);
          } catch (_) {
            continue;
          }
          // 推算时间段key
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
          // 更新数据库
          await db.update(
            'quotes',
            {'day_period': dayPeriodKey},
            where: 'id = ?',
            whereArgs: [map['id']],
          );
          patchedCount++;
        }
      }

      logDebug('已补全 $patchedCount 条记录的 day_period 字段');
    } catch (e) {
      logDebug('补全 day_period 字段失败: $e');
      rethrow;
    }
  }

  /// 修复：安全迁移旧数据dayPeriod字段为英文key
  Future<void> migrateDayPeriodToKey() async {
    try {
      // 检查数据库是否已初始化 - 在初始化过程中允许执行
      if (_database == null) {
        throw Exception('数据库未初始化，无法执行 dayPeriod 字段迁移');
      }

      final db = _database!;

      // 修复：使用事务保护迁移过程
      await db.transaction((txn) async {
        // 1. 创建备份列
        try {
          await txn.execute(
            'ALTER TABLE quotes ADD COLUMN day_period_backup TEXT',
          );

          // 2. 备份原始数据
          await txn.execute(
            'UPDATE quotes SET day_period_backup = day_period WHERE day_period IS NOT NULL',
          );

          logDebug('day_period字段备份完成');
        } catch (e) {
          // 如果列已存在，继续执行
          logDebug('day_period_backup列可能已存在: $e');
        }

        // 3. 查询需要迁移的数据
        final List<Map<String, dynamic>> maps = await txn.query(
          'quotes',
          columns: ['id', 'day_period'],
        );

        if (maps.isEmpty) {
          logDebug('没有需要迁移 dayPeriod 字段的记录');
          return;
        }

        final labelToKey = TimeUtils.dayPeriodKeyToLabel.map(
          (k, v) => MapEntry(v, k),
        );

        int migratedCount = 0;
        int skippedCount = 0;

        for (final map in maps) {
          final id = map['id'] as String?;
          final dayPeriod = map['day_period'] as String?;

          if (id == null || dayPeriod == null || dayPeriod.isEmpty) continue;

          if (labelToKey.containsKey(dayPeriod)) {
            final key = labelToKey[dayPeriod]!;
            await txn.update(
              'quotes',
              {'day_period': key},
              where: 'id = ?',
              whereArgs: [id],
            );
            migratedCount++;
          } else {
            skippedCount++;
          }
        }

        logDebug('dayPeriod字段迁移完成：转换 $migratedCount 条，跳过 $skippedCount 条');

        // 4. 验证迁移结果
        final verifyCount = await txn.rawQuery(
          'SELECT COUNT(*) as count FROM quotes WHERE day_period IS NOT NULL',
        );
        final totalAfter = verifyCount.first['count'] as int;

        if (totalAfter >= migratedCount) {
          logDebug('dayPeriod字段迁移验证通过');
        } else {
          throw Exception('dayPeriod字段迁移验证失败');
        }
      });
    } catch (e) {
      logError('迁移 dayPeriod 字段失败: $e', error: e, source: 'DatabaseService');
      rethrow;
    }
  }

  /// 修复：安全迁移旧数据weather字段为英文key
  Future<void> migrateWeatherToKey() async {
    try {
      if (kIsWeb) {
        int migratedCount = 0;
        for (var i = 0; i < _memoryStore.length; i++) {
          final q = _memoryStore[i];
          if (q.weather != null &&
              WeatherService.weatherKeyToLabel.values.contains(q.weather)) {
            final key = WeatherService.weatherKeyToLabel.entries
                .firstWhere((e) => e.value == q.weather)
                .key;
            _memoryStore[i] = q.copyWith(weather: key);
            migratedCount++;
          }
        }
        notifyListeners();
        logDebug('Web平台已完成 $migratedCount 条记录的 weather 字段 key 迁移');
        return;
      }

      // 检查数据库是否已初始化 - 在初始化过程中允许执行
      if (_database == null) {
        throw Exception('数据库未初始化，无法执行 weather 字段迁移');
      }

      final db = _database!;

      // 修复：使用事务保护迁移过程
      await db.transaction((txn) async {
        // 1. 创建备份列
        try {
          await txn.execute(
            'ALTER TABLE quotes ADD COLUMN weather_backup TEXT',
          );

          // 2. 备份原始数据
          await txn.execute(
            'UPDATE quotes SET weather_backup = weather WHERE weather IS NOT NULL',
          );

          logDebug('weather字段备份完成');
        } catch (e) {
          // 如果列已存在，继续执行
          logDebug('weather_backup列可能已存在: $e');
        }

        // 3. 查询需要迁移的数据
        final maps = await txn.query('quotes', columns: ['id', 'weather']);

        if (maps.isEmpty) {
          logDebug('没有需要迁移 weather 字段的记录');
          return;
        }

        int migratedCount = 0;
        int skippedCount = 0;

        for (final m in maps) {
          final id = m['id'] as String?;
          final weather = m['weather'] as String?;

          if (id == null || weather == null || weather.isEmpty) continue;

          // 检查是否需要迁移（是否为中文标签）
          if (WeatherService.weatherKeyToLabel.values.contains(weather)) {
            final key = WeatherService.weatherKeyToLabel.entries
                .firstWhere((e) => e.value == weather)
                .key;

            await txn.update(
              'quotes',
              {'weather': key},
              where: 'id = ?',
              whereArgs: [id],
            );
            migratedCount++;
          } else {
            skippedCount++;
          }
        }

        logDebug('weather字段迁移完成：转换 $migratedCount 条，跳过 $skippedCount 条');

        // 4. 验证迁移结果
        final verifyCount = await txn.rawQuery(
          'SELECT COUNT(*) as count FROM quotes WHERE weather IS NOT NULL',
        );
        final totalAfter = verifyCount.first['count'] as int;

        if (totalAfter >= migratedCount) {
          logDebug('weather字段迁移验证通过');
        } else {
          throw Exception('weather字段迁移验证失败');
        }
      });
    } catch (e) {
      logError('迁移 weather 字段失败: $e', error: e, source: 'DatabaseService');
      rethrow;
    }
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
    if (kIsWeb) return; // Web平台无需数据迁移

    try {
      // 首先检查数据库是否可用
      if (_database == null) {
        logError('数据库不可用，跳过数据迁移操作', source: 'DatabaseService');
        return;
      }

      logDebug('开始执行数据迁移...');

      // 兼容性检查：验证数据库结构完整性（仅在非新建数据库时执行）
      try {
        await _validateDatabaseCompatibility();
      } catch (e) {
        logDebug('数据库兼容性验证跳过: $e');
        // 如果验证失败，可能是新数据库，继续执行其他迁移
      }

      // 检查并迁移天气数据
      await _checkAndMigrateWeatherData();

      // 检查并迁移时间段数据
      await _checkAndMigrateDayPeriodData();

      // 补全缺失的时间段数据
      await patchQuotesDayPeriod();

      // 修复：检查并清理遗留的tag_ids列
      await _cleanupLegacyTagIdsColumn();

      logDebug('所有数据迁移完成');
    } catch (e) {
      logError('数据迁移失败: $e', error: e, source: 'DatabaseService');
      // 不重新抛出异常，避免影响应用启动
    }
  }

  /// 兼容性验证：检查数据库结构完整性
  Future<void> _validateDatabaseCompatibility() async {
    try {
      final db = database;

      // 检查关键表是否存在
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final tableNames = tables.map((t) => t['name'] as String).toSet();

      final requiredTables = {'quotes', 'categories', 'quote_tags'};
      final missingTables = requiredTables.difference(tableNames);

      if (missingTables.isNotEmpty) {
        logError('缺少必要的数据库表: $missingTables', source: 'DatabaseService');
        throw Exception('数据库结构不完整，缺少表: $missingTables');
      }

      // 检查quote_tags表的数据完整性
      final quoteTagsCount = await db.rawQuery(
        'SELECT COUNT(*) as count FROM quote_tags',
      );

      // 修复：检查quotes表中是否还有tag_ids列，如果有则说明迁移未完成
      final tableInfo = await db.rawQuery('PRAGMA table_info(quotes)');
      final hasTagIdsColumn = tableInfo.any((col) => col['name'] == 'tag_ids');

      if (hasTagIdsColumn) {
        // 如果还有tag_ids列，检查是否有数据需要迁移
        final quotesWithTagsCount = await db.rawQuery(
          'SELECT COUNT(*) as count FROM quotes WHERE tag_ids IS NOT NULL AND tag_ids != ""',
        );
        logDebug(
          '兼容性检查完成 - quote_tags表记录数: ${quoteTagsCount.first['count']}, '
          '有tag_ids列的quotes记录数: ${quotesWithTagsCount.first['count']}',
        );
      } else {
        logDebug(
          '兼容性检查完成 - quote_tags表记录数: ${quoteTagsCount.first['count']}, '
          'tag_ids列已迁移完成',
        );
      }
    } catch (e) {
      logError('数据库兼容性验证失败: $e', error: e, source: 'DatabaseService');
      // 不抛出异常，让应用继续运行
    }
  }

  /// 优化：添加dispose方法，确保资源正确释放
  /// 注意：这是新增方法，现有代码调用时需要确保在适当时机调用dispose()
  @override
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

    super.dispose();
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
    final reportBuilder = MergeReportBuilder(sourceDevice: sourceDevice);
    // 分类ID重映射：用于处理不同设备上相同名称分类(标签)导致的ID不一致与重复问题
    final Map<String, String> categoryIdRemap = {}; // remoteId -> localId

    try {
      final db = database;

      // 验证数据格式
      if (!data.containsKey('categories') || !data.containsKey('quotes')) {
        reportBuilder.addError('备份数据格式无效，缺少 "categories" 或 "quotes" 键');
        return reportBuilder.build();
      }

      await db.transaction((txn) async {
        await _mergeCategories(
          txn,
          data['categories'] as List,
          reportBuilder,
          categoryIdRemap,
        );
        await _mergeQuotes(
          txn,
          data['quotes'] as List,
          reportBuilder,
          categoryIdRemap,
        );
      });

      // 清理缓存并通知监听器，然后刷新当前流（如果存在）
      _clearAllCache();
      notifyListeners();
      _refreshQuotesStream();

      logInfo('LWW合并完成: ${reportBuilder.build().summary}');
    } catch (e) {
      reportBuilder.addError('合并过程发生错误: $e');
      logError('LWW合并失败: $e', error: e, source: 'DatabaseService');
    }

    return reportBuilder.build();
  }

  /// 外部调用的统一刷新入口（同步/恢复后使用）
  void refreshAllData() {
    _clearAllCache();
    notifyListeners();
    _refreshQuotesStream();
  }

  /// 合并分类数据（LWW策略）
  Future<void> _mergeCategories(
    Transaction txn,
    List categories,
    MergeReportBuilder reportBuilder,
    Map<String, String> categoryIdRemap,
  ) async {
    // 预先加载本地分类，建立名称(小写)->行、ID->行映射，便于避免 O(n^2) 查询
    final existingCategoryRows = await txn.query('categories');
    final Map<String, Map<String, dynamic>> idToRow = {
      for (final row in existingCategoryRows) (row['id'] as String): row
    };
    final Map<String, Map<String, dynamic>> nameLowerToRow = {
      for (final row in existingCategoryRows)
        (row['name'] as String).toLowerCase(): row
    };

    for (final c in categories) {
      try {
        final categoryData =
            Map<String, dynamic>.from(c as Map<String, dynamic>);

        // 标准化字段名
        const categoryFieldMappings = {
          'isDefault': 'is_default',
          'iconName': 'icon_name',
        };
        for (final mapping in categoryFieldMappings.entries) {
          if (categoryData.containsKey(mapping.key)) {
            categoryData[mapping.value] = categoryData[mapping.key];
            categoryData.remove(mapping.key);
          }
        }

        final remoteId = (categoryData['id'] as String?) ?? _uuid.v4();
        categoryData['id'] = remoteId; // 统一
        final remoteName = (categoryData['name'] as String?) ?? '未命名分类';
        categoryData['name'] = remoteName;
        categoryData['is_default'] ??= 0;
        categoryData['last_modified'] ??= DateTime.now().toIso8601String();

        // 1. 优先按ID匹配
        if (idToRow.containsKey(remoteId)) {
          final existing = idToRow[remoteId]!;
          final decision = LWWDecisionMaker.makeDecision(
            localTimestamp: existing['last_modified'] as String?,
            remoteTimestamp: categoryData['last_modified'] as String?,
          );
          if (decision.shouldUseRemote) {
            await txn.update('categories', categoryData,
                where: 'id = ?', whereArgs: [remoteId]);
            reportBuilder.addUpdatedCategory();
            // 更新缓存
            idToRow[remoteId] = categoryData;
            nameLowerToRow[remoteName.toLowerCase()] = categoryData;
          } else {
            reportBuilder.addSkippedCategory();
          }
          categoryIdRemap[remoteId] = remoteId; // identity
          continue;
        }

        // 2. 按名称(小写)匹配，处理不同设备相同名称但不同ID的情况 -> 复用本地ID，建立重映射
        final nameKey = remoteName.toLowerCase();
        if (nameLowerToRow.containsKey(nameKey)) {
          final existing = nameLowerToRow[nameKey]!;
          final existingId = existing['id'] as String;
          final decision = LWWDecisionMaker.makeDecision(
            localTimestamp: existing['last_modified'] as String?,
            remoteTimestamp: categoryData['last_modified'] as String?,
          );
          if (decision.shouldUseRemote) {
            // 仅更新可变字段（名称相同无需变更）
            final updateMap = Map<String, dynamic>.from(existing)
              ..addAll({
                'icon_name': categoryData['icon_name'],
                'is_default': categoryData['is_default'],
                'last_modified': categoryData['last_modified'],
              });
            await txn.update('categories', updateMap,
                where: 'id = ?', whereArgs: [existingId]);
            idToRow[existingId] = updateMap;
            nameLowerToRow[nameKey] = updateMap;
            reportBuilder.addUpdatedCategory();
          } else {
            reportBuilder.addSkippedCategory();
          }
          categoryIdRemap[remoteId] = existingId;
          continue;
        }

        // 3. 新分类，直接插入
        await txn.insert('categories', categoryData);
        idToRow[remoteId] = categoryData;
        nameLowerToRow[nameKey] = categoryData;
        categoryIdRemap[remoteId] = remoteId;
        reportBuilder.addInsertedCategory();
      } catch (e) {
        reportBuilder.addError('处理分类失败: $e');
      }
    }
  }

  /// 合并笔记数据（LWW策略）
  Future<void> _mergeQuotes(
    Transaction txn,
    List quotes,
    MergeReportBuilder reportBuilder,
    Map<String, String> categoryIdRemap,
  ) async {
    // 预加载当前事务中有效的分类ID集合，用于过滤无效的远程标签引用，防止外键错误
    final existingCategoryIdRows =
        await txn.query('categories', columns: ['id']);
    final Set<String> validCategoryIds = existingCategoryIdRows
        .map((r) => r['id'] as String)
        .whereType<String>()
        .toSet();

    for (final q in quotes) {
      try {
        final quoteData = Map<String, dynamic>.from(q as Map<String, dynamic>);

        // 标准化字段名
        final fieldMappings = {
          'sourceAuthor': 'source_author',
          'sourceWork': 'source_work',
          'categoryld': 'category_id',
          'categoryId': 'category_id',
          'aiAnalysis': 'ai_analysis',
          'colorHex': 'color_hex',
          'editSource': 'edit_source',
          'deltaContent': 'delta_content',
          'dayPeriod': 'day_period',
        };

        for (final mapping in fieldMappings.entries) {
          if (quoteData.containsKey(mapping.key)) {
            quoteData[mapping.value] = quoteData[mapping.key];
            quoteData.remove(mapping.key);
          }
        }

        // 提取并解析 tag_ids (字符串或列表)，稍后写入 quote_tags
        List<String> parsedTagIds = [];
        if (quoteData.containsKey('tag_ids')) {
          final raw = quoteData['tag_ids'];
          if (raw is String) {
            if (raw.isNotEmpty) {
              parsedTagIds = raw
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toSet()
                  .toList();
            }
          } else if (raw is List) {
            parsedTagIds = raw
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList();
          }
          quoteData.remove('tag_ids'); // 不存储在 quotes 表
        }

        // 重映射 category_id （如果存在）
        final originalCategoryId = quoteData['category_id'] as String?;
        if (originalCategoryId != null &&
            categoryIdRemap.containsKey(originalCategoryId)) {
          quoteData['category_id'] = categoryIdRemap[originalCategoryId];
        }

        // 重映射标签ID并去重
        final remappedTagIds = <String>{};
        for (final tid in parsedTagIds) {
          final mapped = categoryIdRemap[tid] ?? tid; // 若未重映射则保持原ID
          if (validCategoryIds.contains(mapped)) {
            remappedTagIds.add(mapped);
          }
        }

        // 确保必要字段存在
        final quoteId = quoteData['id'] ??= _uuid.v4();
        quoteData['content'] ??= '';
        quoteData['date'] ??= DateTime.now().toIso8601String();
        quoteData['last_modified'] ??=
            (quoteData['date'] as String? ?? DateTime.now().toIso8601String());

        // 查询本地是否存在该笔记
        final existingRows = await txn.query(
          'quotes',
          where: 'id = ?',
          whereArgs: [quoteId],
        );

        bool inserted = false;
        if (existingRows.isEmpty) {
          await txn.insert('quotes', quoteData);
          reportBuilder.addInsertedQuote();
          inserted = true;
        } else {
          final existingQuote = existingRows.first;
          final decision = LWWDecisionMaker.makeDecision(
            localTimestamp: existingQuote['last_modified'] as String?,
            remoteTimestamp: quoteData['last_modified'] as String?,
            localContent: existingQuote['content'] as String?,
            remoteContent: quoteData['content'] as String?,
            checkContentSimilarity: true,
          );
          if (decision.shouldUseRemote) {
            await txn.update('quotes', quoteData,
                where: 'id = ?', whereArgs: [quoteId]);
            reportBuilder.addUpdatedQuote();
          } else if (decision.hasConflict) {
            reportBuilder.addSameTimestampDiffQuote();
          } else {
            reportBuilder.addSkippedQuote();
          }
        }

        // 写入标签关联 (插入或更新场景都需要同步), 仅当存在标签
        if (remappedTagIds.isNotEmpty) {
          // 如果是更新，先清理旧关联
          if (!inserted) {
            await txn.delete('quote_tags',
                where: 'quote_id = ?', whereArgs: [quoteId]);
          }
          final batch = txn.batch();
          for (final tagId in remappedTagIds) {
            batch.insert(
                'quote_tags',
                {
                  'quote_id': quoteId,
                  'tag_id': tagId,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
          await batch.commit(noResult: true);
        }
      } catch (e) {
        reportBuilder.addError('处理笔记失败: $e');
      }
    }
  }
}
