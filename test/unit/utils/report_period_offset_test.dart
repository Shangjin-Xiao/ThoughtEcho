import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/report_period_utils.dart';

void main() {
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

    test('previous week is previous, week before that is other', () {
      final now = DateTime(2026, 8, 24); // 周一
      expect(
        ReportPeriodUtils.offsetFromNow('week', DateTime(2026, 8, 20),
            now: now),
        ReportPeriodOffset.previous,
      );
      expect(
        ReportPeriodUtils.offsetFromNow('week', DateTime(2026, 8, 13),
            now: now),
        ReportPeriodOffset.other,
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
