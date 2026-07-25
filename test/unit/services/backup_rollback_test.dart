import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:thoughtecho/services/database_backup_service.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';
import 'package:thoughtecho/services/database_service.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late DatabaseBackupService backupService;
  late DatabaseService databaseService;
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  setUp(() async {
    dbPath = p.join(Directory.systemTemp.path, 'test_backup_rollback.db');
    if (File(dbPath).existsSync()) {
      File(dbPath).deleteSync();
    }
    db = await databaseFactory.openDatabase(dbPath);
    await DatabaseSchemaManager().createTables(db);

    backupService = DatabaseBackupService();
    databaseService = DatabaseService();
    DatabaseService.setTestDatabase(db);
  });

  tearDown(() async {
    await db.close();
    DatabaseService.clearTestDatabase();
  });

  group('Database Restore Atomic Transaction & Rollback Tests (R1.4, R3.2)',
      () {
    test('importDataFromMap failure rolls back SQLite transaction completely',
        () async {
      // 1. Insert baseline data
      await db.insert('categories', {
        'id': 'cat_baseline',
        'name': 'Baseline Category',
        'is_default': 1,
        'last_modified': '2026-01-01T00:00:00Z',
      });
      await db.insert('quotes', {
        'id': 'quote_baseline',
        'content': 'Baseline Content',
        'date': '2026-01-01T00:00:00Z',
        'last_modified': '2026-01-01T00:00:00Z',
      });
      await db.insert('quote_tags', {
        'quote_id': 'quote_baseline',
        'tag_id': 'cat_baseline',
      });
      await db.insert('quote_tombstones', {
        'quote_id': 'quote_old_tombstone',
        'deleted_at': '2026-01-01T00:00:00Z',
      });

      // 2. Construct malformed restore map (non-map element in quotes list causes exception)
      final malformedData = {
        'categories': [
          {'id': 'cat_new', 'name': 'New Category'},
        ],
        'quotes': [
          'invalid_string_instead_of_map', // Will trigger type error on 'q as Map'
        ],
      };

      // 3. Attempt import and expect exception
      expect(
        () async => await backupService.importDataFromMap(
          db,
          malformedData,
          clearExisting: true,
        ),
        throwsA(anything),
      );

      // 4. Verify baseline data remains intact due to SQLite transaction rollback
      final categories = await db.query('categories');
      expect(categories.length, equals(1));
      expect(categories.first['id'], equals('cat_baseline'));

      final quotes = await db.query('quotes');
      expect(quotes.length, equals(1));
      expect(quotes.first['id'], equals('quote_baseline'));

      final tags = await db.query('quote_tags');
      expect(tags.length, equals(1));
      expect(tags.first['quote_id'], equals('quote_baseline'));

      final tombstones = await db.query('quote_tombstones');
      expect(tombstones.length, equals(1));
      expect(tombstones.first['quote_id'], equals('quote_old_tombstone'));
    });

    test(
        'importDataWithLWWMerge failure rolls back transaction without corrupting DB',
        () async {
      // 1. Insert baseline data
      await db.insert('categories', {
        'id': 'cat_baseline',
        'name': 'Baseline Category',
        'last_modified': '2026-01-01T00:00:00Z',
      });
      await db.insert('quotes', {
        'id': 'quote_baseline',
        'content': 'Baseline Content',
        'date': '2026-01-01T00:00:00Z',
        'last_modified': '2026-01-01T00:00:00Z',
      });

      // 2. Data payload missing required keys returns report with error without modifying DB
      final invalidMergeData = <String, dynamic>{
        'categories': [
          {'id': 'cat_merge', 'name': 'Merge Cat'},
        ],
        // Missing 'quotes' key
      };

      final report = await backupService.importDataWithLWWMerge(
        db,
        invalidMergeData,
      );

      expect(report.hasErrors, isTrue);

      // Verify DB content remains unchanged
      final quotes = await db.query('quotes');
      expect(quotes.length, equals(1));
      expect(quotes.first['id'], equals('quote_baseline'));
      expect(quotes.first['content'], equals('Baseline Content'));
    });
  });

  group('Post-Restore Migration Triggers Tests (R2.3, R3.2)', () {
    test(
        'importDataFromMap triggers post-restore migrations for day_period and weather',
        () async {
      // 1. Restore map containing a quote with missing day_period (time = 09:00:00 morning)
      final restoreData = {
        'categories': [
          {'id': 'cat_1', 'name': 'Category 1'},
        ],
        'quotes': [
          {
            'id': 'quote_patch_test',
            'content': 'Quote needing day period patch',
            'date': '2026-05-10T09:00:00.000Z',
            'day_period': null, // Missing day period
            'weather': '晴', // Legacy Chinese weather value
            'last_modified': '2026-05-10T09:00:00.000Z',
          },
        ],
      };

      // 2. Import via DatabaseService (which executes _triggerPostRestoreMigrations)
      await databaseService.importDataFromMap(restoreData,
          clearExisting: false);

      // 3. Verify quote has patched day_period ('morning') and migrated weather key ('clear')
      final quoteRows = await db.query(
        'quotes',
        where: 'id = ?',
        whereArgs: ['quote_patch_test'],
      );
      expect(quoteRows.length, equals(1));
      expect(quoteRows.first['day_period'], equals('morning'));
      expect(quoteRows.first['weather'], equals('clear'));
    });

    test(
        'importDataWithLWWMerge triggers post-restore migrations upon completion',
        () async {
      final mergeData = {
        'categories': [
          {'id': 'cat_lww', 'name': 'LWW Category'},
        ],
        'quotes': [
          {
            'id': 'quote_lww_patch_test',
            'content': 'LWW Quote needing day period patch',
            'date': '2026-05-10T14:30:00.000Z',
            'day_period': '', // Empty string day_period
            'weather': '多云', // Legacy Chinese weather value
            'last_modified': '2026-05-10T14:30:00.000Z',
          },
        ],
      };

      // Execute LWW merge via DatabaseService
      final report = await databaseService.importDataWithLWWMerge(mergeData);

      expect(report.hasErrors, isFalse);

      // Verify post-restore migration ran for LWW merge
      final quoteRows = await db.query(
        'quotes',
        where: 'id = ?',
        whereArgs: ['quote_lww_patch_test'],
      );
      expect(quoteRows.length, equals(1));
      expect(quoteRows.first['day_period'], equals('afternoon'));
      expect(quoteRows.first['weather'], equals('cloudy'));
    });
  });
}
