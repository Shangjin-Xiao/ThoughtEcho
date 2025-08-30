import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/insight_history_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('InsightHistoryService Tests', () {
    late InsightHistoryService insightHistoryService;
    late SettingsService settingsService;

    setUp(() async {
      // 初始化共享首选项
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      settingsService = SettingsService(prefs);

      insightHistoryService = InsightHistoryService(
        settingsService: settingsService,
      );
    });

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
          insightHistoryService.insights.first.insight, '测试洞察：这周的记录显示了积极的成长趋势');
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
  });
}
