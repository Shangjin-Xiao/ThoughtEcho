import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/time_utils.dart';

void main() {
  group('TimeUtils 单元测试', () {
    test('getDayPeriodLabel 应该返回正确的中文标签或 fallback', () {
      expect(TimeUtils.getDayPeriodLabel('morning'), '上午');
      expect(TimeUtils.getDayPeriodLabel('evening'), '夜晚');
      expect(TimeUtils.getDayPeriodLabel('unknown_key'), 'unknown_key');
    });

    test('getDayPeriodIcon 应该返回正确的图标', () {
      expect(TimeUtils.getDayPeriodIcon('晨曦'), Icons.wb_twilight);
      expect(TimeUtils.getDayPeriodIcon('深夜'), Icons.bedtime);
      expect(TimeUtils.getDayPeriodIcon('未知'), Icons.access_time);
      expect(TimeUtils.getDayPeriodIcon(null), Icons.access_time);
    });

    test('getDayPeriodIconByKey 应该返回正确的图标', () {
      expect(
        TimeUtils.getDayPeriodIconByKey('dusk'),
        Icons.nights_stay_outlined,
      );
      expect(TimeUtils.getDayPeriodIconByKey('invalid'), Icons.access_time);
    });

    test('formatQuoteTime 应该正确补零并返回时间部分', () {
      final dt1 = DateTime(2025, 1, 1, 9, 5);
      expect(TimeUtils.formatQuoteTime(dt1), '09:05');

      final dt2 = DateTime(2025, 1, 1, 14, 30);
      expect(TimeUtils.formatQuoteTime(dt2), '14:30');
    });

    test('formatDate 应该返回 "YYYY年M月D日" 格式', () {
      final dt = DateTime(2025, 6, 21);
      expect(TimeUtils.formatDate(dt), '2025年6月21日');
    });

    test('formatDateTime 应该返回带时间的完整格式', () {
      final dt = DateTime(2025, 6, 21, 14, 30);
      expect(TimeUtils.formatDateTime(dt), '2025年6月21日 14:30');
    });

    test('formatQuoteDate 应该正确格式化并推算时间段', () {
      final dtMorning = DateTime(2025, 6, 21, 10, 0);
      expect(TimeUtils.formatQuoteDate(dtMorning), '2025-06-21 上午');

      final dtMidnight = DateTime(2025, 6, 21, 23, 30);
      expect(TimeUtils.formatQuoteDate(dtMidnight), '2025-06-21 深夜');

      // 测试传入 dayPeriod
      expect(
        TimeUtils.formatQuoteDate(dtMorning, dayPeriod: 'dusk'),
        '2025-06-21 黄昏',
      );
    });

    test('formatFileTimestamp 应该正确补零', () {
      final dt = DateTime(2025, 6, 21, 8, 5);
      expect(TimeUtils.formatFileTimestamp(dt), '20250621_0805');
    });

    test('formatLogTimestamp 应该根据时间差返回不同的格式', () {
      final now = DateTime.now();

      // 当天
      final today = DateTime(now.year, now.month, now.day, 14, 30, 45);
      expect(TimeUtils.formatLogTimestamp(today), '14:30:45');

      // 7天内 (假设 yesterday 不跨周，为简化测试直接算 difference，这里简单断言包含周几即可)
      final yesterday = now.subtract(const Duration(days: 2));
      final logYesterday = TimeUtils.formatLogTimestamp(yesterday);
      expect(logYesterday.contains('周'), isTrue);

      // 7天以上
      final oldDate = now.subtract(const Duration(days: 10));
      final logOld = TimeUtils.formatLogTimestamp(oldDate);
      expect(logOld.contains('-'), isTrue); // 应该有 MM-dd
    });

    test('formatDateFromIso 和 formatDateTimeFromIso 应该处理异常', () {
      final validIso = '2025-06-21T14:30:00.000Z';
      expect(TimeUtils.formatDateFromIso(validIso), '2025年6月21日');
      // 本地时区可能会有影响，由于此函数使用 parse，如果遇到时区可能导致小时变化
      // 不过由于 parse 返回的是 utc/local 根据字符串，简单断言即可

      final invalidIso = 'invalid-date';
      expect(TimeUtils.formatDateFromIso(invalidIso), 'invalid-date');
      expect(TimeUtils.formatDateTimeFromIso(invalidIso), 'invalid-date');
    });
  });
}
