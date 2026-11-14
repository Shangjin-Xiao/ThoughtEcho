/// Unit tests for AI Analysis Database Service
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/periodic_insight.dart';
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
      await service.deleteAllPeriodicInsights();
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

    test('importAnalysesFromList batches inserts and skips malformed items',
        () async {
      final mixedList = [
        ...List.generate(
          20,
          (i) => {
            'id': 'batch-$i',
            'title': 'Batch Test $i',
            'content': 'Content for batch test item $i',
            'analysis_type': 'comprehensive',
            'analysis_style': 'professional',
            'created_at': DateTime.now().toIso8601String(),
          },
        ),
        {
          'id': 'invalid-item',
          'title': null,
          'content': null,
        },
      ];

      final count = await service.importAnalysesFromList(mixedList);
      expect(count, equals(20));

      final item = await service.getAnalysisById('batch-0');
      expect(item, isNotNull);
      expect(item!.title, equals('Batch Test 0'));
    });

    test('query methods handle corrupted database rows defensively', () async {
      final db = await service.database;
      // 插入一条合法数据与一条被直接修饰为触发 Exception 的破坏数据（例如: quote_count 存了无效字符串导致类型解析失败）
      await db.insert('ai_analyses', {
        'id': 'valid-row',
        'title': 'Valid Title',
        'content': 'Valid Content',
        'analysis_type': 'comprehensive',
        'analysis_style': 'professional',
        'created_at': DateTime.now().toIso8601String(),
        'quote_count': 5,
      });

      // 直接使用原始 SQL 写入损坏行（如非数字 quote_count 在 JSON 还原或自定义解析处理）
      // 使用带特异性解析失败的情况
      await db.rawInsert('''
        INSERT INTO ai_analyses (id, title, content, analysis_type, analysis_style, created_at, quote_count)
        VALUES ('corrupt-row', 'Corrupt Title', 'Corrupt Content', 'comprehensive', 'professional', '2026-01-01T00:00:00.000', 'invalid_int')
      ''');

      // getAllAnalyses 应该能捕获/过滤坏行，不崩溃并返回合法记录
      final analyses = await service.getAllAnalyses();
      expect(analyses.any((a) => a.id == 'valid-row'), isTrue);

      // searchAnalysesByType 应该也能安全过滤坏行
      final typeResults = await service.searchAnalysesByType('comprehensive');
      expect(typeResults.any((a) => a.id == 'valid-row'), isTrue);

      // searchAnalyses 应该也能安全过滤坏行
      final searchResults = await service.searchAnalyses('Title');
      expect(searchResults.any((a) => a.id == 'valid-row'), isTrue);
    });

    test(
        'periodic_insights CRUD, signature deduplication, 50-item cap, and deleteAllAnalyses isolation',
        () async {
      final base = DateTime(2026, 8, 1);

      // 保存 55 条，验证保留最新 50 条
      for (var i = 0; i < 55; i++) {
        await service.savePeriodicInsight(
          PeriodicInsight(
            insight: 'Insight $i',
            periodType: 'week',
            periodLabel: '2026年第${(i % 4) + 1}周',
            createdAt: base.add(Duration(hours: i)),
            isAiGenerated: true,
            dataSignature: 'sig_$i',
          ),
        );
      }

      final afterCap = await service.getPeriodicInsights(limit: 100);
      expect(afterCap.length, equals(50));
      expect(afterCap.first.insight, equals('Insight 54'));
      expect(afterCap.last.insight, equals('Insight 5'));

      // 相同 dataSignature 应覆盖旧记录，不产生重复条目
      await service.savePeriodicInsight(
        PeriodicInsight(
          insight: 'Insight 54 updated',
          periodType: 'week',
          periodLabel: '2026年第3周',
          createdAt: base.add(const Duration(hours: 60)),
          isAiGenerated: true,
          dataSignature: 'sig_54',
        ),
      );
      final afterDedup = await service.getPeriodicInsights(limit: 100);
      expect(afterDedup.length, equals(50));
      expect(
        afterDedup.where((e) => e.dataSignature == 'sig_54').single.insight,
        equals('Insight 54 updated'),
      );

      // 删除早于某个时间点的记录
      final removed = await service.deletePeriodicInsightsOlderThan(
        base.add(const Duration(hours: 50)),
      );
      expect(removed, equals(45));
      final remaining = await service.getPeriodicInsights(limit: 100);
      expect(remaining.length, equals(5));

      // deleteAllAnalyses 不得清空 periodic_insights
      await service.deleteAllAnalyses();
      final stillThere = await service.getPeriodicInsights(limit: 100);
      expect(stillThere.length, equals(5));
    });

    test(
        'upgrades v1 database to v2 preserving ai_analyses and creating periodic_insights',
        () async {
      final dbPath = (await service.database).path;
      await service.closeDatabase();

      if (File(dbPath).existsSync()) {
        File(dbPath).deleteSync();
      }

      // 构造 v1 数据库（仅有 ai_analyses，无 periodic_insights）
      final v1Db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE ai_analyses(
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                analysis_type TEXT NOT NULL,
                analysis_style TEXT NOT NULL,
                custom_prompt TEXT,
                created_at TEXT NOT NULL,
                related_quote_ids TEXT,
                quote_count INTEGER
              )
            ''');
          },
        ),
      );
      await v1Db.insert('ai_analyses', {
        'id': 'v1-analysis-1',
        'title': 'V1 Analysis',
        'content': 'Preserved content',
        'analysis_type': 'comprehensive',
        'analysis_style': 'professional',
        'created_at': DateTime(2026, 7, 1).toIso8601String(),
        'quote_count': 3,
      });
      await v1Db.close();

      // 用 AIAnalysisDatabaseService 重新打开触发 v1 -> v2 升级
      await service.init();
      final migratedAnalyses = await service.getAllAnalyses();
      expect(migratedAnalyses.length, equals(1));
      expect(migratedAnalyses.first.id, equals('v1-analysis-1'));
      expect(migratedAnalyses.first.title, equals('V1 Analysis'));

      await service.savePeriodicInsight(
        PeriodicInsight(
          insight: 'Post-upgrade insight',
          periodType: 'month',
          periodLabel: '2026年7月',
          createdAt: DateTime(2026, 8, 1),
          isAiGenerated: false,
          dataSignature: 'upgrade_sig',
        ),
      );
      final insights = await service.getPeriodicInsights();
      expect(insights.length, equals(1));
      expect(insights.first.insight, equals('Post-upgrade insight'));
    });

    test(
        'importPeriodicInsights deduplicates legacy insights without dataSignature and skips corrupt DB timestamps',
        () async {
      final legacyCreatedAt = DateTime.utc(2026, 6, 1, 12, 0);
      final items = [
        PeriodicInsight(
          insight: 'Legacy without signature 1',
          periodType: 'week',
          periodLabel: '2026年第22周',
          createdAt: legacyCreatedAt,
          isAiGenerated: true,
          dataSignature: null,
        ),
        PeriodicInsight(
          insight: 'Legacy without signature 2',
          periodType: 'month',
          periodLabel: '6月',
          createdAt: legacyCreatedAt.add(const Duration(days: 1)),
          isAiGenerated: true,
          dataSignature: '',
        ),
      ];

      await service.importPeriodicInsights(items);
      await service.importPeriodicInsights(items);

      final db = await service.database;
      await db.insert('periodic_insights', {
        'insight': 'Corrupt timestamp row',
        'period_type': 'week',
        'period_label': '本周',
        'created_at': 'not-a-timestamp',
        'is_ai_generated': 1,
        'data_signature': 'corrupt_sig',
      });

      final loaded = await service.getPeriodicInsights(limit: 100);
      expect(loaded.length, equals(2));
      expect(
        loaded.map((e) => e.insight),
        containsAll(
          ['Legacy without signature 1', 'Legacy without signature 2'],
        ),
      );
    });
  });
}
