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
        final prompt =
            manager.appendAnalysisStylePrompt(basePrompt, 'friendly');
        expect(prompt, startsWith(basePrompt));
        expect(prompt, contains('友好的"你"称呼读者'));
      });

      test('appends humorous style', () {
        final prompt =
            manager.appendAnalysisStylePrompt(basePrompt, 'humorous');
        expect(prompt, startsWith(basePrompt));
        expect(prompt, contains('幽默和风趣元素'));
      });

      test('appends literary style', () {
        final prompt =
            manager.appendAnalysisStylePrompt(basePrompt, 'literary');
        expect(prompt, startsWith(basePrompt));
        expect(prompt, contains('优美、富有文学色彩'));
      });

      test('appends professional style', () {
        final prompt =
            manager.appendAnalysisStylePrompt(basePrompt, 'professional');
        expect(prompt, startsWith(basePrompt));
        expect(prompt, contains('专业、清晰和客观'));
      });

      test('appends professional style as default', () {
        final prompt =
            manager.appendAnalysisStylePrompt(basePrompt, 'unknown_style');
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
        final message =
            manager.buildUserMessage(content, prefix: 'Custom Prefix:');
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

      test('buildPolishUserMessage preserves media markers', () {
        const contentWithMarkers =
            'Before [[TE_MEDIA_1]] after [[TE_MEDIA_2]] end.';
        final message = manager.buildPolishUserMessage(contentWithMarkers);
        expect(message, contains('[[TE_MEDIA_1]]'));
        expect(message, contains('必须原样保留'));
        expect(message, contains('不要删除、改写、拆分、合并或调整这些占位符的顺序'));
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
        final prompt =
            manager.getDailyPromptSystemPromptWithContext(testNow: morning);
        expect(prompt, contains('早晨 08:00'));
      });

      test('afternoon time prompt', () {
        final afternoon = date.add(const Duration(hours: 14)); // 14:00
        final prompt =
            manager.getDailyPromptSystemPromptWithContext(testNow: afternoon);
        expect(prompt, contains('下午 14:00'));
      });

      test('evening time prompt', () {
        final evening = date.add(const Duration(hours: 20)); // 20:00
        final prompt =
            manager.getDailyPromptSystemPromptWithContext(testNow: evening);
        expect(prompt, contains('晚上 20:00'));
      });

      test('night time prompt', () {
        final night = date.add(const Duration(hours: 2)); // 02:00
        final prompt =
            manager.getDailyPromptSystemPromptWithContext(testNow: night);
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
        expect(prompt, contains('当前环境信息：'));
        expect(prompt, contains('温度：25°C'));
      });

      test('writes the weather text through verbatim', () {
        // 调用方负责本地化。这里曾经再做一次 key→描述 映射，把已经翻好的
        // 「多云」当成未知 key 换成了 'unknown'。
        final prompt = manager.getDailyPromptSystemPromptWithContext(
          weather: '多云',
          testNow: date,
        );
        expect(prompt, contains('天气：多云'));
        expect(prompt, isNot(contains('unknown')));
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
        final prompt = manager.getDailyPromptSystemPromptWithContext(
            languageCode: 'zh', testNow: date);
        expect(prompt, contains('【语言要求】请使用中文回复。'));
      });

      test('language directive - en', () {
        final prompt = manager.getDailyPromptSystemPromptWithContext(
            languageCode: 'en', testNow: date);
        expect(prompt,
            contains('【Language Requirement】Please respond in English.'));
      });

      test('language directive - other', () {
        final prompt = manager.getDailyPromptSystemPromptWithContext(
            languageCode: 'fr', testNow: date);
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
        final prompt =
            manager.getReportInsightSystemPrompt('poetic', languageCode: 'zh');
        expect(prompt, contains('风格：文学诗意'));
        expect(prompt, contains('【语言要求】请使用中文回复。'));
        // 摘录不能被当成用户自己的经历，这条约束和笔记里的「署名」标注是一对
        expect(prompt, contains('署名'));
        // 必须强制第二人称「你」，防止模型以第三人称「一位……」悬空开头
        expect(prompt, contains('第二人称'));
        expect(prompt, contains('一位……'));
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
        expect(output1, contains('week'));
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

      group('translateTimePeriod and translateWeather', () {
        test('translates time periods correctly', () {
          expect(
              manager.translateTimePeriod('evening', toEnglish: false), '夜晚');
          expect(
              manager.translateTimePeriod('morning', toEnglish: false), '上午');
          expect(manager.translateTimePeriod('夜晚', toEnglish: true), 'evening');
          expect(manager.translateTimePeriod('上午', toEnglish: true), 'morning');
          // Handles unknown or already translated
          expect(
              manager.translateTimePeriod('unknown_period', toEnglish: false),
              'unknown_period');
          expect(manager.translateTimePeriod('夜晚', toEnglish: false), '夜晚');
        });

        test('translates weather correctly', () {
          expect(manager.translateWeather('clear', toEnglish: false), '晴');
          expect(manager.translateWeather('rainy', toEnglish: false), '雨');
          expect(manager.translateWeather('晴', toEnglish: true), 'clear');
          expect(manager.translateWeather('雨', toEnglish: true), 'rainy');
          // Handles unknown or already translated
          expect(manager.translateWeather('unknown_weather', toEnglish: false),
              'unknown_weather');
          expect(manager.translateWeather('晴', toEnglish: false), '晴');
        });

        test('translates inputs through formatLocalReportInsight', () {
          // Choose seed 1 (which generates Growth Mentor insight that contains $time)
          final outputZh = manager.formatLocalReportInsight(
            periodLabel: '本周',
            activeDays: 3,
            noteCount: 5,
            totalWordCount: 500,
            mostTimePeriod: 'evening',
            mostWeather: 'clear',
            topTag: '随记',
            languageCode: 'zh',
            seed: 1,
          );
          expect(outputZh, contains('夜晚'));
          expect(outputZh, isNot(contains('evening')));

          // Choose seed 2 (which generates Warm Companion insight that contains both $time and $weather)
          final outputEn = manager.formatLocalReportInsight(
            periodLabel: 'This Week',
            activeDays: 3,
            noteCount: 5,
            totalWordCount: 500,
            mostTimePeriod: '夜晚',
            mostWeather: '晴',
            topTag: 'Thoughts',
            languageCode: 'en',
            seed: 2,
          );
          expect(outputEn, contains('evening'));
          expect(outputEn, contains('clear'));
        });

        test('cleanEnglishPeriodLabel cleans period labels correctly', () {
          expect(manager.cleanEnglishPeriodLabel('This Week'), 'week');
          expect(manager.cleanEnglishPeriodLabel('this Month'), 'month');
          expect(manager.cleanEnglishPeriodLabel('2026 Annual Report'), 'year');
          expect(manager.cleanEnglishPeriodLabel('2026-07-01 to 2026-07-07'),
              '2026-07-01 to 2026-07-07');
        });
      });
    });
  });

  group('buildAnalysisTimeContext', () {
    // 模型不知道今天星期几，于是"本周"对它只是个词：周一点「总结本周」时
    // 它会拿最近的几条（上周的）当本周说。这组用例钉的是"星期几和闭区间
    // 必须白纸黑字写进提示"。
    test('states today, the weekday and the analysed range', () {
      final text = AIPromptManager.buildAnalysisTimeContext(
        now: DateTime(2026, 8, 24, 9, 5), // 周一
        rangeStart: DateTime(2026, 8, 17),
        rangeEnd: DateTime(2026, 8, 23),
        periodLabel: '上周',
      );

      expect(text, startsWith('<time_context>'));
      expect(text, endsWith('</time_context>'));
      expect(text, contains('2026-08-24'));
      expect(text, contains('周一'));
      expect(text, contains('09:05'));
      expect(text, contains('2026-08-17'));
      expect(text, contains('2026-08-23'));
      expect(text, contains('共 7 天'));
      expect(text, contains('上周'));
      // 空着的日子不许替用户补叙
      expect(text, contains('不要替用户补叙'));
    });

    // 闭区间天数按日历日算。跨夏令时切换时本地 difference 会少一小时，
    // inDays 随之少一天——3 月 1 日到 3 月 31 日会报成「共 30 天」。
    test('counts calendar days across a daylight-saving transition', () {
      final text = AIPromptManager.buildAnalysisTimeContext(
        now: DateTime(2026, 4, 1, 9),
        rangeStart: DateTime(2026, 3, 1),
        rangeEnd: DateTime(2026, 3, 31),
      );
      expect(text, contains('共 31 天'));
    });

    test('a single-day range counts as one day', () {
      final text = AIPromptManager.buildAnalysisTimeContext(
        now: DateTime(2026, 8, 24, 9),
        rangeStart: DateTime(2026, 8, 24),
        rangeEnd: DateTime(2026, 8, 24),
      );
      expect(text, contains('共 1 天'));
    });

    test('omits the range section when no range is given', () {
      final text = AIPromptManager.buildAnalysisTimeContext(
        now: DateTime(2026, 8, 24, 9, 5),
      );

      expect(text, contains('2026-08-24'));
      expect(text, isNot(contains('本次分析的时间范围')));
      // 没有范围也仍然要说清"相对时间以当前时间换算"
      expect(text, contains('当前时间'));
    });
  });

  group('analysisDataContract', () {
    test('spells out excerpt vs original', () {
      const contract = AIPromptManager.analysisDataContract;
      expect(contract, contains('"original"'));
      expect(contract, contains('"excerpt"'));
      expect(contract, contains('摘录'));
      // 模型的原话是"把摘录当成了你的自白"，约束就得直接禁掉那种转述
      expect(contract, contains('你说过'));
    });
  });

  group('formatLocalEmptyPeriodInsight', () {
    final manager = AIPromptManager();

    test('says something instead of nothing when the period is empty', () {
      final text = manager.formatLocalEmptyPeriodInsight(
        periodLabel: '上周',
        daysSinceLastNote: 9,
        seed: 1,
      );
      expect(text, isNotEmpty);
      expect(text, contains('上周'));
      expect(text, contains('9'));
    });

    test('never invents a "last note" when there has never been one', () {
      for (var seed = 0; seed < 8; seed++) {
        final text = manager.formatLocalEmptyPeriodInsight(
          periodLabel: '本周',
          everWroteAnything: false,
          seed: seed,
        );
        expect(text, isNotEmpty);
        expect(text, isNot(contains('上一次')));
        expect(text, isNot(contains('距离上次')));
      }
    });

    test('English locale gets English copy', () {
      final text = manager.formatLocalEmptyPeriodInsight(
        periodLabel: 'This Week',
        languageCode: 'en',
        seed: 3,
      );
      expect(text, isNotEmpty);
      expect(text, isNot(contains('本周')));
    });

    // 周期标签要作为完整短语嵌进句子。之前它先过了
    // _cleanEnglishPeriodLabel（那是给 "This $period" 那类模板用的），
    // 'This Week' 被剥成 'week'，拼出 "No entries for week"。
    test('English copy keeps the period as a natural phrase', () {
      for (var seed = 0; seed < 8; seed++) {
        final text = manager.formatLocalEmptyPeriodInsight(
          periodLabel: 'This Week',
          languageCode: 'en',
          seed: seed,
        );
        expect(text.toLowerCase(), contains('this week'));
        expect(text, isNot(matches(RegExp(r'\bfor week\b'))));
      }
    });

    test('a one-day gap says "day", not "days"', () {
      for (var seed = 0; seed < 8; seed++) {
        final text = manager.formatLocalEmptyPeriodInsight(
          periodLabel: 'Last Week',
          daysSinceLastNote: 1,
          languageCode: 'en',
          seed: seed,
        );
        expect(text, contains('1 day'));
        expect(text, isNot(contains('1 days')));
      }
      expect(
        manager.formatLocalEmptyPeriodInsight(
          periodLabel: 'Last Week',
          daysSinceLastNote: 3,
          languageCode: 'en',
          seed: 0,
        ),
        contains('3 days'),
      );
    });

    // ja / ko / fr / es / de 没有本地模板，退到应用声明的兜底语言（en），
    // 而不是掉进中文分支——那是原来的行为，等于给法语用户发一句中文。
    test('non-Chinese locales fall back to English, not Chinese', () {
      for (final code in ['ja', 'ko', 'fr', 'es', 'de', 'pt-BR']) {
        final text = manager.formatLocalEmptyPeriodInsight(
          periodLabel: 'This Week',
          languageCode: code,
          seed: 1,
        );
        expect(text, isNotEmpty, reason: code);
        expect(
          text,
          isNot(matches(RegExp(r'[\u4e00-\u9fff]'))),
          reason: '$code 不该收到中文兜底文案',
        );
      }
    });

    test('Chinese and "follow system" still get Chinese copy', () {
      for (final code in [null, 'zh', 'zh-Hans']) {
        expect(
          manager.formatLocalEmptyPeriodInsight(
            periodLabel: '本周',
            languageCode: code,
            seed: 1,
          ),
          contains('本周'),
          reason: '${code ?? "null"} 应走中文模板',
        );
      }
    });
  });
}
