import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/utils/report_period_utils.dart';

void main() {
  group('ReportPeriodUtils', () {
    test(
      'includes old notes favorited during the selected week',
      () {
        final selectedDate = DateTime(2026, 5, 10);
        final oldFavoritedThisWeek = Quote(
          id: 'old-favorited-this-week',
          content: 'old note favorited this week',
          date: DateTime(2026, 4, 1).toIso8601String(),
          favoriteCount: 2,
          lastModified: DateTime(2026, 5, 6).toIso8601String(),
        );
        final oldFavoritedLastWeek = Quote(
          id: 'old-favorited-last-week',
          content: 'old note favorited last week',
          date: DateTime(2026, 4, 1).toIso8601String(),
          favoriteCount: 3,
          lastModified: DateTime(2026, 4, 30).toIso8601String(),
        );
        final newNotFavorited = Quote(
          id: 'new-not-favorited',
          content: 'new note without favorites',
          date: DateTime(2026, 5, 7).toIso8601String(),
        );

        final result = ReportPeriodUtils.filterFavoritedByActivityPeriod(
          [oldFavoritedThisWeek, oldFavoritedLastWeek, newNotFavorited],
          selectedPeriod: 'week',
          selectedDate: selectedDate,
        );

        expect(result, [oldFavoritedThisWeek]);
      },
    );
  });

  group('ReportPeriodUtils.offsetFromNow', () {
    // 用户在探索页翻到哪个周期，洞察就该总结哪个周期——这组用例钉的是
    // "翻到的是本周还是上周"这个判断本身。
    test('same week is current', () {
      final now = DateTime(2026, 8, 24); // 周一
      expect(
        ReportPeriodUtils.offsetFromNow('week', DateTime(2026, 8, 28),
            now: now),
        ReportPeriodOffset.current,
      );
      expect(
        ReportPeriodUtils.offsetFromNow('week', now, now: now),
        ReportPeriodOffset.current,
      );
    });

    test('previous week is previous', () {
      final now = DateTime(2026, 8, 24); // 周一
      expect(
        ReportPeriodUtils.offsetFromNow('week', DateTime(2026, 8, 20),
            now: now),
        ReportPeriodOffset.previous,
      );
    });

    test('the week before last is other', () {
      final now = DateTime(2026, 8, 24); // 周一
      expect(
        ReportPeriodUtils.offsetFromNow('week', DateTime(2026, 8, 13),
            now: now),
        ReportPeriodOffset.other,
      );
    });

    // offsetFromNow 靠"往前 3 天再让 dateRange 定边界"来避开 `subtract(7 天)`：
    // 减满 7 天在夏令时切换的那一周会落到前一天 23:00，和 dateRange 算出的
    // 00:00 比不相等，"上周"就被误判成"更早"；3 天的余量则怎么偏都还在上一周内。
    //
    // 说明一句：`DateTime` 用的是测试进程的本地时区，而 CI 没有设 TZ（Ubuntu
    // runner 通常是 UTC），所以下面这两周在 CI 上并不会真的跨越夏令时。真正的
    // 时区回归要 `TZ=America/New_York flutter test` 才跑得出来。这里把上一周的
    // 七天全扫一遍，是在不依赖时区的前提下能拿到的最强保证：任何一天落在上一周，
    // 结论都必须是 previous。
    void expectEveryDayOfPreviousWeekIsPrevious(DateTime now, DateTime monday) {
      for (var i = 0; i < 7; i++) {
        final day = DateTime(monday.year, monday.month, monday.day + i);
        expect(
          ReportPeriodUtils.offsetFromNow('week', day, now: now),
          ReportPeriodOffset.previous,
          reason: '$day 落在上一周，应判为 previous',
        );
      }
    }

    test('every day of the previous week reads as previous', () {
      // 2026-08-24 是周一，上一周是 8-17 ~ 8-23。
      expectEveryDayOfPreviousWeekIsPrevious(
        DateTime(2026, 8, 24),
        DateTime(2026, 8, 17),
      );
    });

    test('previous week holds across the spring-forward week', () {
      // 美国 2026-03-08 入夏令时，那一周的周一是 3 月 2 日。
      expectEveryDayOfPreviousWeekIsPrevious(
        DateTime(2026, 3, 9),
        DateTime(2026, 3, 2),
      );
    });

    test('previous week holds across the fall-back week', () {
      // 美国 2026-11-01 出夏令时，那一周的周一是 10 月 26 日。
      expectEveryDayOfPreviousWeekIsPrevious(
        DateTime(2026, 11, 2),
        DateTime(2026, 10, 26),
      );
    });

    test('month boundaries', () {
      final now = DateTime(2026, 8, 24);
      expect(
        ReportPeriodUtils.offsetFromNow('month', DateTime(2026, 8, 1),
            now: now),
        ReportPeriodOffset.current,
      );
      expect(
        ReportPeriodUtils.offsetFromNow('month', DateTime(2026, 7, 9),
            now: now),
        ReportPeriodOffset.previous,
      );
      expect(
        ReportPeriodUtils.offsetFromNow('month', DateTime(2026, 6, 9),
            now: now),
        ReportPeriodOffset.other,
      );
    });

    test('month rollover across the year boundary', () {
      final now = DateTime(2026, 1, 15);
      expect(
        ReportPeriodUtils.offsetFromNow(
          'month',
          DateTime(2025, 12, 20),
          now: now,
        ),
        ReportPeriodOffset.previous,
      );
    });

    test('year boundaries', () {
      final now = DateTime(2026, 8, 24);
      expect(
        ReportPeriodUtils.offsetFromNow('year', DateTime(2026, 1, 1), now: now),
        ReportPeriodOffset.current,
      );
      expect(
        ReportPeriodUtils.offsetFromNow('year', DateTime(2025, 3, 3), now: now),
        ReportPeriodOffset.previous,
      );
      expect(
        ReportPeriodUtils.offsetFromNow('year', DateTime(2024, 3, 3), now: now),
        ReportPeriodOffset.other,
      );
    });

    test('unknown period never claims to be current', () {
      final now = DateTime(2026, 8, 24);
      expect(
        ReportPeriodUtils.offsetFromNow('decade', now, now: now),
        ReportPeriodOffset.other,
      );
    });
  });
}
