import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/report_period_labels.dart';
import 'package:thoughtecho/utils/report_period_utils.dart';

void main() {
  // 空周期文案里「上一次落笔是 N 天前」的那个 N。"天前"是相对现在说的，
  // 所以它只在现在这个周期和刚过去的那个周期上成立。
  group('emptyPeriodGapDays', () {
    final now = DateTime(2026, 8, 24, 10); // 周一

    ({DateTime start, DateTime end}) rangeFor(String period, DateTime date) =>
        ReportPeriodUtils.dateRange(period, date)!;

    test('reports the gap for the current period', () {
      expect(
        emptyPeriodGapDays(
          lastNoteDate: DateTime(2026, 8, 14, 21),
          range: rangeFor('week', now),
          period: 'week',
          date: now,
          now: now,
        ),
        10,
      );
    });

    test('reports the gap for the previous period', () {
      final lastWeek = DateTime(2026, 8, 20);
      expect(
        emptyPeriodGapDays(
          lastNoteDate: DateTime(2026, 8, 10),
          range: rangeFor('week', lastWeek),
          period: 'week',
          date: lastWeek,
          now: now,
        ),
        14,
      );
    });

    test('stays quiet for an older period, where "N days ago" misleads', () {
      final longAgo = DateTime(2025, 3, 5);
      expect(
        emptyPeriodGapDays(
          lastNoteDate: DateTime(2025, 1, 20),
          range: rangeFor('week', longAgo),
          period: 'week',
          date: longAgo,
          now: now,
        ),
        isNull,
      );
    });

    test('stays quiet when the newest note is not before the period', () {
      final lastWeek = DateTime(2026, 8, 20);
      expect(
        emptyPeriodGapDays(
          // 用户往回翻：最近那条在这个空周期之后，"上一次"无从谈起
          lastNoteDate: DateTime(2026, 8, 24, 8),
          range: rangeFor('week', lastWeek),
          period: 'week',
          date: lastWeek,
          now: now,
        ),
        isNull,
      );
    });

    test('stays quiet when there is nothing to measure', () {
      expect(
        emptyPeriodGapDays(
          lastNoteDate: null,
          range: rangeFor('week', now),
          period: 'week',
          date: now,
          now: now,
        ),
        isNull,
      );
      expect(
        emptyPeriodGapDays(
          lastNoteDate: DateTime(2026, 8, 1),
          range: null,
          period: 'week',
          date: now,
          now: now,
        ),
        isNull,
      );
    });

    // 最贴边的情形：笔记就写在周期开始前的那个晚上。这是 emptyPeriodGapDays
    // 能返回的最小值——不可能是 0，因为守卫已经要求这条笔记早于 range.start
    // （恒为某天 00:00），它必然落在更早的一个日历日上。
    test('a note written the evening before the period reports one day', () {
      expect(
        emptyPeriodGapDays(
          lastNoteDate: DateTime(2026, 8, 23, 23),
          range: rangeFor('week', now), // 本周：8-24 ~ 8-30
          period: 'week',
          date: now,
          now: now,
        ),
        1,
      );
    });
  });
}
