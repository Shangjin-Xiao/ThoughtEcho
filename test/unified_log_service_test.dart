import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart' as logging;
import 'package:sqflite/sqflite.dart';
import 'package:thoughtecho/services/log_database_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';

import 'test_setup.dart';

class _RecordingDatabase implements Database {
  final rawQueries = <String>[];
  final executes = <String>[];

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    rawQueries.add(sql);
    return const [];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    executes.add(sql);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnifiedLogService', () {
    late UnifiedLogService service;
    late LogDatabaseService logDb;

    setUp(() async {
      await TestSetup.setupAll();
      logDb = LogDatabaseService();
      await logDb.clearAllLogs();
      service = UnifiedLogService.instance;
      await service.flushLogs();
      await service.clearAllLogs();
    });

    tearDown(() async {
      service.clearMemoryLogs();
      await logDb.clearAllLogs();
      await logDb.close();
    });

    test('warning logs persist promptly even when persistence is disabled',
        () async {
      final message =
          'warning-persist-${DateTime.now().microsecondsSinceEpoch}';

      service.warning(message, source: 'UnifiedLogServiceTest');
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final queried = await service.queryLogs(
        searchText: message,
        source: 'UnifiedLogServiceTest',
        limit: 10,
      );

      expect(queried.any((entry) => entry.message == message), isTrue);
    });

    test('captures external package logging messages at debug level', () async {
      final message = 'external-debug-${DateTime.now().microsecondsSinceEpoch}';

      await service.setLogLevel(UnifiedLogLevel.debug);
      logging.Logger('ExternalLogger').fine(message);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.logs.any((entry) => entry.message == message), isTrue);
    });

    test('clearAllLogs leaves memory and database empty', () async {
      service.info('to-be-cleared', source: 'UnifiedLogServiceTest');
      await service.flushLogs();

      await service.clearAllLogs();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final queried = await service.queryLogs(limit: 10);

      expect(service.logs, isEmpty);
      expect(queried, isEmpty);
    });

    test('opening log database does not emit PRAGMA setup failure', () async {
      await service.setLogLevel(UnifiedLogLevel.debug);
      service.clearMemoryLogs();
      await logDb.close();

      await logDb.ready;

      expect(
        service.logs.any(
          (entry) => entry.message.contains('PRAGMA setup failed'),
        ),
        isFalse,
      );
    });

    test('log database PRAGMA setup uses rawQuery', () async {
      final db = _RecordingDatabase();

      await configureLogDatabasePragmasForTest(db);

      expect(db.rawQueries, [
        'PRAGMA journal_mode=WAL;',
        'PRAGMA synchronous=NORMAL;',
      ]);
      expect(db.executes, isEmpty);
    });
  });
}
