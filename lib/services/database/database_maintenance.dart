part of '../database_service.dart';

/// DatabaseMaintenanceOperations for DatabaseService.
extension DatabaseMaintenanceOperations on DatabaseService {

  /// 修复：标签数据一致性检查
  Future<Map<String, dynamic>> checkTagDataConsistency() async {
    return _healthService.checkTagDataConsistency(await safeDatabase);
  }

  /// 修复：清理标签数据不一致问题


  /// 修复：清理标签数据不一致问题
  Future<bool> cleanupTagDataInconsistencies() async {
    final result = await _healthService.cleanupTagDataInconsistencies(
      await safeDatabase,
    );
    _clearAllCache();
    return result;
  }

  /// 获取所有笔记
  /// [excludeHiddenNotes] 是否排除隐藏笔记，默认为 true
  /// 注意：媒体引用迁移等需要访问全部数据的场景应传入 false


  /// 批量为旧笔记补全 dayPeriod 字段（根据 date 字段推算并写入）
  Future<void> patchQuotesDayPeriod() async {
    await _schemaManager.patchQuotesDayPeriod(database);
  }

  /// 修复：安全迁移旧数据dayPeriod字段为英文key


  /// 修复：安全迁移旧数据dayPeriod字段为英文key
  Future<void> migrateDayPeriodToKey() async {
    await _schemaManager.migrateDayPeriodToKey(database);
  }

  /// 修复：安全迁移旧数据weather字段为英文key


  /// 修复：安全迁移旧数据weather字段为英文key
  Future<void> migrateWeatherToKey() async {
    await _schemaManager.migrateWeatherToKey(
      database,
      memoryStore: _memoryStore,
    );
  }

  Future<void> _cleanupLegacyTagIdsColumn() async {


  Future<void> _cleanupLegacyTagIdsColumn() async {
    await _schemaManager.cleanupLegacyTagIdsColumn(database);
  }

  /// 根据 ID 获取分类


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


  /// 获取数据库健康状态信息
  Future<Map<String, dynamic>> getDatabaseHealthInfo() async {
    return _healthService.getDatabaseHealthInfo(
      await safeDatabase,
      webQuoteCount: _memoryStore.length,
      webCategoryCount: _categoryStore.length,
    );
  }
}

}
