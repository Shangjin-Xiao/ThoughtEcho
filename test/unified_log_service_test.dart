import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart' as logging;
import 'package:sentry_flutter/sentry_flutter.dart';
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

    test('sentry integration excludes log text and records exceptions',
        () async {
      final mockTransport = _MockSentryTransport();
      await Sentry.init((options) {
        options.dsn = 'https://fake-dsn@sentry.io/1';
        options.transport = mockTransport;
      });

      expect(Sentry.isEnabled, isTrue);

      final warningMessage =
          'sentry-warning-test-${DateTime.now().microsecondsSinceEpoch}';
      service.warning(warningMessage, source: 'UnifiedLogServiceTest');
      await service.flushLogs();

      final errorMessage =
          'sentry-error-test-${DateTime.now().microsecondsSinceEpoch}';
      final exception = Exception('test exception');
      service.error(errorMessage,
          error: exception, source: 'UnifiedLogServiceTest');
      await service.flushLogs();

      // Wait for the asynchronous Sentry event capture to execute
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(mockTransport.envelopes.isNotEmpty, isTrue);

      bool foundBreadcrumb = false;
      bool foundException = false;

      for (final envelope in mockTransport.envelopes) {
        for (final item in envelope.items) {
          final original = item.originalObject;
          if (original is SentryEvent) {
            if (original.breadcrumbs != null) {
              for (final breadcrumb in original.breadcrumbs!) {
                if (breadcrumb.message == warningMessage) {
                  foundBreadcrumb = true;
                }
              }
            }
            if (original.exceptions != null) {
              for (final ex in original.exceptions!) {
                if (ex.value == 'Exception: test exception') {
                  foundException = true;
                }
              }
            }
          }
        }
      }

      expect(foundBreadcrumb, isFalse,
          reason: 'Unstructured warning text should not be sent to Sentry');
      expect(foundException, isTrue,
          reason: 'Severe log with exception should be captured by Sentry');

      Sentry.close();
    });
  });
}

class _MockSentryTransport implements Transport {
  final envelopes = <SentryEnvelope>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    envelopes.add(envelope);
    return SentryId.newId();
  }
}
