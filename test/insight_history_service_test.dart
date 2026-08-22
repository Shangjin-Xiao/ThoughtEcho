import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/insight_history_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

import 'test_harness.dart';

void main() {
  group('InsightHistoryService Tests', () {
    late InsightHistoryService insightHistoryService;
    late MMKVService mmkvService;
    late SettingsService settingsService;

    setUpAll(() async {
      await TestHarness.initialize();
      await MMKVService().init();
    });

    setUp(() async {
      mmkvService = MMKVService();
      await mmkvService.clear();
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      settingsService = SettingsService(prefs);

      insightHistoryService = InsightHistoryService(
        settingsService: settingsService,
      );
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(SharedPreferences.resetStatic);
    tearDownAll(TestHarness.tearDown);

    test('should add and retrieve insights', () async {
      // 添加一个洞察
      await insightHistoryService.addInsight(
        insight: '测试洞察：这周的记录显示了积极的成长趋势',
        periodType: 'week',
        periodLabel: '本周',
        isAiGenerated: true,
      );

      // 验证洞察已添加
      expect(insightHistoryService.insights.length, 1);
      expect(
        insightHistoryService.insights.first.insight,
        '测试洞察：这周的记录显示了积极的成长趋势',
      );
      expect(insightHistoryService.insights.first.periodType, 'week');
      expect(insightHistoryService.insights.first.isAiGenerated, true);
    });

    test('should get recent period insight', () async {
      // 添加一个最近的洞察
      await insightHistoryService.addInsight(
        insight: '月度总结：你在反思中找到了内心的平静',
        periodType: 'month',
        periodLabel: '本月',
        isAiGenerated: true,
      );

      // 获取最近洞察
      final recentInsight = insightHistoryService.getRecentPeriodInsight();
      expect(recentInsight, '月度总结：你在反思中找到了内心的平静');
    });

    test('should format insight for daily prompt', () async {
      // 添加洞察
      await insightHistoryService.addInsight(
        insight: '这周你展现了坚持的力量',
        periodType: 'week',
        periodLabel: '本周',
        isAiGenerated: true,
      );

      // 获取格式化的提示
      final formattedPrompt =
          await insightHistoryService.formatRecentInsightsForDailyPrompt();

      expect(formattedPrompt.contains('参考洞察'), true);
      expect(formattedPrompt.contains('这周你展现了坚持的力量'), true);
      expect(formattedPrompt.contains('你可以选择性地参考'), true);
    });

    test('should not save non-AI insights', () async {
      // 尝试添加非AI生成的洞察
      await insightHistoryService.addInsight(
        insight: '本地生成的洞察',
        periodType: 'week',
        periodLabel: '本周',
        isAiGenerated: false,
      );

      // 验证没有被保存
      expect(insightHistoryService.insights.length, 0);
    });

    test('should clean old insights', () async {
      // 添加最近的洞察
      await insightHistoryService.addInsight(
        insight: '最近的洞察',
        periodType: 'week',
        periodLabel: '本周',
        isAiGenerated: true,
      );

      // 清理过期洞察
      await insightHistoryService.cleanOldInsights();

      // 验证最近的洞察仍然存在
      expect(insightHistoryService.insights.length, 1);
      expect(insightHistoryService.insights.first.insight, '最近的洞察');
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

      // 同一份数据只留最新的一条，不能攒成 5 条把 50 条上限吃光
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

      // 没带签名的记录不该被空签名查询命中
      expect(insightHistoryService.getInsightBySignature(''), isNull);
    });

    test('previous-insight context keeps one entry per period', () async {
      // 同一周重复生成过三次（历史数据里可能还留着这种重复）
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

      // 每个周期只取一条，否则模型就是在参考自己刚写过的东西
      expect(context.contains('上周那版'), true);
      expect('本周第'.allMatches(context).length, 1);
    });

    test('context dedups a period even when signatures differ', () async {
      // 换模型或改提示词版本会让同一周产生不同签名。按签名去重的话两版都会
      // 进上下文，模型就收到了同一周的两种说法。
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

      // 两条都留在历史里（签名不同，不该互相顶掉）
      expect(insightHistoryService.insights.length, 2);

      // 但喂回给模型的上下文里，这个周期只出现最新的一条
      final context = insightHistoryService.getPreviousInsightsContext();
      expect(context.contains('新模型那版'), true);
      expect(context.contains('旧模型那版'), false);
    });
  });
}
