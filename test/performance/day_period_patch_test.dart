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
          'CREATE TABLE categories(id TEXT PRIMARY KEY, name TEXT, is_default BOOLEAN, icon_name TEXT, last_modified TEXT)');
      await db.execute(
          'CREATE TABLE quote_tags(quote_id TEXT, tag_id TEXT, PRIMARY KEY (quote_id, tag_id))');
      await db.execute(
          'CREATE TABLE media_references(id TEXT PRIMARY KEY, file_path TEXT, quote_id TEXT, created_at TEXT)');

      // We don't need full service.init() because we set the test database and created tables manually
      // But we need to ensure service knows database is ready if needed,
      // though patchQuotesDayPeriod checks _database != null which we set.
    });

    tearDown(() async {
      await db.close();
    });

    test('patchQuotesDayPeriod correctly updates day_period based on time',
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
          'expected': 'dawn'
        }, // 5 inclusive
        {
          'id': '9',
          'date': '2023-10-27T08:00:00',
          'expected': 'morning'
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

      // 2. Run the patch
      await service.patchQuotesDayPeriod();

      // 3. Verify
      for (final testCase in testCases) {
        final result = await db.query('quotes',
            columns: ['day_period'],
            where: 'id = ?',
            whereArgs: [testCase['id']]);
        final actual = result.first['day_period'];
        expect(actual, equals(testCase['expected']),
            reason: 'Failed for time ${testCase['date']}');
      }
    });
  });
}
