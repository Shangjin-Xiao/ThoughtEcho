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

    // offsetFromNow 专门绕开了 `subtract(7 天)`：夏令时切换的那一周里，减 7 天
    // 会落到前一天 23:00，和 dateRange 算出的 00:00 比不相等，"上周"就会被误判
    // 成"更早"。测试机的时区未必有夏令时，所以两个方向都钉一遍——在有夏令时的
    // 时区上它才是真正的回归测试，在没有的地方它也不会假过。
    test('previous week survives the spring-forward week', () {
      // 美国 2026-03-08 入夏令时，那一周的周一是 3 月 2 日。
      final now = DateTime(2026, 3, 9); // 切换之后的周一
      expect(
        ReportPeriodUtils.offsetFromNow('week', DateTime(2026, 3, 4), now: now),
        ReportPeriodOffset.previous,
      );
    });

    test('previous week survives the fall-back week', () {
      // 美国 2026-11-01 出夏令时，那一周的周一是 10 月 26 日。
      final now = DateTime(2026, 11, 2); // 切换之后的周一
      expect(
        ReportPeriodUtils.offsetFromNow('week', DateTime(2026, 10, 28),
            now: now),
        ReportPeriodOffset.previous,
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
