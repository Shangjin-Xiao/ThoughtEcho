import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/ai_prompt_manager.dart';

void main() {
  group('AIPromptManager', () {
    test('Singleton pattern works', () {
      final instance1 = AIPromptManager();
      final instance2 = AIPromptManager();
      expect(instance1, same(instance2));
    });

    test('Static constants are not empty', () {
      expect(AIPromptManager.personalGrowthCoachPrompt, isNotEmpty);
      expect(AIPromptManager.dailyPromptGeneratorPrompt, isNotEmpty);
      expect(AIPromptManager.connectionTestPrompt, isNotEmpty);
      expect(AIPromptManager.noteQAAssistantPrompt, isNotEmpty);
      expect(AIPromptManager.textContinuationPrompt, isNotEmpty);
      expect(AIPromptManager.sourceAnalysisPrompt, isNotEmpty);
      expect(AIPromptManager.annualReportPrompt, isNotEmpty);
      expect(AIPromptManager.textPolishPrompt, isNotEmpty);
    });

    group('getAnalysisTypePrompt', () {
      final manager = AIPromptManager();

      test('returns emotional prompt', () {
        final prompt = manager.getAnalysisTypePrompt('emotional');
        expect(prompt, contains('情绪与心理洞察'));
      });

      test('returns mindmap prompt', () {
        final prompt = manager.getAnalysisTypePrompt('mindmap');
        expect(prompt, contains('思维结构与知识图谱'));
      });

      test('returns growth prompt', () {
        final prompt = manager.getAnalysisTypePrompt('growth');
        expect(prompt, contains('个人成长导师'));
      });

      test('returns comprehensive prompt for comprehensive type', () {
        final prompt = manager.getAnalysisTypePrompt('comprehensive');
        expect(prompt, contains('综合洞察导师'));
      });

      test('returns comprehensive prompt for unknown type (default)', () {
        final prompt = manager.getAnalysisTypePrompt('unknown_type');
        expect(prompt, contains('综合洞察导师'));
      });
    });

    group('appendAnalysisStylePrompt', () {
      final manager = AIPromptManager();
      const basePrompt = 'Base Prompt';

      test('appends friendly style', () {
        final prompt = manager.appendAnalysisStylePrompt(basePrompt, 'friendly');
        expect(prompt, startsWith(basePrompt));
        expect(prompt, contains('友好的"你"称呼读者'));
      });

      test('appends humorous style', () {
        final prompt = manager.appendAnalysisStylePrompt(basePrompt, 'humorous');
        expect(prompt, startsWith(basePrompt));
        expect(prompt, contains('幽默和风趣元素'));
      });

      test('appends literary style', () {
        final prompt = manager.appendAnalysisStylePrompt(basePrompt, 'literary');
        expect(prompt, startsWith(basePrompt));
        expect(prompt, contains('优美、富有文学色彩'));
      });

      test('appends professional style', () {
        final prompt = manager.appendAnalysisStylePrompt(basePrompt, 'professional');
        expect(prompt, startsWith(basePrompt));
        expect(prompt, contains('专业、清晰和客观'));
      });

      test('appends professional style as default', () {
        final prompt = manager.appendAnalysisStylePrompt(basePrompt, 'unknown_style');
        expect(prompt, startsWith(basePrompt));
        expect(prompt, contains('专业、清晰和客观'));
      });
    });

    group('Message Builders', () {
      final manager = AIPromptManager();
      const content = 'Test Content';

      test('buildUserMessage with default prefix', () {
        final message = manager.buildUserMessage(content);
        expect(message, contains('请分析以下内容：'));
        expect(message, contains(content));
      });

      test('buildUserMessage with custom prefix', () {
        final message = manager.buildUserMessage(content, prefix: 'Custom Prefix:');
        expect(message, contains('Custom Prefix:'));
        expect(message, contains(content));
      });

      test('buildQAUserMessage', () {
        const question = 'My Question';
        final message = manager.buildQAUserMessage(content, question);
        expect(message, contains(content));
        expect(message, contains(question));
        expect(message, contains('笔记内容：'));
        expect(message, contains('我的问题：'));
      });

      test('buildContinuationUserMessage', () {
        final message = manager.buildContinuationUserMessage(content);
        expect(message, contains('请续写以下文本：'));
        expect(message, contains(content));
      });

      test('buildSourceAnalysisUserMessage', () {
        final message = manager.buildSourceAnalysisUserMessage(content);
        expect(message, contains('请分析以下文本的可能来源：'));
        expect(message, contains(content));
      });

      test('buildPolishUserMessage', () {
        final message = manager.buildPolishUserMessage(content);
        expect(message, contains('请润色以下文本：'));
        expect(message, contains(content));
      });

      test('buildDailyPromptUserMessage', () {
        final message = manager.buildDailyPromptUserMessage();
        expect(message, '请根据当前环境信息生成一个个性化的思考提示。');
      });
    });

    group('getDailyPromptSystemPromptWithContext', () {
      final manager = AIPromptManager();
      // 2023-01-01 is Sunday
      final date = DateTime(2023, 1, 1);

      test('morning time prompt', () {
        final morning = date.add(const Duration(hours: 8)); // 8:00
        final prompt = manager.getDailyPromptSystemPromptWithContext(testNow: morning);
        expect(prompt, contains('早晨 08:00'));
      });

      test('afternoon time prompt', () {
        final afternoon = date.add(const Duration(hours: 14)); // 14:00
        final prompt = manager.getDailyPromptSystemPromptWithContext(testNow: afternoon);
        expect(prompt, contains('下午 14:00'));
      });

      test('evening time prompt', () {
        final evening = date.add(const Duration(hours: 20)); // 20:00
        final prompt = manager.getDailyPromptSystemPromptWithContext(testNow: evening);
        expect(prompt, contains('晚上 20:00'));
      });

      test('night time prompt', () {
        final night = date.add(const Duration(hours: 2)); // 02:00
        final prompt = manager.getDailyPromptSystemPromptWithContext(testNow: night);
        expect(prompt, contains('深夜 02:00'));
      });

      test('includes environment info', () {
        final prompt = manager.getDailyPromptSystemPromptWithContext(
          city: 'Beijing',
          weather: 'Sunny',
          temperature: '25',
          testNow: date,
        );
        expect(prompt, contains('地点：Beijing'));
        // WeatherCodeMapper might transform 'Sunny', assuming it returns same or mapped.
        // Since we didn't mock WeatherCodeMapper, we test that at least environment section is present.
        expect(prompt, contains('当前环境信息：'));
        expect(prompt, contains('温度：25°C'));
      });

      test('includes historical insights', () {
        const insights = 'User likes hiking.';
        final prompt = manager.getDailyPromptSystemPromptWithContext(
          historicalInsights: insights,
          testNow: date,
        );
        expect(prompt, contains('【历史洞察参考】'));
        expect(prompt, contains(insights));
      });

      test('language directive - zh', () {
        final prompt = manager.getDailyPromptSystemPromptWithContext(languageCode: 'zh', testNow: date);
        expect(prompt, contains('【语言要求】请使用中文回复。'));
      });

      test('language directive - en', () {
        final prompt = manager.getDailyPromptSystemPromptWithContext(languageCode: 'en', testNow: date);
        expect(prompt, contains('【Language Requirement】Please respond in English.'));
      });

      test('language directive - other', () {
        final prompt = manager.getDailyPromptSystemPromptWithContext(languageCode: 'fr', testNow: date);
        expect(prompt, contains('locale code: fr'));
      });
    });

    group('Report Insights', () {
      final manager = AIPromptManager();

      test('pickRandomReportInsightStyle is deterministic with seed', () {
        final style1 = manager.pickRandomReportInsightStyle(seed: 123);
        final style2 = manager.pickRandomReportInsightStyle(seed: 123);
        final style3 = manager.pickRandomReportInsightStyle(seed: 456);

        expect(style1, equals(style2));
        // Note: It's possible for different seeds to produce same result if pool is small,
        // but it's unlikely to fail consistently if logic is correct.
        // Given pool size 1, it will ALWAYS be 'poetic'.
        // So actually, for now, they should all be equal since list has only 1 item.
        expect(style1, equals('poetic'));
        expect(style3, equals('poetic'));
      });

      test('getReportInsightSystemPrompt includes style and language', () {
        final prompt = manager.getReportInsightSystemPrompt('poetic', languageCode: 'zh');
        expect(prompt, contains('风格：文学诗意'));
        expect(prompt, contains('【语言要求】请使用中文回复。'));
      });

      test('buildReportInsightUserMessage with all fields', () {
        final message = manager.buildReportInsightUserMessage(
          periodLabel: 'Week 1',
          mostTimePeriod: 'Morning',
          mostWeather: 'Sunny',
          topTag: 'Life',
          activeDays: 5,
          noteCount: 10,
          totalWordCount: 1000,
          fullNotesContent: 'Full content',
          previousInsights: 'Prev insight',
        );

        expect(message, contains('周期：Week 1'));
        expect(message, contains('记录天数：5'));
        expect(message, contains('Morning'));
        expect(message, contains('#Life'));
        expect(message, contains('Full content'));
        expect(message, contains('Prev insight'));
      });

      test('buildReportInsightUserMessage with minimal fields', () {
        final message = manager.buildReportInsightUserMessage(
          periodLabel: 'Week 1',
          activeDays: 5,
          noteCount: 10,
          totalWordCount: 1000,
        );

        expect(message, contains('周期：Week 1'));
        expect(message, contains('高频时段：—'));
        expect(message, contains('常见天气：—'));
        expect(message, contains('高频标签：—'));
        expect(message, contains('（无可用笔记内容）'));
      });

      test('formatLocalReportInsight deterministic with seed - Chinese', () {
        final output1 = manager.formatLocalReportInsight(
          periodLabel: '本周',
          activeDays: 3,
          noteCount: 5,
          totalWordCount: 500,
          languageCode: 'zh',
          seed: 1,
        );
        final output2 = manager.formatLocalReportInsight(
          periodLabel: '本周',
          activeDays: 3,
          noteCount: 5,
          totalWordCount: 500,
          languageCode: 'zh',
          seed: 1,
        );
        expect(output1, equals(output2));
        expect(output1, isNotEmpty);
      });

       test('formatLocalReportInsight deterministic with seed - English', () {
        final output1 = manager.formatLocalReportInsight(
          periodLabel: 'This Week',
          activeDays: 3,
          noteCount: 5,
          totalWordCount: 500,
          languageCode: 'en',
          seed: 2,
        );
        final output2 = manager.formatLocalReportInsight(
          periodLabel: 'This Week',
          activeDays: 3,
          noteCount: 5,
          totalWordCount: 500,
          languageCode: 'en',
          seed: 2,
        );
        expect(output1, equals(output2));
        expect(output1, isNotEmpty);
        // Verify English content
        expect(output1, contains('This Week'));
        // Depending on template selected by seed 2, check for English words
        // seed 2 -> rng.nextInt(3)
        // We can just check it doesn't contain Chinese characters commonly used in templates
        // or just check for common English words like "days", "entries".
        expect(output1, contains('days'));
      });

      test('formatLocalReportInsight handles missing optional fields', () {
        final output = manager.formatLocalReportInsight(
          periodLabel: '本周',
          activeDays: 3,
          noteCount: 5,
          totalWordCount: 500,
          seed: 1,
        );
        // Should use fallback for time, weather, tag
        expect(output, contains('本期时段分布较均衡'));
        expect(output, contains('天气因素不明显'));
        expect(output, contains('多元主题'));
      });
    });
  });
}
