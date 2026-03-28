import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_health_service.dart';

import '../../test_setup.dart';
import 'database_health_security_test.mocks.dart';

@GenerateMocks([Database])
void main() {
  late DatabaseFactory ffiFactory;

  setUpAll(() async {
    await TestSetup.setupAll();
    sqfliteFfiInit();
    ffiFactory = databaseFactoryFfi;
  });

  group('DatabaseHealthService Security Tests', () {
    late DatabaseHealthService healthService;
    late Database db;

    setUp(() async {
      healthService = DatabaseHealthService();
      db = await ffiFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE test_table (
          id INTEGER PRIMARY KEY,
          valid_column TEXT
        )
      ''');
    });

    tearDown(() async {
      await db.close();
    });

    group('checkColumnExists', () {
      test('should allow valid identifiers', () async {
        final result = await healthService.checkColumnExists(
            db, 'test_table', 'valid_column');
        expect(result, isTrue);

        final resultNotFound = await healthService.checkColumnExists(
            db, 'test_table', 'missing_column');
        expect(resultNotFound, isFalse);
      });

      test('should block SQL injection strings in tableName', () async {
        // Use mock database to ensure no SQL is executed
        final mockDb = MockDatabase();

        // SQL injection payload in table name
        final result = await healthService.checkColumnExists(
            mockDb, 'test_table; DROP TABLE users;--', 'valid_column');
        expect(result, isFalse);

        // Verify that no database calls were made
        verifyNever(mockDb.rawQuery(any));

        final result2 = await healthService.checkColumnExists(
            mockDb, 'test_table 1=1', 'valid_column');
        expect(result2, isFalse);

        // Verify that no database calls were made
        verifyNever(mockDb.rawQuery(any));
      });

      test('should block SQL injection strings in columnName', () async {
        // Use mock database to ensure no SQL is executed
        final mockDb = MockDatabase();

        // SQL injection payload in column name
        final result = await healthService.checkColumnExists(
            mockDb, 'test_table', 'valid_column; DROP TABLE users;--');
        expect(result, isFalse);

        // Verify that no database calls were made
        verifyNever(mockDb.rawQuery(any));
      });
    });

    group('createIndexSafely', () {
      test('should allow valid identifiers', () async {
        await healthService.createIndexSafely(
            db, 'test_table', 'valid_column', 'idx_test_valid');

        // Verify index creation
        final result = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_test_valid'");
        expect(result.isNotEmpty, isTrue);
      });

      test('should block SQL injection strings and not create index', () async {
        // Use mock database to ensure no SQL is executed
        final mockDb = MockDatabase();

        // SQL injection payload in table name
        await healthService.createIndexSafely(
            mockDb, 'test_table; DROP TABLE users;--', 'valid_column', 'idx_test');

        // Verify that no database calls were made
        verifyNever(mockDb.rawQuery(any));
        verifyNever(mockDb.execute(any));

        // SQL injection payload in column name
        await healthService.createIndexSafely(
            mockDb, 'test_table', 'valid_column; DROP TABLE users;--', 'idx_test');

        // Verify that no database calls were made
        verifyNever(mockDb.rawQuery(any));
        verifyNever(mockDb.execute(any));

        // SQL injection payload in index name
        await healthService.createIndexSafely(
            mockDb, 'test_table', 'valid_column', 'idx_test; DROP TABLE users;--');

        // Verify that no database calls were made
        verifyNever(mockDb.rawQuery(any));
        verifyNever(mockDb.execute(any));
      });
    });
  });
}