library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/smart_push_settings.dart';

void main() {
  group('SmartPushSettings scheduling helpers', () {
    test('shouldPushOnDate respects weekday and weekend frequencies', () {
      const weekdaySettings = SmartPushSettings(
        frequency: PushFrequency.weekdays,
      );
      const weekendSettings = SmartPushSettings(
        frequency: PushFrequency.weekends,
      );

      expect(
        weekdaySettings.shouldPushOnDate(DateTime(2026, 3, 13)),
        isTrue,
      );
      expect(
        weekdaySettings.shouldPushOnDate(DateTime(2026, 3, 14)),
        isFalse,
      );
      expect(
        weekendSettings.shouldPushOnDate(DateTime(2026, 3, 14)),
        isTrue,
      );
      expect(
        weekendSettings.shouldPushOnDate(DateTime(2026, 3, 13)),
        isFalse,
      );
    });

    test('nextPushDateFrom skips inactive days for weekdays mode', () {
      const settings = SmartPushSettings(
        frequency: PushFrequency.weekdays,
      );

      final nextDate = settings.nextPushDateFrom(DateTime(2026, 3, 14));

      expect(nextDate, DateTime(2026, 3, 16));
    });

    test('nextPushDateFrom skips inactive days for weekends mode', () {
      const settings = SmartPushSettings(
        frequency: PushFrequency.weekends,
      );

      final nextDate = settings.nextPushDateFrom(DateTime(2026, 3, 13));

      expect(nextDate, DateTime(2026, 3, 14));
    });

    test('custom frequency only pushes on selected weekdays', () {
      const settings = SmartPushSettings(
        frequency: PushFrequency.custom,
        selectedWeekdays: {1, 3, 5},
      );

      expect(settings.shouldPushOnDate(DateTime(2026, 3, 16)), isTrue);
      expect(settings.shouldPushOnDate(DateTime(2026, 3, 17)), isFalse);
      expect(settings.nextPushDateFrom(DateTime(2026, 3, 17)),
          DateTime(2026, 3, 18));
    });
  });
}
