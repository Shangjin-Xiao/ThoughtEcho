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
  });
}
