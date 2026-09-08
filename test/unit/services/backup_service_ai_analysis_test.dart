import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/import_cleanup_stats.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/backup_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

class _FakeAIAnalysisDatabaseService extends Fake
    implements AIAnalysisDatabaseService {
  List<dynamic>? importedList;
  bool deleteAllCalled = false;

  @override
  Future<void> deleteAllAnalyses() async {
    deleteAllCalled = true;
  }

  @override
  Future<int> importAnalysesFromList(List<dynamic> analyses) async {
    importedList = analyses;
    return analyses.length;
  }
}

class _FakeDatabaseService extends Fake implements DatabaseService {
  @override
  Future<ImportCleanupStats> importDataFromMap(
    Map<String, dynamic> data, {
    bool clearExisting = false,
  }) async {
    return const ImportCleanupStats();
  }
}

class _FakeSettingsService extends Fake implements SettingsService {
  @override
  Future<void> restoreAllSettingsFromBackup(Map<String, dynamic> data) async {}
}

void main() {
  group('BackupService AI Analysis Import Tests', () {
    late _FakeDatabaseService fakeDb;
    late _FakeSettingsService fakeSettings;
    late _FakeAIAnalysisDatabaseService fakeAiDb;
    late BackupService backupService;

    setUp(() {
      fakeDb = _FakeDatabaseService();
      fakeSettings = _FakeSettingsService();
      fakeAiDb = _FakeAIAnalysisDatabaseService();
      backupService = BackupService(
        databaseService: fakeDb,
        settingsService: fakeSettings,
        aiAnalysisDbService: fakeAiDb,
      );
    });

    test(
        'passes raw ai_analysis list directly to AIAnalysisDatabaseService without crash',
        () async {
      final rawList = [
        <dynamic, dynamic>{'title': 'T1', 'content': 'C1'},
        'corrupt_entry',
        42,
        <String, dynamic>{'title': 'T2', 'content': 'C2'},
      ];

      final backupData = <String, dynamic>{
        'ai_analysis': rawList,
      };

      await backupService.testProcessImportData(backupData);

      expect(fakeAiDb.importedList, isNotNull);
      expect(fakeAiDb.importedList, equals(rawList));
    });

    test('safely handles non-List ai_analysis node without crashing', () async {
      final backupData = <String, dynamic>{
        'ai_analysis': 'invalid_string_not_a_list',
      };

      await backupService.testProcessImportData(backupData);

      expect(fakeAiDb.importedList, isNull);
    });

    test('calls deleteAllAnalyses when clearExisting is true', () async {
      final backupData = <String, dynamic>{
        'ai_analysis': [
          {'title': 'T', 'content': 'C'}
        ],
      };

      await backupService.testProcessImportData(backupData,
          clearExisting: true);

      expect(fakeAiDb.deleteAllCalled, isTrue);
      expect(fakeAiDb.importedList, isNotNull);
    });
  });
}
