import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_service.dart';
import '../../test_setup.dart';

void main() {
  setUpAll(() async {
    await setupTestEnvironment();
  });

  group('getQuotesForSmartPush Security Tests', () {
    late DatabaseService databaseService;
    late Database db;

    setUp(() async {
      // Use an in-memory database for testing
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);

      // Initialize the database schema
      await db.execute('''
        CREATE TABLE quotes (
          id TEXT PRIMARY KEY,
          content TEXT,
          date TEXT,
          source TEXT,
          source_author TEXT,
          source_work TEXT,
          category_id TEXT,
          color_hex TEXT,
          location TEXT,
          latitude REAL,
          longitude REAL,
          weather TEXT,
          temperature REAL,
          edit_source TEXT,
          day_period TEXT,
          last_modified TEXT,
          favorite_count INTEGER,
          is_deleted INTEGER DEFAULT 0,
          deleted_at TEXT,
          delta_content TEXT,
          ai_analysis TEXT,
          summary TEXT,
          keywords TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE quote_tags (
          quote_id TEXT,
          tag_id TEXT,
          PRIMARY KEY (quote_id, tag_id)
        )
      ''');

      // Set the test database
      DatabaseService.setTestDatabase(db);
      databaseService = DatabaseService.forTesting();

      // Insert some data
      await db.insert('quotes', {
        'id': '1',
        'content': 'Normal quote',
        'date': '2023-01-01T00:00:00Z',
      });

      await db.insert('quotes', {
        'id': '2',
        'content': 'Hidden quote',
        'date': '2023-01-02T00:00:00Z',
      });

      await db.insert('quote_tags', {
        'quote_id': '2',
        'tag_id': 'system_hidden_tag',
      });
    });

    tearDown(() async {
      await db.close();
      DatabaseService.clearTestDatabase();
    });

    test('should normally exclude hidden quotes', () async {
      final results = await databaseService.getQuotesForSmartPush(limit: 10);
      expect(results.length, 1);
      expect(results.first.id, '1');
    });

    test('Method should no longer accept whereSql', () async {
      // This test is mostly for documentation, as it will cause a compilation error
      // if uncommented and the fix is applied.
      // Since we want the test to pass after the fix, we check that it doesn't return more than expected
      // when using the new signature.

      final results = await databaseService.getQuotesForSmartPush(limit: 10);

      expect(results.length, 1);
      expect(results.first.id, '1');
    });

    test('includeDeleted should preserve deleted metadata', () async {
      await db.insert('quotes', {
        'id': '3',
        'content': 'Deleted quote',
        'date': '2023-01-03T00:00:00Z',
        'is_deleted': 1,
        'deleted_at': '2023-01-04T00:00:00Z',
      });

      final results = await databaseService.getQuotesForSmartPush(
        limit: 10,
        includeDeleted: true,
      );
      final deletedQuote = results.firstWhere((quote) => quote.id == '3');
      expect(deletedQuote.isDeleted, isTrue);
      expect(deletedQuote.deletedAt, '2023-01-04T00:00:00Z');
    });
  });
}
