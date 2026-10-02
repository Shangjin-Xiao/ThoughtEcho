import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late DatabaseSchemaDefinitions schemaDefinitions;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(inMemoryDatabasePath);
    schemaDefinitions = DatabaseSchemaDefinitions();
  });

  tearDown(() async {
    await database.close();
  });

  group('DatabaseSchemaDefinitions Constants & Pure Functions', () {
    test('schemaVersion is defined and positive', () {
      expect(DatabaseSchemaDefinitions.schemaVersion, equals(21));
    });

    test('poiNameColumn constant', () {
      expect(DatabaseSchemaDefinitions.poiNameColumn, equals('poi_name'));
    });

    test('requiredTables contains all core database tables', () {
      expect(
        DatabaseSchemaDefinitions.requiredTables,
        containsAll(<String>{
          'quotes',
          'categories',
          'quote_tags',
          'quote_tombstones',
          'media_references',
        }),
      );
    });

    test(
        'requiredQuoteColumns includes repairable quote columns and core fields',
        () {
      expect(
        DatabaseSchemaDefinitions.requiredQuoteColumns,
        containsAll(<String>[
          'id',
          'content',
          'date',
          'poi_name',
          'weather',
          'latitude',
          'longitude'
        ]),
      );
      for (final key in DatabaseSchemaDefinitions.repairableQuoteColumns.keys) {
        expect(DatabaseSchemaDefinitions.requiredQuoteColumns.contains(key),
            isTrue);
      }
    });

    test('requiredIndexNames matches all defined index statements', () {
      final allIndexNames = DatabaseSchemaDefinitions.requiredIndexNames;
      expect(allIndexNames, isNotEmpty);
      expect(allIndexNames, contains('idx_quotes_category_id'));
      expect(allIndexNames, contains('idx_categories_last_modified'));
      expect(allIndexNames, contains('idx_quote_tags_quote_id'));
      expect(allIndexNames, contains('idx_quote_tombstones_deleted_at'));
      expect(allIndexNames, contains('idx_media_references_quote_id'));
    });

    test(
        'quotesTableSql returns valid CREATE TABLE SQL for allowed table names',
        () {
      final quotesSql = schemaDefinitions.quotesTableSql('quotes');
      expect(quotesSql, contains('CREATE TABLE quotes('));
      expect(quotesSql, contains('id TEXT PRIMARY KEY'));
      expect(quotesSql, contains('content TEXT NOT NULL'));

      final quotesNewSql = schemaDefinitions.quotesTableSql('quotes_new');
      expect(quotesNewSql, contains('CREATE TABLE quotes_new('));
    });

    test('quotesTableSql throws ArgumentError for unsupported table names', () {
      expect(
        () => schemaDefinitions.quotesTableSql('invalid_table'),
        throwsArgumentError,
      );
      expect(
        () => schemaDefinitions.quotesTableSql(''),
        throwsArgumentError,
      );
    });
  });

  group('DatabaseSchemaDefinitions SQLite Operations', () {
    test('createCurrentSchema initializes all tables and indexes', () async {
      await schemaDefinitions.createCurrentSchema(database);

      final tables = await schemaDefinitions.tableNames(database);
      expect(
        tables,
        containsAll(<String>{
          'quotes',
          'categories',
          'quote_tags',
          'quote_tombstones',
          'media_references',
        }),
      );

      final quotesColumns =
          await schemaDefinitions.columnNames(database, 'quotes');
      expect(
        quotesColumns,
        containsAll(<String>[
          'id',
          'content',
          'date',
          'source',
          'source_author',
          'source_work',
          'ai_analysis',
          'sentiment',
          'keywords',
          'summary',
          'category_id',
          'color_hex',
          'location',
          'latitude',
          'longitude',
          'poi_name',
          'weather',
          'temperature',
          'edit_source',
          'delta_content',
          'day_period',
          'last_modified',
          'favorite_count',
          'is_deleted',
          'deleted_at',
        ]),
      );

      final categoriesColumns =
          await schemaDefinitions.columnNames(database, 'categories');
      expect(
        categoriesColumns,
        containsAll(<String>[
          'id',
          'name',
          'is_default',
          'icon_name',
          'last_modified',
        ]),
      );
    });

    test('columnNames throws ArgumentError for unsupported table names',
        () async {
      await schemaDefinitions.createCurrentSchema(database);

      expect(
        () => schemaDefinitions.columnNames(database, 'quote_tags'),
        throwsArgumentError,
      );
      expect(
        () => schemaDefinitions.columnNames(database, 'unknown_table'),
        throwsArgumentError,
      );
    });

    test(
        'ensureQuoteTagsTable, ensureQuoteTombstonesTable, ensureMediaReferencesTable create tables selectively',
        () async {
      // Execute categories & quotes table creation manually
      await database.execute(DatabaseSchemaDefinitions.categoriesTableSql);
      await database.execute(schemaDefinitions.quotesTableSql('quotes'));

      await schemaDefinitions.ensureQuoteTagsTable(database);
      await schemaDefinitions.ensureQuoteTombstonesTable(database);
      await schemaDefinitions.ensureMediaReferencesTable(database);

      final tables = await schemaDefinitions.tableNames(database);
      expect(
        tables,
        containsAll(<String>{
          'quotes',
          'categories',
          'quote_tags',
          'quote_tombstones',
          'media_references',
        }),
      );
    });
  });
}
