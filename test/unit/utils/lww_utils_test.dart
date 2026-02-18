import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/lww_utils.dart';

void main() {
  group('LWWUtils', () {
    const defaultTimestamp = '1970-01-01T00:00:00.000Z';

    group('parseTimestamp', () {
      test('parses valid ISO8601 string', () {
        final result = LWWUtils.parseTimestamp('2023-01-01T12:00:00.000Z');
        expect(result.year, 2023);
        expect(result.month, 1);
        expect(result.isUtc, isTrue);
      });

      test('returns epoch for null', () {
        final result = LWWUtils.parseTimestamp(null);
        expect(result.millisecondsSinceEpoch, 0);
        expect(result.isUtc, isTrue);
      });

      test('returns epoch for empty string', () {
        final result = LWWUtils.parseTimestamp('');
        expect(result.millisecondsSinceEpoch, 0);
        expect(result.isUtc, isTrue);
      });

      test('returns epoch for invalid string', () {
        final result = LWWUtils.parseTimestamp('invalid-date');
        expect(result.millisecondsSinceEpoch, 0);
        expect(result.isUtc, isTrue);
      });
    });

    group('compareTimestamps', () {
      test('returns positive when remote is newer', () {
        final result = LWWUtils.compareTimestamps(
          '2023-01-01T10:00:00.000Z',
          '2023-01-01T11:00:00.000Z',
        );
        expect(result, greaterThan(0));
      });

      test('returns negative when local is newer', () {
        final result = LWWUtils.compareTimestamps(
          '2023-01-01T11:00:00.000Z',
          '2023-01-01T10:00:00.000Z',
        );
        expect(result, lessThan(0));
      });

      test('returns zero when equal', () {
        final result = LWWUtils.compareTimestamps(
          '2023-01-01T10:00:00.000Z',
          '2023-01-01T10:00:00.000Z',
        );
        expect(result, 0);
      });

      test('handles null timestamps as epoch', () {
        // null vs valid -> valid is newer (remote newer -> positive)
        expect(LWWUtils.compareTimestamps(null, '2023-01-01T10:00:00.000Z'),
            greaterThan(0));

        // valid vs null -> valid is newer (local newer -> negative)
        expect(LWWUtils.compareTimestamps('2023-01-01T10:00:00.000Z', null),
            lessThan(0));

        // null vs null -> equal
        expect(LWWUtils.compareTimestamps(null, null), 0);
      });
    });

    group('shouldUseRemote', () {
      test('returns true when remote is newer', () {
        expect(
            LWWUtils.shouldUseRemote(
              '2023-01-01T10:00:00.000Z',
              '2023-01-01T11:00:00.000Z',
            ),
            isTrue);
      });

      test('returns false when local is newer or equal', () {
        expect(
            LWWUtils.shouldUseRemote(
              '2023-01-01T11:00:00.000Z',
              '2023-01-01T10:00:00.000Z',
            ),
            isFalse);

        expect(
            LWWUtils.shouldUseRemote(
              '2023-01-01T10:00:00.000Z',
              '2023-01-01T10:00:00.000Z',
            ),
            isFalse);
      });
    });

    group('shouldKeepLocal', () {
      test('returns true when local is newer or equal', () {
        expect(
            LWWUtils.shouldKeepLocal(
              '2023-01-01T11:00:00.000Z',
              '2023-01-01T10:00:00.000Z',
            ),
            isTrue);

        expect(
            LWWUtils.shouldKeepLocal(
              '2023-01-01T10:00:00.000Z',
              '2023-01-01T10:00:00.000Z',
            ),
            isTrue);
      });

      test('returns false when remote is newer', () {
        expect(
            LWWUtils.shouldKeepLocal(
              '2023-01-01T10:00:00.000Z',
              '2023-01-01T11:00:00.000Z',
            ),
            isFalse);
      });
    });

    group('generateTimestamp', () {
      test('returns valid ISO8601 string', () {
        final timestamp = LWWUtils.generateTimestamp();
        expect(() => DateTime.parse(timestamp), returnsNormally);
      });
    });

    group('isDefaultTimestamp', () {
      test('returns true for null or empty', () {
        expect(LWWUtils.isDefaultTimestamp(null), isTrue);
        expect(LWWUtils.isDefaultTimestamp(''), isTrue);
      });

      test('returns true for default timestamp constant', () {
        expect(LWWUtils.isDefaultTimestamp(defaultTimestamp), isTrue);
      });

      test('returns false for other timestamps', () {
        expect(
            LWWUtils.isDefaultTimestamp('2023-01-01T10:00:00.000Z'), isFalse);
      });
    });

    group('formatTimestamp', () {
      test('formats days correctly', () {
        final date = DateTime.now().subtract(const Duration(days: 2));
        expect(LWWUtils.formatTimestamp(date.toIso8601String()), '2天前');
      });

      test('formats hours correctly', () {
        final date = DateTime.now().subtract(const Duration(hours: 3));
        expect(LWWUtils.formatTimestamp(date.toIso8601String()), '3小时前');
      });

      test('formats minutes correctly', () {
        final date = DateTime.now().subtract(const Duration(minutes: 5));
        expect(LWWUtils.formatTimestamp(date.toIso8601String()), '5分钟前');
      });

      test('formats just now correctly', () {
        final date = DateTime.now().subtract(const Duration(seconds: 10));
        expect(LWWUtils.formatTimestamp(date.toIso8601String()), '刚刚');
      });

      test('handles invalid timestamp', () {
        expect(LWWUtils.formatTimestamp('invalid'), '时间格式错误');
      });

      test('handles null/empty timestamp', () {
        expect(LWWUtils.formatTimestamp(null), '未知时间');
        expect(LWWUtils.formatTimestamp(''), '未知时间');
      });
    });

    group('detectClockSkew', () {
      test('returns duration if remote is > 5 mins ahead', () {
        final futureDate = DateTime.now().add(const Duration(minutes: 10));
        final skew = LWWUtils.detectClockSkew(futureDate.toIso8601String());
        expect(skew, isNotNull);
        expect(skew!.inMinutes, greaterThanOrEqualTo(9));
      });

      test('returns null if remote is < 5 mins ahead', () {
        final futureDate = DateTime.now().add(const Duration(minutes: 4));
        final skew = LWWUtils.detectClockSkew(futureDate.toIso8601String());
        expect(skew, isNull);
      });

      test('returns null if remote is in past', () {
        final pastDate = DateTime.now().subtract(const Duration(minutes: 10));
        final skew = LWWUtils.detectClockSkew(pastDate.toIso8601String());
        expect(skew, isNull);
      });

      test('returns null for invalid/null inputs', () {
        expect(LWWUtils.detectClockSkew(null), isNull);
        expect(LWWUtils.detectClockSkew('invalid'), isNull);
      });
    });

    group('isValidTimestamp', () {
      test('returns true for valid timestamp', () {
        expect(LWWUtils.isValidTimestamp('2023-01-01T10:00:00.000Z'), isTrue);
      });

      test('returns false for invalid timestamp', () {
        expect(LWWUtils.isValidTimestamp('invalid'), isFalse);
        expect(LWWUtils.isValidTimestamp(null), isFalse);
        expect(LWWUtils.isValidTimestamp(''), isFalse);
      });
    });

    group('normalizeTimestamp', () {
      test('returns ISO string for valid input', () {
        const input = '2023-01-01T10:00:00.000Z';
        expect(LWWUtils.normalizeTimestamp(input), input);
      });

      test('returns default timestamp for invalid input', () {
        expect(LWWUtils.normalizeTimestamp('invalid'), defaultTimestamp);
        expect(LWWUtils.normalizeTimestamp(null), defaultTimestamp);
      });
    });

    group('getNewerTimestamp', () {
      test('returns newer timestamp', () {
        const oldTime = '2023-01-01T10:00:00.000Z';
        const newTime = '2023-01-01T11:00:00.000Z';
        expect(LWWUtils.getNewerTimestamp(oldTime, newTime), newTime);
        expect(LWWUtils.getNewerTimestamp(newTime, oldTime), newTime);
      });
    });

    group('getTimestampDifferenceSeconds', () {
      test('calculates difference correctly', () {
        const time1 = '2023-01-01T10:00:00.000Z';
        const time2 = '2023-01-01T10:00:10.000Z';
        // time2 - time1 = 10 seconds
        expect(LWWUtils.getTimestampDifferenceSeconds(time1, time2), 10);
        // time1 - time2 = -10 seconds
        expect(LWWUtils.getTimestampDifferenceSeconds(time2, time1), -10);
      });
    });
  });
}
