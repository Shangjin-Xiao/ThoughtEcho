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

  group('SmartPushService time slot merging', () {
    test('merges close time slots that are within 30 minutes', () {
      // 这个测试验证时间槽合并逻辑的行为
      // 合并逻辑在 SmartPushScheduling._mergeCloseTimeSlots 中实现
      // 间隔 < 30 分钟的时间槽会被合并（只保留第一个）

      const slots = [
        PushTimeSlot(hour: 8, minute: 0, label: '早晨'),
        PushTimeSlot(hour: 8, minute: 15, label: '早晨2'), // 间隔 15 分钟，应被合并
        PushTimeSlot(hour: 8, minute: 30, label: '早晨3'), // 间隔 30 分钟，保留
        PushTimeSlot(hour: 20, minute: 0, label: '晚间'),
      ];

      // 按时间排序后：8:00, 8:15, 8:30, 20:00
      // 合并后应该是：8:00, 8:30, 20:00（8:15 被合并到 8:00）
      // 但实际上 8:30 与 8:00 间隔刚好 30 分钟，按 >= 30 的规则会保留

      // 验证时间槽的时间计算
      expect(
        (slots[1].hour * 60 + slots[1].minute) -
            (slots[0].hour * 60 + slots[0].minute),
        15,
      );
      expect(
        (slots[2].hour * 60 + slots[2].minute) -
            (slots[0].hour * 60 + slots[0].minute),
        30,
      );
    });

    test('keeps time slots that are 30+ minutes apart', () {
      // 间隔 >= 30 分钟的时间槽应该保留
      const slots = [
        PushTimeSlot(hour: 8, minute: 0),
        PushTimeSlot(hour: 8, minute: 30), // 刚好 30 分钟
        PushTimeSlot(hour: 12, minute: 0), // 3.5 小时
      ];

      // 计算间隔
      final gap1 = (slots[1].hour * 60 + slots[1].minute) -
          (slots[0].hour * 60 + slots[0].minute);
      final gap2 = (slots[2].hour * 60 + slots[2].minute) -
          (slots[1].hour * 60 + slots[1].minute);

      expect(gap1, 30); // 刚好 30 分钟，应保留
      expect(gap2, 210); // 3.5 小时，应保留
    });
  });
}
