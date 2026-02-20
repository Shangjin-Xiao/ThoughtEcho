import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/utils/time_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('开启精确时间后不显示时间段标签', (tester) async {
    String formatted = '';

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            formatted = TimeUtils.formatQuoteDateLocalized(
              context,
              DateTime(2025, 6, 21, 21, 15),
              dayPeriod: '', // 模拟存储了空字符串的时间段
              showExactTime: true,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.pump();

    expect(formatted, isNot(contains('夜晚')));
    expect(formatted, contains('21:15'));
  });

  group('formatQuoteTime', () {
    test('formats midnight correctly', () {
      final dateTime = DateTime(2023, 10, 27, 0, 0);
      expect(TimeUtils.formatQuoteTime(dateTime), '00:00');
    });

    test('formats single digit hour and minute correctly', () {
      final dateTime = DateTime(2023, 10, 27, 9, 5);
      expect(TimeUtils.formatQuoteTime(dateTime), '09:05');
    });

    test('formats double digit hour and minute correctly', () {
      final dateTime = DateTime(2023, 10, 27, 21, 15);
      expect(TimeUtils.formatQuoteTime(dateTime), '21:15');
    });

    test('formats end of day correctly', () {
      final dateTime = DateTime(2023, 10, 27, 23, 59);
      expect(TimeUtils.formatQuoteTime(dateTime), '23:59');
    });
  });

  group('formatDateFromIso', () {
    test('formats valid ISO date string correctly', () {
      const isoDate = '2023-10-27T10:00:00.000Z';
      expect(TimeUtils.formatDateFromIso(isoDate), '2023年10月27日');
    });

    test('returns original string for invalid ISO date string', () {
      const invalidDate = 'invalid-date-string';
      expect(TimeUtils.formatDateFromIso(invalidDate), invalidDate);
    });

    test('returns original string for empty string', () {
      const emptyString = '';
      expect(TimeUtils.formatDateFromIso(emptyString), emptyString);
    });
  });
}
