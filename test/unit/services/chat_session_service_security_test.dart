import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/chat_session_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ChatSessionService definition regex tests', () {
    Database? db;
    late ChatSessionService service;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      // Create dummy table to avoid missing table error
      await db!.execute('CREATE TABLE dummy(id TEXT)');
      service = ChatSessionService(openOwnDatabase: false);
    });

    tearDown(() async {
      await db?.close();
    });

    test('valid definitions are allowed', () async {
      await service.addColumnIfMissing(
        db!,
        tableName: 'dummy',
        columnName: 'col1',
        definition: "TEXT NOT NULL DEFAULT 'note'",
      );

      await service.addColumnIfMissing(
        db!,
        tableName: 'dummy',
        columnName: 'col2',
        definition: 'INTEGER NOT NULL DEFAULT 0',
      );

      await service.addColumnIfMissing(
        db!,
        tableName: 'dummy',
        columnName: 'col3',
        definition: 'TEXT',
      );
    });

    test('invalid definitions with SQL injection payload are rejected',
        () async {
      await expectLater(
        () async => await service.addColumnIfMissing(
          db!,
          tableName: 'dummy',
          columnName: 'col4',
          definition: "TEXT; DROP TABLE dummy;",
        ),
        throwsA(isA<ArgumentError>()
            .having((e) => e.message, 'message', 'Invalid column definition')),
      );

      await expectLater(
        () async => await service.addColumnIfMissing(
          db!,
          tableName: 'dummy',
          columnName: 'col5',
          definition: "TEXT DEFAULT 'a'; --",
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('empty string or blank string definitions are rejected', () async {
      await expectLater(
        () async => await service.addColumnIfMissing(
          db!,
          tableName: 'dummy',
          columnName: 'col6',
          definition: "",
        ),
        throwsA(isA<ArgumentError>()),
      );

      await expectLater(
        () async => await service.addColumnIfMissing(
          db!,
          tableName: 'dummy',
          columnName: 'col7',
          definition: "   ",
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
