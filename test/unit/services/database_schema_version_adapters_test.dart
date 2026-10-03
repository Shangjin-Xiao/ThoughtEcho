import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late DatabaseSchemaDefinitions schemaDefinitions;
  late SchemaLegacyTagAdapter legacyTagAdapter;
  late SchemaVersionAdapters schemaAdapters;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(inMemoryDatabasePath);
    schemaDefinitions = DatabaseSchemaDefinitions();
    legacyTagAdapter = SchemaLegacyTagAdapter(schemaDefinitions);
    schemaAdapters = SchemaVersionAdapters(schemaDefinitions, legacyTagAdapter);
  });

  tearDown(() async {
    await database.close();
  });

  group('SchemaVersionAdapter & SchemaMigrationException', () {
    test('SchemaMigrationException stores context and formats toString()', () {
      final cause = Exception('root cause');
      final exception = SchemaMigrationException(
        version: 5,
        description: 'v5 upgrade failed',
        cause: cause,
      );

      expect(exception.version, equals(5));
      expect(exception.description, equals('v5 upgrade failed'));
      expect(exception.cause, equals(cause));
      expect(
        exception.toString(),
        equals(
            'SchemaMigrationException(v5: v5 upgrade failed, cause: Exception: root cause)'),
      );
    });
  });

  group('SchemaMigrationPolicy', () {
    test('sorts adapters by version automatically', () async {
      final executedVersions = <int>[];
      final trackerPolicy = SchemaMigrationPolicy([
        SchemaVersionAdapter(
          version: 10,
          description: 'v10',
          apply: (_) async => executedVersions.add(10),
        ),
        SchemaVersionAdapter(
          version: 2,
          description: 'v2',
          apply: (_) async => executedVersions.add(2),
        ),
        SchemaVersionAdapter(
          version: 5,
          description: 'v5',
          apply: (_) async => executedVersions.add(5),
        ),
      ]);

      await database.transaction((txn) async {
        await trackerPolicy.apply(txn, fromVersion: 0, toVersion: 20);
      });

      expect(executedVersions, equals(<int>[2, 5, 10]));
    });

    test('throws ArgumentError on duplicate schema adapter versions', () {
      final adapterA = SchemaVersionAdapter(
        version: 2,
        description: 'v2 A',
        apply: (_) async {},
      );
      final adapterB = SchemaVersionAdapter(
        version: 2,
        description: 'v2 B',
        apply: (_) async {},
      );

      expect(
        () => SchemaMigrationPolicy([adapterA, adapterB]),
        throwsArgumentError,
      );
    });

    test('filters adapters strictly based on fromVersion and toVersion range',
        () async {
      final executed = <int>[];
      final policy = SchemaMigrationPolicy([
        SchemaVersionAdapter(
            version: 2, description: 'v2', apply: (_) async => executed.add(2)),
        SchemaVersionAdapter(
            version: 3, description: 'v3', apply: (_) async => executed.add(3)),
        SchemaVersionAdapter(
            version: 4, description: 'v4', apply: (_) async => executed.add(4)),
        SchemaVersionAdapter(
            version: 5, description: 'v5', apply: (_) async => executed.add(5)),
      ]);

      await database.transaction((txn) async {
        await policy.apply(txn, fromVersion: 2, toVersion: 4);
      });

      expect(executed, equals(<int>[3, 4]));
    });

    test('wraps failure in SchemaMigrationException and stops execution',
        () async {
      final executed = <int>[];
      final policy = SchemaMigrationPolicy([
        SchemaVersionAdapter(
            version: 2,
            description: 'v2 ok',
            apply: (_) async => executed.add(2)),
        SchemaVersionAdapter(
          version: 3,
          description: 'v3 failing',
          apply: (_) async => throw Exception('database error'),
        ),
        SchemaVersionAdapter(
            version: 4,
            description: 'v4 unreached',
            apply: (_) async => executed.add(4)),
      ]);

      await expectLater(
        () => database.transaction((txn) async {
          await policy.apply(txn, fromVersion: 1, toVersion: 4);
        }),
        throwsA(
          isA<SchemaMigrationException>()
              .having((e) => e.version, 'version', 3)
              .having((e) => e.description, 'description', 'v3 failing'),
        ),
      );

      expect(executed, equals(<int>[2]));
    });
  });

  group('SchemaVersionAdapters Adapter List Configuration', () {
    test(
        'adapters list starts at version 2 and ends at schemaVersion without gaps',
        () {
      final adapters = schemaAdapters.adapters;
      expect(adapters.first.version, equals(2));
      expect(
        adapters.last.version,
        equals(DatabaseSchemaDefinitions.schemaVersion),
      );

      for (var i = 0; i < adapters.length; i++) {
        final expectedVersion = i + 2;
        expect(adapters[i].version, equals(expectedVersion));
        expect(adapters[i].description, isNotEmpty);
      }
    });
  });

  group('SchemaVersionAdapters Individual Migrations', () {
    test('v2 adds tag_ids to quotes', () async {
      await database
          .execute('CREATE TABLE quotes (id TEXT PRIMARY KEY, content TEXT)');
      final adapterV2 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 2);

      await database.transaction((txn) async {
        await adapterV2.apply(txn);
      });

      final columns = await database.rawQuery('PRAGMA table_info(quotes)');
      final columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames, contains('tag_ids'));
    });

    test('v3 adds icon_name to categories', () async {
      await database
          .execute('CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT)');
      final adapterV3 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 3);

      await database.transaction((txn) async {
        await adapterV3.apply(txn);
      });

      final columns = await database.rawQuery('PRAGMA table_info(categories)');
      final columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames, contains('icon_name'));
    });

    test('v4 adds category_id to quotes', () async {
      await database
          .execute('CREATE TABLE quotes (id TEXT PRIMARY KEY, content TEXT)');
      final adapterV4 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 4);

      await database.transaction((txn) async {
        await adapterV4.apply(txn);
      });

      final columns = await database.rawQuery('PRAGMA table_info(quotes)');
      final columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames, contains('category_id'));
    });

    test('v5 adds source to quotes', () async {
      await database
          .execute('CREATE TABLE quotes (id TEXT PRIMARY KEY, content TEXT)');
      final adapterV5 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 5);

      await database.transaction((txn) async {
        await adapterV5.apply(txn);
      });

      final columns = await database.rawQuery('PRAGMA table_info(quotes)');
      final columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames, contains('source'));
    });

    test('v6 adds color_hex to quotes', () async {
      await database
          .execute('CREATE TABLE quotes (id TEXT PRIMARY KEY, content TEXT)');
      final adapterV6 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 6);

      await database.transaction((txn) async {
        await adapterV6.apply(txn);
      });

      final columns = await database.rawQuery('PRAGMA table_info(quotes)');
      final columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames, contains('color_hex'));
    });

    test('v7 splits quote source metadata correctly across multiple formats',
        () async {
      await database
          .execute('CREATE TABLE quotes (id TEXT PRIMARY KEY, source TEXT)');
      await database.insert('quotes', {'id': 'q1', 'source': '鲁迅《狂人日记》'});
      await database.insert('quotes', {'id': 'q2', 'source': '《红楼梦》'});
      await database
          .insert('quotes', {'id': 'q3', 'source': 'Tolstoy - War and Peace'});
      await database.insert(
          'quotes', {'id': 'q4', 'source': 'Author - Work - Extra Note'});
      await database
          .insert('quotes', {'id': 'q5', 'source': 'Just Plain Author'});
      await database.insert('quotes', {'id': 'q6', 'source': ''});
      await database.insert('quotes', {'id': 'q7', 'source': null});

      final adapterV7 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 7);

      await database.transaction((txn) async {
        await adapterV7.apply(txn);
      });

      final rows = await database.query('quotes', orderBy: 'id');
      final rowMap = {for (var r in rows) r['id'] as String: r};

      expect(rowMap['q1']!['source_author'], equals('鲁迅'));
      expect(rowMap['q1']!['source_work'], equals('狂人日记'));

      expect(rowMap['q2']!['source_author'], isNull);
      expect(rowMap['q2']!['source_work'], equals('红楼梦'));

      expect(rowMap['q3']!['source_author'], equals('Tolstoy'));
      expect(rowMap['q3']!['source_work'], equals('War and Peace'));

      expect(rowMap['q4']!['source_author'], equals('Author'));
      expect(rowMap['q4']!['source_work'], equals('Work - Extra Note'));

      expect(rowMap['q5']!['source_author'], equals('Just Plain Author'));
      expect(rowMap['q5']!['source_work'], isNull);

      expect(rowMap['q6']!['source_author'], isNull);
      expect(rowMap['q6']!['source_work'], isNull);

      expect(rowMap['q7']!['source_author'], isNull);
      expect(rowMap['q7']!['source_work'], isNull);
    });

    test('v8 adds location, weather, and temperature to quotes', () async {
      await database.execute('CREATE TABLE quotes (id TEXT PRIMARY KEY)');
      final adapterV8 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 8);

      await database.transaction((txn) async {
        await adapterV8.apply(txn);
      });

      final columns = await database.rawQuery('PRAGMA table_info(quotes)');
      final columnNames = columns.map((c) => c['name'] as String).toSet();
      expect(columnNames, containsAll(['location', 'weather', 'temperature']));
    });

    test('v9 creates category_id and date indexes', () async {
      await database.execute(
          'CREATE TABLE quotes (id TEXT PRIMARY KEY, category_id TEXT, date TEXT)');
      final adapterV9 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 9);

      await database.transaction((txn) async {
        await adapterV9.apply(txn);
      });

      final indexes = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name IN ('idx_quotes_category_id', 'idx_quotes_date')",
      );
      expect(indexes.length, equals(2));
    });

    test('v10 adds edit_source to quotes', () async {
      await database.execute('CREATE TABLE quotes (id TEXT PRIMARY KEY)');
      final adapterV10 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 10);

      await database.transaction((txn) async {
        await adapterV10.apply(txn);
      });

      final columns = await database.rawQuery('PRAGMA table_info(quotes)');
      final columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames, contains('edit_source'));
    });

    test('v11 adds delta_content to quotes idempotently', () async {
      await database.execute('CREATE TABLE quotes (id TEXT PRIMARY KEY)');
      final adapterV11 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 11);

      // First run
      await database.transaction((txn) async {
        await adapterV11.apply(txn);
      });

      var columns = await database.rawQuery('PRAGMA table_info(quotes)');
      var columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames, contains('delta_content'));

      // Second run (idempotency check)
      await database.transaction((txn) async {
        await adapterV11.apply(txn);
      });
      columns = await database.rawQuery('PRAGMA table_info(quotes)');
      columnNames = columns.map((c) => c['name'] as String).toList();
      expect(columnNames, contains('delta_content'));
    });

    test('v12 normalizes quote tags via legacyTagAdapter', () async {
      await database
          .execute('CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT)');
      await database
          .execute('CREATE TABLE quotes (id TEXT PRIMARY KEY, tag_ids TEXT)');
      await database.insert('categories', {'id': 't1', 'name': 'Tag 1'});
      await database.insert('quotes', {'id': 'q1', 'tag_ids': 't1'});

      final adapterV12 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 12);

      await database.transaction((txn) async {
        await adapterV12.apply(txn);
      });

      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'quote_tags'",
      );
      expect(tables, hasLength(1));
    });

    test('v13 creates media_references table', () async {
      final adapterV13 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 13);

      await database.transaction((txn) async {
        await adapterV13.apply(txn);
      });

      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'media_references'",
      );
      expect(tables, hasLength(1));
    });

    test('v14 adds day_period column and index idempotently', () async {
      await database.execute('CREATE TABLE quotes (id TEXT PRIMARY KEY)');
      final adapterV14 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 14);

      await database.transaction((txn) async {
        await adapterV14.apply(txn);
      });

      Future<void> assertDayPeriodApplied() async {
        final columns = await database.rawQuery('PRAGMA table_info(quotes)');
        final columnNames = columns.map((c) => c['name'] as String).toList();
        expect(columnNames, contains('day_period'));

        final indexes = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_quotes_day_period'",
        );
        expect(indexes, hasLength(1));
      }

      await assertDayPeriodApplied();

      // Idempotency re-run must not throw and must not change the schema
      await database.transaction((txn) async {
        await adapterV14.apply(txn);
      });
      await assertDayPeriodApplied();
    });

    test('v15 adds last_modified to quotes, populates value, and creates index',
        () async {
      await database
          .execute('CREATE TABLE quotes (id TEXT PRIMARY KEY, date TEXT)');
      await database
          .insert('quotes', {'id': 'q1', 'date': '2025-01-01T10:00:00.000Z'});
      await database.insert('quotes', {'id': 'q2', 'date': null});

      final adapterV15 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 15);

      await database.transaction((txn) async {
        await adapterV15.apply(txn);
      });

      Future<void> assertLastModifiedApplied() async {
        final rows = await database.query('quotes', orderBy: 'id');
        expect(rows[0]['last_modified'], equals('2025-01-01T10:00:00.000Z'));
        // Null date falls back to the migration timestamp (COALESCE(date, now))
        expect(
          DateTime.tryParse(rows[1]['last_modified'] as String),
          isNotNull,
        );

        final indexes = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_quotes_last_modified'",
        );
        expect(indexes, hasLength(1));
      }

      await assertLastModifiedApplied();

      // Idempotency re-run must not throw and must not change data or schema
      await database.transaction((txn) async {
        await adapterV15.apply(txn);
      });
      await assertLastModifiedApplied();
    });

    test('v16 adds last_modified to categories and creates index', () async {
      await database
          .execute('CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT)');
      await database.insert('categories', {'id': 'c1', 'name': 'General'});

      final adapterV16 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 16);

      await database.transaction((txn) async {
        await adapterV16.apply(txn);
      });

      Future<void> assertV16Applied() async {
        final row = (await database.query('categories')).single;
        expect(DateTime.tryParse(row['last_modified'] as String), isNotNull);

        final indexes = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_categories_last_modified'",
        );
        expect(indexes, hasLength(1));
      }

      await assertV16Applied();

      // Idempotency re-run must not throw and must not change data or schema
      await database.transaction((txn) async {
        await adapterV16.apply(txn);
      });
      await assertV16Applied();
    });

    test('v17 adds favorite_count default 0 to quotes and creates index',
        () async {
      await database.execute('CREATE TABLE quotes (id TEXT PRIMARY KEY)');
      await database.insert('quotes', {'id': 'q1'});

      final adapterV17 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 17);

      await database.transaction((txn) async {
        await adapterV17.apply(txn);
      });

      Future<void> assertV17Applied() async {
        final row = (await database.query('quotes')).single;
        expect(row['favorite_count'], equals(0));

        final indexes = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_quotes_favorite_count'",
        );
        expect(indexes, hasLength(1));
      }

      await assertV17Applied();

      // Idempotency re-run must not throw and must not change data or schema
      await database.transaction((txn) async {
        await adapterV17.apply(txn);
      });
      await assertV17Applied();
    });

    test('v18 migrates default category icons', () async {
      await database.execute(
          'CREATE TABLE categories (id TEXT PRIMARY KEY, icon_name TEXT, is_default INTEGER)');
      await database.insert('categories',
          {'id': 'c1', 'icon_name': 'flutter_dash', 'is_default': 1});
      await database.insert(
          'categories', {'id': 'c2', 'icon_name': 'movie', 'is_default': 1});
      await database.insert('categories', {
        'id': 'c3',
        'icon_name': 'movie',
        'is_default': 0
      }); // Non-default category

      final adapterV18 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 18);

      await database.transaction((txn) async {
        await adapterV18.apply(txn);
      });

      final rows = await database.query('categories', orderBy: 'id');
      final rowMap = {for (var r in rows) r['id'] as String: r};

      expect(rowMap['c1']!['icon_name'], equals('format_quote'));
      expect(rowMap['c2']!['icon_name'], equals('🎬'));
      expect(
          rowMap['c3']!['icon_name'], equals('movie')); // Non-default unchanged
    });

    test('v19 adds quote coordinates latitude, longitude and index', () async {
      await database.execute('CREATE TABLE quotes (id TEXT PRIMARY KEY)');
      final adapterV19 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 19);

      await database.transaction((txn) async {
        await adapterV19.apply(txn);
      });

      Future<void> assertV19Applied() async {
        final columns = await database.rawQuery('PRAGMA table_info(quotes)');
        final columnNames = columns.map((c) => c['name'] as String).toSet();
        expect(columnNames, containsAll(['latitude', 'longitude']));

        final indexes = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_quotes_coordinates'",
        );
        expect(indexes, hasLength(1));
      }

      await assertV19Applied();

      // Idempotency re-run must not throw and must not change the schema
      await database.transaction((txn) async {
        await adapterV19.apply(txn);
      });
      await assertV19Applied();
    });

    test(
        'v20 adds trash metadata (is_deleted, deleted_at) and quote_tombstones',
        () async {
      await database.execute(
          'CREATE TABLE quotes (id TEXT PRIMARY KEY, date TEXT, last_modified TEXT)');
      await database.insert('quotes', {
        'id': 'q1',
        'date': '2025-01-01T00:00:00Z',
        'last_modified': '2025-01-02T00:00:00Z'
      });

      final adapterV20 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 20);

      await database.transaction((txn) async {
        await adapterV20.apply(txn);
      });

      Future<void> assertV20Applied() async {
        final columns = await database.rawQuery('PRAGMA table_info(quotes)');
        final columnNames = columns.map((c) => c['name'] as String).toSet();
        expect(columnNames, containsAll(['is_deleted', 'deleted_at']));

        final tables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'quote_tombstones'",
        );
        expect(tables, hasLength(1));
      }

      await assertV20Applied();

      // Idempotency re-run must not throw and must not change the schema
      await database.transaction((txn) async {
        await adapterV20.apply(txn);
      });
      await assertV20Applied();
    });

    test('v21 adds poi_name column and idx_quotes_poi_name index', () async {
      await database.execute(
          'CREATE TABLE quotes (id TEXT PRIMARY KEY, latitude REAL, longitude REAL)');
      final adapterV21 =
          schemaAdapters.adapters.firstWhere((a) => a.version == 21);

      await database.transaction((txn) async {
        await adapterV21.apply(txn);
      });

      Future<void> assertV21Applied() async {
        final columns = await database.rawQuery('PRAGMA table_info(quotes)');
        final columnNames = columns.map((c) => c['name'] as String).toList();
        expect(columnNames, contains('poi_name'));

        final indexes = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_quotes_poi_name'",
        );
        expect(indexes, hasLength(1));
      }

      await assertV21Applied();

      // Idempotency re-run must not throw and must not change the schema
      await database.transaction((txn) async {
        await adapterV21.apply(txn);
      });
      await assertV21Applied();
    });
  });
}
