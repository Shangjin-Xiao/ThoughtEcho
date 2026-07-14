import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(inMemoryDatabasePath);
  });

  tearDown(() async {
    await database.close();
  });

  group('Database schema lifecycle', () {
    test('creates and validates the current schema from one definition',
        () async {
      final manager = DatabaseSchemaManager();

      await manager.createTables(database);
      await manager.validateSchema(database);

      final quotesColumns =
          await database.rawQuery('PRAGMA table_info(quotes)');
      final columnNames =
          quotesColumns.map((column) => column['name'] as String).toSet();

      expect(
          columnNames,
          containsAll(<String>[
            'latitude',
            'longitude',
            'poi_name',
            'is_deleted',
            'deleted_at',
          ]));
    });

    test('upgrades a version 11 database through every remaining adapter',
        () async {
      await _createVersion11Schema(database);
      await database.insert('categories', <String, Object?>{
        'id': 'tag-1',
        'name': 'Existing tag',
        'is_default': 0,
        'icon_name': 'format_quote',
      });
      await database.insert('quotes', <String, Object?>{
        'id': 'quote-1',
        'content': 'Legacy content',
        'date': '2024-01-01T12:00:00.000',
        'source': 'Author - Work',
        'source_author': 'Author',
        'source_work': 'Work',
        'tag_ids': 'tag-1',
      });

      final manager = DatabaseSchemaManager();
      await manager.upgradeDatabase(
        database,
        11,
        DatabaseSchemaManager.schemaVersion,
      );
      await manager.validateSchema(database);

      final migratedQuote = (await database.query('quotes')).single;
      expect(migratedQuote['content'], 'Legacy content');
      expect(migratedQuote['source_author'], 'Author');
      expect(migratedQuote['source_work'], 'Work');
      expect(migratedQuote['poi_name'], isNull);

      final quoteTags = await database.query('quote_tags');
      expect(quoteTags, <Map<String, Object?>>[
        <String, Object?>{'quote_id': 'quote-1', 'tag_id': 'tag-1'},
      ]);

      final columns = await database.rawQuery('PRAGMA table_info(quotes)');
      expect(
          columns.map((column) => column['name']), isNot(contains('tag_ids')));
    });

    test('upgrades the earliest supported schema through all adapters',
        () async {
      await _createVersion1Schema(database);
      await database.insert('quotes', <String, Object?>{
        'id': 'quote-1',
        'content': 'Oldest content',
        'date': '2021-01-01T12:00:00.000',
      });

      final manager = DatabaseSchemaManager();
      await manager.upgradeDatabase(
        database,
        1,
        DatabaseSchemaManager.schemaVersion,
      );
      await manager.validateSchema(database);

      final quote = (await database.query('quotes')).single;
      expect(quote['content'], 'Oldest content');
      expect(quote['favorite_count'], 0);
      expect(quote['is_deleted'], 0);
    });

    test('repairs missing current structure from the shared definition',
        () async {
      final manager = DatabaseSchemaManager();
      await manager.createTables(database);
      await database.execute('DROP INDEX idx_quotes_poi_name');
      await database.execute('DROP TABLE quote_tombstones');

      await manager.checkAndFixDatabaseStructure(database);
      await manager.validateSchema(database);
    });

    test('rolls back and stops when a version adapter fails', () async {
      var followingAdapterRan = false;
      final policy = SchemaMigrationPolicy(<SchemaVersionAdapter>[
        SchemaVersionAdapter(
          version: 2,
          description: 'failing migration',
          apply: (transaction) async {
            await transaction
                .execute('CREATE TABLE migration_marker(id INTEGER)');
            throw StateError('simulated migration failure');
          },
        ),
        SchemaVersionAdapter(
          version: 3,
          description: 'must not run',
          apply: (_) async {
            followingAdapterRan = true;
          },
        ),
      ]);

      await expectLater(
        () => database.transaction(
          (transaction) =>
              policy.apply(transaction, fromVersion: 1, toVersion: 3),
        ),
        throwsA(isA<SchemaMigrationException>()),
      );

      expect(followingAdapterRan, isFalse);
      final marker = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'migration_marker'",
      );
      expect(marker, isEmpty);
    });
  });
}

Future<void> _createVersion11Schema(Database database) async {
  await database.execute('''
    CREATE TABLE categories(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      is_default BOOLEAN DEFAULT 0,
      icon_name TEXT
    )
  ''');
  await database.execute('''
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
      tag_ids TEXT DEFAULT ''
    )
  ''');
}

Future<void> _createVersion1Schema(Database database) async {
  await database.execute('''
    CREATE TABLE categories(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      is_default BOOLEAN DEFAULT 0
    )
  ''');
  await database.execute('''
    CREATE TABLE quotes(
      id TEXT PRIMARY KEY,
      content TEXT NOT NULL,
      date TEXT NOT NULL,
      ai_analysis TEXT,
      sentiment TEXT,
      keywords TEXT,
      summary TEXT
    )
  ''');
}
