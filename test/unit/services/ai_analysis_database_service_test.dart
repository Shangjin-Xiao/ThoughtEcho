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
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  group('AIAnalysisDatabaseService Tests', () {
    late AIAnalysisDatabaseService service;

    setUp(() async {
      service = AIAnalysisDatabaseService();
      await service.init();
    });

    tearDown(() async {
      await service.deleteAllAnalyses();
      await service.closeDatabase();
      final dbPath = p.join(Directory.systemTemp.path, 'ai_analyses.db');
      if (File(dbPath).existsSync()) {
        File(dbPath).deleteSync();
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
      ];
      final jsonStr = jsonEncode(jsonList);

      final count = await service.restoreFromJson(jsonStr);
      expect(count, equals(1));

      final item = await service.getAnalysisById('json-1');
      expect(item, isNotNull);
      expect(item!.title, equals('JSON Analysis 1'));
    });
  });
}
