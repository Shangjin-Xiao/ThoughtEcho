part of '../database_service.dart';

/// Mixin providing import/export operations for DatabaseService.
mixin _DatabaseImportExportMixin on _DatabaseServiceBase {
  /// 从Map对象导入数据
  @override
  Future<void> importDataFromMap(
    Map<String, dynamic> data, {
    bool clearExisting = true,
  }) async {
    await _backupService.importDataFromMap(
      database,
      data,
      clearExisting: clearExisting,
    );
    await _triggerPostRestoreMigrations();
    await updateCategoriesStreamForParts();
    clearAllCacheForParts();
    notifyListeners();
    refreshQuotesStreamForParts();
  }

  /// 从 JSON 文件导入数据
  ///
  /// [filePath] - 导入文件的路径
  /// [clearExisting] - 是否清空现有数据，默认为 true
  @override
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
  @override
  Future<bool> checkCanExport() async {
    return _backupService.checkCanExport(_DatabaseServiceBase._database);
  }

  /// 验证备份文件是否有效
  @override
  Future<bool> validateBackupFile(String filePath) async {
    return _backupService.validateBackupFile(filePath);
  }

  /// LWW (Last-Write-Wins) 合并导入数据
  ///
  /// 使用时间戳比较来决定是否覆盖本地数据
  /// [data] - 远程数据Map
  /// [sourceDevice] - 源设备标识符（可选）
  /// 返回 [MergeReport] 包含合并统计信息
  @override
  Future<MergeReport> importDataWithLWWMerge(
    Map<String, dynamic> data, {
    String? sourceDevice,
  }) async {
    final report = await _backupService.importDataWithLWWMerge(
      database,
      data,
      sourceDevice: sourceDevice,
    );
    if (!report.hasErrors) {
      await _triggerPostRestoreMigrations();
    }
    await updateCategoriesStreamForParts();
    clearAllCacheForParts();
    notifyListeners();
    refreshQuotesStreamForParts();
    return report;
  }

  /// 统一触发恢复/合并后的数据迁移与修补任务
  Future<void> _triggerPostRestoreMigrations() async {
    logDebug('开始触发恢复/合并后数据迁移与修补任务...', source: 'DatabaseService');
    try {
      await patchQuotesDayPeriod();
      await migrateWeatherToKey();
      await migrateDayPeriodToKey();
      await MediaReferenceService.migrateExistingQuotes();
      logDebug('恢复/合并后数据迁移触发完成', source: 'DatabaseService');
    } catch (e, stackTrace) {
      logError(
        '恢复/合并后数据迁移触发失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'DatabaseService',
      );
    }
  }

  /// 开启 SQLite 单一读取事务以获得一致性快照，防止导出/打包时脏读或数据不一致
  Future<T> runWithSnapshotTransaction<T>(
    Future<T> Function(Transaction txn) action,
  ) async {
    return await database.transaction((txn) async {
      return await action(txn);
    });
  }
}
