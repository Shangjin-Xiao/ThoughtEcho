/// Unit tests for AI Analysis Database Service
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  String tempPath = Directory.systemTemp.path;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return tempPath;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return tempPath;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePathProviderPlatform fakePlatform;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    fakePlatform = FakePathProviderPlatform();
    PathProviderPlatform.instance = fakePlatform;
  });

  group('AIAnalysisDatabaseService Tests', () {
    late AIAnalysisDatabaseService service;
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('ai_analysis_test_');
      fakePlatform.tempPath = tempDir.path;
      service = AIAnalysisDatabaseService();
      await service.init();
    });

    tearDown(() async {
      await service.deleteAllAnalyses();
      await service.closeDatabase();

      final docDbPath = p.join(tempDir.path, 'ai_analyses.db');
      if (File(docDbPath).existsSync()) {
        File(docDbPath).deleteSync();
      }

      try {
        final sqfliteDbPath =
            p.join(await getDatabasesPath(), 'ai_analyses.db');
        if (File(sqfliteDbPath).existsSync()) {
          File(sqfliteDbPath).deleteSync();
        }
      } catch (_) {}

      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
        'importAnalysesFromList handles Map<dynamic, dynamic> and skips non-map elements',
        () async {
      final mixedData = [
        <dynamic, dynamic>{
          'id': 'test-1',
          'title': 'Analysis 1',
          'content': 'Content 1',
          'analysis_type': 'comprehensive',
          'analysis_style': 'professional',
          'created_at': DateTime.now().toIso8601String(),
        },
        'corrupt_string_item',
        12345,
        <String, dynamic>{
          'id': 'test-2',
          'title': 'Analysis 2',
          'content': 'Content 2',
          'analysis_type': 'emotional',
          'analysis_style': 'friendly',
          'created_at': DateTime.now().toIso8601String(),
        },
      ];

      final importedCount = await service.importAnalysesFromList(mixedData);
      expect(importedCount, equals(2));

      final all = await service.getAllAnalyses();
      expect(all.length, equals(2));
      final ids = all.map((e) => e.id).toSet();
      expect(ids, containsAll(['test-1', 'test-2']));
    });

    test('importAnalysesFromList skips items missing title or content',
        () async {
      final dataWithIncompletes = [
        <String, dynamic>{
          'id': 'valid-1',
          'title': 'Valid Title',
          'content': 'Valid Content',
        },
        <String, dynamic>{
          'id': 'no-title',
          'content': 'Content only',
        },
        <String, dynamic>{
          'id': 'empty-title',
          'title': '   ',
          'content': 'Content only',
        },
        <String, dynamic>{
          'id': 'no-content',
          'title': 'Title only',
        },
        <String, dynamic>{
          'id': 'empty-content',
          'title': 'Title',
          'content': '   ',
        },
        <dynamic, dynamic>{},
      ];

      final count = await service.importAnalysesFromList(dataWithIncompletes);
      expect(count, equals(1));

      final all = await service.getAllAnalyses();
      expect(all.length, equals(1));
      expect(all.first.id, equals('valid-1'));
    });

    test('restoreFromJson safely parses JSON and filters invalid items',
        () async {
      final jsonList = [
        {
          'id': 'json-1',
          'title': 'JSON Analysis 1',
          'content': 'JSON Content 1',
          'analysis_type': 'mindmap',
          'analysis_style': 'literary',
          'created_at': DateTime.now().toIso8601String(),
        },
        null,
        'invalid_string',
        {'id': 'json-2', 'title': '', 'content': ''},
      ];
      final jsonStr = jsonEncode(jsonList);

      final count = await service.restoreFromJson(jsonStr);
      expect(count, equals(1));

      final item = await service.getAnalysisById('json-1');
      expect(item, isNotNull);
      expect(item!.title, equals('JSON Analysis 1'));
    });

    test('restoreFromJson returns 0 for non-List JSON root without error',
        () async {
      final count = await service.restoreFromJson('{"error": "not a list"}');
      expect(count, equals(0));
    });
  });
}
