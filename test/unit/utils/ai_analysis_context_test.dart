import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/utils/ai_prompt_manager.dart';
import 'package:thoughtecho/utils/ai_request_helper.dart';

void main() {
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

  group('convertQuotesToJson attribution', () {
    final helper = AIRequestHelper();

    Quote note({String? author, String? work}) => Quote(
          id: 'n',
          content: '一段内容',
          date: DateTime(2026, 8, 20).toIso8601String(),
          sourceAuthor: author,
          sourceWork: work,
        );

    test('notes without attribution are original', () {
      final json = helper.convertQuotesToJson([note()]);
      final quotes = json['quotes'] as List<dynamic>;
      expect((quotes.single as Map)['type'], 'original');
      expect((json['metadata'] as Map)['originalCount'], 1);
      expect((json['metadata'] as Map)['excerptCount'], 0);
    });

    test('an author or a work marks the note as an excerpt', () {
      final byAuthor = helper.convertQuotesToJson([note(author: '苏轼')]);
      expect(((byAuthor['quotes'] as List).single as Map)['type'], 'excerpt');

      final byWork = helper.convertQuotesToJson([note(work: '东坡志林')]);
      expect(((byWork['quotes'] as List).single as Map)['type'], 'excerpt');
      // 出处本身也要送出去：模型要能说出"你抄的是哪一句"
      expect(((byWork['quotes'] as List).single as Map)['sourceWork'], '东坡志林');
    });

    test('counts are split across a mixed batch', () {
      final json = helper.convertQuotesToJson([
        note(),
        note(author: '加缪'),
        note(work: '局外人'),
      ]);
      expect((json['metadata'] as Map)['originalCount'], 1);
      expect((json['metadata'] as Map)['excerptCount'], 2);
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
  });
}
