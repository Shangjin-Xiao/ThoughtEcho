import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/services/insight_history_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

import '../../test_harness.dart';

void main() {
  group('InsightHistoryService Tests', () {
    late InsightHistoryService insightHistoryService;
    late AppPreferencesService prefsService;
    late SettingsService settingsService;
    late AIAnalysisDatabaseService aiDbService;

    setUpAll(() async {
      await TestHarness.initialize();
      await AppPreferencesService().init();
      aiDbService = AIAnalysisDatabaseService();
      await aiDbService.init();
    });

    setUp(() async {
      prefsService = AppPreferencesService();
      await prefsService.clear();
      await aiDbService.deleteAllPeriodicInsights();
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({kKvEngineMigratedKey: true});
      prefsService.resetForTesting();
      await prefsService.init();
      final prefs = await SharedPreferences.getInstance();

      settingsService = SettingsService(prefs);

      insightHistoryService = InsightHistoryService(
        settingsService: settingsService,
        aiAnalysisDbService: aiDbService,
      );
      await insightHistoryService.ensureLoaded();
    });

    tearDown(SharedPreferences.resetStatic);
    tearDownAll(() async {
      await aiDbService.closeDatabase();
      await TestHarness.tearDown();
    });

    test('should add and retrieve insights', () async {
      await insightHistoryService.addInsight(
        insight: '测试洞察：这周的记录显示了积极的成长趋势',
        periodType: 'week',
        periodLabel: '本周',
        isAiGenerated: true,
      );

      expect(insightHistoryService.insights.length, 1);
      expect(
        insightHistoryService.insights.first.insight,
        '测试洞察：这周的记录显示了积极的成长趋势',
      );
      expect(insightHistoryService.insights.first.periodType, 'week');
      expect(insightHistoryService.insights.first.isAiGenerated, true);

      // Should NOT be stored back in KV storage
      expect(prefsService.containsKey('periodic_insights_history'), isFalse);

      // Reopen database & service to verify true SQLite persistence
      await aiDbService.closeDatabase();
      await aiDbService.init();
      final reloadedService = InsightHistoryService(
        settingsService: settingsService,
        aiAnalysisDbService: aiDbService,
      );
      await reloadedService.ensureLoaded();
      expect(reloadedService.insights.length, 1);
      expect(
        reloadedService.insights.first.insight,
        '测试洞察：这周的记录显示了积极的成长趋势',
      );
    });

    test('should get recent period insight', () async {
      await insightHistoryService.addInsight(
        insight: '月度总结：你在反思中找到了内心的平静',
        periodType: 'month',
        periodLabel: '本月',
        isAiGenerated: true,
      );

      final recentInsight = insightHistoryService.getRecentPeriodInsight();
      expect(recentInsight, '月度总结：你在反思中找到了内心的平静');
    });

    test('should format insight for daily prompt', () async {
      await insightHistoryService.addInsight(
        insight: '这周你展现了坚持的力量',
        periodType: 'week',
        periodLabel: '本周',
        isAiGenerated: true,
      );

      final formattedPrompt =
          await insightHistoryService.formatRecentInsightsForDailyPrompt();

      expect(formattedPrompt.contains('参考洞察'), true);
      expect(formattedPrompt.contains('这周你展现了坚持的力量'), true);
      expect(formattedPrompt.contains('你可以选择性地参考'), true);
    });

    test('should not save non-AI insights', () async {
      await insightHistoryService.addInsight(
        insight: '本地生成的洞察',
        periodType: 'week',
        periodLabel: '本周',
        isAiGenerated: false,
      );

      expect(insightHistoryService.insights.length, 0);
    });

    test('should clean old insights', () async {
      final oldInsight = PeriodicInsight(
        insight: '四个月前的洞察',
        periodType: 'month',
        periodLabel: '上季',
        createdAt: DateTime.now().subtract(const Duration(days: 120)),
        isAiGenerated: true,
        dataSignature: 'old_sig',
      );
      await aiDbService.savePeriodicInsight(oldInsight);

      await insightHistoryService.addInsight(
        insight: '最近的洞察',
        periodType: 'week',
        periodLabel: '本周',
        isAiGenerated: true,
      );

      final reloaded = InsightHistoryService(
        settingsService: settingsService,
        aiAnalysisDbService: aiDbService,
      );
      await reloaded.ensureLoaded();
      expect(reloaded.insights.length, 2);

      await reloaded.cleanOldInsights();

      expect(reloaded.insights.length, 1);
      expect(reloaded.insights.first.insight, '最近的洞察');
    });

    test('same signature replaces instead of piling up', () async {
      for (var i = 0; i < 5; i++) {
        await insightHistoryService.addInsight(
          insight: '第$i次生成',
          periodType: 'week',
          periodLabel: '本周',
          isAiGenerated: true,
          dataSignature: 'week_2026-08-17~2026-08-23_p2',
        );
      }

      expect(insightHistoryService.insights.length, 1);
      expect(insightHistoryService.insights.first.insight, '第4次生成');
    });

    test('different signatures are kept apart', () async {
      await insightHistoryService.addInsight(
        insight: '上周的洞察',
        periodType: 'week',
        periodLabel: '上周',
        isAiGenerated: true,
        dataSignature: 'week_a',
      );
      await insightHistoryService.addInsight(
        insight: '本周的洞察',
        periodType: 'week',
        periodLabel: '本周',
        isAiGenerated: true,
        dataSignature: 'week_b',
      );

      expect(insightHistoryService.insights.length, 2);
      expect(
        insightHistoryService.getInsightBySignature('week_a')?.insight,
        '上周的洞察',
      );
    });

    test('signature lookup ignores empty signature', () async {
      await insightHistoryService.addInsight(
        insight: '没有签名的洞察',
        periodType: 'week',
        periodLabel: '本周',
        isAiGenerated: true,
      );

      expect(insightHistoryService.getInsightBySignature(''), isNull);
    });

    test('previous-insight context keeps one entry per period', () async {
      for (var i = 0; i < 3; i++) {
        await insightHistoryService.addInsight(
          insight: '本周第$i版',
          periodType: 'week',
          periodLabel: '本周',
          isAiGenerated: true,
        );
      }
      await insightHistoryService.addInsight(
        insight: '上周那版',
        periodType: 'week',
        periodLabel: '上周',
        isAiGenerated: true,
      );

      final context = insightHistoryService.getPreviousInsightsContext();

      expect(context.contains('上周那版'), true);
      expect('本周第'.allMatches(context).length, 1);
    });

    test('context dedups a period even when signatures differ', () async {
      await insightHistoryService.addInsight(
        insight: '旧模型那版',
        periodType: 'week',
        periodLabel: '8月17日 - 8月23日',
        isAiGenerated: true,
        dataSignature: 'week_range_p1_gpt',
      );
      await insightHistoryService.addInsight(
        insight: '新模型那版',
        periodType: 'week',
        periodLabel: '8月17日 - 8月23日',
        isAiGenerated: true,
        dataSignature: 'week_range_p2_claude',
      );

      expect(insightHistoryService.insights.length, 2);

      final context = insightHistoryService.getPreviousInsightsContext();
      expect(context.contains('新模型那版'), true);
      expect(context.contains('旧模型那版'), false);
    });

    test(
        'migrates legacy KV periodic_insights_history to SQLite and removes key',
        () async {
      await aiDbService.deleteAllPeriodicInsights();
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({
        kKvEngineMigratedKey: true,
        'periodic_insights_history': json.encode([
          {
            'insight': '历史洞察A',
            'periodType': 'week',
            'periodLabel': '第1周',
            'createdAt': '2026-07-01T10:00:00.000Z',
            'isAiGenerated': true,
            'dataSignature': 'legacy_sig_a',
          },
          {
            'insight': '历史洞察B',
            'periodType': 'month',
            'periodLabel': '7月',
            'createdAt': '2026-07-15T10:00:00.000Z',
            'isAiGenerated': true,
            'dataSignature': 'legacy_sig_b',
          },
        ]),
      });
      prefsService.resetForTesting();
      await prefsService.init();
      final prefs = await SharedPreferences.getInstance();
      final freshSettings = SettingsService(prefs);

      final migratedService = InsightHistoryService(
        settingsService: freshSettings,
        aiAnalysisDbService: aiDbService,
      );
      await migratedService.ensureLoaded();

      expect(migratedService.insights.length, 2);
      expect(migratedService.insights.first.insight, '历史洞察B');
      expect(migratedService.insights.last.insight, '历史洞察A');
      expect(prefsService.containsKey('periodic_insights_history'), isFalse);
      expect(prefsService.getBool(kPeriodicInsightsSqliteMigratedKey), isTrue);
    });

    test(
        'partial corrupt legacy KV entries preserve KV key without blocking valid or SQLite insights',
        () async {
      await aiDbService.deleteAllPeriodicInsights();
      await aiDbService.savePeriodicInsight(
        PeriodicInsight(
          insight: 'SQLite已有洞察',
          periodType: 'week',
          periodLabel: '本周',
          createdAt: DateTime(2026, 8, 10),
          isAiGenerated: true,
          dataSignature: 'sqlite_existing',
        ),
      );

      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({
        kKvEngineMigratedKey: true,
        'periodic_insights_history': json.encode([
          {
            'insight': '有效旧洞察',
            'periodType': 'week',
            'periodLabel': '第1周',
            'createdAt': '2026-07-01T10:00:00.000Z',
            'isAiGenerated': true,
            'dataSignature': 'valid_legacy_sig',
          },
          {
            'insight': 12345, // 类型损坏
            'createdAt': 'invalid-date',
          },
          'not_a_map',
        ]),
      });
      prefsService.resetForTesting();
      await prefsService.init();
      final prefs = await SharedPreferences.getInstance();
      final freshSettings = SettingsService(prefs);

      final service = InsightHistoryService(
        settingsService: freshSettings,
        aiAnalysisDbService: aiDbService,
      );
      await service.ensureLoaded();

      // 既有 SQLite 记录与有效旧记录均可读取
      expect(
        service.insights.map((e) => e.insight),
        containsAll(['SQLite已有洞察', '有效旧洞察']),
      );
      // 因存在损坏条目，原 KV 键保留且未设置迁移完成标记
      expect(prefsService.containsKey('periodic_insights_history'), isTrue);
      expect(
        prefsService.getBool(kPeriodicInsightsSqliteMigratedKey),
        isNot(isTrue),
      );
    });

    test('retries ensureLoaded after an initial database failure', () async {
      await aiDbService.deleteAllPeriodicInsights();
      await aiDbService.savePeriodicInsight(
        PeriodicInsight(
          insight: '恢复后可读洞察',
          periodType: 'week',
          periodLabel: '本周',
          createdAt: DateTime(2026, 8, 12),
          isAiGenerated: true,
          dataSignature: 'retry_sig',
        ),
      );

      final dbFake = _FlakyInsightDatabaseService(aiDbService);
      final service = InsightHistoryService(
        settingsService: settingsService,
        aiAnalysisDbService: dbFake,
      );
      await service.ensureLoaded();
      expect(service.insights, isEmpty);

      dbFake.shouldFailQuery = false;
      await service.ensureLoaded();
      expect(service.insights.length, 1);
      expect(service.insights.first.insight, '恢复后可读洞察');
    });
  });
}

class _FlakyInsightDatabaseService extends ChangeNotifier
    implements AIAnalysisDatabaseService {
  final AIAnalysisDatabaseService _delegate;
  bool shouldFailQuery = true;

  _FlakyInsightDatabaseService(this._delegate);

  @override
  Future<List<PeriodicInsight>> getPeriodicInsights({int limit = 50}) async {
    if (shouldFailQuery) {
      throw StateError('Simulated transient DB error');
    }
    return _delegate.getPeriodicInsights(limit: limit);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
