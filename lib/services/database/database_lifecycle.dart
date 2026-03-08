part of '../database_service.dart';

/// DatabaseLifecycleOperations for DatabaseService.
extension DatabaseLifecycleOperations on DatabaseService {

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


  /// 验证外键约束是否已启用
  Future<void> _verifyForeignKeysEnabled(Database db) async {
    await _schemaManager.verifyForeignKeysEnabled(db);
  }

  /// 配置数据库安全和性能PRAGMA参数


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


  /// 启动时执行数据库健康检查
  Future<void> _performStartupHealthCheck() async {
    await _healthService.performStartupHealthCheck(await safeDatabase);
  }

  /// 修复：标签数据一致性检查


  /// 优化：在初始化阶段执行所有数据迁移
  /// 兼容性保证：所有迁移都是向后兼容的，不会破坏现有数据
  Future<void> _performAllDataMigrations() async {
    await _schemaManager.performAllDataMigrations(database);
  }

  /// 优化：添加dispose方法，确保资源正确释放
  /// 注意：这是新增方法，现有代码调用时需要确保在适当时机调用dispose()
  @override


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

}
