import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/backup_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

import '../../test_harness.dart';

class _ExportDatabase extends Fake implements DatabaseService {
  int reads = 0;
  final hiddenNote = Quote(
    id: 'hidden-note',
    content: 'Synthetic private note',
    date: '2026-01-01T00:00:00.000Z',
    tagIds: [DatabaseService.hiddenTagId],
  );

  @override
  Future<List<Map<String, dynamic>>> getAllTagMaps() async {
    reads++;
    return [
      {'id': DatabaseService.hiddenTagId, 'name': 'Hidden'},
    ];
  }

  @override
  Future<int> getQuotesCount({
    List<String>? tagIds,
    String? categoryId,
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool excludeHiddenNotes = true,
    String? dateStart,
    String? dateEnd,
    bool includeDeleted = false,
  }) async =>
      1;

  @override
  Future<List<Quote>> getUserQuotes({
    List<String>? tagIds,
    String? categoryId,
    int offset = 0,
    int limit = 10,
    String orderBy = 'date DESC',
    String? searchQuery,
    List<String>? selectedWeathers,
    List<String>? selectedDayPeriods,
    bool excludeHiddenNotes = true,
    String? dateStart,
    String? dateEnd,
    bool includeDeleted = false,
  }) async =>
      offset == 0 ? [hiddenNote] : [];

  @override
  Future<List<Map<String, dynamic>>> getTombstonesForBackup() async => [];
}

class _ExportSettings extends Fake implements SettingsService {
  bool protectionEnabled = true;

  @override
  bool get requireBiometricForHidden => protectionEnabled;
  @override
  String? get localeCode => 'en';
  @override
  String getOrCreateDeviceId() => 'synthetic-device';
  @override
  int get trashRetentionDays => 30;
  @override
  String get trashRetentionLastModified => '2026-01-01T00:00:00.000Z';
  @override
  Map<String, dynamic> getAllSettingsForBackup() => {};
}

class _ExportAnalyses extends Fake implements AIAnalysisDatabaseService {
  @override
  Future<List<Map<String, dynamic>>> exportAnalysesPage(
    int offset,
    int limit,
  ) async =>
      [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const authChannel = MethodChannel('plugins.flutter.io/local_auth');
  late _ExportDatabase database;
  late _ExportSettings settings;
  late BackupService service;
  late Directory temporaryDirectory;
  bool supported = true;
  bool authenticated = false;
  bool authError = false;
  int authenticationCalls = 0;

  setUp(() async {
    await TestHarness.initialize();
    temporaryDirectory = await getTemporaryDirectory();
    database = _ExportDatabase();
    settings = _ExportSettings();
    service = BackupService(
      databaseService: database,
      settingsService: settings,
      aiAnalysisDbService: _ExportAnalyses(),
    );
    supported = true;
    authenticated = false;
    authError = false;
    authenticationCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(authChannel, (call) async {
      switch (call.method) {
        case 'isDeviceSupported':
        case 'deviceSupportsBiometrics':
          return supported;
        case 'getAvailableBiometrics':
          return supported ? ['fingerprint'] : <String>[];
        case 'authenticate':
          authenticationCalls++;
          if (authError) {
            throw PlatformException(code: 'auth_error');
          }
          return authenticated;
      }
      throw UnsupportedError(call.method);
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(authChannel, null);
    await TestHarness.tearDown();
  });

  for (final includeMedia in [false, true]) {
    test(
        'denied authentication prevents ${includeMedia ? 'ZIP' : 'JSON'} export',
        () async {
      await expectLater(
        service.exportAllData(includeMediaFiles: includeMedia),
        throwsStateError,
      );
      expect(authenticationCalls, 1);
      expect(database.reads, 0);
      expect(await temporaryDirectory.list(recursive: true).toList(), isEmpty);
    });
  }

  for (final failure in ['unavailable', 'platform error']) {
    test('$failure prevents protected backup export', () async {
      supported = failure != 'unavailable';
      authError = failure == 'platform error';
      await expectLater(
        service.exportAllData(includeMediaFiles: false),
        throwsStateError,
      );
      expect(database.reads, 0);
      expect(await temporaryDirectory.list(recursive: true).toList(), isEmpty);
    });
  }

  test('successful authentication exports hidden content and is not reused',
      () async {
    authenticated = true;
    final backupPath = await service.exportAllData(includeMediaFiles: false);
    final backup = jsonDecode(await File(backupPath).readAsString()) as Map;
    expect(backup['notes']['quotes'].single['content'],
        database.hiddenNote.content);
    expect(authenticationCalls, 1);

    authenticated = false;
    await expectLater(
      service.exportAllData(includeMediaFiles: false, customPath: backupPath),
      throwsStateError,
    );
    expect(authenticationCalls, 2);
    expect(await File(backupPath).readAsString(), jsonEncode(backup));
  });

  test('unprotected backups export without requesting authentication',
      () async {
    settings.protectionEnabled = false;
    final backupPath = await service.exportAllData(includeMediaFiles: false);
    final backup = jsonDecode(await File(backupPath).readAsString()) as Map;
    expect(backup['notes']['quotes'].single['content'],
        database.hiddenNote.content);
    expect(authenticationCalls, 0);
  });
}
