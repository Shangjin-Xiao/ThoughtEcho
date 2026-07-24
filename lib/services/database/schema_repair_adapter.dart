part of '../database_schema_manager.dart';

/// Validates the full current schema after creation, upgrade and repair.
class SchemaValidationAdapter {
  SchemaValidationAdapter(this._definitions);

  final DatabaseSchemaDefinitions _definitions;

  Future<void> validate(Database database) => _validate(database);

  Future<void> validateTransaction(Transaction transaction) =>
      _validate(transaction);

  Future<void> _validate(DatabaseExecutor executor) async {
    final tables = await _definitions.tableNames(executor);
    final missingTables =
        DatabaseSchemaDefinitions.requiredTables.difference(tables);
    if (missingTables.isNotEmpty) {
      throw StateError('数据库结构不完整，缺少表: $missingTables');
    }

    final quoteColumns = await _definitions.columnNames(executor, 'quotes');
    final missingColumns =
        DatabaseSchemaDefinitions.requiredQuoteColumns.difference(quoteColumns);
    if (missingColumns.isNotEmpty) {
      throw StateError('quotes 表缺少必要列: $missingColumns');
    }

    final indexes = await executor.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    );
    final indexNames = indexes.map((index) => index['name'] as String).toSet();
    final missingIndexes = DatabaseSchemaDefinitions.requiredIndexNames
        .toSet()
        .difference(indexNames);
    if (missingIndexes.isNotEmpty) {
      throw StateError('数据库结构不完整，缺少索引: $missingIndexes');
    }

    logDebug('数据库schema验证通过');
  }
}

/// Repairs interrupted historical upgrades before startup data backfills run.
class SchemaRepairAdapter {
  SchemaRepairAdapter(this._definitions, this._validation);

  final DatabaseSchemaDefinitions _definitions;
  final SchemaValidationAdapter _validation;

  Future<void> repair(Database database) async {
    try {
      await database.transaction((transaction) async {
        final tables = await _definitions.tableNames(transaction);
        final missingBaseTables =
            <String>{'quotes', 'categories'}.difference(tables);
        if (missingBaseTables.isNotEmpty) {
          throw StateError('无法修复缺少基础表的数据库: $missingBaseTables');
        }

        final quoteColumns =
            await _definitions.columnNames(transaction, 'quotes');
        for (final entry
            in DatabaseSchemaDefinitions.repairableQuoteColumns.entries) {
          if (!quoteColumns.contains(entry.key)) {
            final colName = entry.key;
            final colDef = entry.value;
            // 🛡️ Sentinel: 安全校验，防止 DDL 注入
            if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(colName)) {
              throw StateError('不安全的列名: $colName');
            }
            if (!RegExp(
                    r"^[a-zA-Z0-9_ ]+(?:DEFAULT (?:'[a-zA-Z0-9_]*'|[0-9]+))?$")
                .hasMatch(colDef)) {
              throw StateError('不安全的列定义: $colDef');
            }
            // ignore: prefer_interpolation_to_compose_strings
            final safeColName = '"' + colName.replaceAll('"', '""') + '"';
            // ignore: prefer_interpolation_to_compose_strings
            final query =
                'ALTER TABLE quotes ADD COLUMN ' + safeColName + ' ' + colDef;
            await transaction.execute(query);
            logDebug('数据库repair添加 quotes.$colName');
          }
        }

        final categoryColumns =
            await _definitions.columnNames(transaction, 'categories');
        if (!categoryColumns.contains('icon_name')) {
          await transaction
              .execute('ALTER TABLE categories ADD COLUMN icon_name TEXT');
        }
        if (!categoryColumns.contains('last_modified')) {
          await transaction.execute(
            'ALTER TABLE categories ADD COLUMN last_modified TEXT',
          );
        }

        await _definitions.ensureCurrentIndexes(transaction);
        await _definitions.ensureQuoteTagsTable(transaction);
        await _definitions.ensureQuoteTombstonesTable(transaction);
        await _definitions.ensureMediaReferencesTable(transaction);
        await _validation.validateTransaction(transaction);
      });
    } catch (error, stackTrace) {
      logError(
        '检查或修复数据库结构失败: $error',
        error: error,
        stackTrace: stackTrace,
        source: 'DatabaseStructureRepair',
      );
      rethrow;
    }
  }
}

/// Performs post-schema data backfills. Failures remain visible to startup so a
/// partially migrated database is never treated as ready.
class SchemaDataBackfillAdapter {
  SchemaDataBackfillAdapter(
    this._definitions,
    this._validation,
    this._legacyTags,
  );

  final DatabaseSchemaDefinitions _definitions;
  final SchemaValidationAdapter _validation;
  final SchemaLegacyTagAdapter _legacyTags;

  Future<void> run(Database? database) async {
    if (kIsWeb) {
      return;
    }
    if (database == null) {
      throw StateError('数据库未初始化，无法执行数据迁移');
    }

    try {
      await _validation.validate(database);
      await _checkAndMigrateWeatherData(database);
      await _checkAndMigrateDayPeriodData(database);
      await patchQuotesDayPeriod(database);
      await cleanupLegacyTagIdsColumn(database);
      logDebug('所有数据迁移完成');
    } catch (error, stackTrace) {
      logError(
        '数据迁移失败: $error',
        error: error,
        stackTrace: stackTrace,
        source: 'DatabaseDataBackfill',
      );
      rethrow;
    }
  }

  Future<void> _checkAndMigrateWeatherData(Database database) async {
    final weatherCheck = await database.query(
      'quotes',
      where: "weather IS NOT NULL AND weather != ''",
      limit: 1,
    );
    if (weatherCheck.isEmpty) {
      return;
    }

    final weather = weatherCheck.first['weather'] as String?;
    if (weather != null &&
        WeatherService.legacyWeatherKeyToLabel.values.contains(weather)) {
      logDebug('检测到未迁移的weather数据，开始迁移...');
      await migrateWeatherToKey(database);
    }
  }

  Future<void> _checkAndMigrateDayPeriodData(Database database) async {
    final dayPeriodCheck = await database.query(
      'quotes',
      where: "day_period IS NOT NULL AND day_period != ''",
      limit: 1,
    );
    if (dayPeriodCheck.isEmpty) {
      return;
    }

    final dayPeriod = dayPeriodCheck.first['day_period'] as String?;
    final labelToKey = TimeUtils.dayPeriodKeyToLabel.map(
      (key, label) => MapEntry(label, key),
    );
    if (dayPeriod != null && labelToKey.containsKey(dayPeriod)) {
      logDebug('检测到未迁移的day_period数据，开始迁移...');
      await migrateDayPeriodToKey(database);
    }
  }

  Future<void> patchQuotesDayPeriod(Database? database) async {
    if (database == null) {
      throw StateError('数据库未初始化，无法执行 day_period 字段补全');
    }

    try {
      final count = await database.rawUpdate('''
        UPDATE quotes
        SET day_period = CASE
          WHEN CAST(strftime('%H', date) AS INTEGER) >= 5 AND CAST(strftime('%H', date) AS INTEGER) < 8 THEN 'dawn'
          WHEN CAST(strftime('%H', date) AS INTEGER) >= 8 AND CAST(strftime('%H', date) AS INTEGER) < 12 THEN 'morning'
          WHEN CAST(strftime('%H', date) AS INTEGER) >= 12 AND CAST(strftime('%H', date) AS INTEGER) < 17 THEN 'afternoon'
          WHEN CAST(strftime('%H', date) AS INTEGER) >= 17 AND CAST(strftime('%H', date) AS INTEGER) < 20 THEN 'dusk'
          WHEN CAST(strftime('%H', date) AS INTEGER) >= 20 AND CAST(strftime('%H', date) AS INTEGER) < 23 THEN 'evening'
          ELSE 'midnight'
        END
        WHERE (day_period IS NULL OR day_period = '')
          AND date IS NOT NULL
          AND date != ''
          AND strftime('%H', date) IS NOT NULL
      ''');
      logDebug(
        count > 0
            ? '已批量补全 $count 条记录的 day_period 字段'
            : '没有需要补全 day_period 字段的记录',
      );
    } catch (error, stackTrace) {
      logError(
        '补全 day_period 字段失败: $error',
        error: error,
        stackTrace: stackTrace,
        source: 'DatabaseDataBackfill',
      );
      rethrow;
    }
  }

  Future<void> migrateDayPeriodToKey(Database? database) async {
    if (database == null) {
      throw StateError('数据库未初始化，无法执行 dayPeriod 字段迁移');
    }

    try {
      await database.transaction((transaction) async {
        await _ensureBackupColumn(
          transaction,
          columnName: 'day_period_backup',
          sourceColumn: 'day_period',
        );

        final labelToKey = TimeUtils.dayPeriodKeyToLabel.map(
          (key, label) => MapEntry(label, key),
        );
        var migratedCount = 0;
        final batch = transaction.batch();
        for (final entry in labelToKey.entries) {
          batch.update(
            'quotes',
            {'day_period': entry.value},
            where: 'day_period = ?',
            whereArgs: [entry.key],
          );
        }
        final results = await batch.commit();
        for (final result in results) {
          migratedCount += (result as int?) ?? 0;
        }
        if (migratedCount == 0) {
          logDebug('没有需要迁移 dayPeriod 字段的记录');
          return;
        }

        final verifyCount = await transaction.rawQuery(
          'SELECT COUNT(*) as count FROM quotes WHERE day_period IS NOT NULL',
        );
        final totalAfter = verifyCount.first['count'] as int;
        if (totalAfter < migratedCount) {
          throw StateError('dayPeriod字段迁移验证失败');
        }
        logDebug('dayPeriod字段迁移完成：转换 $migratedCount 条');
      });
    } catch (error, stackTrace) {
      logError(
        '迁移 dayPeriod 字段失败: $error',
        error: error,
        stackTrace: stackTrace,
        source: 'DatabaseDataBackfill',
      );
      rethrow;
    }
  }

  Future<void> migrateWeatherToKey(
    Database? database, {
    List<Quote> memoryStore = const <Quote>[],
  }) async {
    if (kIsWeb) {
      var migratedCount = 0;
      for (var index = 0; index < memoryStore.length; index++) {
        final quote = memoryStore[index];
        if (quote.weather != null &&
            WeatherService.legacyWeatherKeyToLabel.values
                .contains(quote.weather)) {
          final key = WeatherService.legacyWeatherKeyToLabel.entries
              .firstWhere((entry) => entry.value == quote.weather)
              .key;
          memoryStore[index] = quote.copyWith(weather: key);
          migratedCount++;
        }
      }
      logDebug('Web平台已完成 $migratedCount 条记录的 weather 字段 key 迁移');
      return;
    }
    if (database == null) {
      throw StateError('数据库未初始化，无法执行 weather 字段迁移');
    }

    try {
      await database.transaction((transaction) async {
        await _ensureBackupColumn(
          transaction,
          columnName: 'weather_backup',
          sourceColumn: 'weather',
        );

        var migratedCount = 0;
        final batch = transaction.batch();
        for (final entry in WeatherService.legacyWeatherKeyToLabel.entries) {
          batch.update(
            'quotes',
            {'weather': entry.key},
            where: 'weather = ?',
            whereArgs: [entry.value],
          );
        }
        final results = await batch.commit();
        for (final result in results) {
          migratedCount += (result as int?) ?? 0;
        }
        if (migratedCount == 0) {
          logDebug('没有需要迁移 weather 字段的记录');
          return;
        }

        final verifyCount = await transaction.rawQuery(
          'SELECT COUNT(*) as count FROM quotes WHERE weather IS NOT NULL',
        );
        final totalAfter = verifyCount.first['count'] as int;
        if (totalAfter < migratedCount) {
          throw StateError('weather字段迁移验证失败');
        }
        logDebug('weather字段迁移完成：转换 $migratedCount 条');
      });
    } catch (error, stackTrace) {
      logError(
        '迁移 weather 字段失败: $error',
        error: error,
        stackTrace: stackTrace,
        source: 'DatabaseDataBackfill',
      );
      rethrow;
    }
  }

  Future<void> cleanupLegacyTagIdsColumn(Database database) async {
    await _legacyTags.cleanup(database);
  }

  Future<void> _ensureBackupColumn(
    Transaction transaction, {
    required String columnName,
    required String sourceColumn,
  }) async {
    final columns = await _definitions.columnNames(transaction, 'quotes');
    if (columns.contains(columnName)) {
      return;
    }
    // 🛡️ Sentinel: 安全校验，防止 DDL 注入
    if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(columnName) ||
        !RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(sourceColumn)) {
      throw StateError('不安全的列名: $columnName 或 $sourceColumn');
    }
    // ignore: prefer_interpolation_to_compose_strings
    final safeColumnName = '"' + columnName.replaceAll('"', '""') + '"';
    // ignore: prefer_interpolation_to_compose_strings
    final safeSourceColumn = '"' + sourceColumn.replaceAll('"', '""') + '"';

    // ignore: prefer_interpolation_to_compose_strings
    final queryAlter =
        'ALTER TABLE quotes ADD COLUMN ' + safeColumnName + ' TEXT';
    await transaction.execute(queryAlter);

    // ignore: prefer_interpolation_to_compose_strings
    final queryUpdate = 'UPDATE quotes SET ' +
        safeColumnName +
        ' = ' +
        safeSourceColumn +
        ' WHERE ' +
        safeSourceColumn +
        ' IS NOT NULL';
    await transaction.execute(queryUpdate);
  }
}

/// Safely transfers the retired comma-separated tag column to quote_tags.
class SchemaLegacyTagAdapter {
  SchemaLegacyTagAdapter(this._definitions);

  final DatabaseSchemaDefinitions _definitions;

  Future<void> upgrade(Transaction transaction) async {
    await _definitions.ensureQuoteTagsTable(transaction);
    await _migrateTagData(transaction);
    await _removeTagIdsColumn(transaction);
  }

  Future<void> cleanup(Database database) async {
    final columns = await _definitions.columnNames(database, 'quotes');
    if (!columns.contains('tag_ids')) {
      return;
    }
    try {
      await database.transaction(upgrade);
      logDebug('遗留tag_ids列清理完成');
    } catch (error, stackTrace) {
      logError(
        '清理遗留tag_ids列失败: $error',
        error: error,
        stackTrace: stackTrace,
        source: 'DatabaseLegacyTagMigration',
      );
      rethrow;
    }
  }

  Future<void> _migrateTagData(Transaction transaction) async {
    final columns = await _definitions.columnNames(transaction, 'quotes');
    if (!columns.contains('tag_ids')) {
      return;
    }

    final quotesWithTags = await transaction.query(
      'quotes',
      columns: const <String>['id', 'tag_ids'],
      where: "tag_ids IS NOT NULL AND tag_ids != ''",
    );
    if (quotesWithTags.isEmpty) {
      return;
    }

    final categories =
        await transaction.query('categories', columns: const <String>['id']);
    final categoryIds =
        categories.map((category) => category['id'] as String).toSet();
    final batch = transaction.batch();

    for (final quote in quotesWithTags) {
      final quoteId = quote['id'] as String;
      final tagIds = (quote['tag_ids'] as String)
          .split(',')
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty && categoryIds.contains(id));
      for (final tagId in tagIds) {
        batch.insert(
          'quote_tags',
          <String, Object?>{'quote_id': quoteId, 'tag_id': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> _removeTagIdsColumn(Transaction transaction) async {
    final columns = await _definitions.columnNames(transaction, 'quotes');
    if (!columns.contains('tag_ids')) {
      return;
    }

    await transaction.execute(_definitions.quotesTableSql('quotes_new'));
    String selectExpression(String column, String fallback) =>
        columns.contains(column) ? column : fallback;

    await transaction.execute('''
      INSERT INTO quotes_new (
        id, content, date, source, source_author, source_work, ai_analysis,
        sentiment, keywords, summary, category_id, color_hex, location,
        latitude, longitude, poi_name, weather, temperature, edit_source,
        delta_content, day_period, last_modified, favorite_count, is_deleted,
        deleted_at
      )
      SELECT
        ${selectExpression('id', "''")},
        ${selectExpression('content', "''")},
        ${selectExpression('date', "''")},
        ${selectExpression('source', 'NULL')},
        ${selectExpression('source_author', 'NULL')},
        ${selectExpression('source_work', 'NULL')},
        ${selectExpression('ai_analysis', 'NULL')},
        ${selectExpression('sentiment', 'NULL')},
        ${selectExpression('keywords', 'NULL')},
        ${selectExpression('summary', 'NULL')},
        ${selectExpression('category_id', "''")},
        ${selectExpression('color_hex', 'NULL')},
        ${selectExpression('location', 'NULL')},
        ${selectExpression('latitude', 'NULL')},
        ${selectExpression('longitude', 'NULL')},
        ${selectExpression(DatabaseSchemaDefinitions.poiNameColumn, 'NULL')},
        ${selectExpression('weather', 'NULL')},
        ${selectExpression('temperature', 'NULL')},
        ${selectExpression('edit_source', 'NULL')},
        ${selectExpression('delta_content', 'NULL')},
        ${selectExpression('day_period', 'NULL')},
        ${selectExpression('last_modified', 'NULL')},
        COALESCE(${selectExpression('favorite_count', '0')}, 0),
        COALESCE(${selectExpression('is_deleted', '0')}, 0),
        ${selectExpression('deleted_at', 'NULL')}
      FROM quotes
    ''');
    await transaction.execute('DROP TABLE quotes');
    await transaction.execute('ALTER TABLE quotes_new RENAME TO quotes');
    await _definitions.ensureQuoteIndexes(transaction);
  }
}
