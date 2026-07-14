import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/chat_session_service.dart';

// ignore: depend_on_referenced_packages
import 'package:sqflite_common/sqlite_api.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ChatSessionService definition regex tests', () {
    test('valid definitions are allowed', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      // Create dummy table to avoid missing table error
      await db.execute('CREATE TABLE dummy(id TEXT)');

      // Access the private method via dynamic for testing
      final service = ChatSessionService(openOwnDatabase: false);
      dynamic dynamicService = service;

      await expectLater(
        () async => await dynamicService._addColumnIfMissing(
          db,
          tableName: 'dummy',
          columnName: 'col1',
          definition: "TEXT NOT NULL DEFAULT 'note'",
        ),
        returnsNormally,
      );

      await expectLater(
        () async => await dynamicService._addColumnIfMissing(
          db,
          tableName: 'dummy',
          columnName: 'col2',
          definition: 'INTEGER NOT NULL DEFAULT 0',
        ),
        returnsNormally,
      );

      await expectLater(
        () async => await dynamicService._addColumnIfMissing(
          db,
          tableName: 'dummy',
          columnName: 'col3',
          definition: 'TEXT',
        ),
        returnsNormally,
      );

      await db.close();
    });

    test('invalid definitions with SQL injection payload are rejected', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE dummy(id TEXT)');

      final service = ChatSessionService(openOwnDatabase: false);
      dynamic dynamicService = service;

      await expectLater(
        () async => await dynamicService._addColumnIfMissing(
          db,
          tableName: 'dummy',
          columnName: 'col4',
          definition: "TEXT; DROP TABLE dummy;",
        ),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', 'Invalid column definition')),
      );

      await expectLater(
        () async => await dynamicService._addColumnIfMissing(
          db,
          tableName: 'dummy',
          columnName: 'col5',
          definition: "TEXT DEFAULT 'a'; --",
        ),
        throwsA(isA<ArgumentError>()),
      );

      await db.close();
    });

    test('empty string or blank string definitions are rejected', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE dummy(id TEXT)');

      final service = ChatSessionService(openOwnDatabase: false);
      dynamic dynamicService = service;

      await expectLater(
        () async => await dynamicService._addColumnIfMissing(
          db,
          tableName: 'dummy',
          columnName: 'col6',
          definition: "",
        ),
        throwsA(isA<ArgumentError>()),
      );

      await expectLater(
        () async => await dynamicService._addColumnIfMissing(
          db,
          tableName: 'dummy',
          columnName: 'col7',
          definition: "   ",
        ),
        throwsA(isA<ArgumentError>()),
      );

      await db.close();
    });
  });
}
