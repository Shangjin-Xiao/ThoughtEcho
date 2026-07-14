part of '../database_schema_manager.dart';

/// Coordinates every schema lifecycle operation behind one migration policy.
class DatabaseSchemaLifecycle {
  DatabaseSchemaLifecycle._({
    required DatabaseSchemaDefinitions definitions,
    required SchemaMigrationPolicy migrationPolicy,
    required SchemaValidationAdapter validation,
    required SchemaRepairAdapter repair,
    required SchemaDataBackfillAdapter backfill,
  })  : _definitions = definitions,
        _migrationPolicy = migrationPolicy,
        _validation = validation,
        _repair = repair,
        _backfill = backfill;

  factory DatabaseSchemaLifecycle.standard() {
    final definitions = DatabaseSchemaDefinitions();
    final legacyTags = SchemaLegacyTagAdapter(definitions);
    final validation = SchemaValidationAdapter(definitions);
    return DatabaseSchemaLifecycle._(
      definitions: definitions,
      migrationPolicy: SchemaMigrationPolicy(
        SchemaVersionAdapters(definitions, legacyTags).adapters,
      ),
      validation: validation,
      repair: SchemaRepairAdapter(definitions, validation),
      backfill: SchemaDataBackfillAdapter(
        definitions,
        validation,
        legacyTags,
      ),
    );
  }

  final DatabaseSchemaDefinitions _definitions;
  final SchemaMigrationPolicy _migrationPolicy;
  final SchemaValidationAdapter _validation;
  final SchemaRepairAdapter _repair;
  final SchemaDataBackfillAdapter _backfill;

  Future<void> createCurrentSchema(Database database) async {
    await _definitions.createCurrentSchema(database);
    await configureDatabasePragmas(database, inTransaction: true);
    await _validation.validate(database);
  }

  Future<void> upgrade(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion >= newVersion) {
      return;
    }
    if (newVersion > DatabaseSchemaDefinitions.schemaVersion) {
      throw ArgumentError.value(
        newVersion,
        'newVersion',
        'Cannot upgrade beyond the current schema version',
      );
    }

    logDebug('开始数据库升级: $oldVersion -> $newVersion');
    try {
      await database.transaction((transaction) async {
        await _createUpgradeBackup(transaction, oldVersion);
        await _migrationPolicy.apply(
          transaction,
          fromVersion: oldVersion,
          toVersion: newVersion,
        );
        await _validation.validateTransaction(transaction);
      });
      logDebug('数据库升级成功完成');
    } catch (error, stackTrace) {
      logError(
        '数据库升级失败: $error',
        error: error,
        stackTrace: stackTrace,
        source: 'DatabaseUpgrade',
      );
      rethrow;
    }
  }

  Future<void> repair(Database database) => _repair.repair(database);

  Future<void> validate(Database database) => _validation.validate(database);

  Future<void> backfill(Database? database) => _backfill.run(database);

  Future<void> patchQuotesDayPeriod(Database? database) =>
      _backfill.patchQuotesDayPeriod(database);

  Future<void> migrateDayPeriodToKey(Database? database) =>
      _backfill.migrateDayPeriodToKey(database);

  Future<void> migrateWeatherToKey(
    Database? database, {
    required List<Quote> memoryStore,
  }) =>
      _backfill.migrateWeatherToKey(database, memoryStore: memoryStore);

  Future<void> cleanupLegacyTagIdsColumn(Database database) =>
      _backfill.cleanupLegacyTagIdsColumn(database);

  Future<void> verifyForeignKeysEnabled(Database database) async {
    try {
      final result = await database.rawQuery('PRAGMA foreign_keys');
      final isEnabled = result.isNotEmpty && result.first['foreign_keys'] == 1;
      if (isEnabled) {
        logDebug('✅ 外键约束已启用，数据完整性受保护');
      } else {
        logError(
          '⚠️ 警告：外键约束未启用，可能影响数据完整性',
          source: 'DatabaseService',
        );
      }
    } catch (error, stackTrace) {
      logError(
        '验证外键约束状态失败: $error',
        error: error,
        stackTrace: stackTrace,
        source: 'DatabaseService',
      );
    }
  }

  Future<void> configureDatabasePragmas(
    Database database, {
    required bool inTransaction,
  }) async {
    try {
      await database.rawQuery('PRAGMA foreign_keys = ON');
      await database.rawQuery('PRAGMA busy_timeout = 5000');
      await database.rawQuery('PRAGMA cache_size = -8000');
      await database.rawQuery('PRAGMA temp_store = MEMORY');

      if (!inTransaction) {
        await database.rawQuery('PRAGMA journal_mode = WAL');
        await database.rawQuery('PRAGMA synchronous = NORMAL');
      }

      final foreignKeys = await database.rawQuery('PRAGMA foreign_keys');
      final journalMode = await database.rawQuery('PRAGMA journal_mode');
      logDebug(
        '数据库PRAGMA配置完成 (inTransaction=$inTransaction): '
        'foreign_keys=${foreignKeys.first['foreign_keys']}, '
        'journal_mode=${journalMode.first['journal_mode']}',
      );
    } catch (error, stackTrace) {
      logError(
        '配置数据库PRAGMA失败: $error',
        error: error,
        stackTrace: stackTrace,
        source: 'DatabaseService',
      );
    }
  }

  Future<void> _createUpgradeBackup(
    Transaction transaction,
    int oldVersion,
  ) async {
    logDebug('创建数据库升级备份...');
    await transaction.execute('''
      CREATE TABLE IF NOT EXISTS quotes_backup_v$oldVersion AS
      SELECT * FROM quotes
    ''');
    await transaction.execute('''
      CREATE TABLE IF NOT EXISTS categories_backup_v$oldVersion AS
      SELECT * FROM categories
    ''');

    final tables = await transaction.rawQuery(
      'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
      <Object?>['table', 'quote_tags'],
    );
    if (tables.isNotEmpty) {
      final tableName = 'quote_tags_backup_v$oldVersion';
      await transaction.execute('''
        CREATE TABLE IF NOT EXISTS $tableName AS
        SELECT * FROM quote_tags
      ''');
    }
    logDebug('升级备份创建完成');
  }
}
