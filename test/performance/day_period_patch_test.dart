import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DatabaseService DayPeriod Patch Test', () {
    late DatabaseService service;
    late Database db;

    setUp(() async {
      service = DatabaseService();
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      DatabaseService.setTestDatabase(db);

      // Initialize basic tables
      await db.execute('''
          CREATE TABLE quotes(
            id TEXT PRIMARY KEY,
            content TEXT NOT NULL,
            date TEXT NOT NULL,
            day_period TEXT,
            source TEXT,
            source_author TEXT,
            source_work TEXT,
            ai_analysis TEXT,
            category_id TEXT DEFAULT '',
            last_modified TEXT,
            favorite_count INTEGER DEFAULT 0,
            weather TEXT,
            temperature TEXT,
            edit_source TEXT,
            delta_content TEXT,
            color_hex TEXT,
            location TEXT,
            latitude REAL,
            longitude REAL,
            sentiment TEXT,
            keywords TEXT,
            summary TEXT
          )
        ''');
      await db.execute(
        'CREATE TABLE categories(id TEXT PRIMARY KEY, name TEXT, is_default BOOLEAN, icon_name TEXT, last_modified TEXT)',
      );
      await db.execute(
        'CREATE TABLE quote_tags(quote_id TEXT, tag_id TEXT, PRIMARY KEY (quote_id, tag_id))',
      );
      await db.execute(
        'CREATE TABLE media_references(id TEXT PRIMARY KEY, file_path TEXT, quote_id TEXT, created_at TEXT)',
      );
    });

    tearDown(() async {
      await db.close();
      DatabaseService.clearTestDatabase();
    });

    test(
      'patchQuotesDayPeriod correctly updates day_period based on time',
      () async {
        // 1. Insert test data with NULL day_period
        final testCases = [
          {'id': '1', 'date': '2023-10-27T06:00:00', 'expected': 'dawn'},
          {'id': '2', 'date': '2023-10-27T09:00:00', 'expected': 'morning'},
          {'id': '3', 'date': '2023-10-27T14:00:00', 'expected': 'afternoon'},
          {'id': '4', 'date': '2023-10-27T18:00:00', 'expected': 'dusk'},
          {'id': '5', 'date': '2023-10-27T21:00:00', 'expected': 'evening'},
          {'id': '6', 'date': '2023-10-27T02:00:00', 'expected': 'midnight'},
          {'id': '7', 'date': '2023-10-27T23:30:00', 'expected': 'midnight'},
          // Edge cases
          {
            'id': '8',
            'date': '2023-10-27T05:00:00',
            'expected': 'dawn',
          }, // 5 inclusive
          {
            'id': '9',
            'date': '2023-10-27T08:00:00',
            'expected': 'morning',
          }, // 8 inclusive
        ];

        for (final testCase in testCases) {
          await db.insert('quotes', {
            'id': testCase['id'],
            'content': 'test',
            'date': testCase['date'],
            'day_period': null, // Explicitly null
          });
        }

        // Add empty string day_period case
        await db.insert('quotes', {
          'id': 'empty_day_period',
          'content': 'test',
          'date': '2023-10-27T09:00:00',
          'day_period': '', // Empty string
        });

        // Add existing day_period case (should NOT be overwritten)
        await db.insert('quotes', {
          'id': 'existing_day_period',
          'content': 'test',
          'date': '2023-10-27T02:00:00', // Midnight time
          'day_period': 'morning', // But marked as morning manually
        });

        // Add invalid date case (should be skipped due to strftime check)
        await db.insert('quotes', {
          'id': 'invalid_date',
          'content': 'test',
          'date': 'not-a-date',
          'day_period': null,
        });

        // Add empty date case
        await db.insert('quotes', {
          'id': 'empty_date',
          'content': 'test',
          'date': '',
          'day_period': null,
        });

        // 2. Run the patch
        await service.patchQuotesDayPeriod();

        // 3. Verify standard cases
        for (final testCase in testCases) {
          final result = await db.query(
            'quotes',
            columns: ['day_period'],
            where: 'id = ?',
            whereArgs: [testCase['id']],
          );
          final actual = result.first['day_period'];
          expect(
            actual,
            equals(testCase['expected']),
            reason: 'Failed for time ${testCase['date']}',
          );
        }

        // Verify empty string day_period was patched
        final emptyResult = await db.query(
          'quotes',
          columns: ['day_period'],
          where: 'id = ?',
          whereArgs: ['empty_day_period'],
        );
        expect(emptyResult.first['day_period'], equals('morning'));

        // Verify existing day_period was NOT overwritten
        final existingResult = await db.query(
          'quotes',
          columns: ['day_period'],
          where: 'id = ?',
          whereArgs: ['existing_day_period'],
        );
        expect(
          existingResult.first['day_period'],
          equals('morning'),
        ); // Still morning, not midnight

        // Verify invalid date was skipped (remains null)
        final invalidResult = await db.query(
          'quotes',
          columns: ['day_period'],
          where: 'id = ?',
          whereArgs: ['invalid_date'],
        );
        expect(invalidResult.first['day_period'], isNull);

        // Verify empty date was skipped (remains null)
        final emptyDateResult = await db.query(
          'quotes',
          columns: ['day_period'],
          where: 'id = ?',
          whereArgs: ['empty_date'],
        );
        expect(emptyDateResult.first['day_period'], isNull);
      },
    );
  });
}
