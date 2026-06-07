// ignore_for_file: experimental_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_sqflite/sentry_sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/utils/sentry_database_tracing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sentry database tracing', () {
    late DatabaseFactory originalFactory;
    late Database database;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      originalFactory = databaseFactory;
      database = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await database.execute(
        'CREATE TABLE notes (id INTEGER PRIMARY KEY, content TEXT)',
      );
      await database.insert('notes', {'content': 'existing note'});
    });

    tearDown(() async {
      await database.close();
    });

    test('wraps the opened database without replacing the global factory',
        () async {
      final traced = enableSentryDatabaseTracing(database);

      expect(traced, isA<SentryDatabase>());
      expect(databaseFactory, same(originalFactory));
      expect(traced.path, database.path);
      expect(await traced.query('notes'), hasLength(1));
    });

    test('does not wrap an already traced database twice', () {
      final traced = enableSentryDatabaseTracing(database);

      expect(enableSentryDatabaseTracing(traced), same(traced));
    });
  });
}
