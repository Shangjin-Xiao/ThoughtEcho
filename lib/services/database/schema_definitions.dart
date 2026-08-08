part of '../database_schema_manager.dart';

/// The authoritative SQL definitions for the current main notes schema.
class DatabaseSchemaDefinitions {
  static const int schemaVersion = 21;

  static const String poiNameColumn = 'poi_name';

  static const Set<String> requiredTables = <String>{
    'quotes',
    'categories',
    'quote_tags',
    'quote_tombstones',
    'media_references',
  };

  static const Map<String, String> repairableQuoteColumns = <String, String>{
    'source': 'TEXT',
    'source_author': 'TEXT',
    'source_work': 'TEXT',
    'ai_analysis': 'TEXT',
    'sentiment': 'TEXT',
    'keywords': 'TEXT',
    'summary': 'TEXT',
    'category_id': "TEXT DEFAULT ''",
    'color_hex': 'TEXT',
    'location': 'TEXT',
    'latitude': 'REAL',
    'longitude': 'REAL',
    poiNameColumn: 'TEXT',
    'weather': 'TEXT',
    'temperature': 'TEXT',
    'edit_source': 'TEXT',
    'delta_content': 'TEXT',
    'day_period': 'TEXT',
    'last_modified': 'TEXT',
    'favorite_count': 'INTEGER DEFAULT 0',
    'is_deleted': 'INTEGER DEFAULT 0',
    'deleted_at': 'TEXT',
  };

  static final Set<String> requiredQuoteColumns = Set<String>.unmodifiable(
    <String>{
      'id',
      'content',
      'date',
      ...repairableQuoteColumns.keys,
    },
  );

  static const List<String> quoteIndexStatements = <String>[
    'CREATE INDEX IF NOT EXISTS idx_quotes_category_id ON quotes(category_id)',
    'CREATE INDEX IF NOT EXISTS idx_quotes_date ON quotes(date)',
    'CREATE INDEX IF NOT EXISTS idx_quotes_date_category ON quotes(date DESC, category_id)',
    'CREATE INDEX IF NOT EXISTS idx_quotes_category_date ON quotes(category_id, date DESC)',
    'CREATE INDEX IF NOT EXISTS idx_quotes_content_fts ON quotes(content)',
    'CREATE INDEX IF NOT EXISTS idx_quotes_weather ON quotes(weather)',
    'CREATE INDEX IF NOT EXISTS idx_quotes_day_period ON quotes(day_period)',
    'CREATE INDEX IF NOT EXISTS idx_quotes_last_modified ON quotes(last_modified)',
    'CREATE INDEX IF NOT EXISTS idx_quotes_favorite_count ON quotes(favorite_count)',
    'CREATE INDEX IF NOT EXISTS idx_quotes_is_deleted ON quotes(is_deleted)',
    'CREATE INDEX IF NOT EXISTS idx_quotes_deleted_at ON quotes(deleted_at)',
    'CREATE INDEX IF NOT EXISTS idx_quotes_poi_name ON quotes(poi_name)',
    'CREATE INDEX IF NOT EXISTS idx_quotes_coordinates ON quotes(latitude, longitude)',
  ];

  static const List<String> requiredIndexNames = <String>[
    'idx_quotes_category_id',
    'idx_quotes_date',
    'idx_quotes_date_category',
    'idx_quotes_category_date',
    'idx_quotes_content_fts',
    'idx_quotes_weather',
    'idx_quotes_day_period',
    'idx_quotes_last_modified',
    'idx_quotes_favorite_count',
    'idx_quotes_is_deleted',
    'idx_quotes_deleted_at',
    'idx_quotes_poi_name',
    'idx_quotes_coordinates',
    'idx_categories_last_modified',
    'idx_quote_tags_quote_id',
    'idx_quote_tags_composite',
    'idx_quote_tombstones_deleted_at',
    'idx_media_references_file_path',
    'idx_media_references_quote_id',
  ];

  static const List<String> categoryIndexStatements = <String>[
    'CREATE INDEX IF NOT EXISTS idx_categories_last_modified ON categories(last_modified)',
  ];

  static const List<String> quoteTagsIndexStatements = <String>[
    'CREATE INDEX IF NOT EXISTS idx_quote_tags_quote_id ON quote_tags(quote_id)',
    'CREATE INDEX IF NOT EXISTS idx_quote_tags_composite ON quote_tags(tag_id, quote_id)',
  ];

  static const List<String> quoteTombstoneIndexStatements = <String>[
    'CREATE INDEX IF NOT EXISTS idx_quote_tombstones_deleted_at ON quote_tombstones(deleted_at)',
  ];

  static const List<String> mediaReferenceIndexStatements = <String>[
    'CREATE INDEX IF NOT EXISTS idx_media_references_file_path ON media_references(file_path)',
    'CREATE INDEX IF NOT EXISTS idx_media_references_quote_id ON media_references(quote_id)',
  ];

  static const String categoriesTableSql = '''
    CREATE TABLE categories(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      is_default BOOLEAN DEFAULT 0,
      icon_name TEXT,
      last_modified TEXT
    )
  ''';

  static const String quoteTagsTableSql = '''
    CREATE TABLE IF NOT EXISTS quote_tags(
      quote_id TEXT NOT NULL,
      tag_id TEXT NOT NULL,
      PRIMARY KEY (quote_id, tag_id),
      FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE,
      FOREIGN KEY (tag_id) REFERENCES categories(id) ON DELETE CASCADE
    )
  ''';

  static const String quoteTombstonesTableSql = '''
    CREATE TABLE IF NOT EXISTS quote_tombstones(
      quote_id TEXT PRIMARY KEY,
      deleted_at TEXT NOT NULL,
      device_id TEXT
    )
  ''';

  static const String mediaReferencesTableSql = '''
    CREATE TABLE IF NOT EXISTS media_references(
      id TEXT PRIMARY KEY,
      file_path TEXT NOT NULL,
      quote_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY (quote_id) REFERENCES quotes(id) ON DELETE CASCADE,
      UNIQUE(file_path, quote_id)
    )
  ''';

  Future<void> createCurrentSchema(Database database) async {
    await database.execute(categoriesTableSql);
    await database.execute(quotesTableSql('quotes'));
    await ensureCurrentIndexes(database);
    await ensureQuoteTagsTable(database);
    await ensureQuoteTombstonesTable(database);
    await ensureMediaReferencesTable(database);
  }

  Future<void> ensureCurrentIndexes(DatabaseExecutor executor) async {
    await ensureQuoteIndexes(executor);
    await ensureCategoryIndexes(executor);
  }

  Future<void> ensureQuoteIndexes(DatabaseExecutor executor) async {
    await _executeAll(executor, quoteIndexStatements);
  }

  Future<void> ensureCategoryIndexes(DatabaseExecutor executor) async {
    await _executeAll(executor, categoryIndexStatements);
  }

  Future<void> ensureQuoteTagsTable(DatabaseExecutor executor) async {
    await executor.execute(quoteTagsTableSql);
    await _executeAll(executor, quoteTagsIndexStatements);
  }

  Future<void> ensureQuoteTombstonesTable(DatabaseExecutor executor) async {
    await executor.execute(quoteTombstonesTableSql);
    await _executeAll(executor, quoteTombstoneIndexStatements);
  }

  Future<void> ensureMediaReferencesTable(DatabaseExecutor executor) async {
    await executor.execute(mediaReferencesTableSql);
    await _executeAll(executor, mediaReferenceIndexStatements);
  }

  Future<void> _executeAll(
    DatabaseExecutor executor,
    Iterable<String> statements,
  ) async {
    for (final statement in statements) {
      await executor.execute(statement);
    }
  }

  String quotesTableSql(String tableName) {
    if (tableName != 'quotes' && tableName != 'quotes_new') {
      throw ArgumentError.value(
          tableName, 'tableName', 'Unsupported schema table');
    }

    return '''
      CREATE TABLE $tableName(
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
        latitude REAL,
        longitude REAL,
        poi_name TEXT,
        weather TEXT,
        temperature TEXT,
        edit_source TEXT,
        delta_content TEXT,
        day_period TEXT,
        last_modified TEXT,
        favorite_count INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        deleted_at TEXT
      )
    ''';
  }

  Future<Set<String>> tableNames(DatabaseExecutor executor) async {
    final tables = await executor.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    return tables.map((table) => table['name'] as String).toSet();
  }

  Future<Set<String>> columnNames(
    DatabaseExecutor executor,
    String tableName,
  ) async {
    if (tableName != 'quotes' && tableName != 'categories') {
      throw ArgumentError.value(
          tableName, 'tableName', 'Unsupported schema table');
    }
    final tableInfo = await executor.rawQuery(
      'SELECT * FROM pragma_table_info(?)',
      [tableName],
    );
    return tableInfo.map((column) => column['name'] as String).toSet();
  }
}
