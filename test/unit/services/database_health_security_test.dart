import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_health_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DatabaseHealthService Security Tests', () {
    late DatabaseHealthService healthService;
    late Database db;

    setUp(() async {
      healthService = DatabaseHealthService();
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
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
        // SQL injection payload in table name
        final result = await healthService.checkColumnExists(
            db, 'test_table; DROP TABLE users;--', 'valid_column');
        expect(result, isFalse);

        final result2 = await healthService.checkColumnExists(
            db, 'test_table 1=1', 'valid_column');
        expect(result2, isFalse);
      });

      test('should block SQL injection strings in columnName', () async {
        // SQL injection payload in column name
        final result = await healthService.checkColumnExists(
            db, 'test_table', 'valid_column; DROP TABLE users;--');
        expect(result, isFalse);
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
        await healthService.createIndexSafely(
            db, 'test_table; DROP TABLE users;--', 'valid_column', 'idx_test');

        await healthService.createIndexSafely(
            db, 'test_table', 'valid_column; DROP TABLE users;--', 'idx_test');

        await healthService.createIndexSafely(
            db, 'test_table', 'valid_column', 'idx_test; DROP TABLE users;--');

        // Verify index was not created by checking sqlite_master for index
        final result = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_test%'");
        expect(result.isEmpty, isTrue);
      });
    });
  });
}
