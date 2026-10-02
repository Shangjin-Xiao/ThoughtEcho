import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/insight_history_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import '../../test_harness.dart';

void main() {
  group('PeriodicInsight', () {
    test('toJson and fromJson serialize and deserialize correctly', () {
      final now = DateTime.now();
      final insight = PeriodicInsight(
        insight: '持续学习是最大的动能',
        periodType: 'week',
        periodLabel: '本周',
        createdAt: now,
        isAiGenerated: true,
        dataSignature: 'sig_123',
      );

      final jsonMap = insight.toJson();

      expect(jsonMap['insight'], equals('持续学习是最大的动能'));
      expect(jsonMap['periodType'], equals('week'));
      expect(jsonMap['periodLabel'], equals('本周'));
      expect(jsonMap['createdAt'], equals(now.toIso8601String()));
      expect(jsonMap['isAiGenerated'], isTrue);
      expect(jsonMap['dataSignature'], equals('sig_123'));

      final restored = PeriodicInsight.fromJson(jsonMap);

      expect(restored.insight, equals(insight.insight));
      expect(restored.periodType, equals(insight.periodType));
      expect(restored.periodLabel, equals(insight.periodLabel));
      expect(
        restored.createdAt.millisecondsSinceEpoch,
        equals(now.millisecondsSinceEpoch),
      );
      expect(restored.isAiGenerated, isTrue);
      expect(restored.dataSignature, equals('sig_123'));
    });

    test('fromJson handles null, missing, or invalid values safely', () {
      final restored = PeriodicInsight.fromJson(const {});

      expect(restored.insight, isEmpty);
      expect(restored.periodType, isEmpty);
      expect(restored.periodLabel, isEmpty);
      expect(restored.isAiGenerated, isFalse);
      expect(restored.dataSignature, isNull);
      expect(restored.createdAt, isA<DateTime>());
    });

    test('toJson omits dataSignature when null', () {
      final insight = PeriodicInsight(
        insight: '测试洞察',
        periodType: 'month',
        periodLabel: '本月',
        createdAt: DateTime.now(),
        isAiGenerated: false,
      );

      final jsonMap = insight.toJson();

      expect(jsonMap.containsKey('dataSignature'), isFalse);
    });
  });

  group('InsightHistoryService', () {
    late SettingsService settingsService;

    setUp(() async {
      await TestHarness.initialize();
      settingsService = await SettingsService.create();
      await settingsService.setCustomString('periodic_insights_history', '');
    });

    tearDown(() async {
      await TestHarness.tearDown();
    });

    /// Helper to wait for the asynchronous `_loadInsights()` triggered in the constructor to complete.
    Future<InsightHistoryService> createService() async {
      final service = InsightHistoryService(settingsService: settingsService);
      // Wait for async initialization _loadInsights() to complete
      await Future<void>.delayed(Duration.zero);
      return service;
    }

    test('loads saved insights from settings service on initialization',
        () async {
      final oldDate = DateTime.utc(2025, 1, 1);
      final newDate = DateTime.utc(2025, 1, 2);

      final mockList = [
        PeriodicInsight(
          insight: '较旧的洞察',
          periodType: 'week',
          periodLabel: '第1周',
          createdAt: oldDate,
          isAiGenerated: true,
          dataSignature: 'sig_1',
        ).toJson(),
        PeriodicInsight(
          insight: '较新的洞察',
          periodType: 'week',
          periodLabel: '第2周',
          createdAt: newDate,
          isAiGenerated: true,
          dataSignature: 'sig_2',
        ).toJson(),
      ];

      await settingsService.setCustomString(
        'periodic_insights_history',
        json.encode(mockList),
      );

      final service = await createService();

      // sorted descending by createdAt
      expect(service.insights.length, equals(2));
      expect(service.insights.first.insight, equals('较新的洞察'));
      expect(service.insights.last.insight, equals('较旧的洞察'));
    });

    test('handles invalid json string gracefully during initialization',
        () async {
      await settingsService.setCustomString(
        'periodic_insights_history',
        'invalid json format',
      );

      final service = await createService();

      expect(service.insights, isEmpty);
    });

    test('addInsight ignores non-AI generated insights', () async {
      final service = await createService();

      await service.addInsight(
        insight: '本地兜底洞察',
        periodType: 'week',
        periodLabel: '本周',
        isAiGenerated: false,
      );

      expect(service.insights, isEmpty);
    });

    test('addInsight saves AI insight and notifies listeners', () async {
      final service = await createService();

      var notifiedCount = 0;
      service.addListener(() => notifiedCount++);

      await service.addInsight(
        insight: 'AI 生成洞察',
        periodType: 'week',
        periodLabel: '本周',
        isAiGenerated: true,
        dataSignature: 'sig_ai',
      );

      expect(service.insights.length, equals(1));
      expect(service.insights.first.insight, equals('AI 生成洞察'));
      expect(notifiedCount, greaterThan(0));

      final persistedJson =
          await settingsService.getCustomString('periodic_insights_history');
      expect(persistedJson, contains('AI 生成洞察'));
    });

    test('addInsight deduplicates by dataSignature keeping only the newest',
        () async {
      final service = await createService();

      await service.addInsight(
        insight: '旧的洞察内容',
        periodType: 'week',
        periodLabel: '本周',
        dataSignature: 'same_sig',
      );

      await service.addInsight(
        insight: '新的洞察内容',
        periodType: 'week',
        periodLabel: '本周',
        dataSignature: 'same_sig',
      );

      expect(service.insights.length, equals(1));
      expect(service.insights.first.insight, equals('新的洞察内容'));
    });

    test('addInsight limits max insights count to 50', () async {
      final service = await createService();

      for (var i = 1; i <= 60; i++) {
        await service.addInsight(
          insight: '洞察 $i',
          periodType: 'week',
          periodLabel: '第 $i 周',
          dataSignature: 'sig_$i',
        );
      }

      expect(service.insights.length, equals(50));
      expect(service.insights.first.insight, equals('洞察 60'));
    });

    test('addInsight triggers onAiInsightPersisted callback safely', () async {
      final service = await createService();

      var callbackTriggered = false;
      service.onAiInsightPersisted = () async {
        callbackTriggered = true;
      };

      await service.addInsight(
        insight: '触发归纳洞察',
        periodType: 'week',
        periodLabel: '本周',
      );

      expect(callbackTriggered, isTrue);
    });

    test('addInsight swallows background consolidation errors safely',
        () async {
      final service = await createService();

      service.onAiInsightPersisted = () async {
        throw Exception('后台归纳错误');
      };

      // Should not throw exception
      await service.addInsight(
        insight: '抛异常的洞察',
        periodType: 'week',
        periodLabel: '本周',
      );

      expect(service.insights.length, equals(1));
    });

    test('getInsightBySignature retrieves correct AI insight', () async {
      final service = await createService();

      await service.addInsight(
        insight: '签名匹配洞察',
        periodType: 'week',
        periodLabel: '本周',
        dataSignature: 'target_sig',
      );

      expect(service.getInsightBySignature(''), isNull);
      expect(service.getInsightBySignature('non_existent'), isNull);

      final found = service.getInsightBySignature('target_sig');
      expect(found, isNotNull);
      expect(found!.insight, equals('签名匹配洞察'));
    });

    test(
        'getPreviousInsightsContext filters AI week insights and deduplicates by period',
        () async {
      final service = await createService();

      expect(service.getPreviousInsightsContext(), isEmpty);

      // Add month insight
      await service.addInsight(
        insight: '月度洞察',
        periodType: 'month',
        periodLabel: '本月',
      );

      // Add older week 1 insight
      await service.addInsight(
        insight: '第一周旧观点',
        periodType: 'week',
        periodLabel: '第一周',
        dataSignature: 'week1_old',
      );

      // Add newer week 1 insight (different signature)
      await service.addInsight(
        insight: '第一周新观点',
        periodType: 'week',
        periodLabel: '第一周',
        dataSignature: 'week1_new',
      );

      // Add week 2 insight
      await service.addInsight(
        insight: '第二周观点',
        periodType: 'week',
        periodLabel: '第二周',
        dataSignature: 'week2',
      );

      final contextText = service.getPreviousInsightsContext(limit: 3);

      expect(contextText, contains('- [第二周] 第二周观点'));
      expect(contextText, contains('- [第一周] 第一周新观点'));
      expect(contextText, isNot(contains('第一周旧观点')));
      expect(contextText, isNot(contains('月度洞察')));
    });

    test(
        'getRecentPeriodInsight returns correct week or month insight within 30 days',
        () async {
      final service = await createService();

      expect(service.getRecentPeriodInsight(), isNull);

      await service.addInsight(
        insight: '最近一周洞察',
        periodType: 'week',
        periodLabel: '本周',
      );

      expect(service.getRecentPeriodInsight(), equals('最近一周洞察'));
    });

    test('getRecentPeriodInsight falls back to recent AI insight within 7 days',
        () async {
      final yearInsight = PeriodicInsight(
        insight: '年度洞察',
        periodType: 'year',
        periodLabel: '2025年',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        isAiGenerated: true,
      );

      await settingsService.setCustomString(
        'periodic_insights_history',
        json.encode([yearInsight.toJson()]),
      );

      // Re-initialize service
      final newService = await createService();

      expect(newService.getRecentPeriodInsight(), equals('年度洞察'));
    });

    test('formatInsightForPrompt returns empty on null or empty input',
        () async {
      final service = await createService();

      expect(service.formatInsightForPrompt(null), isEmpty);
      expect(service.formatInsightForPrompt(''), isEmpty);
    });

    test('formatInsightForPrompt formats valid insight text', () async {
      final service = await createService();

      final result = service.formatInsightForPrompt('坚持习惯');

      expect(result, contains('【参考洞察】'));
      expect(result, contains('"坚持习惯"'));
    });

    test('formatRecentInsightsForDailyPrompt auto loads insights if empty',
        () async {
      final insight = PeriodicInsight(
        insight: '预存洞察',
        periodType: 'week',
        periodLabel: '本周',
        createdAt: DateTime.now(),
        isAiGenerated: true,
      );

      await settingsService.setCustomString(
        'periodic_insights_history',
        json.encode([insight.toJson()]),
      );

      final service = InsightHistoryService(settingsService: settingsService);

      final prompt = await service.formatRecentInsightsForDailyPrompt();

      expect(prompt, contains('"预存洞察"'));
    });

    test('cleanOldInsights removes insights older than 90 days', () async {
      final oldDate = DateTime.now().subtract(const Duration(days: 100));
      final freshDate = DateTime.now().subtract(const Duration(days: 10));

      final oldInsight = PeriodicInsight(
        insight: '过期的洞察',
        periodType: 'week',
        periodLabel: '旧周',
        createdAt: oldDate,
        isAiGenerated: true,
      );

      final freshInsight = PeriodicInsight(
        insight: '新鲜的洞察',
        periodType: 'week',
        periodLabel: '新周',
        createdAt: freshDate,
        isAiGenerated: true,
      );

      await settingsService.setCustomString(
        'periodic_insights_history',
        json.encode([oldInsight.toJson(), freshInsight.toJson()]),
      );

      final newService = await createService();

      expect(newService.insights.length, equals(2));

      var notified = false;
      newService.addListener(() => notified = true);

      await newService.cleanOldInsights();

      expect(newService.insights.length, equals(1));
      expect(newService.insights.first.insight, equals('新鲜的洞察'));
      expect(notified, isTrue);
    });
  });
}
