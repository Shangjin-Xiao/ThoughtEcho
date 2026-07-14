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

    test('keeps unexpired values', () {
      var now = DateTime(2026);
      final cache = ExpiringCache<String, int>(
        expiration: const Duration(minutes: 5),
        now: () => now,
      );

      cache['total'] = 3;
      now = now.add(const Duration(minutes: 4));
      final removedCount = cache.removeExpired();

      expect(removedCount, 0);
      expect(cache['total'], 3);
    });

    test('handles mixed expired and unexpired values', () {
      var now = DateTime(2026);
      final cache = ExpiringCache<String, int>(
        expiration: const Duration(minutes: 5),
        now: () => now,
      );

      cache['old'] = 1;
      now = now.add(const Duration(minutes: 3));
      cache['new'] = 2;

      now = now.add(const Duration(minutes: 3));

      final removedCount = cache.removeExpired();

      expect(removedCount, 1);
      expect(cache['old'], isNull);
      expect(cache['new'], 2);
    });

    test('keeps boundary values (exactly at expiration)', () {
      var now = DateTime(2026);
      final cache = ExpiringCache<String, int>(
        expiration: const Duration(minutes: 5),
        now: () => now,
      );

      cache['total'] = 3;
      now = now.add(const Duration(minutes: 5));
      final removedCount = cache.removeExpired();

      expect(removedCount, 0);
      expect(cache['total'], 3);
    });
  });
}
