import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';
import 'package:thoughtecho/services/database_service.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseService startup failures', () {
    late String originalDatabasesPath;

    setUp(() async {
      await TestHarness.initialize();
      await DatabaseService.closeDatabase();

      originalDatabasesPath = await databaseFactory.getDatabasesPath();
      final directory =
          await TestHarness.createTempDirectory('database_startup_failure');
      await databaseFactory.setDatabasesPath(directory.path);
      final databasePath = path.join(directory.path, 'thoughtecho.db');

      final database = await databaseFactory.openDatabase(databasePath);
      final schemaManager = DatabaseSchemaManager();
      await schemaManager.createTables(database);
      await database.insert('quotes', <String, Object?>{
        'id': 'quote-without-day-period',
        'content': 'Backfill must fail',
        'date': '2024-01-01T12:00:00.000',
      });
      await database.execute('''
        CREATE TRIGGER fail_startup_backfill
        BEFORE UPDATE OF day_period ON quotes
        WHEN OLD.day_period IS NULL
        BEGIN
          SELECT RAISE(ABORT, 'simulated startup backfill failure');
        END
      ''');
      await database.execute(
        'PRAGMA user_version = ${DatabaseSchemaManager.schemaVersion}',
      );
      await database.close();
    });

    tearDown(() async {
      await DatabaseService.closeDatabase();
      await databaseFactory.setDatabasesPath(originalDatabasesPath);
    });

    test('does not reuse a connection after startup backfill fails', () async {
      final service = DatabaseService();

      final initialStartup = service.init();
      final concurrentStartup = service.init();
      unawaited(concurrentStartup.catchError((_) {}));
      await expectLater(initialStartup, throwsA(isA<DatabaseException>()));
      await expectLater(concurrentStartup, throwsA(isA<DatabaseException>()));
      expect(DatabaseService.rawDatabaseInstance, isNull);

      final retryStartup = service.init();
      unawaited(retryStartup.catchError((_) {}));
      await expectLater(
        service.safeDatabase,
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(retryStartup, throwsA(isA<DatabaseException>()));
      expect(DatabaseService.rawDatabaseInstance, isNull);
    });
  });
}
