part of '../database_service.dart';

/// Mixin providing migration and maintenance operations for DatabaseService.
mixin _DatabaseMigrationMixin on ChangeNotifier {
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

  /// 修复：标签数据一致性检查
  Future<Map<String, dynamic>> checkTagDataConsistency() async {
    return _healthService.checkTagDataConsistency(await safeDatabase);
  }

  /// 修复：清理标签数据不一致问题
  Future<bool> cleanupTagDataInconsistencies() async {
    final result = await _healthService.cleanupTagDataInconsistencies(
      await safeDatabase,
    );
    _clearAllCache();
    return result;
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
      logError(
        'getHourDistributionForSmartPush 失败: $e',
        error: e,
        source: 'DatabaseService',
      );
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

  Future<bool> _checkColumnExists(
    Database db,
    String tableName,
    String columnName,
  ) async {
    return _healthService.checkColumnExists(db, tableName, columnName);
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
    return _executeWithLock<Map<String, dynamic>>(
      'databaseMaintenance',
      () async {
        return _healthService.performDatabaseMaintenance(
          await safeDatabase,
          onProgress: onProgress,
        );
      },
    );
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
