library;

import 'package:flutter_test/flutter_test.dart';
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
}
