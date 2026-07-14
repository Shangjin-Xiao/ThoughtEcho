part of '../database_schema_manager.dart';

typedef SchemaVersionMigration = Future<void> Function(Transaction transaction);

/// An immutable adapter for one published schema version.
class SchemaVersionAdapter {
  const SchemaVersionAdapter({
    required this.version,
    required this.description,
    required this.apply,
  });

  final int version;
  final String description;
  final SchemaVersionMigration apply;
}

/// Raised with version context whenever an adapter fails.
class SchemaMigrationException implements Exception {
  const SchemaMigrationException({
    required this.version,
    required this.description,
    required this.cause,
  });

  final int version;
  final String description;
  final Object cause;

  @override
  String toString() =>
      'SchemaMigrationException(v$version: $description, cause: $cause)';
}

/// Applies version adapters in order. No adapter failure is recoverable here:
/// the surrounding database transaction must roll back as one unit.
class SchemaMigrationPolicy {
  SchemaMigrationPolicy(Iterable<SchemaVersionAdapter> adapters)
      : _adapters = List<SchemaVersionAdapter>.of(adapters)
          ..sort((left, right) => left.version.compareTo(right.version)) {
    final duplicateVersions = <int>{};
    int? previousVersion;
    for (final adapter in _adapters) {
      if (previousVersion == adapter.version) {
        duplicateVersions.add(adapter.version);
      }
      previousVersion = adapter.version;
    }
    if (duplicateVersions.isNotEmpty) {
      throw ArgumentError('Duplicate schema adapters: $duplicateVersions');
    }
  }

  final List<SchemaVersionAdapter> _adapters;

  Future<void> apply(
    Transaction transaction, {
    required int fromVersion,
    required int toVersion,
  }) async {
    for (final adapter in _adapters) {
      if (adapter.version <= fromVersion || adapter.version > toVersion) {
        continue;
      }

      try {
        logDebug('执行schema迁移 v${adapter.version}: ${adapter.description}');
        await adapter.apply(transaction);
      } catch (error, stackTrace) {
        final exception = SchemaMigrationException(
          version: adapter.version,
          description: adapter.description,
          cause: error,
        );
        logError(
          'schema迁移 v${adapter.version} 失败: $error',
          error: exception,
          stackTrace: stackTrace,
          source: 'DatabaseUpgrade',
        );
        Error.throwWithStackTrace(exception, stackTrace);
      }
    }
  }
}

/// Historical migrations kept as independently addressable version adapters.
class SchemaVersionAdapters {
  SchemaVersionAdapters(this._definitions, this._legacyTags);

  final DatabaseSchemaDefinitions _definitions;
  final SchemaLegacyTagAdapter _legacyTags;

  late final List<SchemaVersionAdapter> adapters = <SchemaVersionAdapter>[
    SchemaVersionAdapter(
      version: 2,
      description: 'add quotes.tag_ids',
      apply: _upgradeToV2,
    ),
    SchemaVersionAdapter(
      version: 3,
      description: 'add categories.icon_name',
      apply: _upgradeToV3,
    ),
    SchemaVersionAdapter(
      version: 4,
      description: 'add quotes.category_id',
      apply: _upgradeToV4,
    ),
    SchemaVersionAdapter(
      version: 5,
      description: 'add quotes.source',
      apply: _upgradeToV5,
    ),
    SchemaVersionAdapter(
      version: 6,
      description: 'add quotes.color_hex',
      apply: _upgradeToV6,
    ),
    SchemaVersionAdapter(
      version: 7,
      description: 'split quote source metadata',
      apply: _upgradeToV7,
    ),
    SchemaVersionAdapter(
      version: 8,
      description: 'add location and weather columns',
      apply: _upgradeToV8,
    ),
    SchemaVersionAdapter(
      version: 9,
      description: 'add base quote indexes',
      apply: _upgradeToV9,
    ),
    SchemaVersionAdapter(
      version: 10,
      description: 'add quotes.edit_source',
      apply: _upgradeToV10,
    ),
    SchemaVersionAdapter(
      version: 11,
      description: 'add quotes.delta_content',
      apply: _upgradeToV11,
    ),
    SchemaVersionAdapter(
      version: 12,
      description: 'normalize quote tags',
      apply: _upgradeToV12,
    ),
    SchemaVersionAdapter(
      version: 13,
      description: 'create media references',
      apply: _upgradeToV13,
    ),
    SchemaVersionAdapter(
      version: 14,
      description: 'add quotes.day_period',
      apply: _upgradeToV14,
    ),
    SchemaVersionAdapter(
      version: 15,
      description: 'add quotes.last_modified',
      apply: _upgradeToV15,
    ),
    SchemaVersionAdapter(
      version: 16,
      description: 'add categories.last_modified',
      apply: _upgradeToV16,
    ),
    SchemaVersionAdapter(
      version: 17,
      description: 'add quotes.favorite_count',
      apply: _upgradeToV17,
    ),
    SchemaVersionAdapter(
      version: 18,
      description: 'migrate default category icons',
      apply: _upgradeToV18,
    ),
    SchemaVersionAdapter(
      version: 19,
      description: 'add quote coordinates',
      apply: _upgradeToV19,
    ),
    SchemaVersionAdapter(
      version: 20,
      description: 'add quote trash metadata',
      apply: _upgradeToV20,
    ),
    SchemaVersionAdapter(
      version: 21,
      description: 'add quotes.poi_name',
      apply: _upgradeToV21,
    ),
  ];

  Future<void> _upgradeToV2(Transaction transaction) => transaction.execute(
        "ALTER TABLE quotes ADD COLUMN tag_ids TEXT DEFAULT ''",
      );

  Future<void> _upgradeToV3(Transaction transaction) => transaction.execute(
        'ALTER TABLE categories ADD COLUMN icon_name TEXT',
      );

  Future<void> _upgradeToV4(Transaction transaction) => transaction.execute(
        "ALTER TABLE quotes ADD COLUMN category_id TEXT DEFAULT ''",
      );

  Future<void> _upgradeToV5(Transaction transaction) =>
      transaction.execute('ALTER TABLE quotes ADD COLUMN source TEXT');

  Future<void> _upgradeToV6(Transaction transaction) =>
      transaction.execute('ALTER TABLE quotes ADD COLUMN color_hex TEXT');

  Future<void> _upgradeToV7(Transaction transaction) async {
    await transaction
        .execute('ALTER TABLE quotes ADD COLUMN source_author TEXT');
    await transaction.execute('ALTER TABLE quotes ADD COLUMN source_work TEXT');

    final quotes = await transaction.query(
      'quotes',
      where: "source IS NOT NULL AND source != ''",
    );

    final updateBatch = transaction.batch();

    for (final quote in quotes) {
      final source = quote['source'] as String?;
      if (source == null || source.isEmpty) {
        continue;
      }

      String? sourceAuthor;
      String? sourceWork;
      if (source.contains('《') && source.contains('》')) {
        final workMatch = RegExp(r'《(.+?)》').firstMatch(source);
        if (workMatch != null) {
          sourceWork = workMatch.group(1);
          sourceAuthor = source.replaceAll(RegExp(r'《.+?》'), '').trim();
          if (sourceAuthor.isEmpty) {
            sourceAuthor = null;
          }
        }
      } else if (source.contains(' - ')) {
        final parts = source.split(' - ');
        if (parts.length >= 2) {
          sourceAuthor = parts.first.trim();
          sourceWork = parts.sublist(1).join(' - ').trim();
        }
      } else {
        sourceAuthor = source.trim();
      }

      updateBatch.update(
        'quotes',
        <String, Object?>{
          'source_author': sourceAuthor,
          'source_work': sourceWork,
        },
        where: 'id = ?',
        whereArgs: <Object?>[quote['id']],
      );
    }

    await updateBatch.commit(noResult: true);
  }

  Future<void> _upgradeToV8(Transaction transaction) async {
    await transaction.execute('ALTER TABLE quotes ADD COLUMN location TEXT');
    await transaction.execute('ALTER TABLE quotes ADD COLUMN weather TEXT');
    await transaction.execute('ALTER TABLE quotes ADD COLUMN temperature TEXT');
  }

  Future<void> _upgradeToV9(Transaction transaction) async {
    await transaction.execute(
      'CREATE INDEX IF NOT EXISTS idx_quotes_category_id ON quotes(category_id)',
    );
    await transaction.execute(
      'CREATE INDEX IF NOT EXISTS idx_quotes_date ON quotes(date)',
    );
  }

  Future<void> _upgradeToV10(Transaction transaction) =>
      transaction.execute('ALTER TABLE quotes ADD COLUMN edit_source TEXT');

  Future<void> _upgradeToV11(Transaction transaction) async {
    if (!await _hasColumn(transaction, 'quotes', 'delta_content')) {
      await transaction
          .execute('ALTER TABLE quotes ADD COLUMN delta_content TEXT');
    }
  }

  Future<void> _upgradeToV12(Transaction transaction) =>
      _legacyTags.upgrade(transaction);

  Future<void> _upgradeToV13(Transaction transaction) =>
      _definitions.ensureMediaReferencesTable(transaction);

  Future<void> _upgradeToV14(Transaction transaction) async {
    if (!await _hasColumn(transaction, 'quotes', 'day_period')) {
      await transaction
          .execute('ALTER TABLE quotes ADD COLUMN day_period TEXT');
    }
    await transaction.execute(
      'CREATE INDEX IF NOT EXISTS idx_quotes_day_period ON quotes(day_period)',
    );
  }

  Future<void> _upgradeToV15(Transaction transaction) async {
    if (!await _hasColumn(transaction, 'quotes', 'last_modified')) {
      await transaction.execute(
        'ALTER TABLE quotes ADD COLUMN last_modified TEXT',
      );
      final now = DateTime.now().toIso8601String();
      await transaction.execute(
        'UPDATE quotes SET last_modified = COALESCE(date, ?)',
        <Object?>[now],
      );
    }
    await transaction.execute(
      'CREATE INDEX IF NOT EXISTS idx_quotes_last_modified ON quotes(last_modified)',
    );
  }

  Future<void> _upgradeToV16(Transaction transaction) async {
    if (!await _hasColumn(transaction, 'categories', 'last_modified')) {
      await transaction.execute(
        'ALTER TABLE categories ADD COLUMN last_modified TEXT',
      );
      await transaction.execute(
        'UPDATE categories SET last_modified = ?',
        <Object?>[DateTime.now().toIso8601String()],
      );
    }
    await transaction.execute(
      'CREATE INDEX IF NOT EXISTS idx_categories_last_modified ON categories(last_modified)',
    );
  }

  Future<void> _upgradeToV17(Transaction transaction) async {
    if (!await _hasColumn(transaction, 'quotes', 'favorite_count')) {
      await transaction.execute(
        'ALTER TABLE quotes ADD COLUMN favorite_count INTEGER DEFAULT 0',
      );
    }
    await transaction.execute(
      'CREATE INDEX IF NOT EXISTS idx_quotes_favorite_count ON quotes(favorite_count)',
    );
  }

  Future<void> _upgradeToV18(Transaction transaction) async {
    const iconMigration = <String, String>{
      'flutter_dash': 'format_quote',
      '💭': 'format_quote',
      'format_quote': 'format_quote',
      'movie': '🎬',
      'menu_book': '📚',
      'sports_esports': '🎮',
      'auto_stories': '📖',
      'create': '✨',
      'public': '🌐',
      'category': '📦',
      '📝': '📦',
      'theaters': '🎞️',
      'brush': '🪶',
      'music_note': '🎧',
      '🎶': '🎧',
      'psychology': '🤔',
    };
    final batch = transaction.batch();
    for (final entry in iconMigration.entries) {
      batch.execute(
        'UPDATE categories SET icon_name = ? '
        'WHERE icon_name = ? AND is_default = 1',
        <Object?>[entry.value, entry.key],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> _upgradeToV19(Transaction transaction) async {
    if (!await _hasColumn(transaction, 'quotes', 'latitude')) {
      await transaction.execute('ALTER TABLE quotes ADD COLUMN latitude REAL');
    }
    if (!await _hasColumn(transaction, 'quotes', 'longitude')) {
      await transaction.execute('ALTER TABLE quotes ADD COLUMN longitude REAL');
    }
    await transaction.execute(
      'CREATE INDEX IF NOT EXISTS idx_quotes_coordinates ON quotes(latitude, longitude)',
    );
  }

  Future<void> _upgradeToV20(Transaction transaction) async {
    if (!await _hasColumn(transaction, 'quotes', 'is_deleted')) {
      await transaction.execute(
        'ALTER TABLE quotes ADD COLUMN is_deleted INTEGER DEFAULT 0',
      );
    }
    if (!await _hasColumn(transaction, 'quotes', 'deleted_at')) {
      await transaction
          .execute('ALTER TABLE quotes ADD COLUMN deleted_at TEXT');
    }
    await transaction.execute(
      'CREATE INDEX IF NOT EXISTS idx_quotes_is_deleted ON quotes(is_deleted)',
    );
    await transaction.execute(
      'CREATE INDEX IF NOT EXISTS idx_quotes_deleted_at ON quotes(deleted_at)',
    );
    await _definitions.ensureQuoteTombstonesTable(transaction);
    await transaction.rawUpdate('''
      UPDATE quotes
      SET deleted_at = COALESCE(last_modified, date)
      WHERE is_deleted = 1 AND deleted_at IS NULL
    ''');
  }

  Future<void> _upgradeToV21(Transaction transaction) async {
    if (!await _hasColumn(
      transaction,
      'quotes',
      DatabaseSchemaDefinitions.poiNameColumn,
    )) {
      await transaction.execute(
        'ALTER TABLE quotes ADD COLUMN ${DatabaseSchemaDefinitions.poiNameColumn} TEXT',
      );
    }
    await transaction.execute(
      'CREATE INDEX IF NOT EXISTS idx_quotes_poi_name ON quotes(poi_name)',
    );
    await transaction.execute(
      'CREATE INDEX IF NOT EXISTS idx_quotes_coordinates ON quotes(latitude, longitude)',
    );
  }

  Future<bool> _hasColumn(
    DatabaseExecutor executor,
    String tableName,
    String columnName,
  ) async {
    final columns = await _definitions.columnNames(executor, tableName);
    return columns.contains(columnName);
  }
}
