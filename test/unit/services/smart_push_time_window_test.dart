library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/smart_push_settings.dart';
import 'package:thoughtecho/services/smart_push_service.dart';

void main() {
  group('SmartPushService time window helpers', () {
    test('matches slot only when current time is after slot within tolerance',
        () {
      final now = DateTime(2026, 3, 13, 8, 5);
      const slot = PushTimeSlot(hour: 8, minute: 0);

      expect(SmartPushService.isWithinPushWindow(now, slot), isTrue);
      expect(
        SmartPushService.isWithinPushWindow(
          DateTime(2026, 3, 13, 7, 55),
          slot,
        ),
        isFalse,
      );
      expect(
        SmartPushService.isWithinPushWindow(
          DateTime(2026, 3, 13, 8, 11),
          slot,
        ),
        isFalse,
      );
    });

    test('matches any eligible slot in list', () {
      final now = DateTime(2026, 3, 13, 20, 8);
      const slots = [
        PushTimeSlot(hour: 8, minute: 0),
        PushTimeSlot(hour: 20, minute: 0),
      ];

      expect(SmartPushService.isWithinAnyPushWindow(now, slots), isTrue);
      expect(
        SmartPushService.isWithinAnyPushWindow(
          DateTime(2026, 3, 13, 18, 0),
          slots,
        ),
        isFalse,
      );
    });

    test('builds notification payload with actual content type', () {
      expect(
        SmartPushService.buildNotificationPayload(
          noteId: '12345678-1234-1234-1234-1234567890ab',
          contentType: 'yearAgoToday',
        ),
        'contentType:yearAgoToday|noteId:12345678-1234-1234-1234-1234567890ab',
      );
      expect(
        SmartPushService.buildNotificationPayload(contentType: 'dailyQuote'),
        'contentType:dailyQuote',
      );
    });

    test('next scheduled date skips to next active weekday', () {
      const settings = SmartPushSettings(
        frequency: PushFrequency.weekdays,
      );

      final scheduled = SmartPushService.nextScheduledDate(
        now: DateTime(2026, 3, 14, 9, 0),
        hour: 8,
        minute: 0,
        settings: settings,
      );

      expect(scheduled, DateTime(2026, 3, 16, 8, 0));
    });

    test('daily quote scheduling can ignore smart push frequency', () {
      const settings = SmartPushSettings(
        frequency: PushFrequency.weekdays,
      );

      final scheduled = SmartPushService.nextScheduledDate(
        now: DateTime(2026, 3, 14, 9, 0),
        hour: 7,
        minute: 0,
        settings: settings,
        respectsFrequency: false,
      );

      expect(scheduled, DateTime(2026, 3, 15, 7, 0));
    });
  });
}
