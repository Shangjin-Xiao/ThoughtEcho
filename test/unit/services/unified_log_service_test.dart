import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart' as logging;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/services/log_database_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

import '../../test_harness.dart';

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

class _FakeStorageAdapter implements StorageAdapter {
  final Map<String, Object?> values = {
    kKvEngineMigratedKey: true,
    kLegacyMmkvMigrationCompleteKey: true,
  };

  Future<bool> Function(String key, int value)? onSetInt;
  Future<bool> Function(String key, bool value)? onSetBool;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<bool> setInt(String key, int value) async {
    if (onSetInt != null) {
      final ok = await onSetInt!(key, value);
      if (!ok) return false;
    }
    values[key] = value;
    return true;
  }

  @override
  int? getInt(String key) => values[key] as int?;

  @override
  Future<bool> setDouble(String key, double value) async {
    values[key] = value;
    return true;
  }

  @override
  double? getDouble(String key) => values[key] as double?;

  @override
  Future<bool> setBool(String key, bool value) async {
    if (onSetBool != null) {
      final ok = await onSetBool!(key, value);
      if (!ok) return false;
    }
    values[key] = value;
    return true;
  }

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    values[key] = List<String>.from(value);
    return true;
  }

  @override
  List<String>? getStringList(String key) =>
      (values[key] as List<String>?)?.toList();

  @override
  bool containsKey(String key) => values.containsKey(key);

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }

  @override
  Set<String> getKeys() => values.keys.toSet();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnifiedLogService', () {
    late UnifiedLogService service;
    late LogDatabaseService logDb;

    setUp(() async {
      await TestHarness.initialize();
      logDb = LogDatabaseService();
      await logDb.clearAllLogs();
      service = UnifiedLogService.instance;
      await service.flushLogs();
      await service.clearAllLogs();
    });

    tearDown(() async {
      service.setPersistenceEnabled(false);
      service.clearMemoryLogs();
      await logDb.clearAllLogs();
      await logDb.close();
    });

    test(
        'warning logs stay in memory without opening the database when '
        'persistence is disabled', () async {
      final message =
          'warning-memory-only-${DateTime.now().microsecondsSinceEpoch}';

      service.setPersistenceEnabled(false);
      await logDb.close();

      service.warning(message, source: 'UnifiedLogServiceTest');
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final status = await logDb.getDatabaseStatus();

      expect(service.logs.any((entry) => entry.message == message), isTrue);
      expect(status['initialized'], isFalse);
    });

    test('info logs persist when persistence is enabled', () async {
      final message =
          'developer-persist-${DateTime.now().microsecondsSinceEpoch}';

      service.setPersistenceEnabled(true);
      service.info(message, source: 'UnifiedLogServiceTest');
      await service.flushLogs();

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

    test(
        'setLogLevel rolls back memory, persisted level, and logger when userSet write returns false',
        () async {
      final adapter = _FakeStorageAdapter();
      AppPreferencesService().resetForTesting();
      SafeMMKV().configureForTesting(
        primaryAdapter: adapter,
        candidateMmkvFiles: const [],
        forceNativeMmkvSupport: false,
      );
      await AppPreferencesService().init();
      addTearDown(() async {
        adapter.onSetBool = null;
        adapter.onSetInt = null;
        await service.setLogLevel(UnifiedLogLevel.info);
        AppPreferencesService().resetForTesting();
      });

      await service.setLogLevel(UnifiedLogLevel.error);
      await service.setLogLevel(UnifiedLogLevel.info);
      expect(service.currentLevel, UnifiedLogLevel.info);
      expect(logging.Logger.root.level, logging.Level.INFO);

      // Pretend user_set flag was previously absent, and fail writing it
      adapter.values.remove('log_level_user_set');
      adapter.onSetBool = (key, value) async => false;

      await service.setLogLevel(UnifiedLogLevel.debug);

      expect(service.currentLevel, UnifiedLogLevel.info);
      expect(logging.Logger.root.level, logging.Level.INFO);
      expect(
        adapter.values['log_level'],
        UnifiedLogLevel.info.index,
      );
      expect(adapter.values.containsKey('log_level_user_set'), isFalse);

      // Also verify non-null false user_set flag is restored when setBool fails on true
      adapter.values['log_level_user_set'] = false;
      adapter.onSetBool = (key, value) async => !value;
      await service.setLogLevel(UnifiedLogLevel.debug);
      expect(adapter.values['log_level_user_set'], isFalse);
      expect(
        adapter.values['log_level'],
        UnifiedLogLevel.info.index,
      );
    });

    test('setLogLevel logs warning when preference rollback itself fails',
        () async {
      final adapter = _FakeStorageAdapter();
      AppPreferencesService().resetForTesting();
      SafeMMKV().configureForTesting(
        primaryAdapter: adapter,
        candidateMmkvFiles: const [],
        forceNativeMmkvSupport: false,
      );
      await AppPreferencesService().init();
      addTearDown(() async {
        adapter.onSetBool = null;
        adapter.onSetInt = null;
        await service.setLogLevel(UnifiedLogLevel.info);
        AppPreferencesService().resetForTesting();
      });

      await service.setLogLevel(UnifiedLogLevel.error);
      await service.setLogLevel(UnifiedLogLevel.info);
      service.clearMemoryLogs();

      var setIntCalls = 0;
      adapter.onSetInt = (key, value) async {
        setIntCalls++;
        // First write succeeds (newLevel), rollback write returns false
        return setIntCalls == 1;
      };
      adapter.onSetBool = (key, value) async => false;

      await service.setLogLevel(UnifiedLogLevel.debug);

      expect(service.currentLevel, UnifiedLogLevel.info);
      expect(
        service.logs.any(
          (entry) =>
              entry.level == UnifiedLogLevel.warning &&
              entry.message.contains('回滚日志级别偏好失败'),
        ),
        isTrue,
      );
    });

    test(
        'overlapping setLogLevel calls serialize so an earlier failure cannot overwrite a later success',
        () async {
      final adapter = _FakeStorageAdapter();
      AppPreferencesService().resetForTesting();
      SafeMMKV().configureForTesting(
        primaryAdapter: adapter,
        candidateMmkvFiles: const [],
        forceNativeMmkvSupport: false,
      );
      await AppPreferencesService().init();
      addTearDown(() async {
        adapter.onSetBool = null;
        adapter.onSetInt = null;
        await service.setLogLevel(UnifiedLogLevel.info);
        AppPreferencesService().resetForTesting();
      });

      await service.setLogLevel(UnifiedLogLevel.error);
      await service.setLogLevel(UnifiedLogLevel.info);

      final firstAttemptGate = Completer<void>();
      var boolAttempt = 0;
      adapter.onSetBool = (key, value) async {
        boolAttempt++;
        if (boolAttempt == 1) {
          await firstAttemptGate.future;
          return false;
        }
        return true;
      };

      final first = service.setLogLevel(UnifiedLogLevel.debug);
      final second = service.setLogLevel(UnifiedLogLevel.warning);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      firstAttemptGate.complete();
      await Future.wait([first, second]);

      expect(service.currentLevel, UnifiedLogLevel.warning);
      expect(logging.Logger.root.level, logging.Level.WARNING);
      expect(
        adapter.values['log_level'],
        UnifiedLogLevel.warning.index,
      );
      expect(adapter.values['log_level_user_set'], isTrue);
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
