import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late DatabaseSchemaDefinitions definitions;
  late SchemaValidationAdapter validation;
  late SchemaRepairAdapter repairAdapter;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(inMemoryDatabasePath);
    definitions = DatabaseSchemaDefinitions();
    validation = SchemaValidationAdapter(definitions);
    repairAdapter = SchemaRepairAdapter(definitions, validation);
  });

  tearDown(() async {
    await database.close();
  });

  group('SchemaValidationAdapter', () {
    test('passes validation on a fully created database', () async {
      await definitions.createCurrentSchema(database);

      await expectLater(validation.validate(database), completes);
      await database.transaction((txn) async {
        await expectLater(validation.validateTransaction(txn), completes);
      });
    });

    test('throws StateError when a required table is missing', () async {
      await database.execute('''
        CREATE TABLE categories(
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL
        )
      ''');
      // quotes table missing

      await expectLater(
        validation.validate(database),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('数据库结构不完整，缺少表'),
          ),
        ),
      );
    });

    test('throws StateError when quotes table is missing required columns',
        () async {
      await definitions.createCurrentSchema(database);
      // Recreate quotes table without 'poi_name' column
      await database.execute('DROP TABLE quotes');
      await database.execute('''
        CREATE TABLE quotes(
          id TEXT PRIMARY KEY,
          content TEXT NOT NULL,
          date TEXT NOT NULL
        )
      ''');

      await expectLater(
        validation.validate(database),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('quotes 表缺少必要列'),
          ),
        ),
      );
    });

    test('throws StateError when a required index is missing', () async {
      await definitions.createCurrentSchema(database);
      await database.execute('DROP INDEX idx_quotes_poi_name');

      await expectLater(
        validation.validate(database),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('数据库结构不完整，缺少索引'),
          ),
        ),
      );
    });
  });

  group('SchemaRepairAdapter', () {
    test('throws StateError when base tables (quotes/categories) are missing',
        () async {
      // Empty database with no tables
      await expectLater(
        repairAdapter.repair(database),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('无法修复缺少基础表的数据库'),
          ),
        ),
      );
    });

    test('repairs missing columns, indexes, and auxiliary tables', () async {
      // Create minimal base tables with missing columns, indexes, and auxiliary tables
      await database.execute('''
        CREATE TABLE categories(
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL
        )
      ''');
      await database.execute('''
        CREATE TABLE quotes(
          id TEXT PRIMARY KEY,
          content TEXT NOT NULL,
          date TEXT NOT NULL
        )
      ''');

      // Ensure repair succeeds
      await repairAdapter.repair(database);

      // Validate schema now passes
      await validation.validate(database);

      // Verify category columns were added
      final categoryCols =
          await definitions.columnNames(database, 'categories');
      expect(categoryCols, containsAll(['icon_name', 'last_modified']));

      // Verify quote columns were added
      final quoteCols = await definitions.columnNames(database, 'quotes');
      expect(
        quoteCols,
        containsAll([
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

      // Verify auxiliary tables were created
      final tables = await definitions.tableNames(database);
      expect(
        tables,
        containsAll([
          'quotes',
          'categories',
          'quote_tags',
          'quote_tombstones',
          'media_references',
        ]),
      );
    });

    test('repair is idempotent on an already complete database', () async {
      await definitions.createCurrentSchema(database);

      await expectLater(repairAdapter.repair(database), completes);
      await expectLater(validation.validate(database), completes);
    });

    test('rethrows exception when repair fails inside transaction', () async {
      await database.execute('''
        CREATE TABLE categories(
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL
        )
      ''');
      await database.execute('''
        CREATE TABLE quotes(
          id TEXT PRIMARY KEY,
          content TEXT NOT NULL,
          date TEXT NOT NULL
        )
      ''');

      // Create a validation adapter that fails validation on purpose
      final failingValidation = _FailingValidationAdapter(definitions);
      final failingRepairAdapter =
          SchemaRepairAdapter(definitions, failingValidation);

      await expectLater(
        failingRepairAdapter.repair(database),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('simulated validation failure'),
          ),
        ),
      );
    });
  });
}

class _FailingValidationAdapter extends SchemaValidationAdapter {
  _FailingValidationAdapter(super.definitions);

  @override
  Future<void> validateTransaction(Transaction transaction) async {
    throw StateError('simulated validation failure');
  }
}
