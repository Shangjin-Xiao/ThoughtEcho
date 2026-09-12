import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/utils/time_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimeUtils 单元测试 - 时间段与边界转换', () {
    test('formatQuoteDate 时间段边界测试', () {
      // 04:59 -> 深夜
      expect(
        TimeUtils.formatQuoteDate(DateTime(2025, 6, 21, 4, 59)),
        '2025-06-21 深夜',
      );
      // 05:00 -> 晨曦
      expect(
        TimeUtils.formatQuoteDate(DateTime(2025, 6, 21, 5, 0)),
        '2025-06-21 晨曦',
      );
      // 07:59 -> 晨曦
      expect(
        TimeUtils.formatQuoteDate(DateTime(2025, 6, 21, 7, 59)),
        '2025-06-21 晨曦',
      );
      // 08:00 -> 上午
      expect(
        TimeUtils.formatQuoteDate(DateTime(2025, 6, 21, 8, 0)),
        '2025-06-21 上午',
      );
      // 11:59 -> 上午
      expect(
        TimeUtils.formatQuoteDate(DateTime(2025, 6, 21, 11, 59)),
        '2025-06-21 上午',
      );
      // 12:00 -> 午后
      expect(
        TimeUtils.formatQuoteDate(DateTime(2025, 6, 21, 12, 0)),
        '2025-06-21 午后',
      );
      // 16:59 -> 午后
      expect(
        TimeUtils.formatQuoteDate(DateTime(2025, 6, 21, 16, 59)),
        '2025-06-21 午后',
      );
      // 17:00 -> 黄昏
      expect(
        TimeUtils.formatQuoteDate(DateTime(2025, 6, 21, 17, 0)),
        '2025-06-21 黄昏',
      );
      // 19:59 -> 黄昏
      expect(
        TimeUtils.formatQuoteDate(DateTime(2025, 6, 21, 19, 59)),
        '2025-06-21 黄昏',
      );
      // 20:00 -> 夜晚
      expect(
        TimeUtils.formatQuoteDate(DateTime(2025, 6, 21, 20, 0)),
        '2025-06-21 夜晚',
      );
      // 22:59 -> 夜晚
      expect(
        TimeUtils.formatQuoteDate(DateTime(2025, 6, 21, 22, 59)),
        '2025-06-21 夜晚',
      );
      // 23:00 -> 深夜
      expect(
        TimeUtils.formatQuoteDate(DateTime(2025, 6, 21, 23, 0)),
        '2025-06-21 深夜',
      );
      // 00:00 -> 深夜
      expect(
        TimeUtils.formatQuoteDate(DateTime(2025, 6, 21, 0, 0)),
        '2025-06-21 深夜',
      );
    });

    test('getDayPeriodLabel 应该返回正确的中文标签或 fallback', () {
      expect(TimeUtils.getDayPeriodLabel('dawn'), '晨曦');
      expect(TimeUtils.getDayPeriodLabel('morning'), '上午');
      expect(TimeUtils.getDayPeriodLabel('afternoon'), '午后');
      expect(TimeUtils.getDayPeriodLabel('dusk'), '黄昏');
      expect(TimeUtils.getDayPeriodLabel('evening'), '夜晚');
      expect(TimeUtils.getDayPeriodLabel('midnight'), '深夜');
      expect(TimeUtils.getDayPeriodLabel('unknown_key'), 'unknown_key');
    });
  });

  group('TimeUtils 单元测试 - 本地化与 Key 解析', () {
    testWidgets('localizedDayPeriodLabel 应该正确返回本地化文案或逆向解析旧中文标签',
        (tester) async {
      late AppLocalizations zhL10n;
      late AppLocalizations enL10n;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              zhL10n = AppLocalizations.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              enL10n = AppLocalizations.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // 标准 key
      expect(TimeUtils.localizedDayPeriodLabel(zhL10n, 'dawn'),
          zhL10n.dayPeriodDawn);
      expect(TimeUtils.localizedDayPeriodLabel(enL10n, 'dawn'),
          enL10n.dayPeriodDawn);

      // 旧中文标签 -> 逆向解析 map -> 本地化文案
      expect(TimeUtils.localizedDayPeriodLabel(enL10n, '晨曦'),
          enL10n.dayPeriodDawn);
      expect(TimeUtils.localizedDayPeriodLabel(enL10n, '上午'),
          enL10n.dayPeriodMorning);
      expect(TimeUtils.localizedDayPeriodLabel(enL10n, '午后'),
          enL10n.dayPeriodAfternoon);
      expect(TimeUtils.localizedDayPeriodLabel(enL10n, '黄昏'),
          enL10n.dayPeriodDusk);
      expect(TimeUtils.localizedDayPeriodLabel(enL10n, '夜晚'),
          enL10n.dayPeriodEvening);
      expect(TimeUtils.localizedDayPeriodLabel(enL10n, '深夜'),
          enL10n.dayPeriodMidnight);

      // 未知 Key 或任意文本 -> 原样返回
      expect(TimeUtils.localizedDayPeriodLabel(enL10n, 'custom_period'),
          'custom_period');
    });

    testWidgets('formatQuoteDateLocalized 各种情况的解析', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              // 1. showExactTime 为 true
              final exactTime = TimeUtils.formatQuoteDateLocalized(
                context,
                DateTime(2025, 6, 21, 14, 30),
                dayPeriod: 'afternoon',
                showExactTime: true,
              );
              expect(exactTime, '2025-06-21 14:30');

              // 2. 传入标准 key
              final keyTime = TimeUtils.formatQuoteDateLocalized(
                context,
                DateTime(2025, 6, 21, 14, 30),
                dayPeriod: 'afternoon',
              );
              expect(keyTime, '2025-06-21 午后');

              // 3. 传入中文标签
              final cnLabelTime = TimeUtils.formatQuoteDateLocalized(
                context,
                DateTime(2025, 6, 21, 14, 30),
                dayPeriod: '黄昏',
              );
              expect(cnLabelTime, '2025-06-21 黄昏');

              // 4. dayPeriod 为空字符串，根据时间推算 (14:30 -> afternoon)
              final emptyPeriod = TimeUtils.formatQuoteDateLocalized(
                context,
                DateTime(2025, 6, 21, 14, 30),
                dayPeriod: '  ',
              );
              expect(emptyPeriod, '2025-06-21 午后');

              // 5. dayPeriod 为 null，根据时间推算 (06:00 -> dawn)
              final nullPeriod = TimeUtils.formatQuoteDateLocalized(
                context,
                DateTime(2025, 6, 21, 6, 0),
              );
              expect(nullPeriod, '2025-06-21 晨曦');

              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });

  group('TimeUtils 单元测试 - 相对时间与模糊时间格式化', () {
    testWidgets('formatRelativeDateTimeLocalized 测试', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final now = DateTime.now();

              // 今天
              final today = DateTime(now.year, now.month, now.day, 10, 15);
              expect(
                TimeUtils.formatRelativeDateTimeLocalized(context, today),
                '10:15',
              );

              // 昨天
              final yesterdayNow = now.subtract(const Duration(days: 1));
              final yesterday = DateTime(yesterdayNow.year, yesterdayNow.month,
                  yesterdayNow.day, 14, 20);
              expect(
                TimeUtils.formatRelativeDateTimeLocalized(context, yesterday),
                contains('14:20'),
              );

              // 7天内 (不是今天/昨天，但比 7 天前的当前时刻晚)
              final fourDaysAgo = now.subtract(const Duration(days: 4));
              if (fourDaysAgo.day != today.day &&
                  fourDaysAgo.day != yesterday.day) {
                final rel = TimeUtils.formatRelativeDateTimeLocalized(
                    context, fourDaysAgo);
                expect(rel, contains(':'));
              }

              // 当年 (10天前)
              if (now.month > 1 || now.day > 10) {
                final tenDaysAgo = DateTime(now.year, now.month, now.day)
                    .subtract(const Duration(days: 10, hours: 2));
                final formatted = TimeUtils.formatRelativeDateTimeLocalized(
                    context, tenDaysAgo);
                expect(formatted.contains('-'), isTrue);
              }

              // 往年
              final lastYear = DateTime(now.year - 1, 5, 20, 8, 30);
              expect(
                TimeUtils.formatRelativeDateTimeLocalized(context, lastYear),
                '${now.year - 1}-05-20 08:30',
              );

              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('formatElapsedRelativeTimeLocalized 测试', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final now = DateTime.now();

              // 刚刚 (<1分钟)
              final justNow = now.subtract(const Duration(seconds: 30));
              expect(
                TimeUtils.formatElapsedRelativeTimeLocalized(context, justNow),
                '刚刚',
              );

              // 几分钟前
              final minsAgo = now.subtract(const Duration(minutes: 5));
              expect(
                TimeUtils.formatElapsedRelativeTimeLocalized(context, minsAgo),
                '5分钟前',
              );

              // 几小时前
              final hoursAgo = now.subtract(const Duration(hours: 3));
              expect(
                TimeUtils.formatElapsedRelativeTimeLocalized(context, hoursAgo),
                '3小时前',
              );

              // 几天前
              final daysAgo = now.subtract(const Duration(days: 2));
              expect(
                TimeUtils.formatElapsedRelativeTimeLocalized(context, daysAgo),
                '2天前',
              );

              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });

  group('TimeUtils 单元测试 - 图标与格式化辅助方法', () {
    test('getDayPeriodIcon 应该涵盖所有分支', () {
      expect(TimeUtils.getDayPeriodIcon('晨曦'), Icons.wb_twilight);
      expect(TimeUtils.getDayPeriodIcon('上午'), Icons.wb_sunny_outlined);
      expect(TimeUtils.getDayPeriodIcon('午后'), Icons.wb_sunny);
      expect(TimeUtils.getDayPeriodIcon('黄昏'), Icons.nights_stay_outlined);
      expect(TimeUtils.getDayPeriodIcon('夜晚'), Icons.nightlight_round);
      expect(TimeUtils.getDayPeriodIcon('深夜'), Icons.bedtime);
      expect(TimeUtils.getDayPeriodIcon('未知'), Icons.access_time);
      expect(TimeUtils.getDayPeriodIcon(''), Icons.access_time);
      expect(TimeUtils.getDayPeriodIcon(null), Icons.access_time);
    });

    test('getDayPeriodIconByKey 应该涵盖所有分支与 null/unknown', () {
      expect(TimeUtils.getDayPeriodIconByKey('dawn'), Icons.wb_twilight);
      expect(
          TimeUtils.getDayPeriodIconByKey('morning'), Icons.wb_sunny_outlined);
      expect(TimeUtils.getDayPeriodIconByKey('afternoon'), Icons.wb_sunny);
      expect(
          TimeUtils.getDayPeriodIconByKey('dusk'), Icons.nights_stay_outlined);
      expect(
          TimeUtils.getDayPeriodIconByKey('evening'), Icons.nightlight_round);
      expect(TimeUtils.getDayPeriodIconByKey('midnight'), Icons.bedtime);
      expect(TimeUtils.getDayPeriodIconByKey('unknown'), Icons.access_time);
      expect(TimeUtils.getDayPeriodIconByKey(null), Icons.access_time);
    });

    test('formatFileTimestamp 补零与组合', () {
      final dt1 = DateTime(2025, 1, 2, 3, 4);
      expect(TimeUtils.formatFileTimestamp(dt1), '20250102_0304');

      final dt2 = DateTime(2025, 12, 31, 23, 59);
      expect(TimeUtils.formatFileTimestamp(dt2), '20251231_2359');
    });

    test('formatLogTimestamp 涵盖今天、一周内、一周以上', () {
      final now = DateTime.now();

      // 今天
      final today = DateTime(now.year, now.month, now.day, 9, 5, 3);
      expect(TimeUtils.formatLogTimestamp(today), '09:05:03');

      // 一周内 (2天前)
      final twoDaysAgo = now.subtract(const Duration(days: 2));
      final logWeek = TimeUtils.formatLogTimestamp(twoDaysAgo);
      expect(logWeek.contains('周'), isTrue);

      // 一周以上 (10天前)
      final tenDaysAgo = now.subtract(const Duration(days: 10));
      final logOld = TimeUtils.formatLogTimestamp(tenDaysAgo);
      expect(logOld, contains('-'));
      expect(logOld.split('-').length, 2);
    });

    test('formatDateFromIso 与 formatDateTimeFromIso 正常与异常处理', () {
      const validIso = '2025-06-21T14:30:00.000Z';
      expect(TimeUtils.formatDateFromIso(validIso), '2025年6月21日');
      expect(TimeUtils.formatDateTimeFromIso(validIso), contains('2025年6月21日'));

      const invalidIso = 'not-a-date';
      expect(TimeUtils.formatDateFromIso(invalidIso), 'not-a-date');
      expect(TimeUtils.formatDateTimeFromIso(invalidIso), 'not-a-date');

      const emptyIso = '';
      expect(TimeUtils.formatDateFromIso(emptyIso), '');
      expect(TimeUtils.formatDateTimeFromIso(emptyIso), '');
    });
  });
}
