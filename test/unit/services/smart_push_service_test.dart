library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/smart_push_service.dart';

void main() {
  group('SmartPushService Daily Quote Normalization', () {
    test('normalizes homepage quote payload to shared push payload', () {
      final normalized = SmartPushService.normalizeDailyQuoteData({
        'content': '同一句话',
        'author': '作者',
        'source': '出处',
        'type': 'd',
      });

      expect(normalized, isNotNull);
      expect(normalized!['hitokoto'], equals('同一句话'));
      expect(normalized['from_who'], equals('作者'));
      expect(normalized['from'], equals('出处'));
      expect(normalized['type'], equals('d'));
    });

    test('returns null when quote content is empty', () {
      final normalized = SmartPushService.normalizeDailyQuoteData({
        'content': '   ',
        'author': '作者',
      });

      expect(normalized, isNull);
    });
  });

  group('SmartPushService notification helpers', () {
    test('buildNotificationPayload includes route target for note list', () {
      final payload = SmartPushService.buildNotificationPayload(
        noteId: '12345678-1234-1234-1234-1234567890ab',
        contentType: 'monthAgoToday',
        routeTarget: 'noteList',
      );

      expect(
        payload,
        equals(
          'contentType:monthAgoToday|noteId:12345678-1234-1234-1234-1234567890ab|routeTarget:noteList',
        ),
      );
    });

    test('notification summary is removed even for historical notes', () {
      final note = Quote(
        id: '12345678-1234-1234-1234-1234567890ab',
        content: '春天会再来。',
        date: DateTime(2025, 10, 15, 9, 0).toIso8601String(),
      );

      expect(SmartPushService.notificationSummaryForTest(note), isNull);
    });
  });
}
