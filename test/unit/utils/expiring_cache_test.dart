import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/expiring_cache.dart';

void main() {
  group('ExpiringCache', () {
    test('stores and clears values', () {
      final cache = ExpiringCache<String, int>(
        expiration: const Duration(minutes: 5),
      );

      cache['total'] = 3;
      cache.clear();

      expect(cache['total'], isNull);
    });

    test('removes expired values', () {
      var now = DateTime(2026);
      final cache = ExpiringCache<String, int>(
        expiration: const Duration(minutes: 5),
        now: () => now,
      );

      cache['total'] = 3;
      now = now.add(const Duration(minutes: 6));
      final removedCount = cache.removeExpired();

      expect(removedCount, 1);
      expect(cache['total'], isNull);
    });
  });
}
